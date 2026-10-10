use std::collections::HashSet;

use matrix_sdk::ruma::{
    api::client::profile::{AvatarUrl, DisplayName},
    events::ignored_user_list::IgnoredUserListEventContent,
    events::{room::power_levels::UserPowerLevel, StateEventType},
    RoomId, UserId,
};

use crate::matrix::session::{get_client, SESSION};
use crate::protocol::commands::{RoomMemberInfo, UserDetails, UserDirectoryEntry};
use crate::storage::profile_cache::{
    get_cached_user_details, invalidate_user_details, store_user_details,
};
use crate::storage::profiles::update_profile_identity;

pub(crate) async fn ignored_user_ids(client: &matrix_sdk::Client) -> HashSet<String> {
    client
        .account()
        .account_data::<IgnoredUserListEventContent>()
        .await
        .ok()
        .flatten()
        .and_then(|raw| raw.deserialize().ok())
        .map(|content| {
            content
                .ignored_users
                .into_keys()
                .map(|user_id| user_id.to_string())
                .collect()
        })
        .unwrap_or_default()
}

pub async fn search_user_directory(
    query: &str,
    limit: u32,
) -> Result<(Vec<UserDirectoryEntry>, bool), String> {
    let query = query.trim();
    if query.is_empty() {
        return Ok((Vec::new(), false));
    }
    let query_lower = query.to_lowercase();
    let bare_query = query_lower.trim_start_matches('@');
    if bare_query.is_empty() {
        return Ok((Vec::new(), false));
    }

    let client = get_client().await?;
    let response = client
        .search_users(query, u64::from(limit.clamp(1, 50)))
        .await
        .map_err(|error| format!("Не удалось найти пользователей: {error}"))?;

    let users = response
        .results
        .into_iter()
        .filter(|user| {
            let user_id = user.user_id.to_string().to_lowercase();
            let localpart = user.user_id.localpart().to_lowercase();
            let display_name = user.display_name.as_deref().unwrap_or("").to_lowercase();
            user_id.starts_with(&query_lower)
                || localpart.starts_with(bare_query)
                || display_name.starts_with(&query_lower)
        })
        .map(|user| UserDirectoryEntry {
            user_id: user.user_id.to_string(),
            display_name: user.display_name,
            avatar_url: user.avatar_url.map(|url| url.to_string()),
        })
        .collect();

    Ok((users, response.limited))
}

pub async fn get_user_details(
    user_id: &str,
    room_id: Option<String>,
) -> Result<UserDetails, String> {
    let (current_user_id, current_profile_id) = {
        let session = SESSION.lock().await;
        (session.user_id.clone(), session.profile_id.clone())
    };
    let is_self_request = current_user_id.as_deref() == Some(user_id);
    let canonical_self_request = is_self_request && room_id.is_none();

    // The active account identity is authoritative and intentionally bypasses
    // the short-lived profile cache. Every refresh reads the global Matrix
    // profile endpoint and then updates the single saved identity snapshot.
    if !canonical_self_request {
        if let Some(cached) = get_cached_user_details(user_id, room_id.as_deref()).await {
            return Ok(cached);
        }
    }

    let client = get_client().await?;
    let ruma_user_id = <&UserId>::try_from(user_id)
        .map_err(|e| format!("Некорректный user_id: {}", e))?
        .to_owned();

    let is_self = current_user_id.as_deref() == Some(ruma_user_id.as_str());
    let can_send_dm = !is_self;

    let mut room_member: Option<RoomMemberInfo> = None;
    let mut power_level: i64 = -1;
    let mut is_admin = false;
    let mut is_moderator = false;
    let mut viewer_power_level: i64 = -1;
    let mut viewer_can_kick = false;
    let mut viewer_can_ban = false;
    let mut viewer_can_manage_roles = false;

    let mut effective_display_name = ruma_user_id.localpart().to_string();
    let mut effective_avatar_url: Option<String> = None;
    let mut global_display_name: Option<String> = None;
    let mut global_avatar_url: Option<String> = None;

    match client.account().fetch_user_profile_of(&ruma_user_id).await {
        Ok(profile) => {
            global_display_name = profile.get_static::<DisplayName>().ok().flatten();
            global_avatar_url = profile
                .get_static::<AvatarUrl>()
                .ok()
                .flatten()
                .map(|url| url.to_string());
            if let Some(name) = global_display_name
                .as_ref()
                .filter(|name| !name.trim().is_empty())
            {
                effective_display_name = name.clone();
            }
            effective_avatar_url = global_avatar_url.clone();
        }
        Err(error) if canonical_self_request => {
            return Err(format!(
                "Не удалось синхронизировать профиль текущего пользователя: {error}"
            ));
        }
        Err(_) => {}
    }

    // 1. Получаем данные участника комнаты (стандартный и самый надежный способ)
    if let Some(room_id_str) = room_id.as_deref() {
        let ruma_room_id = <&RoomId>::try_from(room_id_str)
            .map_err(|e| format!("Некорректный room_id: {}", e))?
            .to_owned();

        if let Some(room) = client.get_room(&ruma_room_id) {
            if let Some(member) = room
                .get_member(&ruma_user_id)
                .await
                .map_err(|e| e.to_string())?
            {
                let display_name = member.display_name().map(str::to_owned);
                let avatar_url = member.avatar_url().map(|mxc| mxc.to_string());

                let membership = serde_json::to_value(member.membership())
                    .ok()
                    .and_then(|v| v.as_str().map(str::to_owned))
                    .unwrap_or_else(|| format!("{:?}", member.membership()).to_lowercase());

                let pl = member.power_level();
                let npl = member.normalized_power_level();

                let power_level_int = match pl {
                    UserPowerLevel::Infinite => i64::MAX,
                    UserPowerLevel::Int(v) => i64::from(v),
                    _ => -1,
                };

                let normalized_power_level_int = match npl {
                    UserPowerLevel::Infinite => i64::MAX,
                    UserPowerLevel::Int(v) => i64::from(v),
                    _ => -1,
                };

                power_level = power_level_int;
                is_admin = power_level_int >= 100;
                is_moderator = power_level_int >= 50 && power_level_int < 100;

                if let Some(name) = display_name.clone() {
                    effective_display_name = name;
                }
                effective_avatar_url = avatar_url.clone();

                room_member = Some(RoomMemberInfo {
                    room_id: room_id_str.to_string(),
                    display_name,
                    resolved_name: member.name().to_string(),
                    avatar_url,
                    membership,
                    power_level: power_level_int.to_string(),
                    normalized_power_level: normalized_power_level_int.to_string(),
                    power_level_int,
                    normalized_power_level_int,
                    is_ignored: member.is_ignored(),
                    can_invite: member.can_invite(),
                    can_kick: member.can_kick(),
                    can_ban: member.can_ban(),
                    can_redact_own: member.can_redact_own(),
                    can_redact_other: member.can_redact_other(),
                });
            }

            if !is_self {
                if let Some(own_user_id) = client.user_id() {
                    if let Some(viewer) = room
                        .get_member(own_user_id)
                        .await
                        .map_err(|e| e.to_string())?
                    {
                        viewer_power_level = match viewer.power_level() {
                            UserPowerLevel::Infinite => i64::MAX,
                            UserPowerLevel::Int(value) => i64::from(value),
                            _ => -1,
                        };
                        // Matrix requires the acting user to have the action's
                        // configured level and to outrank the target.
                        let outranks_target = viewer_power_level > power_level;
                        viewer_can_kick = viewer.can_kick() && outranks_target;
                        viewer_can_ban = viewer.can_ban() && outranks_target;
                        viewer_can_manage_roles = viewer
                            .can_send_state(StateEventType::RoomPowerLevels)
                            && outranks_target;
                    }
                }
            }
        }
    }

    let details = UserDetails {
        user_id: ruma_user_id.to_string(),
        display_name: effective_display_name,
        global_display_name,
        avatar_url: effective_avatar_url,
        global_avatar_url,
        is_self,
        is_ignored: room_member.as_ref().is_some_and(|member| member.is_ignored),
        can_send_dm,
        power_level,
        is_admin,
        is_moderator,
        room_member,
        viewer_power_level,
        viewer_can_kick,
        viewer_can_ban,
        viewer_can_manage_roles,
    };

    if canonical_self_request {
        if let Some(profile_id) = current_profile_id.as_deref() {
            let display_name = details
                .global_display_name
                .clone()
                .filter(|name| !name.trim().is_empty())
                .or_else(|| Some(details.display_name.clone()));
            let avatar_url = details
                .global_avatar_url
                .clone()
                .or_else(|| details.avatar_url.clone());
            if let Err(error) = update_profile_identity(profile_id, display_name, avatar_url) {
                println!("[Users] Не удалось сохранить identity snapshot: {error}");
            }
        }
    }

    store_user_details(details.clone(), room_id.as_deref()).await;
    Ok(details)
}

pub async fn set_user_ignored(user_id: &str, ignored: bool) -> Result<(), String> {
    let client = get_client().await?;
    let user_id = <&UserId>::try_from(user_id)
        .map_err(|error| format!("Некорректный user_id: {error}"))?
        .to_owned();

    if client.user_id() == Some(user_id.as_ref()) {
        return Err("Нельзя заблокировать самого себя".to_string());
    }

    let result = if ignored {
        client.account().ignore_user(&user_id).await
    } else {
        client.account().unignore_user(&user_id).await
    };
    result.map_err(|error| format!("Не удалось изменить блокировку пользователя: {error}"))?;

    invalidate_user_details(user_id.as_str()).await;
    Ok(())
}

async fn current_user_id() -> Result<String, String> {
    let session = SESSION.lock().await;
    session
        .user_id
        .clone()
        .ok_or_else(|| "Нет активного user_id в текущей сессии".to_string())
}

pub async fn update_own_profile(
    display_name: Option<String>,
    clear_display_name: bool,
) -> Result<UserDetails, String> {
    let client = get_client().await?;
    let current_user_id = current_user_id().await?;

    if clear_display_name || display_name.is_some() {
        let desired_name = if clear_display_name {
            None
        } else {
            display_name.as_deref().map(str::trim)
        };

        client
            .account()
            .set_display_name(desired_name.filter(|value| !value.is_empty()))
            .await
            .map_err(|e| format!("Не удалось обновить display name: {}", e))?;
    }

    invalidate_user_details(&current_user_id).await;
    let details = get_user_details(&current_user_id, None).await?;
    Ok(details)
}

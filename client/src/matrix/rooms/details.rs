use crate::matrix::session::get_client;
use crate::protocol::commands::RoomDetails;
use crate::protocol::commands::RoomUserPowerLevel;
use matrix_sdk::ruma::events::room::guest_access::RoomGuestAccessEventContent;
use matrix_sdk::ruma::events::room::history_visibility::RoomHistoryVisibilityEventContent;
use matrix_sdk::ruma::events::room::join_rules::RoomJoinRulesEventContent;
use matrix_sdk::ruma::events::StateEventType;
use matrix_sdk::ruma::Int;
use matrix_sdk::ruma::MxcUri;
use matrix_sdk::RoomMemberships;
use matrix_sdk::RoomState;

use super::{format_room_state, power_level_to_i64};
fn optional_change_string<'a>(
    changes: &'a serde_json::Map<String, serde_json::Value>,
    key: &str,
) -> Result<Option<&'a str>, String> {
    match changes.get(key) {
        None => Ok(None),
        Some(value) => value
            .as_str()
            .map(Some)
            .ok_or_else(|| format!("Поле {key} должно быть строкой")),
    }
}

pub async fn update_room(room_id: &str, changes: serde_json::Value) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?
        .to_owned();
    let room = client
        .get_room(&room_id)
        .ok_or_else(|| format!("Комната не найдена: {room_id}"))?;
    if room.state() != RoomState::Joined {
        return Err(
            "Редактировать можно только комнату, в которой пользователь состоит".to_string(),
        );
    }
    let changes = changes
        .as_object()
        .ok_or_else(|| "Изменения комнаты должны быть JSON-объектом".to_string())?;
    for key in changes.keys() {
        match key.as_str() {
            "name" | "topic" | "avatar_url" | "join_rule" | "history_visibility"
            | "guest_access" | "user_power_levels" => {}
            _ => return Err(format!("Неизвестное поле редактирования комнаты: {key}")),
        }
    }

    if let Some(name) = optional_change_string(changes, "name")? {
        room.set_name(name.to_owned())
            .await
            .map_err(|error| format!("Не удалось изменить название: {error}"))?;
    }
    if let Some(topic) = optional_change_string(changes, "topic")? {
        room.set_room_topic(topic)
            .await
            .map_err(|error| format!("Не удалось изменить тему: {error}"))?;
    }
    if let Some(avatar_url) = optional_change_string(changes, "avatar_url")? {
        if !avatar_url.is_empty() && !avatar_url.starts_with("mxc://") {
            return Err("Аватар комнаты должен быть ссылкой mxc:// или пустой строкой".to_string());
        }
        if avatar_url.is_empty() {
            room.remove_avatar()
                .await
                .map_err(|error| format!("Не удалось удалить аватар: {error}"))?;
        } else {
            room.set_avatar_url(<&MxcUri>::from(avatar_url), None)
                .await
                .map_err(|error| format!("Не удалось изменить аватар: {error}"))?;
        }
    }
    if let Some(join_rule) = optional_change_string(changes, "join_rule")? {
        if !matches!(
            join_rule,
            "invite" | "public" | "knock" | "restricted" | "knock_restricted"
        ) {
            return Err("Недопустимое правило вступления".to_string());
        }
        let content = serde_json::from_value::<RoomJoinRulesEventContent>(
            serde_json::json!({ "join_rule": join_rule }),
        )
        .map_err(|error| format!("Некорректное правило вступления: {error}"))?;
        room.send_state_event(content)
            .await
            .map_err(|error| format!("Не удалось изменить правило вступления: {error}"))?;
    }
    if let Some(history_visibility) = optional_change_string(changes, "history_visibility")? {
        if !matches!(
            history_visibility,
            "invited" | "joined" | "shared" | "world_readable"
        ) {
            return Err("Недопустимая видимость истории".to_string());
        }
        let content = serde_json::from_value::<RoomHistoryVisibilityEventContent>(
            serde_json::json!({ "history_visibility": history_visibility }),
        )
        .map_err(|error| format!("Некорректная видимость истории: {error}"))?;
        room.send_state_event(content)
            .await
            .map_err(|error| format!("Не удалось изменить видимость истории: {error}"))?;
    }
    if let Some(guest_access) = optional_change_string(changes, "guest_access")? {
        if !matches!(guest_access, "forbidden" | "can_join") {
            return Err("Недопустимый гостевой доступ".to_string());
        }
        let content = serde_json::from_value::<RoomGuestAccessEventContent>(
            serde_json::json!({ "guest_access": guest_access }),
        )
        .map_err(|error| format!("Некорректный гостевой доступ: {error}"))?;
        room.send_state_event(content)
            .await
            .map_err(|error| format!("Не удалось изменить гостевой доступ: {error}"))?;
    }

    if let Some(power_level_changes) = changes.get("user_power_levels") {
        let power_level_changes = power_level_changes
            .as_object()
            .ok_or_else(|| "Права пользователей должны быть JSON-объектом".to_string())?;
        let mut owned_updates = Vec::with_capacity(power_level_changes.len());
        for (user_id, level_value) in power_level_changes {
            let level = level_value.as_i64().ok_or_else(|| {
                format!("Уровень доступа пользователя {user_id} должен быть целым числом")
            })?;
            if level > 100 {
                return Err(format!(
                    "Уровень доступа пользователя {user_id} не может быть больше 100"
                ));
            }
            if level < -100 {
                return Err(format!(
                    "Уровень доступа пользователя {user_id} не может быть меньше -100"
                ));
            }
            let user_id = <&matrix_sdk::ruma::UserId>::try_from(user_id.as_str())
                .map_err(|error| format!("Некорректный Matrix ID пользователя: {error}"))?
                .to_owned();
            let level = Int::try_from(level)
                .map_err(|_| "Уровень доступа выходит за допустимый диапазон Matrix".to_string())?;
            owned_updates.push((user_id, level));
        }
        let borrowed_updates = owned_updates
            .iter()
            .map(|(user_id, level)| (user_id.as_ref(), *level))
            .collect::<Vec<_>>();
        room.update_power_levels(borrowed_updates)
            .await
            .map_err(|error| format!("Не удалось изменить права пользователей: {error}"))?;
    }

    Ok(())
}

pub async fn get_room_details(room_id: &str) -> Result<RoomDetails, String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|e| format!("Некорректный room_id: {}", e))?
        .to_owned();

    let room = client
        .get_room(&room_id)
        .ok_or_else(|| format!("Комната не найдена в локальном состоянии SDK: {}", room_id))?;

    let unread = room.unread_notification_counts();
    // `members_no_sync()` may return an incomplete or empty list when member
    // lazy-loading is enabled. The information dialog needs authoritative
    // counts and power levels, so ask the SDK to synchronize members first and
    // only fall back to the local snapshot if that request fails.
    let mut members = match room.members(RoomMemberships::ACTIVE).await {
        Ok(members) => members,
        Err(error) => {
            eprintln!("[Rooms] Failed to synchronize members: {error}");
            room.members_no_sync(RoomMemberships::ACTIVE)
                .await
                .unwrap_or_default()
        }
    };

    let mut joined_members_count = 0u64;
    let mut invited_members_count = 0u64;
    for member in &members {
        let membership = serde_json::to_value(member.membership())
            .ok()
            .and_then(|value| value.as_str().map(str::to_owned))
            .unwrap_or_else(|| format!("{:?}", member.membership()).to_lowercase());
        match membership.as_str() {
            "join" | "joined" => joined_members_count += 1,
            "invite" | "invited" => invited_members_count += 1,
            _ => {}
        }
    }
    if members.is_empty() {
        joined_members_count = room.joined_members_count();
        invited_members_count = room.invited_members_count();
    }
    let active_members_count = if members.is_empty() {
        room.active_members_count()
    } else {
        members.len() as u64
    };

    members.sort_by(|left, right| {
        power_level_to_i64(right.power_level())
            .cmp(&power_level_to_i64(left.power_level()))
            .then_with(|| left.name().to_lowercase().cmp(&right.name().to_lowercase()))
    });
    let power_levels_truncated = members.len() > 200;
    let mut can_kick_members = false;
    let mut can_ban_members = false;
    let mut can_manage_power_levels = false;
    let mut current_user_power_level = -1;
    if let Some(current_user_id) = client.user_id() {
        if let Some(current_member) = members
            .iter()
            .find(|member| member.user_id() == current_user_id)
        {
            current_user_power_level = power_level_to_i64(current_member.power_level());
            can_kick_members = current_member.can_kick();
            can_ban_members = current_member.can_ban();
            can_manage_power_levels =
                current_member.can_send_state(StateEventType::RoomPowerLevels);
        }
    }
    let user_power_levels = members
        .iter()
        .take(200)
        .map(|member| RoomUserPowerLevel {
            user_id: member.user_id().to_string(),
            display_name: member.name().to_string(),
            avatar_url: member.avatar_url().map(|url| url.to_string()),
            power_level: power_level_to_i64(member.power_level()),
        })
        .collect::<Vec<_>>();

    Ok(RoomDetails {
        room_id: room.room_id().to_string(),
        name: room.name(),
        display_name: room.cached_display_name().map(|d| d.to_string()),
        canonical_alias: room.canonical_alias().map(|a| a.to_string()),
        topic: room.topic(),
        avatar_url: room.avatar_url().map(|mxc| mxc.to_string()),
        room_type: room
            .room_type()
            .map(|kind| format!("{:?}", kind).to_lowercase()),
        room_state: format_room_state(room.state()),
        join_rule: room
            .join_rule()
            .map(|join_rule| join_rule.as_str().to_owned())
            .unwrap_or_else(|| "invite".to_string()),
        history_visibility: room.history_visibility_or_default().as_str().to_owned(),
        guest_access: room.guest_access().as_str().to_owned(),
        is_dm: room.is_direct().await.unwrap_or(false),
        is_space: room.is_space(),
        is_encrypted: room.encryption_settings().is_some(),
        joined_members_count,
        invited_members_count,
        active_members_count,
        direct_targets_count: room.direct_targets_length() as u64,
        unread_notification_count: unread.notification_count,
        unread_highlight_count: unread.highlight_count,
        last_event_timestamp: room.latest_event_timestamp().map(|ts| ts.0.into()),
        user_power_levels,
        power_levels_truncated,
        can_kick_members,
        can_ban_members,
        can_manage_power_levels,
        current_user_power_level,
    })
}

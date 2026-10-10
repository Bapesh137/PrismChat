//! Room operations; stable entry point for listing, membership and administration.
use crate::matrix::session::get_client;
use crate::protocol::commands::RoomInfo;
use matrix_sdk::ruma::events::room::power_levels::UserPowerLevel;
use matrix_sdk::ruma::events::space::child::SpaceChildEventContent;
use matrix_sdk::ruma::events::space::parent::SpaceParentEventContent;
use matrix_sdk::ruma::events::StateEventType;
use matrix_sdk::RoomMemberships;
use matrix_sdk::RoomState;
use std::collections::HashMap;

mod creation;
mod details;
mod directory;
mod members;
mod spaces;
pub use creation::create_room;
pub use details::{get_room_details, update_room};
pub use directory::search_public_rooms;
pub use members::{
    clear_member_snapshots, get_room_members_page, invalidate_member_snapshot, moderate_room_member,
};
pub use spaces::{add_room_to_space, remove_room_from_space};
fn format_room_state(state: matrix_sdk::RoomState) -> String {
    format!("{:?}", state).to_lowercase()
}

pub async fn get_room_list() -> Result<Vec<RoomInfo>, String> {
    let client = get_client().await?;
    let joined_rooms = client.joined_rooms();
    let mut parents_from_spaces: HashMap<String, Vec<String>> = HashMap::new();
    for space in joined_rooms.iter().filter(|room| room.is_space()) {
        for child in space
            .get_state_events_static::<SpaceChildEventContent>()
            .await
            .unwrap_or_default()
            .into_iter()
            .filter_map(|event| event.deserialize().ok())
        {
            if child
                .as_sync()
                .is_some_and(|event| event.as_original().is_none())
            {
                continue;
            }
            parents_from_spaces
                .entry(child.state_key().to_string())
                .or_default()
                .push(space.room_id().to_string());
        }
    }
    let mut rooms = Vec::new();

    let visible_rooms = client
        .rooms()
        .into_iter()
        .filter(|room| matches!(room.state(), RoomState::Joined | RoomState::Invited));

    for room in visible_rooms {
        let room_id = room.room_id().to_string();
        let room_state = format_room_state(room.state());
        let is_joined = room.state() == RoomState::Joined;
        let name = room
            .name()
            .or_else(|| room.cached_display_name().map(|d| d.to_string()));
        let avatar_url = room.avatar_url().map(|mxc| mxc.to_string());
        let topic = room.topic();
        let is_dm = room.is_direct().await.unwrap_or(false);
        let is_space = room.is_space();
        let is_encrypted = room.encryption_settings().is_some();
        let can_edit = if is_joined {
            match client.user_id() {
                Some(current_user_id) => room
                    .get_member_no_sync(current_user_id)
                    .await
                    .ok()
                    .flatten()
                    .map(|member| member.can_send_state(StateEventType::RoomPowerLevels))
                    .unwrap_or(false),
                None => false,
            }
        } else {
            false
        };
        let (dm_avatar_url, direct_user_id, is_ignored) = if is_dm && is_joined {
            room.members_no_sync(RoomMemberships::ACTIVE)
                .await
                .ok()
                .and_then(|members| {
                    let current_user_id = client.user_id()?;
                    members
                        .into_iter()
                        .find(|member| member.user_id() != current_user_id)
                        .map(|member| {
                            (
                                member.avatar_url().map(|mxc| mxc.to_string()),
                                Some(member.user_id().to_string()),
                                member.is_ignored(),
                            )
                        })
                })
                .unwrap_or((None, None, false))
        } else {
            (None, None, false)
        };

        let mut parent_space_ids = if is_joined {
            room.get_state_events_static::<SpaceParentEventContent>()
                .await
                .unwrap_or_default()
                .into_iter()
                .filter_map(|event| event.deserialize().ok())
                .map(|event| event.state_key().to_string())
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        if let Some(parents) = parents_from_spaces.get(&room_id) {
            for parent in parents {
                if !parent_space_ids.contains(parent) {
                    parent_space_ids.push(parent.clone());
                }
            }
        }
        let unread = room.unread_notification_counts();
        // The SDK's locally computed count also covers ordinary messages and
        // is more reliable for encrypted rooms than the server notification
        // counter, which can legitimately contain only push-rule matches.
        let unread_messages = room.num_unread_messages();
        let is_marked_unread = room.is_marked_unread();
        let latest_value = serde_json::to_value(room.latest_event()).unwrap_or_default();
        let last_message = find_text_body(&latest_value);

        rooms.push(RoomInfo {
            room_id: room_id.clone(),
            name: name.or(Some(room_id.clone())),
            avatar_url: dm_avatar_url.or(avatar_url),
            topic,
            last_message,
            last_timestamp: room.latest_event_timestamp().map(|ts| ts.0.into()),
            last_event_id: room.latest_event().event_id().map(|id| id.to_string()),
            unread_count: if is_ignored {
                0
            } else if is_marked_unread {
                unread.notification_count.max(unread_messages).max(1)
            } else {
                unread.notification_count.max(unread_messages)
            },
            is_marked_unread: !is_ignored && is_marked_unread,
            member_count: room.active_members_count(),
            is_dm,
            direct_user_id,
            is_ignored,
            is_space,
            is_voice: room.room_type().as_ref().map(|v| v.as_str())
                == Some(crate::matrix::rtc::VOICE_ROOM_TYPE),
            voice_members: crate::matrix::rtc::participants(&room).await,
            parent_space_ids,
            is_encrypted,
            can_edit,
            room_state,
        });
    }

    // RoomListService owns ordering (local echo, recency, then name). Keep
    // this conversion layer data-only and never re-sort the SDK result.
    Ok(merge_sdk_room_order(
        rooms,
        crate::matrix::sync_loop::ordered_room_ids(),
    ))
}

fn merge_sdk_room_order(mut remaining: Vec<RoomInfo>, sdk_room_ids: Vec<String>) -> Vec<RoomInfo> {
    let mut ordered = Vec::with_capacity(remaining.len());
    for room_id in sdk_room_ids {
        if let Some(index) = remaining.iter().position(|room| room.room_id == room_id) {
            ordered.push(remaining.remove(index));
        }
    }
    // During cached first paint RoomListService may not have emitted its
    // initial Reset yet. Only rooms missing from SDK order receive a stable
    // recency fallback; the next RoomList diff replaces this fallback.
    remaining.sort_by(|left, right| {
        right
            .last_timestamp
            .cmp(&left.last_timestamp)
            .then_with(|| {
                left.name
                    .as_deref()
                    .unwrap_or(&left.room_id)
                    .to_lowercase()
                    .cmp(
                        &right
                            .name
                            .as_deref()
                            .unwrap_or(&right.room_id)
                            .to_lowercase(),
                    )
            })
            .then_with(|| left.room_id.cmp(&right.room_id))
    });
    ordered.extend(remaining);
    ordered
}

fn find_text_body(value: &serde_json::Value) -> Option<String> {
    if let Some(body) = value
        .get("content")
        .and_then(|content| content.get("body"))
        .and_then(|body| body.as_str())
    {
        return Some(body.to_string());
    }

    match value {
        serde_json::Value::Object(map) => map.values().find_map(find_text_body),
        serde_json::Value::Array(values) => values.iter().find_map(find_text_body),
        _ => None,
    }
}

pub async fn leave_room(room_id: &str) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?
        .to_owned();

    let room = client
        .get_room(&room_id)
        .ok_or_else(|| format!("Комната не найдена: {room_id}"))?;

    room.leave()
        .await
        .map_err(|error| format!("Не удалось покинуть комнату: {error}"))
}

pub async fn open_direct_message(
    user_id: &str,
) -> Result<(String, String, Option<String>, bool), String> {
    let client = get_client().await?;
    let user_id = <&matrix_sdk::ruma::UserId>::try_from(user_id)
        .map_err(|error| format!("Некорректный user_id: {error}"))?
        .to_owned();

    if client.user_id() == Some(user_id.as_ref()) {
        return Err("Нельзя создать личный чат с самим собой".to_string());
    }

    let (room, created) = match client.get_dm_room(&user_id) {
        Some(room) => (room, false),
        None => (
            client
                .create_dm(&user_id)
                .await
                .map_err(|error| format!("Не удалось создать личный чат: {error}"))?,
            true,
        ),
    };

    let target_profile = client.account().fetch_user_profile_of(&user_id).await.ok();
    let room_name = target_profile
        .as_ref()
        .and_then(|profile| profile.get("displayname"))
        .and_then(|value| value.as_str())
        .map(str::to_owned)
        .or_else(|| room.name())
        .or_else(|| room.cached_display_name().map(|name| name.to_string()))
        .unwrap_or_else(|| user_id.to_string());
    let avatar_url = target_profile
        .as_ref()
        .and_then(|profile| profile.get("avatar_url"))
        .and_then(|value| value.as_str())
        .map(str::to_owned);

    Ok((room.room_id().to_string(), room_name, avatar_url, created))
}

fn power_level_to_i64(level: UserPowerLevel) -> i64 {
    match level {
        // PrismChat exposes Matrix power levels on the conventional -100..100
        // scale. Newer room versions can represent creators as `Infinite`;
        // render that immutable maximum as 100 in the UI.
        UserPowerLevel::Infinite => 100,
        UserPowerLevel::Int(value) => i64::from(value),
        _ => -1,
    }
}

pub async fn accept_room_invite(room_id: &str) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?
        .to_owned();
    let room = client
        .get_room(&room_id)
        .ok_or_else(|| format!("Приглашённая комната не найдена: {room_id}"))?;
    if room.state() != RoomState::Invited {
        return Ok(());
    }
    client
        .join_room_by_id(&room_id)
        .await
        .map_err(|error| format!("Не удалось принять приглашение: {error}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn room_info(room_id: &str, timestamp: u64) -> RoomInfo {
        RoomInfo {
            room_id: room_id.to_owned(),
            name: Some(room_id.to_owned()),
            avatar_url: None,
            topic: None,
            last_message: None,
            last_timestamp: Some(timestamp),
            last_event_id: None,
            unread_count: 0,
            is_marked_unread: false,
            member_count: 0,
            is_dm: false,
            direct_user_id: None,
            is_ignored: false,
            is_space: false,
            is_voice: false,
            voice_members: Vec::new(),
            parent_space_ids: Vec::new(),
            can_edit: false,
            is_encrypted: false,
            room_state: "joined".to_owned(),
        }
    }

    #[test]
    fn sdk_room_order_wins_and_missing_rooms_use_recency_fallback() {
        let rooms = vec![
            room_info("!old:example.org", 10),
            room_info("!sdk:example.org", 5),
            room_info("!new:example.org", 20),
        ];
        let ordered = merge_sdk_room_order(rooms, vec!["!sdk:example.org".to_owned()]);
        let ids = ordered
            .into_iter()
            .map(|room| room.room_id)
            .collect::<Vec<_>>();
        assert_eq!(
            ids,
            vec!["!sdk:example.org", "!new:example.org", "!old:example.org"]
        );
    }
}

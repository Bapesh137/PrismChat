use crate::matrix::session::current_session_epoch;
use crate::matrix::session::get_client;
use crate::protocol::commands::RoomMemberSummary;
use crate::storage::profile_cache::invalidate_user_details;
use matrix_sdk::ruma::Int;
use matrix_sdk::RoomMemberships;
use matrix_sdk::RoomState;
use std::collections::HashMap;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::sync::LazyLock;
use tokio::sync::Mutex;

use super::power_level_to_i64;
const MEMBER_CURSOR_PREFIX: &str = "prism-members-v1";
const MEMBER_SNAPSHOT_STALE: &str = "MEMBERS_SNAPSHOT_STALE";
// Background prefetch keeps the first page ready for many rooms. Retain enough
// immutable snapshots for a later scroll to continue without restarting most
// rooms, while still putting a firm bound on memory use.
const MAX_MEMBER_SNAPSHOTS: usize = 64;

static NEXT_MEMBER_SNAPSHOT_ID: AtomicU64 = AtomicU64::new(1);
static MEMBER_SNAPSHOTS: LazyLock<Mutex<HashMap<String, MemberSnapshot>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Clone)]
struct MemberSnapshot {
    session_epoch: u64,
    snapshot_id: u64,
    members: Arc<Vec<RoomMemberSummary>>,
}

fn member_cursor(session_epoch: u64, snapshot_id: u64, offset: usize) -> String {
    format!("{MEMBER_CURSOR_PREFIX}:{session_epoch}:{snapshot_id}:{offset}")
}

fn parse_member_cursor(cursor: &str) -> Option<(u64, u64, usize)> {
    let mut parts = cursor.split(':');
    if parts.next()? != MEMBER_CURSOR_PREFIX {
        return None;
    }
    let session_epoch = parts.next()?.parse().ok()?;
    let snapshot_id = parts.next()?.parse().ok()?;
    let offset = parts.next()?.parse().ok()?;
    parts
        .next()
        .is_none()
        .then_some((session_epoch, snapshot_id, offset))
}

pub async fn invalidate_member_snapshot(room_id: &str) {
    MEMBER_SNAPSHOTS.lock().await.remove(room_id);
}

pub async fn clear_member_snapshots() {
    MEMBER_SNAPSHOTS.lock().await.clear();
}

pub async fn moderate_room_member(
    room_id: &str,
    user_id: &str,
    action: &str,
    power_level: Option<i64>,
    reason: Option<&str>,
) -> Result<(), String> {
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?
        .to_owned();
    let user_id = <&matrix_sdk::ruma::UserId>::try_from(user_id)
        .map_err(|error| format!("Некорректный user_id: {error}"))?
        .to_owned();
    if client.user_id() == Some(user_id.as_ref()) {
        return Err("Нельзя применить действие модерации к самому себе".to_string());
    }
    let room = client
        .get_room(&room_id)
        .ok_or_else(|| format!("Комната не найдена: {room_id}"))?;
    if room.state() != RoomState::Joined {
        return Err(
            "Модерация доступна только в комнате, в которой пользователь состоит".to_string(),
        );
    }
    let normalized_reason = reason.map(str::trim).filter(|value| !value.is_empty());
    match action {
        "kick" => room
            .kick_user(&user_id, normalized_reason)
            .await
            .map_err(|error| format!("Не удалось исключить пользователя: {error}"))?,
        "ban" => room
            .ban_user(&user_id, normalized_reason)
            .await
            .map_err(|error| format!("Не удалось заблокировать пользователя: {error}"))?,
        "unban" => room
            .unban_user(&user_id, normalized_reason)
            .await
            .map_err(|error| format!("Не удалось снять блокировку пользователя: {error}"))?,
        "set_power_level" => {
            let level = power_level.ok_or_else(|| "Не указан уровень доступа".to_string())?;
            if !(-100..=100).contains(&level) {
                return Err("Уровень доступа должен быть от -100 до 100".to_string());
            }
            let level = Int::try_from(level)
                .map_err(|_| "Уровень доступа выходит за диапазон Matrix".to_string())?;
            room.update_power_levels(vec![(user_id.as_ref(), level)])
                .await
                .map_err(|error| format!("Не удалось изменить роль пользователя: {error}"))?;
        }
        _ => return Err(format!("Неизвестное действие модерации: {action}")),
    }
    invalidate_user_details(user_id.as_str()).await;
    Ok(())
}

pub async fn get_room_members_page(
    room_id: &str,
    from: Option<String>,
    limit: Option<u32>,
) -> Result<(Vec<RoomMemberSummary>, Option<String>), String> {
    let room_key = room_id.to_owned();
    let epoch = current_session_epoch();
    let (snapshot, offset) = if let Some(cursor) = from.as_deref().filter(|value| !value.is_empty())
    {
        let (cursor_epoch, snapshot_id, offset) = parse_member_cursor(cursor)
            .ok_or_else(|| format!("{MEMBER_SNAPSHOT_STALE}: некорректный cursor"))?;
        let snapshot = MEMBER_SNAPSHOTS
            .lock()
            .await
            .get(&room_key)
            .filter(|snapshot| {
                snapshot.session_epoch == epoch
                    && cursor_epoch == epoch
                    && snapshot.snapshot_id == snapshot_id
            })
            .cloned()
            .ok_or_else(|| format!("{MEMBER_SNAPSHOT_STALE}: список участников обновился"))?;
        (snapshot, offset)
    } else {
        let client = get_client().await?;
        let parsed_room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
            .map_err(|error| format!("Некорректный room_id: {error}"))?;
        let room = client
            .get_room(parsed_room_id)
            .ok_or_else(|| format!("Комната не найдена: {parsed_room_id}"))?;

        // Room::members() is the matrix-sdk API that first calls sync_members()
        // when lazy loading left the local state incomplete. Freeze that full,
        // SDK-owned state once; every continuation page reads this same vector.
        let mut members = room
            .members(RoomMemberships::ACTIVE)
            .await
            .map_err(|error| format!("Не удалось синхронизировать участников: {error}"))?
            .into_iter()
            .map(|member| {
                let event = member.event();
                RoomMemberSummary {
                    user_id: member.user_id().to_string(),
                    display_name: member.name().to_string(),
                    avatar_url: member.avatar_url().map(|url| url.to_string()),
                    membership: serde_json::to_value(member.membership())
                        .ok()
                        .and_then(|value| value.as_str().map(str::to_owned))
                        .unwrap_or_else(|| format!("{:?}", member.membership()).to_lowercase()),
                    role: format!("{:?}", member.suggested_role_for_power_level()).to_lowercase(),
                    power_level: power_level_to_i64(member.power_level()),
                    can_redact_own: member.can_redact_own(),
                    can_redact_other: member.can_redact_other(),
                    membership_event_sender: Some(event.sender().to_string()),
                    membership_event_timestamp: event.origin_server_ts().map(|ts| ts.0.into()),
                }
            })
            .collect::<Vec<_>>();

        members.sort_by(|left, right| {
            right.power_level.cmp(&left.power_level).then_with(|| {
                left.display_name
                    .to_lowercase()
                    .cmp(&right.display_name.to_lowercase())
                    .then_with(|| left.user_id.cmp(&right.user_id))
            })
        });
        if current_session_epoch() != epoch {
            return Err("Сессия изменилась во время загрузки участников".to_owned());
        }
        let snapshot = MemberSnapshot {
            session_epoch: epoch,
            snapshot_id: NEXT_MEMBER_SNAPSHOT_ID.fetch_add(1, Ordering::Relaxed),
            members: Arc::new(members),
        };
        let mut snapshots = MEMBER_SNAPSHOTS.lock().await;
        snapshots.insert(room_key.clone(), snapshot.clone());
        while snapshots.len() > MAX_MEMBER_SNAPSHOTS {
            let victim = snapshots
                .iter()
                .filter(|(candidate, _)| candidate.as_str() != room_key)
                .min_by_key(|(_, snapshot)| snapshot.snapshot_id)
                .map(|(candidate, _)| candidate.clone());
            let Some(victim) = victim else { break };
            snapshots.remove(&victim);
        }
        drop(snapshots);
        (snapshot, 0)
    };

    // Normal scrolling requests 30. A live refresh may request the number of
    // rows already visible so QML can reconcile without collapsing the list.
    let page_size = limit.unwrap_or(25).clamp(1, 10_000) as usize;
    let page = snapshot
        .members
        .iter()
        .skip(offset)
        .take(page_size)
        .cloned()
        .collect::<Vec<_>>();
    let next_offset = offset.saturating_add(page.len());
    let next_batch = (next_offset < snapshot.members.len())
        .then(|| member_cursor(snapshot.session_epoch, snapshot.snapshot_id, next_offset));
    if next_batch.is_none() {
        MEMBER_SNAPSHOTS.lock().await.remove(&room_key);
    }
    Ok((page, next_batch))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn member_cursor_roundtrips_snapshot_identity_and_offset() {
        let cursor = member_cursor(7, 42, 100);
        assert_eq!(parse_member_cursor(&cursor), Some((7, 42, 100)));
    }

    #[test]
    fn legacy_numeric_and_malformed_member_cursors_are_rejected() {
        assert_eq!(parse_member_cursor("100"), None);
        assert_eq!(parse_member_cursor("prism-members-v1:7:42"), None);
        assert_eq!(parse_member_cursor("prism-members-v1:7:42:100:extra"), None);
    }
}

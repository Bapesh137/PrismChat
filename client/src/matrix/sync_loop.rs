use std::{
    collections::{HashSet, VecDeque},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, LazyLock, RwLock,
    },
    time::Duration,
};

use eyeball_im::VectorDiff;
use futures_util::StreamExt;
use matrix_sdk::{
    config::SyncSettings,
    ruma::{
        api::client::filter::{FilterDefinition, RoomEventFilter, RoomFilter},
        events::{
            call::{member::SyncCallMemberEvent, notify::SyncCallNotifyEvent},
            room::{
                encrypted::OriginalSyncRoomEncryptedEvent, member::OriginalSyncRoomMemberEvent,
            },
            rtc::{
                decline::SyncRtcDeclineEvent,
                notification::{NotificationType, SyncRtcNotificationEvent},
            },
            typing::SyncTypingEvent,
            AnySyncMessageLikeEvent,
        },
        serde::Raw,
        MilliSecondsSinceUnixEpoch,
    },
    Client, Room,
};
use matrix_sdk_ui::room_list_service::{filters, RoomListItem, RoomListService};
use serde_json::Value;
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Message;

use crate::{
    matrix::session::{current_session_epoch, get_client, SESSION},
    network::transport::Tx,
    protocol::commands::{QmlResponse, SyncFreshness},
};

#[derive(Default)]
struct EpochRoomOrder {
    epoch: u64,
    room_ids: Vec<String>,
}

#[derive(Clone)]
struct EpochFreshness {
    epoch: u64,
    freshness: SyncFreshness,
}

static ORDERED_ROOM_IDS: LazyLock<RwLock<EpochRoomOrder>> =
    LazyLock::new(|| RwLock::new(EpochRoomOrder::default()));
static ACTIVE_SYNC: LazyLock<Mutex<Option<(u64, Arc<RoomListService>)>>> =
    LazyLock::new(|| Mutex::new(None));
static SYNC_EVENT_TX: Mutex<Option<Tx>> = Mutex::const_new(None);
static SYNC_LOOP_RUNNING: AtomicBool = AtomicBool::new(false);
static REQUESTED_ROOM_SUBSCRIPTION: LazyLock<Mutex<Option<(u64, u64, String)>>> =
    LazyLock::new(|| Mutex::new(None));
static VOICE_ROOM_SUBSCRIPTION: Mutex<Option<(u64, String)>> = Mutex::const_new(None);

pub async fn set_voice_room(room_id: Option<String>) {
    let _guard = ROOM_SUBSCRIPTION_UPDATE.lock().await;
    let epoch = current_session_epoch();
    *VOICE_ROOM_SUBSCRIPTION.lock().await = room_id.map(|id| (epoch, id));
    if let Some((active_epoch, service)) = ACTIVE_SYNC.lock().await.as_ref() {
        if *active_epoch == epoch {
            let text = REQUESTED_ROOM_SUBSCRIPTION
                .lock()
                .await
                .as_ref()
                .filter(|(e, _, _)| *e == epoch)
                .map(|(_, _, id)| id.clone());
            apply_room_subscriptions(service, text.as_deref(), epoch).await;
        }
    }
}

async fn apply_room_subscriptions(service: &RoomListService, text: Option<&str>, epoch: u64) {
    let voice = VOICE_ROOM_SUBSCRIPTION
        .lock()
        .await
        .as_ref()
        .filter(|(e, _)| *e == epoch)
        .map(|(_, id)| id.clone());
    let ids: Vec<&matrix_sdk::ruma::RoomId> = text
        .into_iter()
        .chain(voice.as_deref())
        .filter_map(|id| <&matrix_sdk::ruma::RoomId>::try_from(id).ok())
        .collect();
    service.subscribe_to_rooms(&ids).await;
}

static ROOM_SUBSCRIPTION_UPDATE: Mutex<()> = Mutex::const_new(());
static SYNC_FRESHNESS: LazyLock<RwLock<EpochFreshness>> = LazyLock::new(|| {
    RwLock::new(EpochFreshness {
        epoch: 0,
        freshness: SyncFreshness::Offline,
    })
});
static EVENT_HANDLERS_EPOCH: AtomicU64 = AtomicU64::new(0);
static PENDING_MEMBER_REFRESHES: LazyLock<Mutex<HashSet<(u64, String)>>> =
    LazyLock::new(|| Mutex::new(HashSet::new()));
static PENDING_VOICE_REFRESHES: LazyLock<Mutex<HashSet<(u64, String)>>> =
    LazyLock::new(|| Mutex::new(HashSet::new()));

// Recover MSC4354 sticky RTC events that matrix-sdk 0.18 cannot decode.
static STICKY_HTTP: LazyLock<reqwest::Client> = LazyLock::new(reqwest::Client::new);
static SEEN_STICKY_EVENT_IDS: LazyLock<Mutex<(HashSet<String>, VecDeque<String>)>> =
    LazyLock::new(|| Mutex::new((HashSet::new(), VecDeque::new())));

fn encryption_and_calls_filter() -> FilterDefinition {
    let mut filter = FilterDefinition::ignore_all();
    let mut timeline = RoomEventFilter::default();
    timeline.limit = Some(20u32.into());
    timeline.types = Some(
        [
            "m.rtc.notification",
            "org.matrix.msc4075.rtc.notification",
            "m.call.notify",
            "org.matrix.msc4075.call.notify",
            "m.rtc.decline",
            "org.matrix.msc4310.rtc.decline",
            // Redaction ends an unanswered ring before its expiry.
            "m.room.redaction",
            // Encrypted DMs hide the inner RTC event type from the server.
            "m.room.encrypted",
        ]
        .into_iter()
        .map(str::to_owned)
        .collect(),
    );
    // Incoming calls may belong to rooms outside the room-list window.
    let mut room = RoomFilter::default();
    room.account_data = RoomEventFilter::ignore_all();
    room.ephemeral = RoomEventFilter::ignore_all();
    // Classic sync carries RTC membership outside the Sliding Sync window.
    let mut state = RoomEventFilter::ignore_all();
    state.types = Some(
        ["org.matrix.msc3401.call.member", "m.call.member"]
            .into_iter()
            .map(str::to_owned)
            .collect(),
    );
    room.state = state;
    room.timeline = timeline;
    filter.room = room;
    filter
}

/// Keep the visible room in the SDK's Sliding Sync subscription. The desired
/// room is remembered even while the SDK sync pipeline is being constructed.
pub async fn subscribe_to_room(room_id: &str, request_generation: u64) -> Result<(), String> {
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?
        .to_owned();
    let epoch = current_session_epoch();
    let _update_guard = ROOM_SUBSCRIPTION_UPDATE.lock().await;
    {
        let mut requested = REQUESTED_ROOM_SUBSCRIPTION.lock().await;
        if requested
            .as_ref()
            .is_some_and(|(requested_epoch, generation, _)| {
                *requested_epoch == epoch && *generation > request_generation
            })
        {
            return Ok(());
        }
        *requested = Some((epoch, request_generation, room_id.to_string()));
    }

    let room_list_service = ACTIVE_SYNC
        .lock()
        .await
        .as_ref()
        .filter(|(active_epoch, _)| *active_epoch == epoch)
        .map(|(_, room_list_service)| room_list_service.clone());
    if let Some(room_list_service) = room_list_service {
        apply_room_subscriptions(&room_list_service, Some(room_id.as_str()), epoch).await;
    }
    Ok(())
}

/// Unsubscribe only when this room is still the requested room. This makes an
/// old CloseTimeline harmless if a newer room was opened concurrently.
pub async fn unsubscribe_from_room(room_id: &str, request_generation: u64) {
    let epoch = current_session_epoch();
    let _update_guard = ROOM_SUBSCRIPTION_UPDATE.lock().await;
    let should_clear = {
        let mut requested = REQUESTED_ROOM_SUBSCRIPTION.lock().await;
        let matches =
            requested
                .as_ref()
                .is_some_and(|(requested_epoch, generation, requested_room)| {
                    *requested_epoch == epoch
                        && *generation <= request_generation
                        && requested_room == room_id
                });
        if matches {
            requested.take();
        }
        matches
    };
    if !should_clear {
        return;
    }

    let room_list_service = ACTIVE_SYNC
        .lock()
        .await
        .as_ref()
        .filter(|(active_epoch, _)| *active_epoch == epoch)
        .map(|(_, room_list_service)| room_list_service.clone());
    if let Some(room_list_service) = room_list_service {
        apply_room_subscriptions(&room_list_service, None, epoch).await;
    }
}

pub fn current_sync_freshness() -> SyncFreshness {
    let epoch = current_session_epoch();
    SYNC_FRESHNESS
        .read()
        .ok()
        .filter(|state| state.epoch == epoch)
        .map(|state| state.freshness.clone())
        .unwrap_or(SyncFreshness::Offline)
}

pub fn ordered_room_ids() -> Vec<String> {
    let epoch = current_session_epoch();
    ORDERED_ROOM_IDS
        .read()
        .map(|state| room_ids_for_epoch(&state, epoch))
        .unwrap_or_default()
}

/// Ensure that the one SDK sync pipeline for the active account is running
/// before starting an interactive to-device operation such as SAS.
pub async fn ensure_encryption_sync_running() -> Result<(), String> {
    let epoch = current_session_epoch();
    ACTIVE_SYNC
        .lock()
        .await
        .as_ref()
        .filter(|(active_epoch, _)| *active_epoch == epoch)
        .map(|_| ())
        .ok_or_else(|| "Matrix sync ещё не готов; повторите через несколько секунд".to_owned())?;
    Ok(())
}

/// Local-only diagnostic snapshot. It performs no network request and never
/// includes credentials or crypto material.
pub async fn diagnostic_state() -> String {
    let epoch = current_session_epoch();
    let active_epoch = ACTIVE_SYNC
        .lock()
        .await
        .as_ref()
        .map(|(active_epoch, _)| *active_epoch);
    let Some(active_epoch) = active_epoch else {
        return format!("missing(current_epoch={epoch})");
    };
    format!(
        "{:?}(current_epoch={epoch}, active_epoch={active_epoch})",
        current_sync_freshness()
    )
}

fn room_ids_for_epoch(state: &EpochRoomOrder, epoch: u64) -> Vec<String> {
    if state.epoch == epoch {
        state.room_ids.clone()
    } else {
        Vec::new()
    }
}

async fn event_tx() -> Option<Tx> {
    SYNC_EVENT_TX.lock().await.clone()
}

async fn emit_freshness(epoch: u64, freshness: SyncFreshness) {
    if current_session_epoch() != epoch {
        return;
    }
    if let Ok(mut state) = SYNC_FRESHNESS.write() {
        if current_session_epoch() != epoch {
            return;
        }
        state.epoch = epoch;
        state.freshness = freshness.clone();
    }
    let response = QmlResponse::SyncFreshnessChanged {
        session_epoch: epoch,
        freshness,
    };
    if let (Some(tx), Ok(json)) = (event_tx().await, serde_json::to_string(&response)) {
        let _ = tx.lock().await.send(Message::Text(json.into())).await;
    }
}

async fn emit_voice_participants(room: &Room, epoch: u64) {
    if current_session_epoch() != epoch {
        return;
    }
    let response = QmlResponse::VoiceParticipantsChanged {
        session_epoch: epoch,
        room_id: room.room_id().to_string(),
        participants: crate::matrix::rtc::participants(room).await,
    };
    if let (Some(event_tx), Ok(json)) = (event_tx().await, serde_json::to_string(&response)) {
        let _ = event_tx.lock().await.send(Message::Text(json.into())).await;
    }
}

async fn emit_rooms_changed(epoch: u64, rooms: &[Room], initial: bool) {
    if current_session_epoch() != epoch {
        return;
    }
    if let Ok(mut ordered) = ORDERED_ROOM_IDS.write() {
        if current_session_epoch() != epoch {
            return;
        }
        ordered.epoch = epoch;
        ordered.room_ids = rooms
            .iter()
            .map(|room| room.room_id().to_string())
            .collect();
    }
    let changed_room_ids = rooms
        .iter()
        .map(|room| room.room_id().to_string())
        .collect::<Vec<_>>();
    let event = serde_json::json!({
        "type": "sync_completed",
        "session_epoch": epoch,
        "initial": initial,
        "changed_room_ids": changed_room_ids,
        "identity_changed": initial,
    });
    if let Some(tx) = event_tx().await {
        let _ = tx
            .lock()
            .await
            .send(Message::Text(event.to_string().into()))
            .await;
    }
}

fn apply_room_diffs(rooms: &mut Vec<Room>, diffs: Vec<VectorDiff<RoomListItem>>) {
    for diff in diffs {
        match diff {
            VectorDiff::Append { values } => {
                rooms.extend(values.into_iter().map(RoomListItem::into_inner));
            }
            VectorDiff::Clear => rooms.clear(),
            VectorDiff::PushFront { value } => rooms.insert(0, value.into_inner()),
            VectorDiff::PushBack { value } => rooms.push(value.into_inner()),
            VectorDiff::PopFront => {
                if !rooms.is_empty() {
                    rooms.remove(0);
                }
            }
            VectorDiff::PopBack => {
                rooms.pop();
            }
            VectorDiff::Insert { index, value } => {
                rooms.insert(index.min(rooms.len()), value.into_inner());
            }
            VectorDiff::Set { index, value } => {
                if index < rooms.len() {
                    rooms[index] = value.into_inner();
                }
            }
            VectorDiff::Remove { index } => {
                if index < rooms.len() {
                    rooms.remove(index);
                }
            }
            VectorDiff::Truncate { length } => rooms.truncate(length),
            VectorDiff::Reset { values } => {
                *rooms = values.into_iter().map(RoomListItem::into_inner).collect();
            }
        }
    }
}

async fn handle_rtc_notification_event(event: SyncRtcNotificationEvent, room: Room, epoch: u64) {
    if current_session_epoch() != epoch || room.state() != matrix_sdk::RoomState::Joined {
        return;
    }
    let Some(event) = event.as_original() else {
        return;
    };
    let own_user_id = room.own_user_id();
    if event.sender == own_user_id || event.content.notification_type != NotificationType::Ring {
        return;
    }
    if let Some(mentions) = &event.content.mentions {
        if !mentions.room
            && !mentions.user_ids.contains(own_user_id)
            && !crate::matrix::rtc::is_direct_call_room(&room).await
        {
            return;
        }
    }
    let expires = event.content.expiration_ts(event.origin_server_ts, None);
    if expires <= MilliSecondsSinceUnixEpoch::now() {
        return;
    }
    eprintln!(
        "[Voice] incoming m.rtc.notification room={} sender={}",
        room.room_id(),
        event.sender
    );
    let member = room.get_member_no_sync(&event.sender).await.ok().flatten();
    let room_name = room
        .display_name()
        .await
        .map(|name| name.to_string())
        .unwrap_or_else(|_| room.room_id().to_string());
    let response = QmlResponse::VoiceIncoming {
        session_epoch: epoch,
        room_id: room.room_id().to_string(),
        room_name,
        caller_user_id: event.sender.to_string(),
        caller_name: member
            .as_ref()
            .and_then(|m| m.display_name())
            .unwrap_or(event.sender.as_str())
            .to_owned(),
        caller_avatar_url: member.and_then(|m| m.avatar_url().map(ToString::to_string)),
        notification_event_id: event.event_id.to_string(),
        expires_at: expires.get().into(),
    };
    if let (Some(event_tx), Ok(json)) = (event_tx().await, serde_json::to_string(&response)) {
        let _ = event_tx.lock().await.send(Message::Text(json.into())).await;
    }
}

async fn handle_call_notify_event(event: SyncCallNotifyEvent, room: Room, epoch: u64) {
    if current_session_epoch() != epoch || room.state() != matrix_sdk::RoomState::Joined {
        return;
    }
    let Some(event) = event.as_original() else {
        return;
    };
    let own_user_id = room.own_user_id();
    if event.sender == own_user_id || event.content.notify_type != NotificationType::Ring {
        return;
    }
    if !event.content.mentions.room
        && !event.content.mentions.user_ids.contains(own_user_id)
        && !crate::matrix::rtc::is_direct_call_room(&room).await
    {
        return;
    }

    // m.call.notify lacks a lifetime; apply the normal ringing window.
    let origin_ts: u64 = event.origin_server_ts.get().into();
    let now: u64 = MilliSecondsSinceUnixEpoch::now().get().into();
    let expires_at = origin_ts.saturating_add(90_000);
    if expires_at <= now {
        return;
    }
    eprintln!(
        "[Voice] incoming m.call.notify room={} sender={}",
        room.room_id(),
        event.sender
    );
    let member = room.get_member_no_sync(&event.sender).await.ok().flatten();
    let room_name = room
        .display_name()
        .await
        .map(|name| name.to_string())
        .unwrap_or_else(|_| room.room_id().to_string());
    let response = QmlResponse::VoiceIncoming {
        session_epoch: epoch,
        room_id: room.room_id().to_string(),
        room_name,
        caller_user_id: event.sender.to_string(),
        caller_name: member
            .as_ref()
            .and_then(|m| m.display_name())
            .unwrap_or(event.sender.as_str())
            .to_owned(),
        caller_avatar_url: member.and_then(|m| m.avatar_url().map(ToString::to_string)),
        notification_event_id: event.event_id.to_string(),
        expires_at,
    };
    if let (Some(event_tx), Ok(json)) = (event_tx().await, serde_json::to_string(&response)) {
        let _ = event_tx.lock().await.send(Message::Text(json.into())).await;
    }
}

async fn handle_rtc_decline_event(event: SyncRtcDeclineEvent, room: Room, epoch: u64) {
    if current_session_epoch() != epoch {
        return;
    }
    let Some(event) = event.as_original() else {
        return;
    };
    if event.sender == room.own_user_id() {
        return;
    }
    let response = QmlResponse::VoiceIncomingEnded {
        session_epoch: epoch,
        room_id: room.room_id().to_string(),
        notification_event_id: event.content.relates_to.event_id.to_string(),
        reason: "declined".into(),
    };
    if let (Some(event_tx), Ok(json)) = (event_tx().await, serde_json::to_string(&response)) {
        let _ = event_tx.lock().await.send(Message::Text(json.into())).await;
    }
}

async fn handle_room_redaction_event(
    event: matrix_sdk::ruma::events::room::redaction::SyncRoomRedactionEvent,
    room: Room,
    epoch: u64,
) {
    if current_session_epoch() != epoch {
        return;
    }
    let Some(event) = event.as_original() else {
        return;
    };
    let Some(redacted_event_id) = event.redacts.as_ref().or(event.content.redacts.as_ref()) else {
        return;
    };
    let response = QmlResponse::VoiceIncomingEnded {
        session_epoch: epoch,
        room_id: room.room_id().to_string(),
        notification_event_id: redacted_event_id.to_string(),
        reason: "notification_redacted".into(),
    };
    if let (Some(event_tx), Ok(json)) = (event_tx().await, serde_json::to_string(&response)) {
        let _ = event_tx.lock().await.send(Message::Text(json.into())).await;
    }
}

async fn remember_sticky_event(event_id: &str) -> bool {
    let mut seen = SEEN_STICKY_EVENT_IDS.lock().await;
    let (ids, order) = &mut *seen;
    if !ids.insert(event_id.to_owned()) {
        return false;
    }
    order.push_back(event_id.to_owned());
    while order.len() > 512 {
        if let Some(old) = order.pop_front() {
            ids.remove(&old);
        }
    }
    true
}

fn sticky_sync_filter() -> String {
    // Early Synapse MSC4354 breaks when ephemeral EDUs are explicitly filtered.
    serde_json::json!({
        "presence": { "types": [] },
        "account_data": { "types": [] },
        "room": {
            "timeline": {
                "limit": 1,
                "types": [
                    "m.room.encrypted",
                    "m.rtc.notification",
                    "org.matrix.msc4075.rtc.notification",
                    "m.call.notify",
                    "org.matrix.msc4075.call.notify",
                    "m.rtc.decline",
                    "org.matrix.msc4310.rtc.decline",
                    "m.room.redaction",
                    "org.matrix.msc4143.rtc.member"
                ]
            },
            "state": { "types": [] },
            "account_data": { "types": [] }
        }
    })
    .to_string()
}

async fn process_sticky_event(client: &Client, room_id: &str, mut event: Value, epoch: u64) {
    if current_session_epoch() != epoch {
        return;
    }
    let Ok(room_id_ref) = <&matrix_sdk::ruma::RoomId>::try_from(room_id) else {
        return;
    };
    let Some(room) = client.get_room(room_id_ref) else {
        return;
    };

    let sticky_info = event.get("msc4354_sticky").cloned();
    if event.get("type").and_then(Value::as_str) == Some("m.room.encrypted") {
        let raw: Raw<OriginalSyncRoomEncryptedEvent> = match serde_json::from_value(event) {
            Ok(raw) => raw,
            Err(error) => {
                eprintln!("[VoiceSticky] invalid encrypted event room={room_id}: {error}");
                return;
            }
        };
        let decrypted = match room.decrypt_event(&raw, None).await {
            Ok(event) => event,
            Err(error) => {
                eprintln!("[VoiceSticky] decrypt failed room={room_id}: {error}");
                return;
            }
        };
        if decrypted.kind.is_utd() {
            eprintln!(
                "[VoiceSticky] unable to decrypt event room={room_id}; will retry while sticky"
            );
            return;
        }
        event = match serde_json::from_str(decrypted.raw().json().get()) {
            Ok(event) => event,
            Err(error) => {
                eprintln!("[VoiceSticky] decrypted JSON invalid room={room_id}: {error}");
                return;
            }
        };
        if let (Some(sticky_info), Some(object)) = (sticky_info, event.as_object_mut()) {
            object.insert("msc4354_sticky".to_owned(), sticky_info);
        }
    }

    let event_type = event
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or("<unknown>")
        .to_owned();
    let event_id = event
        .get("event_id")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();

    // Forward sticky membership to Element Call through the Widget API.
    if event_type == "org.matrix.msc4143.rtc.member" {
        crate::matrix::rtc::forward_sticky_membership_to_widget(&room, &event, epoch).await;

        if let Some((event_key, expires_at_ms, changed)) =
            crate::matrix::rtc::observe_sticky_participant(&room, &event).await
        {
            if changed {
                emit_voice_participants(&room, epoch).await;
                let expiry_room = room.clone();
                let expiry_room_id = room_id.to_owned();
                tokio::spawn(async move {
                    let now_ms = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis()
                        .min(u64::MAX as u128) as u64;
                    let wait_ms = expires_at_ms.saturating_sub(now_ms);
                    tokio::time::sleep(Duration::from_millis(wait_ms.saturating_add(25))).await;
                    if current_session_epoch() != epoch {
                        return;
                    }
                    if crate::matrix::rtc::expire_sticky_participant(
                        &expiry_room_id,
                        &event_key,
                        expires_at_ms,
                        epoch,
                    )
                    .await
                    {
                        emit_voice_participants(&expiry_room, epoch).await;
                    }
                });
            }
        }
    }

    // The raw-sync sidecar supplies MSC4354/MSC4407 data missing from the SDK.

    if !event_id.is_empty() && !remember_sticky_event(&event_id).await {
        return;
    }

    eprintln!(
        "[VoiceSticky] received room={room_id} type={event_type} event={}",
        if event_id.is_empty() {
            "<none>"
        } else {
            &event_id
        }
    );

    match event_type.as_str() {
        "m.rtc.notification" | "org.matrix.msc4075.rtc.notification" => {
            match serde_json::from_value::<SyncRtcNotificationEvent>(event) {
                Ok(event) => handle_rtc_notification_event(event, room, epoch).await,
                Err(error) => eprintln!(
                    "[VoiceSticky] cannot decode RTC notification room={room_id}: {error}"
                ),
            }
        }
        "m.call.notify" | "org.matrix.msc4075.call.notify" => {
            match serde_json::from_value::<SyncCallNotifyEvent>(event) {
                Ok(event) => handle_call_notify_event(event, room, epoch).await,
                Err(error) => eprintln!(
                    "[VoiceSticky] cannot decode legacy call notify room={room_id}: {error}"
                ),
            }
        }
        "m.rtc.decline" | "org.matrix.msc4310.rtc.decline" => {
            match serde_json::from_value::<SyncRtcDeclineEvent>(event) {
                Ok(event) => handle_rtc_decline_event(event, room, epoch).await,
                Err(error) => {
                    eprintln!("[VoiceSticky] cannot decode RTC decline room={room_id}: {error}")
                }
            }
        }
        // Keep a diagnostic marker for remote sticky membership.
        "org.matrix.msc4143.rtc.member" => {
            eprintln!("[VoiceSticky] MatrixRTC membership visible room={room_id}");
        }
        _ => {}
    }
}

async fn read_sticky_events_for_sync_window(
    client: &Client,
    since: Option<&str>,
    epoch: u64,
) -> Result<Option<String>, String> {
    let session = client
        .matrix_auth()
        .session()
        .ok_or_else(|| "нет Matrix access token для sticky sync".to_owned())?;
    let url = format!(
        "{}/_matrix/client/v3/sync",
        client.homeserver().as_str().trim_end_matches('/')
    );
    let filter = sticky_sync_filter();
    let mut request = STICKY_HTTP
        .get(url)
        .bearer_auth(session.tokens.access_token)
        .query(&[("timeout", "0"), ("filter", filter.as_str())]);
    if let Some(since) = since {
        request = request.query(&[("since", since)]);
    }

    let response = request
        .send()
        .await
        .map_err(|error| format!("sticky /sync request failed: {error}"))?;
    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|error| format!("sticky /sync body failed: {error}"))?;
    if !status.is_success() {
        let body = body.chars().take(512).collect::<String>();
        return Err(format!("sticky /sync HTTP {status}: {body}"));
    }
    let response: Value = serde_json::from_str(&body)
        .map_err(|error| format!("sticky /sync JSON failed: {error}"))?;
    let next_batch = response
        .get("next_batch")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let Some(joined) = response.pointer("/rooms/join").and_then(Value::as_object) else {
        return Ok(next_batch);
    };

    for (room_id, room) in joined {
        let Some(events) = room
            .pointer("/msc4354_sticky/events")
            .and_then(Value::as_array)
        else {
            continue;
        };
        for event in events {
            process_sticky_event(client, room_id, event.clone(), epoch).await;
        }
    }
    Ok(next_batch)
}

async fn install_sdk_event_handlers(client: &Client, epoch: u64) {
    if EVENT_HANDLERS_EPOCH.swap(epoch, Ordering::AcqRel) == epoch {
        return;
    }
    crate::matrix::rooms::clear_member_snapshots().await;
    client.add_event_handler(
        move |_event: OriginalSyncRoomMemberEvent, room: Room| async move {
            if current_session_epoch() != epoch {
                return;
            }
            let room_id = room.room_id().to_string();
            crate::matrix::rooms::invalidate_member_snapshot(&room_id).await;
            let refresh_key = (epoch, room_id.clone());
            if !PENDING_MEMBER_REFRESHES
                .lock()
                .await
                .insert(refresh_key.clone())
            {
                return;
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
            PENDING_MEMBER_REFRESHES.lock().await.remove(&refresh_key);
            if current_session_epoch() != epoch {
                return;
            }
            let event = serde_json::json!({
                "type": "room_members_changed",
                "session_epoch": epoch,
                "room_id": room_id,
            });
            if let Some(event_tx) = event_tx().await {
                let _ = event_tx
                    .lock()
                    .await
                    .send(Message::Text(event.to_string().into()))
                    .await;
            }
        },
    );
    client.add_event_handler(move |_event: SyncCallMemberEvent, room: Room| async move {
        if current_session_epoch() != epoch {
            return;
        }
        let room_id = room.room_id().to_string();
        let refresh_key = (epoch, room_id.clone());
        if !PENDING_VOICE_REFRESHES
            .lock()
            .await
            .insert(refresh_key.clone())
        {
            return;
        }
        // Let the SDK apply state and coalesce membership bursts.
        tokio::time::sleep(Duration::from_millis(120)).await;
        PENDING_VOICE_REFRESHES.lock().await.remove(&refresh_key);
        if current_session_epoch() != epoch {
            return;
        }
        emit_voice_participants(&room, epoch).await;
    });
    client.add_event_handler(move |event: SyncTypingEvent, room: Room| async move {
        if current_session_epoch() != epoch {
            return;
        }
        let client = room.client();
        let own_user_id = client.user_id().map(ToString::to_string);
        let ignored_user_ids = crate::matrix::users::ignored_user_ids(&client).await;
        if current_session_epoch() != epoch {
            return;
        }
        let user_ids = event
            .content
            .user_ids
            .into_iter()
            .map(|user_id| user_id.to_string())
            .filter(|user_id| own_user_id.as_deref() != Some(user_id.as_str()))
            .filter(|user_id| !ignored_user_ids.contains(user_id))
            .collect();
        let response = QmlResponse::TypingUsersChanged {
            session_epoch: epoch,
            room_id: room.room_id().to_string(),
            user_ids,
        };
        if let (Some(event_tx), Ok(json)) = (event_tx().await, serde_json::to_string(&response)) {
            let _ = event_tx.lock().await.send(Message::Text(json.into())).await;
        }
    });
    // Catch call notifications before DM and mention filtering.
    client.add_event_handler(
        move |event: AnySyncMessageLikeEvent, room: Room| async move {
            match event {
                AnySyncMessageLikeEvent::RtcNotification(event) => {
                    eprintln!("[Voice] synced m.rtc.notification room={}", room.room_id());
                    handle_rtc_notification_event(event, room, epoch).await;
                }
                AnySyncMessageLikeEvent::CallNotify(event) => {
                    eprintln!("[Voice] synced m.call.notify room={}", room.room_id());
                    handle_call_notify_event(event, room, epoch).await;
                }
                AnySyncMessageLikeEvent::RtcDecline(event) => {
                    eprintln!("[Voice] synced m.rtc.decline room={}", room.room_id());
                    handle_rtc_decline_event(event, room, epoch).await;
                }
                AnySyncMessageLikeEvent::RoomRedaction(event) => {
                    handle_room_redaction_event(event, room, epoch).await;
                }
                _ => {}
            }
        },
    );
}

async fn run_session(epoch: u64) -> Result<(), String> {
    emit_freshness(epoch, SyncFreshness::Restoring).await;
    let client = get_client().await?;
    eprintln!(
        "[Sync] build epoch={epoch} device={}",
        client.device_id().map(|id| id.as_str()).unwrap_or("<none>")
    );
    install_sdk_event_handlers(&client, epoch).await;

    // Sliding Sync owns the room list; classic sync carries E2EE and call events.
    let room_list_service = Arc::new(
        RoomListService::new_with(client.clone(), true, "room-list", 1)
            .await
            .map_err(|error| format!("Не удалось создать SDK RoomListService: {error}"))?,
    );
    let room_list = room_list_service
        .all_rooms()
        .await
        .map_err(|error| format!("Не удалось открыть SDK RoomList: {error}"))?;
    let (room_diffs, controller) = room_list.entries_with_dynamic_adapters(10_000);
    if !controller.set_filter(Box::new(filters::new_filter_non_left())) {
        return Err("SDK RoomList не принял фильтр комнат".to_owned());
    }
    let mut room_diffs = Box::pin(room_diffs);
    *ACTIVE_SYNC.lock().await = Some((epoch, room_list_service.clone()));

    {
        // A room selected during sync startup must win.
        let _update_guard = ROOM_SUBSCRIPTION_UPDATE.lock().await;
        let requested_room = REQUESTED_ROOM_SUBSCRIPTION
            .lock()
            .await
            .as_ref()
            .filter(|(requested_epoch, _, _)| *requested_epoch == epoch)
            .map(|(_, _, room_id)| room_id.clone());
        apply_room_subscriptions(&room_list_service, requested_room.as_deref(), epoch).await;
    }

    let room_sync = room_list_service.sync();
    let mut room_sync = Box::pin(room_sync);
    let encryption_sync_settings = SyncSettings::new()
        .filter(encryption_and_calls_filter().into())
        .ignore_timeout_on_first_sync(true)
        .timeout(Duration::from_secs(30));
    let encryption_sync = client.sync_stream(encryption_sync_settings).await;
    let mut encryption_sync = Box::pin(encryption_sync);

    let mut rooms = Vec::new();
    let mut first_snapshot = true;
    let mut room_sync_ready = false;
    let mut encryption_sync_ready = false;
    let mut live_emitted = false;
    let mut sticky_since: Option<String> = None;
    let mut sticky_tick = tokio::time::interval(Duration::from_secs(3));
    sticky_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    eprintln!("[Sync] room-list + classic E2EE sync started epoch={epoch}");
    eprintln!("[VoiceSticky] MSC4354 compatibility reader enabled (matrix-sdk 0.18)");
    loop {
        tokio::select! {
            update = room_sync.next() => {
                match update {
                    Some(Ok(())) => room_sync_ready = true,
                    Some(Err(error)) => return Err(format!("SDK room-list sync остановлен: {error}")),
                    None => return Ok(()),
                }
            }
            update = encryption_sync.next() => {
                match update {
                    Some(Ok(_response)) => {
                        encryption_sync_ready = true;
                    }
                    Some(Err(error)) => return Err(format!("SDK E2EE /sync остановлен: {error}")),
                    None => return Ok(()),
                }
            }
            diffs = room_diffs.next() => {
                let Some(diffs) = diffs else { return Ok(()); };
                apply_room_diffs(&mut rooms, diffs);
                emit_rooms_changed(epoch, &rooms, first_snapshot).await;
                first_snapshot = false;
            }
            _ = sticky_tick.tick() => {
                // Poll dropped MSC4354 data separately for timely incoming rings.
                match read_sticky_events_for_sync_window(
                    &client,
                    sticky_since.as_deref(),
                    epoch,
                )
                .await
                {
                    Ok(next_batch) => sticky_since = next_batch,
                    Err(error) => eprintln!("[VoiceSticky] {error}"),
                }
            }
            _ = tokio::time::sleep(Duration::from_millis(500)) => {
                if current_session_epoch() != epoch {
                    let _ = room_list_service.stop_sync();
                    return Ok(());
                }
            }
        }
        if !live_emitted && room_sync_ready && encryption_sync_ready {
            live_emitted = true;
            eprintln!("[Sync] state=running epoch={epoch}");
            emit_freshness(epoch, SyncFreshness::Live).await;
        }
    }
}

pub async fn start_sync_loop(tx: Tx) {
    // IPC reconnects reuse the session's single sync pipeline.
    *SYNC_EVENT_TX.lock().await = Some(tx);
    if SYNC_LOOP_RUNNING.swap(true, Ordering::AcqRel) {
        eprintln!(
            "[Sync] IPC reattached; reusing existing pipeline ({})",
            diagnostic_state().await
        );
        return;
    }
    eprintln!("[Sync] single sync runner created");

    loop {
        let active = {
            let session = SESSION.lock().await;
            session.token.is_some() && session.user_id.is_some() && session.server.is_some()
        };
        if !active {
            if let Some((_, room_list_service)) = ACTIVE_SYNC.lock().await.take() {
                let _ = room_list_service.stop_sync();
            }
            REQUESTED_ROOM_SUBSCRIPTION.lock().await.take();
            let epoch = current_session_epoch();
            if let Ok(mut rooms) = ORDERED_ROOM_IDS.write() {
                rooms.epoch = epoch;
                rooms.room_ids.clear();
            }
            if let Ok(mut freshness) = SYNC_FRESHNESS.write() {
                freshness.epoch = epoch;
                freshness.freshness = SyncFreshness::Offline;
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
            continue;
        }

        let epoch = current_session_epoch();
        if !crate::matrix::e2ee::observers_ready(epoch).await {
            // Install observers before consuming one-shot verification events.
            tokio::time::sleep(Duration::from_millis(50)).await;
            continue;
        }
        if let Err(error) = run_session(epoch).await {
            eprintln!("[Sync] {error}");
            emit_freshness(epoch, SyncFreshness::Offline).await;
        }
        let finished_service = {
            let mut active = ACTIVE_SYNC.lock().await;
            if active
                .as_ref()
                .is_some_and(|(active_epoch, _)| *active_epoch == epoch)
            {
                active
                    .take()
                    .map(|(_, room_list_service)| room_list_service)
            } else {
                None
            }
        };
        if let Some(room_list_service) = finished_service {
            let _ = room_list_service.stop_sync();
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_order_is_stable() {
        let mut rooms = Vec::new();
        apply_room_diffs(&mut rooms, vec![VectorDiff::Clear]);
        assert!(rooms.is_empty());
    }

    #[test]
    fn scoped_room_order_never_crosses_session_epoch() {
        let state = EpochRoomOrder {
            epoch: 7,
            room_ids: vec!["!one:example.org".to_owned()],
        };
        assert_eq!(
            room_ids_for_epoch(&state, 7),
            vec!["!one:example.org".to_owned()]
        );
        assert!(room_ids_for_epoch(&state, 8).is_empty());
    }

    #[test]
    fn classic_sync_listens_for_calls_in_every_room() {
        let json = serde_json::to_value(encryption_and_calls_filter()).unwrap();
        assert!(json["room"].get("rooms").is_none());
        assert_eq!(json["room"]["timeline"]["limit"], 20);
        let types = json["room"]["timeline"]["types"].as_array().unwrap();
        for event_type in [
            "m.rtc.notification",
            "org.matrix.msc4075.rtc.notification",
            "m.call.notify",
            "org.matrix.msc4075.call.notify",
            "m.rtc.decline",
            "org.matrix.msc4310.rtc.decline",
            "m.room.redaction",
            "m.room.encrypted",
        ] {
            assert!(types.iter().any(|value| value == event_type));
        }
        let state_types = json["room"]["state"]["types"].as_array().unwrap();
        for event_type in ["m.call.member", "org.matrix.msc3401.call.member"] {
            assert!(state_types.iter().any(|value| value == event_type));
        }
    }
}

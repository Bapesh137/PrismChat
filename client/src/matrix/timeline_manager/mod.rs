//! Timeline ownership, generation guards, subscriptions and pagination.
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, LazyLock},
    time::Instant,
};

use futures_util::StreamExt;
use matrix_sdk::ruma::EventId;
use matrix_sdk_ui::timeline::{RoomExt, Timeline, TimelineFocus, TimelineReadReceiptTracking};
use tokio::{sync::Mutex, task::JoinHandle};
use tokio_tungstenite::tungstenite::Message as SocketMessage;

use crate::{
    matrix::session::{current_session_epoch, get_client},
    network::transport::Tx,
    protocol::commands::{MessageInfo, QmlResponse, SyncFreshness},
};

mod actions;
mod serialization;
mod thread_reads;
mod threads;
#[cfg(test)]
use actions::read_receipts;
pub use actions::{
    edit_message, mark_as_read, redact_message, retry_message, send_message, set_marked_unread,
    toggle_reaction,
};
use serialization::{timeline_diff_info, timeline_item_info};
pub use thread_reads::mark_room_threads_read;
pub use threads::{mark_thread_read, room_threads, thread_messages};

const MAX_MANAGED_TIMELINES: usize = 4;
const PREVIEW_TIMELINE_CURSOR_PREFIX: &str = "sdk-timeline-preview-v1:";

struct ManagedTimeline {
    timeline: Arc<Timeline>,
}

#[derive(Default)]
struct TimelineManagerState {
    session_epoch: u64,
    timelines: HashMap<String, ManagedTimeline>,
    confirmed_thread_reads: HashMap<(String, String), HashSet<String>>,
    thread_timelines: HashMap<String, Arc<Timeline>>,
    creation_locks: HashMap<String, Arc<Mutex<()>>>,
    last_used: HashMap<String, Instant>,
    subscriptions: HashMap<String, JoinHandle<()>>,
    generations: HashMap<String, u64>,
    latest_open_request: Option<(u64, String)>,
}

static TIMELINE_MANAGER: LazyLock<Mutex<TimelineManagerState>> =
    LazyLock::new(|| Mutex::new(TimelineManagerState::default()));

pub async fn reset() {
    let mut state = TIMELINE_MANAGER.lock().await;
    for (_, task) in state.subscriptions.drain() {
        task.abort();
    }
    state.timelines.clear();
    state.thread_timelines.clear();
    state.confirmed_thread_reads.clear();
    state.creation_locks.clear();
    state.last_used.clear();
    state.generations.clear();
    state.latest_open_request = None;
    state.session_epoch = current_session_epoch();
}

pub(crate) async fn get_or_create_timeline(room_id: &str) -> Result<Arc<Timeline>, String> {
    let epoch = current_session_epoch();
    let creation_lock = {
        let mut state = TIMELINE_MANAGER.lock().await;
        if state.session_epoch != epoch {
            for (_, task) in state.subscriptions.drain() {
                task.abort();
            }
            state.timelines.clear();
            state.thread_timelines.clear();
            state.confirmed_thread_reads.clear();
            state.creation_locks.clear();
            state.last_used.clear();
            state.generations.clear();
            state.latest_open_request = None;
            state.session_epoch = epoch;
        }
        if let Some(managed) = state.timelines.get(room_id) {
            let timeline = managed.timeline.clone();
            state.last_used.insert(room_id.to_owned(), Instant::now());
            return Ok(timeline);
        }
        state
            .creation_locks
            .entry(room_id.to_owned())
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    };
    let _creation_guard = creation_lock.lock().await;

    // Recheck after waiting for the per-room creation lock.
    {
        let mut state = TIMELINE_MANAGER.lock().await;
        if state.session_epoch != epoch {
            return Err("Сессия изменилась до создания Timeline".to_owned());
        }
        if let Some(managed) = state.timelines.get(room_id) {
            let timeline = managed.timeline.clone();
            state.last_used.insert(room_id.to_owned(), Instant::now());
            return Ok(timeline);
        }
    }
    let client = get_client().await?;
    let room_id_parsed = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(room_id_parsed)
        .ok_or_else(|| format!("Комната не найдена в SDK: {room_id}"))?;
    let created = Arc::new(
        room.timeline_builder()
            .track_read_marker_and_receipts(TimelineReadReceiptTracking::AllEvents)
            .build()
            .await
            .map_err(|error| format!("Не удалось создать SDK Timeline: {error}"))?,
    );

    let mut state = TIMELINE_MANAGER.lock().await;
    if state.session_epoch != epoch {
        return Err("Сессия изменилась во время создания Timeline".to_owned());
    }
    if let Some(existing) = state.timelines.get(room_id) {
        return Ok(existing.timeline.clone());
    }

    if state.timelines.len() >= MAX_MANAGED_TIMELINES {
        // Active diff streams are not eviction candidates.
        let victim = state
            .last_used
            .iter()
            .filter(|(room_id, _)| !state.subscriptions.contains_key(*room_id))
            .min_by_key(|(_, last_used)| *last_used)
            .map(|(room_id, _)| room_id.clone());
        if let Some(victim) = victim {
            state.timelines.remove(&victim);
            state.last_used.remove(&victim);
            state.generations.remove(&victim);
            if let Some(task) = state.subscriptions.remove(&victim) {
                task.abort();
            }
        }
    }

    state.timelines.insert(
        room_id.to_owned(),
        ManagedTimeline {
            timeline: created.clone(),
        },
    );
    state.creation_locks.remove(room_id);
    state.last_used.insert(room_id.to_owned(), Instant::now());
    Ok(created)
}

fn thread_timeline_key(room_id: &str, root_event_id: &str) -> String {
    format!("{room_id}\u{1f}{root_event_id}")
}

async fn get_or_create_thread_timeline(
    room_id: &str,
    root_event_id: &str,
) -> Result<Arc<Timeline>, String> {
    let epoch = current_session_epoch();
    let key = thread_timeline_key(room_id, root_event_id);
    {
        let state = TIMELINE_MANAGER.lock().await;
        if state.session_epoch == epoch {
            if let Some(timeline) = state.thread_timelines.get(&key) {
                return Ok(timeline.clone());
            }
        }
    }

    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let root_event_id = <&EventId>::try_from(root_event_id)
        .map_err(|error| format!("Некорректный корневой event_id треда: {error}"))?
        .to_owned();
    let room = client
        .get_room(room_id)
        .ok_or_else(|| format!("Комната не найдена в SDK: {room_id}"))?;
    let timeline = Arc::new(
        room.timeline_builder()
            .with_focus(TimelineFocus::Thread { root_event_id })
            .track_read_marker_and_receipts(TimelineReadReceiptTracking::AllEvents)
            .build()
            .await
            .map_err(|error| format!("Не удалось открыть тред: {error}"))?,
    );

    let mut state = TIMELINE_MANAGER.lock().await;
    if state.session_epoch != epoch {
        return Err("Сессия изменилась во время открытия треда".to_owned());
    }
    if state.thread_timelines.len() >= 4 {
        if let Some(oldest) = state.thread_timelines.keys().next().cloned() {
            state.thread_timelines.remove(&oldest);
        }
    }
    Ok(state
        .thread_timelines
        .entry(key)
        .or_insert_with(|| timeline.clone())
        .clone())
}

pub async fn open_timeline(
    tx: Tx,
    request_id: String,
    room_id: String,
    request_generation: u64,
    freshness: SyncFreshness,
) -> Result<(), String> {
    let epoch = current_session_epoch();

    // Record ordering before the first await so stale opens cannot take over.
    {
        let mut state = TIMELINE_MANAGER.lock().await;
        if state.session_epoch != epoch {
            for (_, task) in state.subscriptions.drain() {
                task.abort();
            }
            state.timelines.clear();
            state.creation_locks.clear();
            state.last_used.clear();
            state.generations.clear();
            state.latest_open_request = None;
            state.session_epoch = epoch;
        }
        if !is_newer_open_request(
            state
                .latest_open_request
                .as_ref()
                .map(|(latest, _)| *latest),
            request_generation,
        ) {
            return Ok(());
        }
        state.latest_open_request = Some((request_generation, room_id.clone()));
    }
    crate::matrix::sync_loop::subscribe_to_room(&room_id, request_generation).await?;

    if !is_current_open_request(&room_id, epoch, request_generation).await {
        return Ok(());
    }

    // Keep one live chat subscription; previews are tracked separately.
    {
        let mut state = TIMELINE_MANAGER.lock().await;
        let stale_rooms = state
            .subscriptions
            .keys()
            .filter(|active_room_id| *active_room_id != &room_id)
            .cloned()
            .collect::<Vec<_>>();
        for stale_room_id in stale_rooms {
            if let Some(task) = state.subscriptions.remove(&stale_room_id) {
                task.abort();
            }
            state.last_used.insert(stale_room_id, Instant::now());
        }
    }

    let timeline = get_or_create_timeline(&room_id).await?;

    if !is_current_open_request(&room_id, epoch, request_generation).await {
        return Ok(());
    }

    let (snapshot, mut stream) = timeline.subscribe().await;
    if !is_current_open_request(&room_id, epoch, request_generation).await {
        return Ok(());
    }
    let current_user_id = timeline.room().client().user_id().map(ToString::to_string);
    let items = snapshot
        .iter()
        .map(|item| timeline_item_info(item, current_user_id.as_deref()))
        .collect::<Vec<_>>();
    let has_more_backwards = !snapshot.iter().any(|item| item.is_timeline_start());

    let generation = {
        let mut state = TIMELINE_MANAGER.lock().await;
        if state.latest_open_request.as_ref() != Some(&(request_generation, room_id.clone())) {
            return Ok(());
        }
        let generation = state.generations.entry(room_id.clone()).or_default();
        *generation = generation.saturating_add(1);
        let generation = *generation;
        if let Some(task) = state.subscriptions.remove(&room_id) {
            task.abort();
        }

        state.last_used.insert(room_id.clone(), Instant::now());
        generation
    };

    let response = QmlResponse::TimelineSnapshot {
        request_id,
        room_id: room_id.clone(),
        session_epoch: epoch,
        generation,
        freshness,
        items,
        has_more_backwards,
        timeline_diffs_v1: true,
    };
    let json = serde_json::to_string(&response)
        .map_err(|error| format!("Не удалось сериализовать Timeline snapshot: {error}"))?;
    tx.lock()
        .await
        .send(SocketMessage::Text(json.into()))
        .await
        .map_err(|error| format!("Не удалось отправить Timeline snapshot: {error}"))?;

    // Send the snapshot before consuming its diff stream.
    let stream_tx = tx.clone();
    let stream_room_id = room_id.clone();
    let stream_user_id = current_user_id.clone();
    let task = tokio::spawn(async move {
        let mut first_diff = true;
        while let Some(batch) = stream.next().await {
            if current_session_epoch() != epoch {
                break;
            }
            let diffs = batch
                .into_iter()
                .map(|diff| timeline_diff_info(diff, stream_user_id.as_deref()))
                .collect::<Vec<_>>();
            if diffs.is_empty() {
                continue;
            }
            if first_diff {
                first_diff = false;
            }
            let response = QmlResponse::TimelineDiffs {
                room_id: stream_room_id.clone(),
                session_epoch: epoch,
                generation,
                diffs,
            };
            let Ok(json) = serde_json::to_string(&response) else {
                continue;
            };
            if stream_tx
                .lock()
                .await
                .send(SocketMessage::Text(json.into()))
                .await
                .is_err()
            {
                break;
            }
        }
    });
    let mut state = TIMELINE_MANAGER.lock().await;
    let still_current = state.session_epoch == epoch
        && state.generations.get(&room_id).copied() == Some(generation)
        && state.latest_open_request.as_ref() == Some(&(request_generation, room_id.clone()));
    if still_current {
        state.subscriptions.insert(room_id.clone(), task);
    } else {
        task.abort();
    }
    drop(state);

    Ok(())
}

async fn is_current_open_request(room_id: &str, epoch: u64, request_generation: u64) -> bool {
    let state = TIMELINE_MANAGER.lock().await;
    state.session_epoch == epoch
        && state
            .latest_open_request
            .as_ref()
            .is_some_and(|(generation, current_room)| {
                *generation == request_generation && current_room == room_id
            })
}

fn is_newer_open_request(latest: Option<u64>, candidate: u64) -> bool {
    // Zero is the unordered legacy value.
    candidate == 0 || latest.is_none_or(|latest| candidate > latest)
}

pub async fn close_timeline(room_id: &str, request_generation: u64) {
    let mut state = TIMELINE_MANAGER.lock().await;
    if state
        .latest_open_request
        .as_ref()
        .is_some_and(|(latest, _)| *latest > request_generation)
    {
        return;
    }
    if let Some(task) = state.subscriptions.remove(room_id) {
        task.abort();
    }
    state.last_used.insert(room_id.to_owned(), Instant::now());
    drop(state);
    crate::matrix::sync_loop::unsubscribe_from_room(room_id, request_generation).await;
}

/// Load a standalone preview, reusing a populated SDK Timeline when available.
pub async fn preview_messages(
    room_id: &str,
    limit: u32,
    from: Option<&str>,
) -> Result<(Vec<MessageInfo>, Option<String>), String> {
    let timeline = get_or_create_timeline(room_id).await?;
    let page_size = limit.clamp(1, 100) as usize;
    let offset = preview_cursor_offset(from)
        .ok_or_else(|| "Некорректный cursor предпросмотра Timeline".to_owned())?;
    // First paint needs one message; later pages use the requested size.
    let target_count = if from.is_none() {
        1
    } else {
        offset.saturating_add(page_size)
    };
    let current_user_id = timeline.room().client().user_id().map(ToString::to_string);

    let (mut snapshot, _stream) = timeline.subscribe().await;
    let mut reached_start = snapshot.iter().any(|item| item.is_timeline_start());
    let mut chronological = snapshot
        .iter()
        .filter_map(|item| timeline_item_info(item, current_user_id.as_deref()).message)
        .collect::<Vec<_>>();
    let mut loaded_pages = 0usize;
    let mut stalled_pages = 0usize;

    while chronological.len() < target_count && !reached_start && loaded_pages < 8 {
        let before = chronological.len();
        reached_start = timeline
            .paginate_backwards(page_size.min(u16::MAX as usize) as u16)
            .await
            .map_err(|error| format!("Timeline preview pagination: {error}"))?;
        loaded_pages += 1;

        (snapshot, _) = timeline.subscribe().await;
        reached_start |= snapshot.iter().any(|item| item.is_timeline_start());
        chronological = snapshot
            .iter()
            .filter_map(|item| timeline_item_info(item, current_user_id.as_deref()).message)
            .collect();

        if chronological.len() > before {
            stalled_pages = 0;
        } else {
            stalled_pages += 1;
            if stalled_pages >= 2 {
                break;
            }
        }
    }

    if offset >= chronological.len() {
        let next_from = (!reached_start).then(|| preview_cursor(offset));
        return Ok((Vec::new(), next_from));
    }

    let end = chronological.len().saturating_sub(offset);
    let start = end.saturating_sub(page_size);
    let mut messages = chronological[start..end].to_vec();
    messages.reverse();
    let new_offset = offset.saturating_add(messages.len());
    let next_from = (!(reached_start && start == 0)).then(|| preview_cursor(new_offset));
    Ok((messages, next_from))
}

fn preview_cursor_offset(from: Option<&str>) -> Option<usize> {
    match from {
        None => Some(0),
        Some(cursor) => cursor
            .strip_prefix(PREVIEW_TIMELINE_CURSOR_PREFIX)
            .and_then(|offset| offset.parse::<usize>().ok()),
    }
}

fn preview_cursor(offset: usize) -> String {
    format!("{PREVIEW_TIMELINE_CURSOR_PREFIX}{offset}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn viewport_receipts_share_the_visible_event_and_preserve_privacy() {
        let event = matrix_sdk::ruma::event_id!("$visible").to_owned();
        let public = read_receipts(event.clone(), true);
        assert_eq!(public.fully_read, Some(event.clone()));
        assert_eq!(public.public_read_receipt, Some(event.clone()));
        assert_eq!(public.private_read_receipt, None);

        let private = read_receipts(event.clone(), false);
        assert_eq!(private.fully_read, Some(event.clone()));
        assert_eq!(private.public_read_receipt, None);
        assert_eq!(private.private_read_receipt, Some(event));
    }

    #[test]
    fn preview_cursor_carries_its_own_offset() {
        assert_eq!(preview_cursor_offset(None), Some(0));
        assert_eq!(preview_cursor_offset(Some(&preview_cursor(30))), Some(30));
        assert_eq!(preview_cursor_offset(Some("server-token")), None);
    }

    #[test]
    fn stale_or_duplicate_timeline_open_is_rejected() {
        assert!(is_newer_open_request(None, 1));
        assert!(is_newer_open_request(Some(5), 0));
        assert!(is_newer_open_request(Some(4), 5));
        assert!(!is_newer_open_request(Some(5), 5));
        assert!(!is_newer_open_request(Some(6), 5));
    }
}

pub async fn paginate_backwards(
    tx: Tx,
    request_id: String,
    room_id: String,
    count: u16,
    session_epoch: u64,
    generation: u64,
    freshness: SyncFreshness,
) -> Result<(), String> {
    if !pagination_target_is_current(&room_id, session_epoch, generation).await {
        // Room switches may cancel queued pagination.
        send_status(
            tx,
            Some(request_id),
            room_id,
            session_epoch,
            Some(generation),
            freshness,
            false,
            None,
            None,
        )
        .await;
        return Ok(());
    }
    let timeline = get_or_create_timeline(&room_id).await?;
    if !pagination_target_is_current(&room_id, session_epoch, generation).await {
        // A replaced timeline completes without surfacing a stale error.
        send_status(
            tx,
            Some(request_id),
            room_id,
            session_epoch,
            Some(generation),
            freshness,
            false,
            None,
            None,
        )
        .await;
        return Ok(());
    }
    send_status(
        tx.clone(),
        Some(request_id.clone()),
        room_id.clone(),
        session_epoch,
        Some(generation),
        freshness.clone(),
        true,
        None,
        None,
    )
    .await;
    let outcome = timeline.paginate_backwards(count.clamp(1, 200)).await;
    match outcome {
        Ok(reached_start) => {
            send_status(
                tx,
                Some(request_id),
                room_id,
                session_epoch,
                Some(generation),
                freshness,
                false,
                Some(!reached_start),
                None,
            )
            .await;
            Ok(())
        }
        Err(error) => {
            let error_display = error.to_string();
            let error_kind = classify_timeline_load_error(&error_display);
            eprintln!("[TimelinePaginationError] Загрузка страницы не удалась: {error_kind}");
            let message = format!("Ошибка backward pagination: {error}");
            send_status(
                tx,
                Some(request_id),
                room_id,
                session_epoch,
                Some(generation),
                freshness,
                false,
                None,
                Some(message.clone()),
            )
            .await;
            Err(message)
        }
    }
}

async fn pagination_target_is_current(room_id: &str, epoch: u64, generation: u64) -> bool {
    if current_session_epoch() != epoch {
        return false;
    }
    // Generation zero is the legacy wildcard.
    if generation == 0 {
        return true;
    }
    let state = TIMELINE_MANAGER.lock().await;
    state.session_epoch == epoch && state.generations.get(room_id).copied() == Some(generation)
}

fn classify_timeline_load_error(error: &str) -> &'static str {
    let error = error.to_ascii_lowercase();
    if error.contains("504") || error.contains("gateway timeout") {
        "gateway_timeout"
    } else if error.contains("timeout") || error.contains("timed out") {
        "http_timeout"
    } else if error.contains("429")
        || error.contains("rate limit")
        || error.contains("m_limit_exceeded")
    {
        "rate_limited"
    } else if error.contains("401")
        || error.contains("m_unknown_token")
        || error.contains("unauthorized")
    {
        "unauthorized"
    } else if error.contains("403") || error.contains("m_forbidden") || error.contains("forbidden")
    {
        "forbidden"
    } else if error.contains("pagination token") || error.contains("stream token") {
        "invalid_pagination_token"
    } else if error.contains("event cache") || error.contains("eventcache") {
        "event_cache"
    } else if error.contains("connect") || error.contains("dns") || error.contains("network") {
        "connection_failure"
    } else if error.contains("cancel") {
        "cancelled"
    } else {
        "unknown"
    }
}

async fn send_status(
    tx: Tx,
    request_id: Option<String>,
    room_id: String,
    session_epoch: u64,
    generation: Option<u64>,
    freshness: SyncFreshness,
    paginating_backwards: bool,
    has_more_backwards: Option<bool>,
    error: Option<String>,
) {
    let response = QmlResponse::TimelineStatus {
        request_id,
        room_id,
        session_epoch,
        generation,
        request_generation: None,
        freshness,
        paginating_backwards,
        has_more_backwards,
        error,
    };
    if let Ok(json) = serde_json::to_string(&response) {
        let _ = tx.lock().await.send(SocketMessage::Text(json.into())).await;
    }
}

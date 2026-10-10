use std::collections::HashMap;

use matrix_sdk::{
    room::ListThreadsOptions,
    ruma::{
        api::client::receipt::create_receipt::v3::ReceiptType as ClientReceiptType, EventId, UInt,
    },
};

use crate::{
    matrix::{
        messages::parse_messages,
        session::{current_session_epoch, get_client},
    },
    protocol::commands::{MessageInfo, ThreadSummaryInfo},
};

use super::get_or_create_thread_timeline;
use super::serialization::timeline_item_info;
pub async fn thread_messages(
    room_id: &str,
    root_event_id: &str,
    limit: u16,
) -> Result<(Vec<MessageInfo>, bool), String> {
    let timeline = get_or_create_thread_timeline(room_id, root_event_id).await?;
    let target = usize::from(limit.clamp(1, 200));
    let current_user_id = timeline.room().client().user_id().map(ToString::to_string);
    let mut items = timeline.items().await;
    let mut has_more = !items.iter().any(|item| item.is_timeline_start());
    let mut message_count = items
        .iter()
        .filter(|item| item.as_event().is_some())
        .count();
    let mut pages = 0;
    while message_count < target && has_more && pages < 8 {
        let reached_start = timeline
            .paginate_backwards(50)
            .await
            .map_err(|error| format!("Не удалось загрузить историю треда: {error}"))?;
        pages += 1;
        items = timeline.items().await;
        message_count = items
            .iter()
            .filter(|item| item.as_event().is_some())
            .count();
        has_more = !reached_start;
    }
    let messages = items
        .iter()
        .rev()
        .filter_map(|item| timeline_item_info(item, current_user_id.as_deref()).message)
        .take(target)
        .collect();
    Ok((messages, has_more))
}

pub async fn room_threads(
    room_id: &str,
    from: Option<String>,
    limit: u16,
) -> Result<(Vec<ThreadSummaryInfo>, Option<String>, u32), String> {
    let epoch = current_session_epoch();
    let client = get_client().await?;
    let room_id = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(room_id)
        .ok_or_else(|| format!("Комната не найдена в SDK: {room_id}"))?;
    let limit = UInt::new(u64::from(limit.clamp(1, 50)))
        .ok_or_else(|| "Некорректный размер страницы тредов".to_owned())?;
    let roots = room
        .list_threads(ListThreadsOptions {
            from,
            limit: Some(limit),
            ..Default::default()
        })
        .await
        .map_err(|error| format!("Не удалось загрузить список тредов: {error}"))?;

    let mut latest_events = Vec::new();
    let mut latest_by_root = HashMap::new();
    for root in &roots.chunk {
        let Some(root_id) = root.event_id().map(|event_id| event_id.to_string()) else {
            continue;
        };
        if let Some(latest) = root.bundled_latest_thread_event.as_deref().cloned() {
            let latest_id = latest.event_id().map(|event_id| event_id.to_string());
            let latest_is_own = latest
                .sender()
                .is_some_and(|sender| Some(sender.as_ref()) == client.user_id());
            latest_by_root.insert(root_id, (latest_id, latest_is_own));
            latest_events.push(latest);
        }
    }

    let event_cache = room.event_cache().await.ok().map(|(cache, _)| cache);
    let root_messages = parse_messages(&room, roots.chunk, event_cache.as_ref()).await?;
    let latest_messages = parse_messages(&room, latest_events, event_cache.as_ref()).await?;
    let latest_messages = latest_messages
        .into_iter()
        .map(|message| (message.thread_root_id.clone().unwrap_or_default(), message))
        .collect::<HashMap<_, _>>();
    let mut threads = Vec::new();

    for root in root_messages {
        let root_id = root.event_id.clone();
        let latest_reply = latest_messages.get(&root_id).cloned();
        let (latest_id, latest_is_own) = latest_by_root
            .get(&root_id)
            .cloned()
            .unwrap_or((None, false));
        let unread = if latest_is_own {
            false
        } else if let Some(latest_id) = latest_id.as_deref() {
            !super::thread_reads::is_thread_read(&room, &root_id, latest_id, epoch).await
        } else {
            false
        };
        threads.push(ThreadSummaryInfo {
            reply_count: root.thread_reply_count,
            root,
            latest_reply,
            unread,
        });
    }
    let unread_count = threads.iter().filter(|thread| thread.unread).count() as u32;
    Ok((threads, roots.prev_batch_token, unread_count))
}

pub async fn mark_thread_read(
    room_id: &str,
    root_event_id: &str,
    event_id: &str,
    public_receipt: bool,
) -> Result<(), String> {
    let epoch = current_session_epoch();
    let timeline = get_or_create_thread_timeline(room_id, root_event_id).await?;
    let event_id = <&EventId>::try_from(event_id)
        .map_err(|error| format!("Некорректный event_id receipt: {error}"))?
        .to_owned();
    let receipt_type = if public_receipt {
        ClientReceiptType::Read
    } else {
        ClientReceiptType::ReadPrivate
    };
    let sent = timeline
        .send_single_receipt(receipt_type, event_id.clone())
        .await
        .map_err(|error| format!("Не удалось отметить тред прочитанным: {error}"))?;
    if sent {
        super::thread_reads::remember_read(epoch, room_id, root_event_id, event_id.as_str()).await;
    }
    Ok(())
}

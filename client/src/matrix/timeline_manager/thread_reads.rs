//! Room-wide thread receipts without opening or paginating each thread Timeline.
use super::TIMELINE_MANAGER;
use crate::matrix::session::{current_session_epoch, get_client};
use futures_util::{stream, StreamExt};
use matrix_sdk::{
    room::ListThreadsOptions,
    ruma::{
        api::client::receipt::create_receipt::v3::ReceiptType as ClientReceiptType,
        events::receipt::{ReceiptThread, ReceiptType},
        EventId, UInt,
    },
    Room,
};
use std::{
    collections::{HashMap, HashSet},
    future::Future,
    time::Duration,
};
use tokio::time::{timeout_at, Instant};

type ReadTargets = HashMap<String, String>;
struct ThreadPage {
    targets: Vec<(String, String)>,
    next: Option<String>,
}
#[derive(Default)]
pub struct ThreadReadBatch {
    pub read_events: ReadTargets,
    pub error: Option<String>,
}

pub(super) async fn remember_read(epoch: u64, room_id: &str, root_id: &str, event_id: &str) {
    let mut state = TIMELINE_MANAGER.lock().await;
    if epoch == current_session_epoch() && state.session_epoch == epoch {
        state
            .confirmed_thread_reads
            .entry((room_id.to_owned(), root_id.to_owned()))
            .or_default()
            .insert(event_id.to_owned());
    }
}

pub(super) async fn is_thread_read(
    room: &Room,
    root_id: &str,
    latest_id: &str,
    epoch: u64,
) -> bool {
    let Ok(root_event_id) = <&EventId>::try_from(root_id) else {
        return false;
    };
    let thread = ReceiptThread::Thread(root_event_id.to_owned());
    let user = room.own_user_id();
    let public = room
        .load_user_receipt(ReceiptType::Read, thread.clone(), user)
        .await
        .ok()
        .flatten();
    let private = room
        .load_user_receipt(ReceiptType::ReadPrivate, thread, user)
        .await
        .ok()
        .flatten();
    let synced = public
        .as_ref()
        .is_some_and(|(id, _)| id.as_str() == latest_id)
        || private
            .as_ref()
            .is_some_and(|(id, _)| id.as_str() == latest_id);
    let mut state = TIMELINE_MANAGER.lock().await;
    if state.session_epoch != epoch || current_session_epoch() != epoch {
        return synced;
    }
    let key = (room.room_id().to_string(), root_id.to_owned());
    if synced {
        if let Some(confirmed) = state.confirmed_thread_reads.get_mut(&key) {
            confirmed.remove(latest_id);
            if confirmed.is_empty() {
                state.confirmed_thread_reads.remove(&key);
            }
        }
        return true;
    }
    // Keep independently acknowledged positions: an older concurrent bulk
    // receipt must not replace a newer receipt sent by an open thread.
    state
        .confirmed_thread_reads
        .get(&key)
        .is_some_and(|events| events.contains(latest_id))
}

fn ensure_epoch(epoch: u64) -> Result<(), String> {
    if current_session_epoch() == epoch {
        Ok(())
    } else {
        Err("Сессия изменилась во время прочтения тредов".to_owned())
    }
}

pub async fn mark_room_threads_read(room_id: &str, public_receipt: bool) -> ThreadReadBatch {
    let epoch = current_session_epoch();
    let room = match async {
        let client = get_client().await?;
        let id = <&matrix_sdk::ruma::RoomId>::try_from(room_id).map_err(|e| e.to_string())?;
        ensure_epoch(epoch)?;
        client
            .get_room(id)
            .ok_or_else(|| format!("Комната не найдена в SDK: {room_id}"))
    }
    .await
    {
        Ok(room) => room,
        Err(error) => {
            return ThreadReadBatch {
                error: Some(error),
                ..Default::default()
            }
        }
    };
    read_all_pages(
        Instant::now() + Duration::from_secs(240),
        |from| {
            let room = room.clone();
            async move {
                ensure_epoch(epoch)?;
                let roots = room
                    .list_threads(ListThreadsOptions {
                        from,
                        limit: UInt::new(50),
                        ..Default::default()
                    })
                    .await
                    .map_err(|e| format!("Не удалось загрузить треды: {e}"))?;
                ensure_epoch(epoch)?;
                let targets = roots
                    .chunk
                    .iter()
                    .filter_map(|root| {
                        Some((
                            root.event_id()?.to_string(),
                            root.bundled_latest_thread_event
                                .as_deref()?
                                .event_id()?
                                .to_string(),
                        ))
                    })
                    .collect();
                Ok(ThreadPage {
                    targets,
                    next: roots.prev_batch_token,
                })
            }
        },
        |root_id, event_id| {
            let room = room.clone();
            async move {
                ensure_epoch(epoch)?;
                if !is_thread_read(&room, &root_id, &event_id, epoch).await {
                    let thread_id = <&EventId>::try_from(root_id.as_str())
                        .map_err(|e| e.to_string())?
                        .to_owned();
                    let event = <&EventId>::try_from(event_id.as_str())
                        .map_err(|e| e.to_string())?
                        .to_owned();
                    ensure_epoch(epoch)?;
                    room.send_single_receipt(
                        if public_receipt {
                            ClientReceiptType::Read
                        } else {
                            ClientReceiptType::ReadPrivate
                        },
                        ReceiptThread::Thread(thread_id),
                        event,
                    )
                    .await
                    .map_err(|e| format!("Не удалось отметить тред прочитанным: {e}"))?;
                }
                ensure_epoch(epoch)?;
                remember_read(epoch, room.room_id().as_str(), &root_id, &event_id).await;
                Ok(())
            }
        },
    )
    .await
}

// Pagination is independent of the visible 20-thread UI page. Keep receipts
// bounded to four concurrent requests and retain successful work on failures.
async fn read_all_pages<List, ListFuture, Send, SendFuture>(
    deadline: Instant,
    mut list: List,
    send: Send,
) -> ThreadReadBatch
where
    List: FnMut(Option<String>) -> ListFuture,
    ListFuture: Future<Output = Result<ThreadPage, String>>,
    Send: Fn(String, String) -> SendFuture,
    SendFuture: Future<Output = Result<(), String>>,
{
    let mut result = ThreadReadBatch::default();
    let mut from = None;
    let mut cursors = HashSet::new();
    let mut roots = HashSet::new();
    loop {
        let page = match timeout_at(deadline, list(from)).await {
            Ok(Ok(page)) => page,
            Ok(Err(error)) => {
                result.error = Some(error);
                break;
            }
            Err(_) => {
                result.error = Some("Время ожидания прочтения тредов истекло".to_owned());
                break;
            }
        };
        let targets = page
            .targets
            .into_iter()
            .filter(|(root, _)| roots.insert(root.clone()))
            .collect::<Vec<_>>();
        let sends = stream::iter(targets.into_iter().map(|(root, event)| {
            let operation = send(root.clone(), event.clone());
            async move { (root, event, operation.await) }
        }))
        .buffer_unordered(4);
        tokio::pin!(sends);
        loop {
            match timeout_at(deadline, sends.next()).await {
                Ok(Some((root, event, Ok(())))) => {
                    result.read_events.insert(root, event);
                }
                Ok(Some((_, _, Err(error)))) => {
                    if result.error.is_none() {
                        result.error = Some(error);
                    }
                }
                Ok(None) => break,
                Err(_) => {
                    result.error = Some("Время ожидания прочтения тредов истекло".to_owned());
                    return result;
                }
            }
        }
        let Some(next) = page.next.filter(|next| !next.is_empty()) else {
            break;
        };
        if !cursors.insert(next.clone()) {
            result.error = Some("Сервер повторил страницу тредов".to_owned());
            break;
        }
        from = Some(next);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };

    #[tokio::test]
    async fn reads_all_pages_with_bounded_concurrency_and_deduplicates_roots() {
        let active = Arc::new(AtomicUsize::new(0));
        let maximum = Arc::new(AtomicUsize::new(0));
        let result = read_all_pages(
            Instant::now() + Duration::from_secs(5),
            |from| async move {
                let page: usize = from.as_deref().unwrap_or("0").parse().unwrap();
                Ok(ThreadPage {
                    targets: (page * 25..page * 25 + 30)
                        .map(|i| (format!("$root{i}"), format!("$reply{i}")))
                        .collect(),
                    next: (page < 2).then(|| (page + 1).to_string()),
                })
            },
            |_, _| {
                let active = active.clone();
                let maximum = maximum.clone();
                async move {
                    let count = active.fetch_add(1, Ordering::SeqCst) + 1;
                    maximum.fetch_max(count, Ordering::SeqCst);
                    tokio::time::sleep(Duration::from_millis(1)).await;
                    active.fetch_sub(1, Ordering::SeqCst);
                    Ok(())
                }
            },
        )
        .await;
        assert!(result.error.is_none());
        assert_eq!(result.read_events.len(), 80);
        assert_eq!(maximum.load(Ordering::SeqCst), 4);
    }

    #[tokio::test]
    async fn partial_failures_preserve_successes_and_keep_paginating() {
        let result = read_all_pages(
            Instant::now() + Duration::from_secs(5),
            |from| async move {
                Ok(ThreadPage {
                    targets: if from.is_none() {
                        vec![("$a".into(), "$1".into()), ("$b".into(), "$2".into())]
                    } else {
                        vec![("$c".into(), "$3".into())]
                    },
                    next: from.is_none().then(|| "next".into()),
                })
            },
            |root, _| async move {
                if root == "$b" {
                    Err("offline".into())
                } else {
                    Ok(())
                }
            },
        )
        .await;
        assert_eq!(result.error.as_deref(), Some("offline"));
        assert_eq!(result.read_events.len(), 2);
        assert!(!result.read_events.contains_key("$b"));
        assert!(result.read_events.contains_key("$c"));
    }

    #[tokio::test]
    async fn repeated_page_tokens_and_deadline_finish_with_an_error() {
        let result = read_all_pages(
            Instant::now() + Duration::from_secs(5),
            |_| async {
                Ok(ThreadPage {
                    targets: vec![],
                    next: Some("same".into()),
                })
            },
            |_, _| async { Ok(()) },
        )
        .await;
        assert!(result.error.is_some());
        let expired = read_all_pages(
            Instant::now(),
            |_| async {
                tokio::time::sleep(Duration::from_millis(20)).await;
                Ok(ThreadPage {
                    targets: vec![],
                    next: None,
                })
            },
            |_, _| async { Ok(()) },
        )
        .await;
        assert!(expired.error.is_some());
    }
    #[tokio::test]
    async fn a_reply_arriving_on_a_later_page_is_not_silently_marked_read() {
        let result = read_all_pages(
            Instant::now() + Duration::from_secs(5),
            |from| async move {
                Ok(ThreadPage {
                    targets: vec![(
                        "$root".into(),
                        if from.is_none() {
                            "$old".into()
                        } else {
                            "$new".into()
                        },
                    )],
                    next: from.is_none().then(|| "next".into()),
                })
            },
            |_, _| async { Ok(()) },
        )
        .await;
        assert!(result.error.is_none());
        assert_eq!(
            result.read_events.get("$root").map(String::as_str),
            Some("$old")
        );
    }
}

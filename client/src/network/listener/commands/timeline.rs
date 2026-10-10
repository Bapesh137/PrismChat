//! Timeline command handlers.
use crate::matrix::session::current_session_epoch;
use crate::matrix::sync_loop::current_sync_freshness;
use crate::network::listener::enrich_messages_in_background;
use crate::network::transport::Tx;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use tokio_tungstenite::tungstenite::Message;

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::GetPinnedMessages {
            request_id,
            room_id,
        } => {
            let response = match crate::matrix::relations::pinned_messages(&room_id).await {
                Ok(messages) => QmlResponse::PinnedMessagesResult {
                    request_id,
                    room_id,
                    success: true,
                    messages,
                    error: None,
                },
                Err(error) => QmlResponse::PinnedMessagesResult {
                    request_id,
                    room_id,
                    success: false,
                    messages: vec![],
                    error: Some(error),
                },
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::PinMessage {
            request_id,
            room_id,
            event_id,
            pinned,
        } => {
            let response =
                match crate::matrix::relations::pin_message(&room_id, &event_id, pinned).await {
                    Ok(()) => QmlResponse::PinMessageResult {
                        request_id,
                        room_id,
                        event_id,
                        pinned,
                        success: true,
                        error: None,
                    },
                    Err(error) => QmlResponse::PinMessageResult {
                        request_id,
                        room_id,
                        event_id,
                        pinned,
                        success: false,
                        error: Some(error),
                    },
                };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::SendReaction {
            request_id,
            room_id,
            event_id,
            key,
            reacted,
            reaction_event_id,
        } => {
            let original_reaction_event_id = reaction_event_id.clone();
            let result =
                crate::matrix::timeline_manager::toggle_reaction(&room_id, &event_id, &key).await;
            let response = match result {
                Ok(next_reacted) => QmlResponse::ReactionResult {
                    request_id,
                    room_id,
                    event_id,
                    key,
                    reacted: next_reacted,
                    reaction_event_id: None,
                    success: true,
                    error: None,
                },
                Err(error) => QmlResponse::ReactionResult {
                    request_id,
                    room_id,
                    event_id,
                    key,
                    reacted,
                    reaction_event_id: original_reaction_event_id,
                    success: false,
                    error: Some(error),
                },
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::GetMessageContext {
            request_id,
            room_id,
            limit,
            event_id,
        } => {
            let limit = limit.unwrap_or(25);
            let result =
                crate::matrix::messages::get_messages_around(&room_id, &event_id, limit).await;

            let enrichment_messages = result.as_ref().ok().map(|(messages, _)| messages.clone());
            let enrichment_request_id = request_id.clone();
            let enrichment_room_id = room_id.clone();

            let response = match result {
                Ok((messages, _next_from)) => {
                    println!("[Listener] Сообщений: {}", messages.len());
                    QmlResponse::MessageContextResult {
                        request_id,
                        room_id,
                        event_id,
                        success: true,
                        messages,
                        error: None,
                    }
                }
                Err(error) => QmlResponse::MessageContextResult {
                    request_id,
                    room_id,
                    event_id,
                    success: false,
                    messages: vec![],
                    error: Some(error),
                },
            };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });

            if let Some(messages) = enrichment_messages {
                if !messages.is_empty() {
                    tokio::spawn(enrich_messages_in_background(
                        tx.clone(),
                        enrichment_request_id,
                        enrichment_room_id,
                        messages,
                    ));
                }
            }
        }

        QmlCommand::GetTimelinePreview {
            request_id,
            room_id,
            limit,
            from,
        } => {
            let result = crate::matrix::timeline_manager::preview_messages(
                &room_id,
                limit.unwrap_or(30),
                from.as_deref(),
            )
            .await;
            let response = match result {
                Ok((messages, next_from)) => QmlResponse::TimelinePreviewResult {
                    request_id,
                    room_id,
                    success: true,
                    messages,
                    next_from,
                    error: None,
                },
                Err(error) => QmlResponse::TimelinePreviewResult {
                    request_id,
                    room_id,
                    success: false,
                    messages: Vec::new(),
                    next_from: None,
                    error: Some(error),
                },
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::OpenTimeline {
            request_id,
            room_id,
            request_generation,
        } => {
            let operation_epoch = current_session_epoch();
            if let Err(error) = crate::matrix::timeline_manager::open_timeline(
                tx.clone(),
                request_id.clone(),
                room_id.clone(),
                request_generation,
                current_sync_freshness(),
            )
            .await
            {
                let response = QmlResponse::TimelineStatus {
                    request_id: Some(request_id),
                    room_id,
                    session_epoch: operation_epoch,
                    generation: None,
                    request_generation: Some(request_generation),
                    freshness: current_sync_freshness(),
                    paginating_backwards: false,
                    has_more_backwards: None,
                    error: Some(error),
                };
                let json = serde_json::to_string(&response).unwrap();
                tx.lock()
                    .await
                    .send(Message::Text(json.into()))
                    .await
                    .unwrap_or_else(|error| {
                        eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                    });
            };
        }

        QmlCommand::CloseTimeline {
            request_id,
            room_id,
            request_generation,
        } => {
            let operation_epoch = current_session_epoch();
            crate::matrix::timeline_manager::close_timeline(&room_id, request_generation).await;
            let response = QmlResponse::TimelineStatus {
                request_id: Some(request_id),
                room_id,
                session_epoch: operation_epoch,
                generation: None,
                request_generation: Some(request_generation),
                freshness: current_sync_freshness(),
                paginating_backwards: false,
                has_more_backwards: None,
                error: None,
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::PaginateTimelineBackwards {
            request_id,
            room_id,
            count,
            session_epoch,
            generation,
        } => {
            let pagination_tx = tx.clone();
            let operation_epoch = if session_epoch == 0 {
                current_session_epoch()
            } else {
                session_epoch
            };
            let freshness = current_sync_freshness();
            tokio::spawn(async move {
                let _ = crate::matrix::timeline_manager::paginate_backwards(
                    pagination_tx,
                    request_id,
                    room_id,
                    count,
                    operation_epoch,
                    generation,
                    freshness,
                )
                .await;
            });
        }

        QmlCommand::MarkRoomRead {
            request_id,
            room_id,
            public_receipt,
            event_id,
        } => {
            let response = match crate::matrix::timeline_manager::mark_as_read(
                &room_id,
                public_receipt.unwrap_or(true),
                event_id.as_deref(),
            )
            .await
            {
                Ok(()) => QmlResponse::MarkRoomReadResult {
                    request_id,
                    room_id,
                    success: true,
                    marked_unread: None,
                    error: None,
                },
                Err(error) => QmlResponse::MarkRoomReadResult {
                    request_id,
                    room_id,
                    success: false,
                    marked_unread: None,
                    error: Some(error),
                },
            };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::MarkRoomThreadsRead {
            request_id,
            room_id,
            public_receipt,
        } => {
            let result = crate::matrix::timeline_manager::mark_room_threads_read(
                &room_id,
                public_receipt.unwrap_or(true),
            )
            .await;
            let response = QmlResponse::MarkRoomThreadsReadResult {
                request_id,
                room_id,
                success: result.error.is_none(),
                read_events: result.read_events,
                error: result.error,
            };
            let json = serde_json::to_string(&response).unwrap();
            let _ = tx.lock().await.send(Message::Text(json.into())).await;
        }

        QmlCommand::MarkThreadRead {
            request_id,
            room_id,
            root_event_id,
            event_id,
            public_receipt,
        } => {
            let result = crate::matrix::timeline_manager::mark_thread_read(
                &room_id,
                &root_event_id,
                &event_id,
                public_receipt.unwrap_or(true),
            )
            .await;
            let response = QmlResponse::MarkThreadReadResult {
                request_id,
                room_id,
                root_event_id,
                success: result.is_ok(),
                error: result.err(),
            };
            let json = serde_json::to_string(&response).unwrap();
            let _ = tx.lock().await.send(Message::Text(json.into())).await;
        }

        QmlCommand::SetTyping {
            request_id,
            room_id,
            typing,
            generation,
        } => {
            let result = crate::matrix::typing::set_typing(&room_id, typing, generation).await;
            let response = QmlResponse::TypingNoticeResult {
                request_id,
                room_id,
                typing,
                success: result.is_ok(),
                error: result.err(),
            };
            let json = serde_json::to_string(&response).unwrap();
            let _ = tx.lock().await.send(Message::Text(json.into())).await;
        }

        QmlCommand::SetRoomMarkedUnread {
            request_id,
            room_id,
            unread,
        } => {
            let response =
                match crate::matrix::timeline_manager::set_marked_unread(&room_id, unread).await {
                    Ok(()) => QmlResponse::MarkRoomReadResult {
                        request_id,
                        room_id,
                        success: true,
                        marked_unread: Some(unread),
                        error: None,
                    },
                    Err(error) => QmlResponse::MarkRoomReadResult {
                        request_id,
                        room_id,
                        success: false,
                        marked_unread: Some(unread),
                        error: Some(error),
                    },
                };
            let json = serde_json::to_string(&response).unwrap();
            let _ = tx.lock().await.send(Message::Text(json.into())).await;
        }

        QmlCommand::GetThreadMessages {
            request_id,
            room_id,
            root_event_id,
            limit,
        } => {
            let response = match crate::matrix::timeline_manager::thread_messages(
                &room_id,
                &root_event_id,
                limit,
            )
            .await
            {
                Ok((messages, has_more)) => QmlResponse::ThreadMessagesResult {
                    request_id,
                    room_id,
                    root_event_id,
                    success: true,
                    messages,
                    has_more,
                    error: None,
                },
                Err(error) => QmlResponse::ThreadMessagesResult {
                    request_id,
                    room_id,
                    root_event_id,
                    success: false,
                    messages: Vec::new(),
                    has_more: false,
                    error: Some(error),
                },
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить тред QML: {error}")
                });
        }

        QmlCommand::GetRoomThreads {
            request_id,
            room_id,
            from,
            limit,
        } => {
            let response =
                match crate::matrix::timeline_manager::room_threads(&room_id, from, limit).await {
                    Ok((threads, next_from, unread_count)) => QmlResponse::RoomThreadsResult {
                        request_id,
                        room_id,
                        success: true,
                        threads,
                        next_from,
                        unread_count,
                        error: None,
                    },
                    Err(error) => QmlResponse::RoomThreadsResult {
                        request_id,
                        room_id,
                        success: false,
                        threads: Vec::new(),
                        next_from: None,
                        unread_count: 0,
                        error: Some(error),
                    },
                };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить список тредов QML: {error}")
                });
        }

        QmlCommand::SendMessage {
            request_id,
            room_id,
            body,
            msg_type,
            reply_to,
            thread_root,
            mentioned_user_ids,
        } => {
            println!("[Listener] Отправка сообщения");

            // matrix-sdk builds a deep future chain for encrypted/raw sends.
            // Heap-box it so the already large listener state machine does not
            // have to keep that future inline inside its own state.
            let send_result = Box::pin(crate::matrix::timeline_manager::send_message(
                &room_id,
                &body,
                msg_type.as_deref(),
                reply_to.as_deref(),
                thread_root.as_deref(),
                &mentioned_user_ids,
            ))
            .await;

            let response = match send_result {
                Ok(()) => {
                    println!("[Listener] Сообщение отправлено");
                    QmlResponse::SendMessageResult {
                        request_id,
                        success: true,
                        // The SDK Timeline reports the local echo and its
                        // eventual event ID through timeline diffs.
                        event_id: None,
                        error: None,
                    }
                }
                Err(e) => QmlResponse::SendMessageResult {
                    request_id,
                    success: false,
                    event_id: None,
                    error: Some(e),
                },
            };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::RetryMessage {
            request_id,
            room_id,
            timeline_item_id,
        } => {
            let result =
                crate::matrix::timeline_manager::retry_message(&room_id, &timeline_item_id).await;
            let response = QmlResponse::RetryMessageResult {
                request_id,
                room_id,
                timeline_item_id,
                success: result.is_ok(),
                error: result.err(),
            };
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить результат повтора QML: {error}")
                });
        }

        QmlCommand::RedactMessage {
            request_id,
            room_id,
            event_id,
        } => {
            println!("[Listener] Удаление сообщения");

            let response =
                match crate::matrix::timeline_manager::redact_message(&room_id, &event_id).await {
                    Ok(_) => QmlResponse::RedactResult {
                        request_id,
                        room_id,
                        event_id,
                        success: true,
                        error: None,
                    },
                    Err(e) => QmlResponse::RedactResult {
                        request_id,
                        room_id,
                        event_id,
                        success: false,
                        error: Some(e),
                    },
                };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::EditMessage {
            request_id,
            room_id,
            event_id,
            new_body,
        } => {
            println!("[Listener] Редактирование сообщения");

            let response =
                match crate::matrix::timeline_manager::edit_message(&room_id, &event_id, &new_body)
                    .await
                {
                    Ok(_) => QmlResponse::EditResult {
                        request_id,
                        success: true,
                        error: None,
                    },
                    Err(e) => QmlResponse::EditResult {
                        request_id,
                        success: false,
                        error: Some(e),
                    },
                };

            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }
        _ => unreachable!("command routed to the wrong domain"),
    }
}

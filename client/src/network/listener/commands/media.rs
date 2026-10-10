//! Media command handlers.
use crate::network::transport::Tx;
use crate::protocol::commands::ClipboardAttachmentInfo;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use std::{
    collections::HashMap,
    sync::{Arc, LazyLock},
};
use tokio::sync::{Mutex as AsyncMutex, Notify};
use tokio_tungstenite::tungstenite::Message;
static ACTIVE_UPLOADS: LazyLock<AsyncMutex<HashMap<String, Arc<Notify>>>> =
    LazyLock::new(|| AsyncMutex::new(HashMap::new()));

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::GetRoomAttachments {
            request_id,
            room_id,
            limit,
            from,
            category,
        } => {
            let response = match crate::matrix::attachments::get_room_attachments(
                &room_id,
                limit.unwrap_or(30),
                from,
                category,
            )
            .await
            {
                Ok((messages, next_from)) => QmlResponse::RoomAttachmentsResult {
                    request_id,
                    room_id,
                    success: true,
                    messages,
                    next_from,
                    error: None,
                },
                Err(error) => QmlResponse::RoomAttachmentsResult {
                    request_id,
                    room_id,
                    success: false,
                    messages: vec![],
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

        QmlCommand::SendBuiltinSticker {
            request_id,
            room_id,
            sticker_id,
        } => {
            let send_result = Box::pin(crate::matrix::media::send_builtin_sticker(
                &room_id,
                &sticker_id,
            ))
            .await;

            let response = match send_result {
                Ok(()) => QmlResponse::SendMessageResult {
                    request_id,
                    success: true,
                    event_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::SendMessageResult {
                    request_id,
                    success: false,
                    event_id: None,
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

        QmlCommand::SendSticker {
            request_id,
            room_id,
            body,
            media_url,
            media_file,
            mime_type,
        } => {
            let send_result = Box::pin(crate::matrix::media::send_sticker_reference(
                &room_id,
                &body,
                media_url.as_deref(),
                media_file,
                mime_type.as_deref(),
            ))
            .await;

            let response = match send_result {
                Ok(()) => QmlResponse::SendMessageResult {
                    request_id,
                    success: true,
                    event_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::SendMessageResult {
                    request_id,
                    success: false,
                    event_id: None,
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

        QmlCommand::UploadStickerAsset {
            request_id,
            path,
            mime_type,
            filename,
        } => {
            let result =
                crate::matrix::media::upload_sticker_asset(&path, &mime_type, &filename).await;

            let response = match result {
                Ok((media_url, effective_mime)) => QmlResponse::StickerAssetUploadResult {
                    request_id,
                    success: true,
                    media_url: Some(media_url),
                    mime_type: Some(effective_mime),
                    error: None,
                },
                Err(error) => QmlResponse::StickerAssetUploadResult {
                    request_id,
                    success: false,
                    media_url: None,
                    mime_type: None,
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

        QmlCommand::ShareStickerPack {
            request_id,
            room_id,
            pack,
        } => {
            let result = crate::matrix::media::share_sticker_pack(&room_id, pack).await;
            let response = match result {
                Ok(()) => QmlResponse::SendMessageResult {
                    request_id,
                    success: true,
                    event_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::SendMessageResult {
                    request_id,
                    success: false,
                    event_id: None,
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

        QmlCommand::CancelUpload {
            request_id,
            upload_request_id,
        } => {
            let cancelled = ACTIVE_UPLOADS.lock().await.get(&upload_request_id).cloned();
            if let Some(cancel) = cancelled {
                cancel.notify_one();
            }
            let response = QmlResponse::UploadMediaResult {
                request_id,
                success: true,
                event_id: None,
                error: None,
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }

        QmlCommand::UploadMedia {
            request_id,
            room_id,
            path,
            mime_type,
            filename,
            duration_ms,
            as_sticker,
        } => {
            let voice_duration_ms = if as_sticker {
                None
            } else {
                duration_ms.filter(|value| *value > 0)
            };
            let prepared_media = if voice_duration_ms.is_some() {
                crate::matrix::voice::transcode_wav_to_ogg_opus(&path)
                    .await
                    .map(|voice_path| {
                        (
                            voice_path.to_string_lossy().into_owned(),
                            "audio/ogg".to_owned(),
                            "Голосовое сообщение.ogg".to_owned(),
                        )
                    })
            } else {
                Ok((path.clone(), mime_type, filename))
            };

            let response = match prepared_media {
                Ok((upload_path, upload_mime, upload_filename)) => {
                    let cancellation = Arc::new(Notify::new());
                    ACTIVE_UPLOADS
                        .lock()
                        .await
                        .insert(request_id.clone(), cancellation.clone());
                    let (progress_tx, mut progress_rx) =
                        tokio::sync::mpsc::unbounded_channel::<matrix_sdk::TransmissionProgress>();
                    let progress_request_id = request_id.clone();
                    let progress_writer = tx.clone();
                    let progress_task = tokio::spawn(async move {
                        while let Some(progress) = progress_rx.recv().await {
                            let response = QmlResponse::UploadMediaProgress {
                                request_id: progress_request_id.clone(),
                                current: progress.current as u64,
                                total: progress.total as u64,
                            };
                            let Ok(json) = serde_json::to_string(&response) else {
                                continue;
                            };
                            if progress_writer
                                .lock()
                                .await
                                .send(Message::Text(json.into()))
                                .await
                                .is_err()
                            {
                                break;
                            }
                        }
                    });

                    let upload_future = async {
                        if as_sticker {
                            crate::matrix::media::send_sticker_with_progress(
                                &room_id,
                                &upload_path,
                                &upload_mime,
                                &upload_filename,
                                progress_tx,
                            )
                            .await
                        } else {
                            crate::matrix::media::send_attachment_with_progress(
                                &room_id,
                                &upload_path,
                                &upload_mime,
                                &upload_filename,
                                voice_duration_ms,
                                progress_tx,
                            )
                            .await
                        }
                    };
                    let upload_result = tokio::select! {
                        result = upload_future => result,
                        _ = cancellation.notified() => Err("Загрузка отменена".to_owned()),
                    };
                    ACTIVE_UPLOADS.lock().await.remove(&request_id);
                    progress_task.abort();

                    if upload_path != path {
                        let _ = tokio::fs::remove_file(&upload_path).await;
                    }

                    match upload_result {
                        Ok(()) => QmlResponse::UploadMediaResult {
                            request_id,
                            success: true,
                            event_id: None,
                            error: None,
                        },
                        Err(error) => QmlResponse::UploadMediaResult {
                            request_id,
                            success: false,
                            event_id: None,
                            error: Some(error),
                        },
                    }
                }
                Err(error) => QmlResponse::UploadMediaResult {
                    request_id,
                    success: false,
                    event_id: None,
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

        QmlCommand::PasteClipboard {
            request_id,
            room_id: _room_id,
        } => {
            let response = match crate::matrix::clipboard::paste_clipboard().await {
                Ok(crate::matrix::clipboard::ClipboardPasteOutcome::Empty) => {
                    QmlResponse::ClipboardPasteResult {
                        request_id,
                        success: true,
                        text: None,
                        attachments: Vec::new(),
                        error: None,
                    }
                }
                Ok(crate::matrix::clipboard::ClipboardPasteOutcome::Text(text)) => {
                    QmlResponse::ClipboardPasteResult {
                        request_id,
                        success: true,
                        text: Some(text),
                        attachments: Vec::new(),
                        error: None,
                    }
                }
                Ok(crate::matrix::clipboard::ClipboardPasteOutcome::Attachments(attachments)) => {
                    QmlResponse::ClipboardPasteResult {
                        request_id,
                        success: true,
                        text: None,
                        attachments: attachments
                            .into_iter()
                            .map(|attachment| ClipboardAttachmentInfo {
                                path: attachment.path,
                                filename: attachment.filename,
                                is_image: attachment.is_image,
                            })
                            .collect(),
                        error: None,
                    }
                }
                Err(error) => QmlResponse::ClipboardPasteResult {
                    request_id,
                    success: false,
                    text: None,
                    attachments: Vec::new(),
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

        QmlCommand::SetAvatar {
            request_id,
            path,
            mime_type,
        } => {
            let response = match crate::matrix::avatar::set_avatar(&path, &mime_type).await {
                Ok(mxc) => QmlResponse::SetAvatarResult {
                    request_id,
                    success: true,
                    avatar_url: Some(mxc),
                    error: None,
                },
                Err(e) => QmlResponse::SetAvatarResult {
                    request_id,
                    success: false,
                    avatar_url: None,
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

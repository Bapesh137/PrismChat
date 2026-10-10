//! Storage command handlers.
use crate::matrix::session::SESSION;
use crate::network::transport::Tx;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use tokio_tungstenite::tungstenite::Message;

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::GetStorageStats { request_id } => {
            let profile_id = SESSION.lock().await.profile_id.clone();
            let preferences = crate::storage::maintenance::load_preferences();
            let response = match profile_id {
                Some(profile_id) => match crate::storage::maintenance::storage_stats(&profile_id) {
                    Ok(stats) => QmlResponse::StorageStatsResult {
                        request_id,
                        success: true,
                        sqlite_bytes: stats.sqlite_bytes,
                        event_cache_bytes: stats.event_cache_bytes,
                        media_bytes: stats.media_bytes,
                        total_cache_bytes: stats.total_cache_bytes,
                        auto_cleanup_days: preferences.auto_cleanup_days,
                        cache_limit_mb: preferences.cache_limit_mb,
                        downloads_dir: preferences.downloads_dir,
                        auto_load_images: preferences.auto_load_images,
                        auto_load_videos: preferences.auto_load_videos,
                        error: None,
                    },
                    Err(error) => QmlResponse::StorageStatsResult {
                        request_id,
                        success: false,
                        sqlite_bytes: 0,
                        event_cache_bytes: 0,
                        media_bytes: 0,
                        total_cache_bytes: 0,
                        auto_cleanup_days: preferences.auto_cleanup_days,
                        cache_limit_mb: preferences.cache_limit_mb,
                        downloads_dir: preferences.downloads_dir,
                        auto_load_images: preferences.auto_load_images,
                        auto_load_videos: preferences.auto_load_videos,
                        error: Some(error),
                    },
                },
                None => QmlResponse::StorageStatsResult {
                    request_id,
                    success: false,
                    sqlite_bytes: 0,
                    event_cache_bytes: 0,
                    media_bytes: 0,
                    total_cache_bytes: 0,
                    auto_cleanup_days: preferences.auto_cleanup_days,
                    cache_limit_mb: preferences.cache_limit_mb,
                    downloads_dir: preferences.downloads_dir,
                    auto_load_images: preferences.auto_load_images,
                    auto_load_videos: preferences.auto_load_videos,
                    error: Some("Нет активного профиля".to_string()),
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

        QmlCommand::ClearCache {
            request_id,
            clear_media,
            clear_event_cache,
            clear_sqlite,
        } => {
            let profile_id = SESSION.lock().await.profile_id.clone();
            let response = match profile_id {
                Some(profile_id) => {
                    match crate::storage::maintenance::clear_cache(
                        &profile_id,
                        clear_media,
                        clear_event_cache,
                        clear_sqlite,
                    ) {
                        Ok(cleanup) => QmlResponse::ClearCacheResult {
                            request_id,
                            success: cleanup.warnings.is_empty(),
                            freed_bytes: cleanup.freed_bytes,
                            restart_required: cleanup.restart_required,
                            warnings: cleanup.warnings,
                            error: None,
                        },
                        Err(error) => QmlResponse::ClearCacheResult {
                            request_id,
                            success: false,
                            freed_bytes: 0,
                            restart_required: false,
                            warnings: Vec::new(),
                            error: Some(error),
                        },
                    }
                }
                None => QmlResponse::ClearCacheResult {
                    request_id,
                    success: false,
                    freed_bytes: 0,
                    restart_required: false,
                    warnings: Vec::new(),
                    error: Some("Нет активного профиля".to_string()),
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

        QmlCommand::SetStoragePreferences {
            request_id,
            auto_cleanup_days,
            cache_limit_mb,
            downloads_dir,
            auto_load_images,
            auto_load_videos,
        } => {
            let preferences = crate::storage::maintenance::StoragePreferences {
                auto_cleanup_days: auto_cleanup_days.min(3650),
                cache_limit_mb: cache_limit_mb.min(1024 * 1024),
                downloads_dir,
                auto_load_images,
                auto_load_videos,
            };
            let response = match crate::storage::maintenance::save_preferences(&preferences) {
                Ok(()) => {
                    if let Some(profile_id) = SESSION.lock().await.profile_id.clone() {
                        let _ =
                            crate::storage::maintenance::run_runtime_media_maintenance(&profile_id);
                    }
                    QmlResponse::SetStoragePreferencesResult {
                        request_id,
                        success: true,
                        error: None,
                    }
                }
                Err(error) => QmlResponse::SetStoragePreferencesResult {
                    request_id,
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

        QmlCommand::DownloadMedia {
            request_id,
            media_url,
            filename,
            media_file,
            media_mime_type,
        } => {
            let media_result = match media_file {
                Some(value) => match serde_json::from_value::<
                    matrix_sdk::ruma::events::room::EncryptedFile,
                >(value)
                {
                    Ok(file) if file.url.to_string() == media_url => {
                        crate::matrix::media::download_encrypted_media(
                            file,
                            media_mime_type.as_deref(),
                        )
                        .await
                    }
                    Ok(_) => Err("URL вложения не совпадает с encrypted file".to_string()),
                    Err(error) => Err(format!(
                        "Некорректное описание зашифрованного вложения: {error}"
                    )),
                },
                None => {
                    crate::matrix::media::download_media(&media_url, media_mime_type.as_deref())
                        .await
                }
            };
            let response = match media_result {
                Ok((bytes, _)) => {
                    match crate::storage::maintenance::save_download(&bytes, &filename) {
                        Ok(path) => QmlResponse::DownloadMediaResult {
                            request_id,
                            success: true,
                            path: Some(path.to_string_lossy().into_owned()),
                            error: None,
                        },
                        Err(error) => QmlResponse::DownloadMediaResult {
                            request_id,
                            success: false,
                            path: None,
                            error: Some(error),
                        },
                    }
                }
                Err(error) => QmlResponse::DownloadMediaResult {
                    request_id,
                    success: false,
                    path: None,
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

        QmlCommand::ClearTemporaryData { request_id } => {
            // Give Qt Multimedia a moment to finish closing a
            // recording cancelled by the UI before scanning temp.
            tokio::time::sleep(std::time::Duration::from_millis(350)).await;
            let cleanup = crate::storage::maintenance::clear_temporary_voice_files();
            let response = QmlResponse::ClearTemporaryDataResult {
                request_id,
                success: cleanup.warnings.is_empty(),
                removed_files: cleanup.removed_files,
                freed_bytes: cleanup.freed_bytes,
                warnings: cleanup.warnings,
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

        QmlCommand::ExportDiagnostics { request_id, path } => {
            let profile_id = SESSION.lock().await.profile_id.clone();
            let response = match crate::storage::maintenance::export_diagnostic_report(
                profile_id.as_deref(),
                &path,
            ) {
                Ok(()) => QmlResponse::ExportDiagnosticsResult {
                    request_id,
                    success: true,
                    path: Some(path),
                    error: None,
                },
                Err(error) => QmlResponse::ExportDiagnosticsResult {
                    request_id,
                    success: false,
                    path: None,
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

        QmlCommand::ShowSystemNotification {
            request_id,
            title,
            message,
        } => {
            let result = crate::system_notifications::show(&title, &message);
            let response = QmlResponse::SystemNotificationResult {
                request_id,
                success: result.is_ok(),
                error: result.err(),
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

        QmlCommand::CopyText { request_id, text } => {
            let result = crate::matrix::clipboard::copy_text(&text);
            let response = QmlResponse::DeviceOperationResult {
                request_id,
                operation: "copy".to_owned(),
                success: result.is_ok(),
                device_ids: vec![],
                error: result.err(),
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }
        _ => unreachable!("command routed to the wrong domain"),
    }
}

//! Encryption command handlers.
use crate::network::transport::Tx;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use tokio_tungstenite::tungstenite::Message;
use zeroize::Zeroize;

pub(super) async fn handle(command: QmlCommand, tx: Tx) {
    match command {
        QmlCommand::ExportRoomKeys {
            request_id,
            path,
            mut passphrase,
        } => {
            let response =
                match crate::matrix::encryption::export_room_keys(&path, &passphrase).await {
                    Ok(()) => QmlResponse::ExportRoomKeysResult {
                        request_id,
                        success: true,
                        error: None,
                    },
                    Err(error) => QmlResponse::ExportRoomKeysResult {
                        request_id,
                        success: false,
                        error: Some(error),
                    },
                };
            passphrase.zeroize();
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::ImportRoomKeys {
            request_id,
            path,
            mut passphrase,
        } => {
            let response =
                match crate::matrix::encryption::import_room_keys(&path, &passphrase).await {
                    Ok((imported_count, total_count)) => QmlResponse::ImportRoomKeysResult {
                        request_id,
                        success: true,
                        imported_count,
                        total_count,
                        error: None,
                    },
                    Err(error) => QmlResponse::ImportRoomKeysResult {
                        request_id,
                        success: false,
                        imported_count: 0,
                        total_count: 0,
                        error: Some(error),
                    },
                };
            passphrase.zeroize();
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::GetEncryptionOverview { request_id } => {
            let response = match crate::matrix::e2ee::overview().await {
                Ok(overview) => QmlResponse::EncryptionOverviewResult {
                    request_id,
                    success: true,
                    overview: Some(overview),
                    error: None,
                },
                Err(error) => QmlResponse::EncryptionOverviewResult {
                    request_id,
                    success: false,
                    overview: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
        }

        QmlCommand::BootstrapCrossSigning {
            request_id,
            password,
            uiaa_session,
        } => {
            let response =
                match crate::matrix::e2ee::bootstrap_cross_signing(password, uiaa_session).await {
                    Ok(session) => QmlResponse::E2eeActionResult {
                        request_id,
                        success: session.is_none(),
                        uiaa_session: session,
                        auth_type: None,
                        approval_url: None,
                        recovery_key: None,
                        flow_id: None,
                        error: None,
                    },
                    Err(error) => QmlResponse::E2eeActionResult {
                        request_id,
                        success: false,
                        uiaa_session: None,
                        auth_type: None,
                        approval_url: None,
                        recovery_key: None,
                        flow_id: None,
                        error: Some(error),
                    },
                };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::EnableRecovery {
            request_id,
            passphrase,
        } => {
            let response = match crate::matrix::e2ee::enable_recovery(passphrase).await {
                Ok(recovery_key) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: Some(recovery_key),
                    flow_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::RecoverEncryption {
            request_id,
            recovery_key,
        } => {
            let response = match crate::matrix::e2ee::recover(recovery_key).await {
                Ok(()) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::ChangeRecoveryKey {
            request_id,
            old_recovery_key,
            passphrase,
        } => {
            let response = match crate::matrix::e2ee::change_recovery_key(
                old_recovery_key,
                passphrase,
            )
            .await
            {
                Ok(recovery_key) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: Some(recovery_key),
                    flow_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::RepairKeyBackup {
            request_id,
            recovery_key,
        } => {
            let response = match crate::matrix::e2ee::repair_key_backup(recovery_key).await {
                Ok(()) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::EnableKeyBackup { request_id } => {
            let response = match crate::matrix::e2ee::enable_backup().await {
                Ok(()) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::RecreateKeyBackup { request_id } => {
            let response = match crate::matrix::e2ee::recreate_backup().await {
                Ok(()) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::ResetCryptoIdentity {
            request_id,
            password,
            uiaa_session,
            oauth_approved,
        } => {
            let response =
                match crate::matrix::e2ee::reset_identity(password, uiaa_session, oauth_approved)
                    .await
                {
                    Ok(crate::matrix::e2ee::IdentityResetStep::Uiaa { session }) => {
                        QmlResponse::E2eeActionResult {
                            request_id,
                            success: false,
                            uiaa_session: Some(session),
                            auth_type: Some("uiaa".to_owned()),
                            approval_url: None,
                            recovery_key: None,
                            flow_id: None,
                            error: None,
                        }
                    }
                    Ok(crate::matrix::e2ee::IdentityResetStep::OAuth { approval_url }) => {
                        QmlResponse::E2eeActionResult {
                            request_id,
                            success: false,
                            uiaa_session: None,
                            auth_type: Some("oauth".to_owned()),
                            approval_url: Some(approval_url),
                            recovery_key: None,
                            flow_id: None,
                            error: None,
                        }
                    }
                    Ok(crate::matrix::e2ee::IdentityResetStep::Refreshing { reason }) => {
                        QmlResponse::E2eeActionResult {
                            request_id,
                            success: false,
                            uiaa_session: None,
                            auth_type: Some("refresh".to_owned()),
                            approval_url: None,
                            recovery_key: None,
                            flow_id: None,
                            error: Some(reason),
                        }
                    }
                    Ok(crate::matrix::e2ee::IdentityResetStep::Done) => {
                        QmlResponse::E2eeActionResult {
                            request_id,
                            success: true,
                            uiaa_session: None,
                            auth_type: None,
                            approval_url: None,
                            recovery_key: None,
                            flow_id: None,
                            error: None,
                        }
                    }
                    Err(error) => QmlResponse::E2eeActionResult {
                        request_id,
                        success: false,
                        uiaa_session: None,
                        auth_type: None,
                        approval_url: None,
                        recovery_key: None,
                        flow_id: None,
                        error: Some(error),
                    },
                };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }

        QmlCommand::CancelCryptoIdentityReset { request_id } => {
            let response = match crate::matrix::e2ee::cancel_pending_identity_reset().await {
                Ok(()) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: true,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: None,
                },
                Err(error) => QmlResponse::E2eeActionResult {
                    request_id,
                    success: false,
                    uiaa_session: None,
                    auth_type: None,
                    approval_url: None,
                    recovery_key: None,
                    flow_id: None,
                    error: Some(error),
                },
            };
            let _ = tx
                .lock()
                .await
                .send(Message::Text(
                    serde_json::to_string(&response).unwrap().into(),
                ))
                .await;
            crate::matrix::e2ee::emit_overview().await;
        }
        _ => unreachable!("command routed to the wrong domain"),
    }
}

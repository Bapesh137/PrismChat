//! Session command handlers.
use crate::matrix::session::{
    clear_session, current_profile_meta, current_session_epoch, delete_profile_by_id,
    list_profiles, switch_profile, SESSION,
};
use crate::network::listener::{ensure_sync_loop, refresh_current_profile_avatar};
use crate::network::transport::Tx;
use crate::network::transport::{
    DEFAULT_COMMAND_TIMEOUT_MS, IPC_HANDSHAKE_TIMEOUT_MS, IPC_NATIVE_FALLBACK_DELAY_MS,
    IPC_RECONNECT_DELAY_MS, LONG_COMMAND_TIMEOUT_MS,
};
use crate::protocol::commands::ProfileInfo;
use crate::protocol::commands::{QmlCommand, QmlResponse};
use tokio_tungstenite::tungstenite::Message;
use zeroize::Zeroize;

pub(super) async fn handle(command: QmlCommand, tx: Tx, session_restore_error: Option<String>) {
    match command {
        QmlCommand::GetCapabilities { request_id } => {
            let response = QmlResponse::Capabilities {
                request_id,
                timeline_diffs_v1: true,
                media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
                handshake_timeout_ms: IPC_HANDSHAKE_TIMEOUT_MS,
                native_fallback_delay_ms: IPC_NATIVE_FALLBACK_DELAY_MS,
                reconnect_delay_ms: IPC_RECONNECT_DELAY_MS,
                default_command_timeout_ms: DEFAULT_COMMAND_TIMEOUT_MS,
                long_command_timeout_ms: LONG_COMMAND_TIMEOUT_MS,
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

        QmlCommand::GetSessionState { request_id } => {
            let (token_present, user_id, server, profile_id) = {
                let session = SESSION.lock().await;
                (
                    session.token.is_some(),
                    session.user_id.clone(),
                    session.server.clone(),
                    session.profile_id.clone(),
                )
            };
            let authenticated =
                token_present && user_id.is_some() && server.is_some() && profile_id.is_some();
            let avatar_url = if authenticated {
                current_profile_meta()
                    .await
                    .and_then(|profile| profile.avatar_url)
            } else {
                None
            };
            let response = QmlResponse::SessionStateResult {
                request_id,
                session_epoch: current_session_epoch(),
                authenticated,
                user_id,
                server,
                profile_id,
                avatar_url,
                error: if authenticated {
                    None
                } else {
                    session_restore_error.clone()
                },
                media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
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

        QmlCommand::Login {
            request_id,
            server,
            nickname,
            mut password,
            profile_id,
        } => {
            println!("[Listener] LOGIN");

            let response =
                match crate::matrix::auth::login(&server, &nickname, &password, profile_id).await {
                    Ok((_, avatar_url, profile_id)) => {
                        let (user_id, srv) = {
                            let session = crate::matrix::session::SESSION.lock().await;
                            (session.user_id.clone(), session.server.clone())
                        };

                        let needs_avatar_refresh = avatar_url.is_none();
                        crate::matrix::e2ee::start_observers(tx.clone(), current_session_epoch())
                            .await;
                        ensure_sync_loop(tx.clone()).await;
                        if needs_avatar_refresh {
                            refresh_current_profile_avatar(tx.clone()).await;
                        }

                        QmlResponse::LoginResult {
                            request_id,
                            session_epoch: current_session_epoch(),
                            success: true,
                            user_id,
                            server: srv,
                            profile_id: Some(profile_id),
                            avatar_url,
                            error: None,
                            media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
                        }
                    }
                    Err(e) => QmlResponse::LoginResult {
                        request_id,
                        session_epoch: current_session_epoch(),
                        success: false,
                        user_id: None,
                        server: None,
                        profile_id: None,
                        avatar_url: None,
                        error: Some(e),
                        media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
                    },
                };

            password.zeroize();
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::Register {
            request_id,
            server,
            username,
            mut password,
            profile_id,
        } => {
            println!("[Listener] REGISTER");

            let response =
                match crate::matrix::register::register(&server, &username, &password, profile_id)
                    .await
                {
                    Ok((_, avatar_url, profile_id)) => {
                        let (user_id, srv) = {
                            let session = crate::matrix::session::SESSION.lock().await;
                            (session.user_id.clone(), session.server.clone())
                        };

                        let needs_avatar_refresh = avatar_url.is_none();
                        crate::matrix::e2ee::start_observers(tx.clone(), current_session_epoch())
                            .await;
                        ensure_sync_loop(tx.clone()).await;
                        if needs_avatar_refresh {
                            refresh_current_profile_avatar(tx.clone()).await;
                        }

                        QmlResponse::RegisterResult {
                            request_id,
                            session_epoch: current_session_epoch(),
                            success: true,
                            user_id,
                            server: srv,
                            profile_id: Some(profile_id),
                            avatar_url,
                            error: None,
                            media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
                        }
                    }
                    Err(e) => QmlResponse::RegisterResult {
                        request_id,
                        session_epoch: current_session_epoch(),
                        success: false,
                        user_id: None,
                        server: None,
                        profile_id: None,
                        avatar_url: None,
                        error: Some(e),
                        media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
                    },
                };

            password.zeroize();
            let json = serde_json::to_string(&response).unwrap();
            tx.lock()
                .await
                .send(Message::Text(json.into()))
                .await
                .unwrap_or_else(|error| {
                    eprintln!("[Listener] Не удалось отправить ответ QML: {error}")
                });
        }

        QmlCommand::Logout { request_id } => {
            println!("[Listener] LOGOUT");
            clear_session().await;

            let response = QmlResponse::LogoutResult {
                request_id,
                session_epoch: current_session_epoch(),
                success: true,
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

        QmlCommand::GetProfileList { request_id } => {
            let response = match list_profiles().await {
                Ok((profiles, active_profile_id)) => {
                    let profiles = profiles
                        .into_iter()
                        .map(|p| {
                            let is_active =
                                active_profile_id.as_deref() == Some(p.profile_id.as_str());

                            ProfileInfo {
                                profile_id: p.profile_id,
                                user_id: p.user_id,
                                server: p.server,
                                device_id: p.device_id,
                                display_name: p.display_name,
                                avatar_url: p.avatar_url,
                                is_active,
                                last_used_ts: p.last_used_ts,
                            }
                        })
                        .collect();

                    QmlResponse::ProfilesResult {
                        request_id,
                        profiles,
                        active_profile_id,
                    }
                }
                Err(e) => {
                    println!("[Listener] Не удалось получить список профилей: {}", e);
                    QmlResponse::ProfilesResult {
                        request_id,
                        profiles: vec![],
                        active_profile_id: None,
                    }
                }
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

        QmlCommand::SwitchProfile {
            request_id,
            profile_id,
        } => {
            let response = match switch_profile(&profile_id).await {
                Ok(state) => {
                    let needs_avatar_refresh = state.avatar_url.is_none();
                    crate::matrix::e2ee::start_observers(tx.clone(), current_session_epoch()).await;
                    ensure_sync_loop(tx.clone()).await;
                    if needs_avatar_refresh {
                        refresh_current_profile_avatar(tx.clone()).await;
                    }

                    QmlResponse::SwitchProfileResult {
                        request_id,
                        session_epoch: current_session_epoch(),
                        success: true,
                        profile_id: Some(state.profile_id),
                        user_id: Some(state.user_id),
                        server: Some(state.server),
                        avatar_url: state.avatar_url,
                        error: None,
                        media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
                    }
                }
                Err(e) => QmlResponse::SwitchProfileResult {
                    request_id,
                    session_epoch: current_session_epoch(),
                    success: false,
                    profile_id: Some(profile_id),
                    user_id: None,
                    server: None,
                    avatar_url: None,
                    error: Some(e),
                    media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
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

        QmlCommand::DeleteProfile {
            request_id,
            profile_id,
        } => {
            let response = match delete_profile_by_id(&profile_id).await {
                Ok(()) => QmlResponse::DeleteProfileResult {
                    request_id,
                    success: true,
                    profile_id: Some(profile_id),
                    error: None,
                },
                Err(e) => QmlResponse::DeleteProfileResult {
                    request_id,
                    success: false,
                    profile_id: Some(profile_id),
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

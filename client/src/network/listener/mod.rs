mod commands;

use std::sync::{Arc, LazyLock};

use tokio::sync::{Mutex as AsyncMutex, Notify, RwLock, Semaphore};
use tokio::task::JoinSet;
use tokio_tungstenite::tungstenite::Message;

use crate::matrix::session::{
    current_profile_meta, current_session_epoch, restore_active_client, ActiveProfileState, SESSION,
};
use crate::matrix::sync_loop::start_sync_loop;
use crate::network::transport::{
    ConnectionAcceptor, Tx, DEFAULT_COMMAND_TIMEOUT_MS, IPC_ACCEPT_RETRY_DELAY_MS,
    IPC_HANDSHAKE_TIMEOUT_MS, IPC_NATIVE_FALLBACK_DELAY_MS, IPC_RECONNECT_DELAY_MS,
    LONG_COMMAND_TIMEOUT_MS, MAX_COMMAND_BYTES,
};
use crate::protocol::commands::{QmlCommand, QmlResponse};

const MAX_CONCURRENT_CONNECTIONS: usize = 4;
const MAX_IN_FLIGHT_COMMANDS: usize = 32;

static SESSION_LIFECYCLE_LOCK: AsyncMutex<()> = AsyncMutex::const_new(());
static COMMAND_SLOTS: LazyLock<Arc<Semaphore>> =
    LazyLock::new(|| Arc::new(Semaphore::new(MAX_IN_FLIGHT_COMMANDS)));

#[derive(Clone, Default)]
struct RestoreGate {
    result: Arc<RwLock<Option<Option<String>>>>,
    ready: Arc<Notify>,
}

impl RestoreGate {
    async fn complete(&self, error: Option<String>) {
        *self.result.write().await = Some(error);
        self.ready.notify_waiters();
    }

    async fn wait(&self) -> Option<String> {
        loop {
            let notified = self.ready.notified();
            if let Some(result) = self.result.read().await.clone() {
                return result;
            }
            notified.await;
        }
    }
}

fn command_changes_session(command: &QmlCommand) -> bool {
    matches!(
        command,
        QmlCommand::Login { .. }
            | QmlCommand::Register { .. }
            | QmlCommand::Logout { .. }
            | QmlCommand::SwitchProfile { .. }
            | QmlCommand::DeleteProfile { .. }
    )
}

async fn runtime_profile_state() -> Option<ActiveProfileState> {
    let (token_present, profile_id, user_id, server) = {
        let session = SESSION.lock().await;
        (
            session.token.is_some(),
            session.profile_id.clone(),
            session.user_id.clone(),
            session.server.clone(),
        )
    };
    if !token_present || crate::matrix::session::get_client().await.is_err() {
        return None;
    }
    let (Some(profile_id), Some(user_id), Some(server)) = (profile_id, user_id, server) else {
        return None;
    };
    let avatar_url = current_profile_meta()
        .await
        .and_then(|profile| profile.avatar_url);
    Some(ActiveProfileState {
        profile_id,
        user_id,
        server,
        avatar_url,
    })
}

fn command_name_for_log(raw_json: &str) -> String {
    serde_json::from_str::<serde_json::Value>(raw_json)
        .ok()
        .and_then(|value| value.get("type").cloned())
        .and_then(|value| value.as_str().map(str::to_owned))
        .unwrap_or_else(|| "unknown".to_string())
}

pub(super) async fn ensure_sync_loop(tx: Tx) {
    tokio::spawn(async move {
        start_sync_loop(tx).await;
    });
}

pub(super) async fn enrich_messages_in_background(
    tx: Tx,
    request_id: String,
    room_id: String,
    messages: Vec<crate::protocol::commands::MessageInfo>,
) {
    let request_epoch = current_session_epoch();
    let result = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        crate::matrix::messages::enrich_message_details(&room_id, messages),
    )
    .await;

    let Ok(Ok(Some(messages))) = result else {
        return;
    };
    if current_session_epoch() != request_epoch {
        return;
    }

    let response = QmlResponse::MessagesEnriched {
        request_id,
        room_id,
        messages,
    };
    let Ok(json) = serde_json::to_string(&response) else {
        return;
    };
    let _ = tx.lock().await.send(Message::Text(json.into())).await;
}

pub(super) async fn refresh_current_profile_avatar(tx: Tx) {
    tokio::spawn(async move {
        let session_epoch = current_session_epoch();
        let Some(avatar_url) = crate::matrix::auth::fetch_own_avatar().await else {
            return;
        };

        let (profile_id, user_id, server) = {
            let session = SESSION.lock().await;
            (
                session.profile_id.clone(),
                session.user_id.clone(),
                session.server.clone(),
            )
        };

        let (Some(profile_id), Some(user_id), Some(server)) = (profile_id, user_id, server) else {
            return;
        };

        if current_session_epoch() != session_epoch {
            return;
        }
        if crate::storage::profiles::update_profile_avatar(&profile_id, Some(avatar_url.clone()))
            .is_err()
        {
            return;
        }
        if current_session_epoch() != session_epoch {
            return;
        }

        let push = QmlResponse::CurrentProfileUpdated {
            profile_id,
            user_id,
            server,
            avatar_url: Some(avatar_url),
        };

        let json = serde_json::to_string(&push).unwrap();
        let _ = tx.lock().await.send(Message::Text(json.into())).await;
    });
}

async fn restore_session_for_connection(tx: Tx, gate: RestoreGate) {
    let restore_result = {
        let _lifecycle_guard = SESSION_LIFECYCLE_LOCK.lock().await;
        match runtime_profile_state().await {
            Some(state) => Ok(Some(state)),
            None => restore_active_client().await,
        }
    };

    match restore_result {
        Ok(Some(state)) => {
            let needs_avatar_refresh = state.avatar_url.is_none();
            println!("[Listener] Сессия восстановлена");
            let push = QmlResponse::SessionRestored {
                session_epoch: current_session_epoch(),
                user_id: state.user_id,
                server: state.server,
                profile_id: Some(state.profile_id),
                avatar_url: state.avatar_url,
                media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
            };
            if let Ok(json) = serde_json::to_string(&push) {
                if let Err(error) = tx.lock().await.send(Message::Text(json.into())).await {
                    eprintln!("[Listener] Не удалось отправить восстановленную сессию: {error}");
                }
            }

            gate.complete(None).await;
            let session_epoch = current_session_epoch();
            crate::matrix::e2ee::start_observers(tx.clone(), session_epoch).await;
            ensure_sync_loop(tx.clone()).await;
            if needs_avatar_refresh {
                refresh_current_profile_avatar(tx).await;
            }
        }
        Ok(None) => gate.complete(None).await,
        Err(error) => gate.complete(Some(error)).await,
    }
}
pub async fn listen_qml_commands(addr: &str) {
    let acceptor = match ConnectionAcceptor::bind(addr).await {
        Ok(acceptor) => acceptor,
        Err(error) => {
            eprintln!(
                "[Listener] Не удалось запустить IPC; возможно, PrismChat уже запущен: {error}"
            );
            return;
        }
    };
    let connection_slots = Arc::new(Semaphore::new(MAX_CONCURRENT_CONNECTIONS));

    loop {
        match acceptor.accept().await {
            Ok(connection) => {
                let Ok(connection_permit) = connection_slots.clone().acquire_owned().await else {
                    return;
                };
                tokio::spawn(async move {
                    let _connection_permit = connection_permit;
                    println!(
                        "[Listener] QML подключился через {}!",
                        connection.transport_name
                    );
                    let tx = connection.tx;
                    let mut rx = connection.reader;

                    // Do not restore or disclose an active session to a client that
                    // merely opens the endpoint and stays idle. The real QML client
                    // always sends get_capabilities immediately after connect.
                    let first_message = match tokio::time::timeout(
                        std::time::Duration::from_millis(IPC_HANDSHAKE_TIMEOUT_MS),
                        rx.next(),
                    )
                    .await
                    {
                        Ok(Some(Ok(message))) => message,
                        Ok(Some(Err(error))) => {
                            eprintln!("[Listener] Ошибка первичного IPC-сообщения: {error}");
                            tx.lock().await.close().await;
                            return;
                        }
                        Ok(None) => {
                            tx.lock().await.close().await;
                            return;
                        }
                        Err(_) => {
                            eprintln!("[Listener] IPC-клиент не прошёл handshake вовремя");
                            tx.lock().await.close().await;
                            return;
                        }
                    };

                    let handshake_request_id = match &first_message {
                        Message::Text(raw) => {
                            match serde_json::from_str::<QmlCommand>(raw.as_str()) {
                                Ok(QmlCommand::GetCapabilities { request_id }) => Some(request_id),
                                _ => None,
                            }
                        }
                        _ => None,
                    };
                    let Some(handshake_request_id) = handshake_request_id else {
                        eprintln!("[Listener] Первой IPC-командой должен быть get_capabilities");
                        tx.lock().await.close().await;
                        return;
                    };

                    // Acknowledge the transport immediately. Restoring the Matrix
                    // client can touch a large local store and must not make the UI
                    // look as if native IPC itself failed.
                    let capabilities = QmlResponse::Capabilities {
                        request_id: handshake_request_id,
                        timeline_diffs_v1: true,
                        media_proxy_url: crate::matrix::media_proxy::media_proxy_url(),
                        handshake_timeout_ms: IPC_HANDSHAKE_TIMEOUT_MS,
                        native_fallback_delay_ms: IPC_NATIVE_FALLBACK_DELAY_MS,
                        reconnect_delay_ms: IPC_RECONNECT_DELAY_MS,
                        default_command_timeout_ms: DEFAULT_COMMAND_TIMEOUT_MS,
                        long_command_timeout_ms: LONG_COMMAND_TIMEOUT_MS,
                    };
                    let capabilities_json = serde_json::to_string(&capabilities).unwrap();
                    if let Err(error) = tx
                        .lock()
                        .await
                        .send(Message::Text(capabilities_json.into()))
                        .await
                    {
                        eprintln!("[Listener] Не удалось подтвердить IPC handshake: {error}");
                        return;
                    }

                    let restore_gate = RestoreGate::default();
                    let restore_tx = tx.clone();
                    let restore_gate_task = restore_gate.clone();
                    tokio::spawn(restore_session_for_connection(
                        restore_tx,
                        restore_gate_task,
                    ));

                    let mut command_tasks = JoinSet::new();

                    loop {
                        let msg = match rx.next().await {
                            Some(Ok(message)) => message,
                            Some(Err(error)) => {
                                eprintln!("[Listener] Ошибка IPC: {error}");
                                break;
                            }
                            None => break,
                        };
                        if let Message::Text(raw_json) = msg {
                            if raw_json.len() > MAX_COMMAND_BYTES {
                                println!(
                            "[Listener] Команда отклонена: превышен лимит {MAX_COMMAND_BYTES} байт"
                        );
                                continue;
                            }

                            println!("[Listener] CMD: {}", command_name_for_log(&raw_json));

                            if let Ok(command) = serde_json::from_str::<QmlCommand>(&raw_json) {
                                let changes_session = command_changes_session(&command);
                                let command_gate = restore_gate.clone();
                                let command_tx = tx.clone();
                                let Ok(command_permit) =
                                    COMMAND_SLOTS.clone().acquire_owned().await
                                else {
                                    break;
                                };
                                command_tasks.spawn(async move {
                                    let _command_permit = command_permit;
                                    let session_restore_error =
                                        if matches!(&command, QmlCommand::GetCapabilities { .. }) {
                                            None
                                        } else {
                                            command_gate.wait().await
                                        };
                                    let _session_guard = if changes_session
                                        || matches!(&command, QmlCommand::VoiceBegin { .. })
                                    {
                                        Some(SESSION_LIFECYCLE_LOCK.lock().await)
                                    } else {
                                        None
                                    };
                                    if changes_session {
                                        crate::matrix::rtc::end(None, None).await;
                                    }
                                    let tx = command_tx;
                                    commands::dispatch(command, tx, session_restore_error).await;
                                });
                                while command_tasks.try_join_next().is_some() {}
                            } else {
                                println!("[Listener] Некорректная JSON-команда отклонена");
                            }
                        }
                    }

                    command_tasks.abort_all();
                    while command_tasks.join_next().await.is_some() {}
                    crate::matrix::rtc::end(None, Some(&tx)).await;
                    tx.lock().await.close().await;
                    println!("[Listener] QML отключился.");
                });
            }
            Err(error) => {
                eprintln!("[Listener] Не удалось принять IPC-соединение: {error}");
                tokio::time::sleep(std::time::Duration::from_millis(IPC_ACCEPT_RETRY_DELAY_MS))
                    .await;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{command_changes_session, command_name_for_log, RestoreGate};
    use crate::protocol::commands::QmlCommand;

    #[test]
    fn command_log_name_does_not_expose_payload() {
        let raw = r#"{"type":"login","request_id":"1","server":"matrix.org","nickname":"alice","password":"super-secret"}"#;
        let logged = command_name_for_log(raw);

        assert_eq!(logged, "login");
        assert!(!logged.contains("super-secret"));

        let key_raw = r#"{"type":"import_room_keys","request_id":"2","path":"keys.txt","passphrase":"room-key-secret"}"#;
        let key_logged = command_name_for_log(key_raw);
        assert_eq!(key_logged, "import_room_keys");
        assert!(!key_logged.contains("room-key-secret"));
    }

    #[test]
    fn only_session_lifecycle_commands_are_serialized() {
        assert!(command_changes_session(&QmlCommand::Logout {
            request_id: "logout".to_owned(),
        }));
        assert!(!command_changes_session(&QmlCommand::GetRoomList {
            request_id: "rooms".to_owned(),
        }));
    }

    #[tokio::test]
    async fn restore_gate_releases_all_waiters() {
        let gate = RestoreGate::default();
        let first_gate = gate.clone();
        let second_gate = gate.clone();
        let first = tokio::spawn(async move { first_gate.wait().await });
        let second = tokio::spawn(async move { second_gate.wait().await });

        tokio::task::yield_now().await;
        gate.complete(Some("restore failed".to_owned())).await;

        assert_eq!(first.await.unwrap().as_deref(), Some("restore failed"));
        assert_eq!(second.await.unwrap().as_deref(), Some("restore failed"));
    }
}

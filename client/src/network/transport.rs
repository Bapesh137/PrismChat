use std::sync::Arc;

use futures_util::{stream::SplitSink, stream::SplitStream, SinkExt, StreamExt};
use tokio::{
    io::{split, AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader, ReadHalf, WriteHalf},
    net::{TcpListener, TcpStream},
    sync::Mutex,
};
use tokio_tungstenite::{
    accept_async_with_config,
    tungstenite::{protocol::WebSocketConfig, Message},
    WebSocketStream,
};

pub const MAX_COMMAND_BYTES: usize = 256 * 1024;
pub const IPC_HANDSHAKE_TIMEOUT_MS: u64 = 5_000;
pub const IPC_NATIVE_FALLBACK_DELAY_MS: u64 = 500;
pub const IPC_RECONNECT_DELAY_MS: u64 = 1_000;
pub const IPC_ACCEPT_RETRY_DELAY_MS: u64 = 500;
pub const DEFAULT_COMMAND_TIMEOUT_MS: u64 = 30_000;
// Backend media/voice operations are capped at 120 seconds. Keep a small
// response-delivery margin so the GUI cannot expire the command first.
pub const LONG_COMMAND_TIMEOUT_MS: u64 = 130_000;

type WebSocket = WebSocketStream<TcpStream>;

#[cfg(windows)]
type NativeStream = tokio::net::windows::named_pipe::NamedPipeServer;
#[cfg(unix)]
type NativeStream = tokio::net::UnixStream;

pub type Tx = Arc<Mutex<ConnectionWriter>>;

pub struct Connection {
    pub tx: Tx,
    pub reader: ConnectionReader,
    pub transport_name: &'static str,
}

pub enum ConnectionReader {
    WebSocket(SplitStream<WebSocket>),
    Native(BufReader<ReadHalf<NativeStream>>),
}

pub enum ConnectionWriter {
    WebSocket(SplitSink<WebSocket, Message>),
    Native(WriteHalf<NativeStream>),
    Closed,
}

impl ConnectionWriter {
    pub async fn send(&mut self, message: Message) -> Result<(), String> {
        match self {
            Self::WebSocket(writer) => writer
                .send(message)
                .await
                .map_err(|error| format!("Ошибка отправки WebSocket: {error}")),
            Self::Native(writer) => {
                let Message::Text(text) = message else {
                    return Ok(());
                };
                writer
                    .write_all(text.as_bytes())
                    .await
                    .map_err(|error| format!("Ошибка записи в локальный IPC: {error}"))?;
                writer
                    .write_all(b"\n")
                    .await
                    .map_err(|error| format!("Ошибка записи границы IPC-команды: {error}"))?;
                writer
                    .flush()
                    .await
                    .map_err(|error| format!("Ошибка flush локального IPC: {error}"))
            }
            Self::Closed => Err("IPC-соединение уже закрыто".to_string()),
        }
    }

    pub async fn close(&mut self) {
        match std::mem::replace(self, Self::Closed) {
            Self::WebSocket(mut writer) => {
                // `WebSocketStream` queues the protocol close reply while its read
                // half handles the peer's Close frame. Closing the sink flushes
                // that queued reply; sending a second Close frame is rejected.
                let _ = writer.close().await;
            }
            Self::Native(mut writer) => {
                let _ = writer.shutdown().await;
            }
            Self::Closed => {}
        }
    }

    pub fn disconnect(&mut self) {
        *self = Self::Closed;
    }
}

impl ConnectionReader {
    pub async fn next(&mut self) -> Option<Result<Message, String>> {
        match self.next_text().await {
            Ok(Some(text)) => Some(Ok(Message::Text(text.into()))),
            Ok(None) => None,
            Err(error) => Some(Err(error)),
        }
    }

    pub async fn next_text(&mut self) -> Result<Option<String>, String> {
        match self {
            Self::WebSocket(reader) => {
                while let Some(message) = reader.next().await {
                    match message.map_err(|error| format!("Ошибка чтения WebSocket: {error}"))?
                    {
                        Message::Text(text) => return Ok(Some(text.to_string())),
                        Message::Close(_) => return Ok(None),
                        _ => {}
                    }
                }
                Ok(None)
            }
            Self::Native(reader) => {
                let mut buffer = Vec::new();
                let mut limited = (&mut *reader).take((MAX_COMMAND_BYTES + 2) as u64);
                let read = limited
                    .read_until(b'\n', &mut buffer)
                    .await
                    .map_err(|error| format!("Ошибка чтения локального IPC: {error}"))?;

                if read == 0 {
                    return Ok(None);
                }
                if buffer.len() > MAX_COMMAND_BYTES + 1 {
                    return Err(format!(
                        "IPC-команда превышает лимит {MAX_COMMAND_BYTES} байт"
                    ));
                }

                if buffer.last() == Some(&b'\n') {
                    buffer.pop();
                }
                if buffer.last() == Some(&b'\r') {
                    buffer.pop();
                }
                if buffer.len() > MAX_COMMAND_BYTES {
                    return Err(format!(
                        "IPC-команда превышает лимит {MAX_COMMAND_BYTES} байт"
                    ));
                }

                String::from_utf8(buffer)
                    .map(Some)
                    .map_err(|error| format!("IPC-команда не является UTF-8: {error}"))
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TransportMode {
    Auto,
    Native,
    WebSocket,
}

impl TransportMode {
    fn from_environment() -> Result<Self, String> {
        match std::env::var("PRISMCHAT_TRANSPORT")
            .unwrap_or_else(|_| "auto".to_string())
            .to_ascii_lowercase()
            .as_str()
        {
            "auto" => Ok(Self::Auto),
            "native" => Ok(Self::Native),
            "websocket" => Ok(Self::WebSocket),
            _ => {
                Err("PRISMCHAT_TRANSPORT должен быть равен auto, native или websocket".to_string())
            }
        }
    }
}

pub struct ConnectionAcceptor {
    mode: TransportMode,
    websocket_listener: Option<TcpListener>,
}

impl ConnectionAcceptor {
    pub async fn bind(websocket_addr: &str) -> Result<Self, String> {
        Self::bind_with_mode(websocket_addr, TransportMode::from_environment()?).await
    }

    async fn bind_with_mode(websocket_addr: &str, mode: TransportMode) -> Result<Self, String> {
        let websocket_listener = if mode == TransportMode::Native {
            None
        } else {
            let listener = TcpListener::bind(websocket_addr).await.map_err(|error| {
                format!("Не удалось занять WebSocket-порт {websocket_addr}: {error}")
            })?;
            let bound_addr = listener
                .local_addr()
                .map(|address| address.to_string())
                .unwrap_or_else(|_| websocket_addr.to_string());
            println!("[Transport] WebSocket совместимости: ws://{bound_addr}");
            Some(listener)
        };

        Ok(Self {
            mode,
            websocket_listener,
        })
    }

    pub async fn accept(&self) -> Result<Connection, String> {
        if self.mode == TransportMode::Native {
            let native_acceptor = NativeAcceptor::bind()?;
            println!("[Transport] Нативный IPC: {}", native_acceptor.endpoint());
            return native_acceptor
                .accept()
                .await
                .and_then(connection_from_native);
        }

        let websocket_listener = self
            .websocket_listener
            .as_ref()
            .expect("WebSocket listener is present outside native-only mode");

        if self.mode == TransportMode::WebSocket {
            return accept_websocket(websocket_listener).await;
        }

        let mut native_error_logged = false;
        loop {
            match NativeAcceptor::bind() {
                Ok(native_acceptor) => {
                    if native_error_logged {
                        println!("[Transport] Нативный IPC снова доступен");
                    }
                    println!("[Transport] Нативный IPC: {}", native_acceptor.endpoint());
                    return tokio::select! {
                        result = accept_websocket(websocket_listener) => result,
                        result = native_acceptor.accept() => result.and_then(connection_from_native),
                    };
                }
                Err(error) => {
                    if !native_error_logged {
                        eprintln!(
                            "[Transport] Нативный IPC временно занят, продолжаю принимать WebSocket: {error}"
                        );
                        native_error_logged = true;
                    }
                    tokio::select! {
                        result = accept_websocket(websocket_listener) => return result,
                        _ = tokio::time::sleep(std::time::Duration::from_millis(
                            IPC_ACCEPT_RETRY_DELAY_MS,
                        )) => {}
                    }
                }
            }
        }
    }

    #[cfg(test)]
    fn websocket_addr(&self) -> std::net::SocketAddr {
        self.websocket_listener
            .as_ref()
            .expect("test acceptor has a WebSocket listener")
            .local_addr()
            .expect("test WebSocket listener has a local address")
    }
}

async fn accept_websocket(listener: &TcpListener) -> Result<Connection, String> {
    let (stream, _) = listener
        .accept()
        .await
        .map_err(|error| format!("Ошибка принятия WebSocket-соединения: {error}"))?;
    let config = WebSocketConfig::default()
        .max_message_size(Some(MAX_COMMAND_BYTES))
        .max_frame_size(Some(MAX_COMMAND_BYTES));
    let websocket = accept_async_with_config(stream, Some(config))
        .await
        .map_err(|error| format!("Ошибка WebSocket handshake: {error}"))?;
    let (writer, reader) = websocket.split();

    Ok(Connection {
        tx: Arc::new(Mutex::new(ConnectionWriter::WebSocket(writer))),
        reader: ConnectionReader::WebSocket(reader),
        transport_name: "WebSocket",
    })
}

fn connection_from_native(stream: NativeStream) -> Result<Connection, String> {
    let (reader, writer) = split(stream);
    Ok(Connection {
        tx: Arc::new(Mutex::new(ConnectionWriter::Native(writer))),
        reader: ConnectionReader::Native(BufReader::new(reader)),
        transport_name: "Named Pipe/UDS",
    })
}

#[cfg(windows)]
struct NativeAcceptor {
    server: tokio::net::windows::named_pipe::NamedPipeServer,
}

#[cfg(windows)]
impl NativeAcceptor {
    const PIPE_NAME: &'static str = r"\\.\pipe\prismchat";

    fn bind() -> Result<Self, String> {
        let mut options = tokio::net::windows::named_pipe::ServerOptions::new();
        options
            .first_pipe_instance(true)
            .reject_remote_clients(true);
        let server = options
            .create(Self::PIPE_NAME)
            .map_err(|error| format!("Не удалось создать {}: {error}", Self::PIPE_NAME))?;
        Ok(Self { server })
    }

    fn endpoint(&self) -> String {
        Self::PIPE_NAME.to_string()
    }

    async fn accept(self) -> Result<NativeStream, String> {
        self.server
            .connect()
            .await
            .map_err(|error| format!("Ошибка подключения Named Pipe: {error}"))?;
        Ok(self.server)
    }
}

#[cfg(unix)]
struct NativeAcceptor {
    listener: tokio::net::UnixListener,
    path: std::path::PathBuf,
}

#[cfg(unix)]
impl NativeAcceptor {
    fn bind() -> Result<Self, String> {
        use std::os::unix::fs::{FileTypeExt, PermissionsExt};

        let path = std::env::var_os("PRISMCHAT_UDS_PATH")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| {
                dirs::runtime_dir()
                    .unwrap_or_else(std::env::temp_dir)
                    .join("prismchat.sock")
            });

        match std::fs::symlink_metadata(&path) {
            Ok(metadata) if metadata.file_type().is_socket() => {
                std::fs::remove_file(&path).map_err(|error| {
                    format!("Не удалось удалить старый UDS {}: {error}", path.display())
                })?;
            }
            Ok(_) => {
                return Err(format!(
                    "Путь UDS {} уже занят не socket-файлом",
                    path.display()
                ));
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(format!(
                    "Не удалось проверить путь UDS {}: {error}",
                    path.display()
                ));
            }
        }

        let listener = tokio::net::UnixListener::bind(&path)
            .map_err(|error| format!("Не удалось создать UDS {}: {error}", path.display()))?;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).map_err(
            |error| {
                format!(
                    "Не удалось ограничить права UDS {}: {error}",
                    path.display()
                )
            },
        )?;

        Ok(Self { listener, path })
    }

    fn endpoint(&self) -> String {
        self.path.display().to_string()
    }

    async fn accept(self) -> Result<NativeStream, String> {
        let (stream, _) = self
            .listener
            .accept()
            .await
            .map_err(|error| format!("Ошибка подключения UDS: {error}"))?;
        let _ = std::fs::remove_file(&self.path);
        Ok(stream)
    }
}
#[cfg(test)]
mod tests {
    use super::{ConnectionAcceptor, TransportMode};
    use futures_util::SinkExt;
    use tokio_tungstenite::tungstenite::Message;

    async fn exchange_once(acceptor: &ConnectionAcceptor, url: &str, payload: &str) {
        let client_task = tokio::spawn(tokio_tungstenite::connect_async(url.to_string()));
        let mut connection = acceptor.accept().await.expect("server accepts WebSocket");
        let (mut client, _) = client_task
            .await
            .expect("client task completes")
            .expect("client connects");

        client
            .send(Message::Text(payload.to_string().into()))
            .await
            .expect("client sends payload");
        let received = connection
            .reader
            .next_text()
            .await
            .expect("server reads payload");
        assert_eq!(received.as_deref(), Some(payload));

        client.close(None).await.expect("client closes cleanly");
        connection.tx.lock().await.disconnect();
    }

    #[tokio::test]
    async fn websocket_acceptor_allows_reconnect_without_rebinding() {
        let acceptor = ConnectionAcceptor::bind_with_mode("127.0.0.1:0", TransportMode::WebSocket)
            .await
            .expect("test listener binds once");
        let url = format!("ws://{}", acceptor.websocket_addr());

        exchange_once(&acceptor, &url, "first").await;
        exchange_once(&acceptor, &url, "second").await;
    }
}

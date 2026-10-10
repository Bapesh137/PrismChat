use axum::{
    body::Body,
    extract::Query,
    http::{header, HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use futures_util::StreamExt;
use matrix_sdk::{
    media::{MediaFileHandle, MediaFormat, MediaRequestParameters, MediaThumbnailSettings},
    ruma::events::room::{EncryptedFile, MediaSource},
};
use rand::{rngs::OsRng, RngCore};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, LazyLock, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::{Mutex as AsyncMutex, Semaphore};
use tokio::{
    io::SeekFrom,
    io::{AsyncReadExt, AsyncSeekExt},
};
use tokio_util::io::ReaderStream;

use crate::matrix::{
    media::{media_request_from_mxc, MAX_MEDIA_BYTES},
    session::{current_session_epoch, get_client},
};

const MEDIA_CAPABILITY_TTL: Duration = Duration::from_secs(30 * 60);
const MAX_MEDIA_CAPABILITIES: usize = 512;
const MEDIA_REQUEST_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_MATERIALIZED_FILES: usize = 256;
const MAX_MATERIALIZED_BYTES: u64 = 512 * 1024 * 1024;
const MATERIALIZED_MEDIA_TTL: Duration = Duration::from_secs(15 * 60);

#[derive(Clone)]
struct EncryptedMediaCapability {
    session_epoch: u64,
    file: EncryptedFile,
    content_type: String,
    created_at: Instant,
}

static SERVER_TOKEN: LazyLock<Mutex<(u64, String)>> =
    LazyLock::new(|| Mutex::new((current_session_epoch(), random_token())));
static MEDIA_CAPABILITIES: LazyLock<Mutex<HashMap<String, EncryptedMediaCapability>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
// Plain and encrypted media are currently materialized in memory before the
// HTTP response is served. Bound concurrency to cap worst-case peak RSS.
static MEDIA_SEMAPHORE: LazyLock<Semaphore> = LazyLock::new(|| Semaphore::new(2));
static MEDIA_FETCH_LOCKS: LazyLock<AsyncMutex<HashMap<String, Arc<AsyncMutex<()>>>>> =
    LazyLock::new(|| AsyncMutex::new(HashMap::new()));

struct MaterializedMedia {
    _handle: MediaFileHandle,
    path: PathBuf,
    len: u64,
    content_type: String,
    session_epoch: u64,
}

struct CachedMaterializedMedia {
    media: Arc<MaterializedMedia>,
    last_access: Instant,
}

static MATERIALIZED_MEDIA: LazyLock<Mutex<HashMap<String, CachedMaterializedMedia>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn random_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn server_token() -> String {
    let epoch = current_session_epoch();
    let Ok(mut token) = SERVER_TOKEN.lock() else {
        return random_token();
    };
    if token.0 != epoch {
        *token = (epoch, random_token());
    }
    token.1.clone()
}
pub fn media_proxy_url() -> String {
    format!("http://127.0.0.1:3043/media?token={}&url=", server_token())
}

pub fn clear_media_capabilities() {
    if let Ok(mut entries) = MEDIA_CAPABILITIES.lock() {
        entries.clear();
    }
    if let Ok(mut files) = MATERIALIZED_MEDIA.lock() {
        // Dropping the SDK MediaFileHandles securely removes their temporary
        // files. Session epochs ensure old-account paths are never reused.
        files.clear();
    }
}

fn cached_materialized_media(cache_key: &str) -> Option<Arc<MaterializedMedia>> {
    let mut files = MATERIALIZED_MEDIA.lock().ok()?;
    let epoch = current_session_epoch();
    let now = Instant::now();
    files.retain(|_, entry| {
        entry.media.session_epoch == epoch
            && (now.duration_since(entry.last_access) <= MATERIALIZED_MEDIA_TTL
                || Arc::strong_count(&entry.media) > 1)
    });
    let entry = files.get_mut(cache_key)?;
    entry.last_access = Instant::now();
    Some(entry.media.clone())
}

fn insert_materialized_media(cache_key: String, media: Arc<MaterializedMedia>) {
    let Ok(mut files) = MATERIALIZED_MEDIA.lock() else {
        return;
    };
    files.retain(|_, entry| entry.media.session_epoch == current_session_epoch());
    files.insert(
        cache_key,
        CachedMaterializedMedia {
            media,
            last_access: Instant::now(),
        },
    );

    loop {
        let total_bytes = files.values().map(|entry| entry.media.len).sum::<u64>();
        if files.len() <= MAX_MATERIALIZED_FILES && total_bytes <= MAX_MATERIALIZED_BYTES {
            break;
        }
        let victim = files
            .iter()
            .filter(|(_, entry)| Arc::strong_count(&entry.media) == 1)
            .min_by_key(|(_, entry)| entry.last_access)
            .map(|(key, _)| key.clone());
        let Some(victim) = victim else { break };
        files.remove(&victim);
    }
}

pub fn decorate_encrypted_file(
    mut value: serde_json::Value,
    content_type: Option<&str>,
) -> serde_json::Value {
    let Ok(file) = serde_json::from_value::<EncryptedFile>(value.clone()) else {
        return value;
    };

    let id = random_token();
    if let Ok(mut entries) = MEDIA_CAPABILITIES.lock() {
        let now = Instant::now();
        entries.retain(|_, entry| {
            entry.session_epoch == current_session_epoch()
                && now.duration_since(entry.created_at) <= MEDIA_CAPABILITY_TTL
        });
        if entries.len() >= MAX_MEDIA_CAPABILITIES {
            if let Some(oldest) = entries
                .iter()
                .min_by_key(|(_, entry)| entry.created_at)
                .map(|(id, _)| id.clone())
            {
                entries.remove(&oldest);
            }
        }
        entries.insert(
            id.clone(),
            EncryptedMediaCapability {
                session_epoch: current_session_epoch(),
                file,
                content_type: safe_content_type(content_type),
                created_at: now,
            },
        );
        if let Some(object) = value.as_object_mut() {
            object.insert("_prism_media_id".to_owned(), serde_json::Value::String(id));
        }
    }
    value
}

fn encrypted_capability(id: &str) -> Option<EncryptedMediaCapability> {
    let mut entries = MEDIA_CAPABILITIES.lock().ok()?;
    let now = Instant::now();
    let epoch = current_session_epoch();
    entries.retain(|_, entry| {
        entry.session_epoch == epoch && now.duration_since(entry.created_at) <= MEDIA_CAPABILITY_TTL
    });
    entries.get(id).cloned()
}

fn safe_content_type(value: Option<&str>) -> String {
    let value = value.unwrap_or_default().trim().to_ascii_lowercase();
    let allowed = value.starts_with("image/") && value != "image/svg+xml"
        || value.starts_with("audio/")
        || value.starts_with("video/")
        || matches!(
            value.as_str(),
            "application/pdf" | "application/json" | "text/plain" | "application/octet-stream"
        );
    if allowed {
        value
    } else {
        "application/octet-stream".to_owned()
    }
}

fn encode_filename(filename: &str) -> String {
    filename
        .as_bytes()
        .iter()
        .map(|byte| match *byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'.' | b'_' | b'-' => {
                (*byte as char).to_string()
            }
            other => format!("%{other:02X}"),
        })
        .collect()
}

fn download_disposition(params: &HashMap<String, String>) -> Option<String> {
    if params.get("download").map(String::as_str) != Some("1") {
        return None;
    }

    let requested = params
        .get("filename")
        .map(String::as_str)
        .unwrap_or("attachment");
    let leaf = Path::new(requested)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("attachment");
    let cleaned = leaf
        .chars()
        .filter(|character| !character.is_control())
        .collect::<String>();
    let filename = if cleaned.trim().is_empty() {
        "attachment"
    } else {
        cleaned.trim()
    };

    Some(format!(
        "attachment; filename*=UTF-8''{}",
        encode_filename(filename)
    ))
}

fn requested_range(headers: &HeaderMap, len: usize) -> Result<Option<(usize, usize)>, ()> {
    let Some(value) = headers.get(header::RANGE) else {
        return Ok(None);
    };
    let value = value.to_str().map_err(|_| ())?;
    let spec = value.strip_prefix("bytes=").ok_or(())?;
    if spec.contains(',') || len == 0 {
        return Err(());
    }

    let (start_text, end_text) = spec.split_once('-').ok_or(())?;
    if start_text.is_empty() {
        let suffix_len = end_text.parse::<usize>().map_err(|_| ())?;
        if suffix_len == 0 {
            return Err(());
        }
        let start = len.saturating_sub(suffix_len.min(len));
        return Ok(Some((start, len - 1)));
    }

    let start = start_text.parse::<usize>().map_err(|_| ())?;
    if start >= len {
        return Err(());
    }
    let end = if end_text.is_empty() {
        len - 1
    } else {
        end_text.parse::<usize>().map_err(|_| ())?.min(len - 1)
    };
    if end < start {
        return Err(());
    }
    Ok(Some((start, end)))
}

fn security_headers(builder: axum::http::response::Builder) -> axum::http::response::Builder {
    builder
        .header(header::CACHE_CONTROL, "private, no-store")
        .header("Pragma", "no-cache")
        .header("X-Content-Type-Options", "nosniff")
        .header("Cross-Origin-Resource-Policy", "same-origin")
        .header("Referrer-Policy", "no-referrer")
}

async fn proxy_handler(
    headers: HeaderMap,
    Query(params): Query<HashMap<String, String>>,
) -> Response {
    let expected_token = server_token();
    if params.get("token").map(String::as_str) != Some(expected_token.as_str()) {
        return StatusCode::NOT_FOUND.into_response();
    }

    let disposition = download_disposition(&params);
    let requested_mxc = params.get("url").cloned().unwrap_or_default();
    let requested_thumbnail = params
        .get("width")
        .and_then(|value| value.parse::<u64>().ok())
        .zip(
            params
                .get("height")
                .and_then(|value| value.parse::<u64>().ok()),
        )
        .map(|(width, height)| (width.clamp(16, 2048), height.clamp(16, 2048)));
    let source = if let Some(id) = params.get("file_id") {
        let Some(capability) = encrypted_capability(id) else {
            return StatusCode::NOT_FOUND.into_response();
        };
        if !requested_mxc.is_empty() && capability.file.url.as_str() != requested_mxc {
            return StatusCode::BAD_REQUEST.into_response();
        }
        let cache_key = format!("encrypted:{}", capability.file.url.as_str());
        EitherMedia::Encrypted(capability.file, capability.content_type, cache_key)
    } else {
        if crate::matrix::media::media_request_from_mxc(&requested_mxc).is_err() {
            return StatusCode::BAD_REQUEST.into_response();
        }
        let cache_key = requested_thumbnail
            .map(|(width, height)| format!("plain:{requested_mxc}:{width}x{height}"))
            .unwrap_or_else(|| format!("plain:{requested_mxc}"));
        EitherMedia::Plain(
            requested_mxc,
            safe_content_type(params.get("mime").map(String::as_str)),
            cache_key,
        )
    };

    let requested_filename = params.get("filename").cloned();
    let request_epoch = current_session_epoch();
    // QML retries media requested before SessionRestored.
    let client = match get_client().await {
        Ok(client) => client,
        Err(_) => return StatusCode::SERVICE_UNAVAILABLE.into_response(),
    };
    let media_future = async {
        let cache_key = match &source {
            EitherMedia::Encrypted(_, _, cache_key) | EitherMedia::Plain(_, _, cache_key) => {
                cache_key.clone()
            }
        };

        if let Some(media) = cached_materialized_media(&cache_key) {
            return Ok::<_, String>(media);
        }

        // Coalesce FFmpeg's overlapping initial Range requests.
        let fetch_lock = {
            let mut locks = MEDIA_FETCH_LOCKS.lock().await;
            if locks.len() > MAX_MEDIA_CAPABILITIES {
                locks.retain(|_, lock| Arc::strong_count(lock) > 1);
            }
            locks
                .entry(cache_key.clone())
                .or_insert_with(|| Arc::new(AsyncMutex::new(())))
                .clone()
        };
        let _fetch_guard = fetch_lock.lock().await;

        if let Some(media) = cached_materialized_media(&cache_key) {
            return Ok(media);
        }

        // The outer timeout bounds queueing and fetch; the semaphore bounds memory.
        let _permit = MEDIA_SEMAPHORE
            .acquire()
            .await
            .map_err(|_| "Очередь медиапрокси закрыта".to_owned())?;

        let (request, requested_content_type) = match source {
            EitherMedia::Encrypted(file, content_type, _) => (
                MediaRequestParameters {
                    source: MediaSource::Encrypted(Box::new(file)),
                    format: MediaFormat::File,
                },
                content_type,
            ),
            EitherMedia::Plain(mxc_url, content_type, _) => {
                let mut request = media_request_from_mxc(&mxc_url)?;
                if let Some((width, height)) = requested_thumbnail {
                    let width = matrix_sdk::ruma::UInt::try_from(width)
                        .map_err(|_| "Некорректная ширина thumbnail".to_owned())?;
                    let height = matrix_sdk::ruma::UInt::try_from(height)
                        .map_err(|_| "Некорректная высота thumbnail".to_owned())?;
                    request.format =
                        MediaFormat::Thumbnail(MediaThumbnailSettings::new(width, height));
                }
                (request, content_type)
            }
        };
        let safe_type = safe_content_type(Some(&requested_content_type));
        let mime = safe_type
            .parse()
            .map_err(|error| format!("Некорректный MIME type медиа: {error}"))?;
        let handle = client
            .media()
            .get_media_file(&request, requested_filename, &mime, true, None)
            .await
            .map_err(|error| format!("SDK не смог материализовать медиа: {error}"))?;
        if current_session_epoch() != request_epoch {
            return Err("Matrix-сессия изменилась во время загрузки медиа".to_owned());
        }
        let path = handle.path().to_path_buf();
        let metadata = std::fs::symlink_metadata(&path)
            .map_err(|error| format!("Не удалось проверить временное медиа: {error}"))?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            return Err("SDK вернул небезопасный временный media path".to_owned());
        }
        if metadata.len() > MAX_MEDIA_BYTES as u64 {
            return Err("Медиа превышает лимит 100 МиБ".to_owned());
        }
        let media = Arc::new(MaterializedMedia {
            _handle: handle,
            path,
            len: metadata.len(),
            content_type: safe_type,
            session_epoch: request_epoch,
        });
        insert_materialized_media(cache_key, media.clone());
        Ok(media)
    };

    let media_result = tokio::time::timeout(MEDIA_REQUEST_TIMEOUT, media_future).await;

    let media = match media_result {
        Ok(Ok(result)) => result,
        Ok(Err(error)) => {
            eprintln!("[Proxy] Не удалось получить медиа: {error}");
            return StatusCode::BAD_GATEWAY.into_response();
        }
        Err(_) => return StatusCode::GATEWAY_TIMEOUT.into_response(),
    };
    let content_type = media
        .content_type
        .parse::<HeaderValue>()
        .unwrap_or_else(|_| HeaderValue::from_static("application/octet-stream"));
    let total_len = media.len as usize;

    let mut file = match tokio::fs::File::open(&media.path).await {
        Ok(file) => file,
        Err(_) => return StatusCode::NOT_FOUND.into_response(),
    };

    match requested_range(&headers, total_len) {
        Ok(Some((start, end))) => {
            if file.seek(SeekFrom::Start(start as u64)).await.is_err() {
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
            let partial_len = end - start + 1;
            let media_guard = media.clone();
            let stream = ReaderStream::new(file.take(partial_len as u64)).map(move |chunk| {
                let _keep_alive = &media_guard;
                chunk
            });
            let mut builder = security_headers(Response::builder())
                .status(StatusCode::PARTIAL_CONTENT)
                .header(header::CONTENT_TYPE, content_type)
                .header(header::CONTENT_LENGTH, partial_len.to_string())
                .header(
                    header::CONTENT_RANGE,
                    format!("bytes {start}-{end}/{total_len}"),
                )
                .header(header::ACCEPT_RANGES, "bytes");
            if let Some(value) = disposition.as_deref() {
                builder = builder.header(header::CONTENT_DISPOSITION, value);
            }
            builder.body(Body::from_stream(stream)).unwrap()
        }
        Ok(None) => {
            let mut builder = security_headers(Response::builder())
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, content_type)
                .header(header::CONTENT_LENGTH, total_len.to_string())
                .header(header::ACCEPT_RANGES, "bytes");
            if let Some(value) = disposition.as_deref() {
                builder = builder.header(header::CONTENT_DISPOSITION, value);
            }
            let media_guard = media.clone();
            let stream = ReaderStream::new(file).map(move |chunk| {
                let _keep_alive = &media_guard;
                chunk
            });
            builder.body(Body::from_stream(stream)).unwrap()
        }
        Err(()) => security_headers(Response::builder())
            .status(StatusCode::RANGE_NOT_SATISFIABLE)
            .header(header::CONTENT_RANGE, format!("bytes */{total_len}"))
            .header(header::ACCEPT_RANGES, "bytes")
            .body(Body::empty())
            .unwrap(),
    }
}

enum EitherMedia {
    Plain(String, String, String),
    Encrypted(EncryptedFile, String, String),
}

pub async fn start_media_proxy(addr: &str) -> Result<(), String> {
    let app = Router::new().route("/media", get(proxy_handler));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|error| format!("не удалось занять локальный медиапорт: {error}"))?;

    println!("[Proxy] Защищённый медиапрокси готов");
    axum::serve(listener, app)
        .await
        .map_err(|error| format!("ошибка HTTP-сервера: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_dangerous_content_types() {
        assert_eq!(
            safe_content_type(Some("text/html")),
            "application/octet-stream"
        );
        assert_eq!(
            safe_content_type(Some("image/svg+xml")),
            "application/octet-stream"
        );
        assert_eq!(safe_content_type(Some("image/png")), "image/png");
    }

    #[test]
    fn creates_safe_utf8_download_header() {
        let params = HashMap::from([
            ("download".to_owned(), "1".to_owned()),
            ("filename".to_owned(), "../Отчёт 2026.pdf".to_owned()),
        ]);
        let value = download_disposition(&params).expect("download header");
        assert!(!value.contains("../"));
        assert!(value.contains("%D0%9E"));
    }
}

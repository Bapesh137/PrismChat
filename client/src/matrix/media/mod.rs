mod builtin_stickers;
use builtin_stickers::render_builtin_payload;

use matrix_sdk::{
    attachment::{AttachmentInfo, BaseAudioInfo, BaseFileInfo, BaseImageInfo, BaseVideoInfo},
    media::{MediaFormat, MediaRequestParameters},
    ruma::{
        events::{
            room::{EncryptedFile, ImageInfo, MediaSource},
            sticker::StickerEventContent,
            AnyMessageLikeEventContent,
        },
        MxcUri, UInt,
    },
    TransmissionProgress,
};
use std::{io::Cursor, path::Path, sync::LazyLock, time::Duration};
use tokio::{
    io::{AsyncReadExt, BufReader},
    sync::{mpsc::UnboundedSender, Semaphore},
};

use crate::matrix::session::get_client;
use matrix_sdk_ui::timeline::{AttachmentConfig, AttachmentSource};

pub const MAX_MEDIA_BYTES: usize = 100 * 1024 * 1024;
const MAX_AVATAR_BYTES: usize = 10 * 1024 * 1024;
// Uploads are currently buffered as complete byte vectors by matrix-sdk.
// Serializing them prevents two 100 MiB files from doubling peak RSS.
static UPLOAD_SEMAPHORE: LazyLock<Semaphore> = LazyLock::new(|| Semaphore::new(1));

pub async fn read_bounded_regular_file(path: &str, max_bytes: usize) -> Result<Vec<u8>, String> {
    let metadata = tokio::fs::symlink_metadata(path)
        .await
        .map_err(|error| format!("Не удалось проверить выбранный файл: {error}"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err("Разрешены только обычные файлы, не символические ссылки".to_owned());
    }
    if metadata.len() > max_bytes as u64 {
        return Err(format!(
            "Файл превышает лимит {} МиБ",
            max_bytes / 1024 / 1024
        ));
    }

    let file = tokio::fs::File::open(path)
        .await
        .map_err(|error| format!("Не удалось открыть выбранный файл: {error}"))?;
    let opened_metadata = file
        .metadata()
        .await
        .map_err(|error| format!("Не удалось проверить открытый файл: {error}"))?;
    if !opened_metadata.is_file() || opened_metadata.len() > max_bytes as u64 {
        return Err("Файл изменился или превышает допустимый размер".to_owned());
    }

    let mut bytes = Vec::with_capacity(opened_metadata.len() as usize);
    BufReader::new(file)
        .take((max_bytes + 1) as u64)
        .read_to_end(&mut bytes)
        .await
        .map_err(|error| format!("Не удалось прочитать выбранный файл: {error}"))?;
    if bytes.len() > max_bytes {
        return Err(format!(
            "Файл превышает лимит {} МиБ",
            max_bytes / 1024 / 1024
        ));
    }
    Ok(bytes)
}

fn effective_mime_type(path: &str, filename: &str, requested: &str) -> String {
    let requested = requested.trim();
    if !requested.is_empty()
        && requested != "application/octet-stream"
        && requested != "binary/octet-stream"
    {
        return requested.to_owned();
    }

    mime_guess::from_path(filename)
        .first()
        .or_else(|| mime_guess::from_path(path).first())
        .map(|mime| mime.essence_str().to_owned())
        .unwrap_or_else(|| "application/octet-stream".to_owned())
}

fn attachment_info(mime_type: &str, file_size: u64, duration_ms: Option<u64>) -> AttachmentInfo {
    let size = UInt::try_from(file_size).ok();
    if mime_type.starts_with("image/") {
        AttachmentInfo::Image(BaseImageInfo {
            size,
            ..Default::default()
        })
    } else if mime_type.starts_with("video/") {
        AttachmentInfo::Video(BaseVideoInfo {
            size,
            duration: duration_ms.map(Duration::from_millis),
            ..Default::default()
        })
    } else if mime_type.starts_with("audio/") {
        let info = BaseAudioInfo {
            size,
            duration: duration_ms.map(Duration::from_millis),
            ..Default::default()
        };
        if duration_ms.is_some() {
            AttachmentInfo::Voice(info)
        } else {
            AttachmentInfo::Audio(info)
        }
    } else {
        AttachmentInfo::File(BaseFileInfo { size })
    }
}

pub async fn send_attachment_with_progress(
    room_id: &str,
    path: &str,
    mime_type: &str,
    filename: &str,
    duration_ms: Option<u64>,
    progress_tx: UnboundedSender<TransmissionProgress>,
) -> Result<(), String> {
    let _permit = tokio::time::timeout(Duration::from_secs(5), UPLOAD_SEMAPHORE.acquire())
        .await
        .map_err(|_| "Слишком много параллельных загрузок".to_owned())?
        .map_err(|_| "Очередь загрузок закрыта".to_owned())?;

    let bytes = read_bounded_regular_file(path, MAX_MEDIA_BYTES).await?;
    let file_size = bytes.len() as u64;
    let effective_mime = effective_mime_type(path, filename, mime_type);
    let mime = effective_mime
        .parse()
        .map_err(|error| format!("Некорректный MIME type: {error}"))?;
    let safe_filename = Path::new(filename)
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.trim().is_empty())
        .unwrap_or("attachment")
        .to_owned();

    let timeline = crate::matrix::timeline_manager::get_or_create_timeline(room_id).await?;
    let send = timeline.send_attachment(
        AttachmentSource::Data {
            bytes,
            filename: safe_filename,
        },
        mime,
        AttachmentConfig {
            info: Some(attachment_info(&effective_mime, file_size, duration_ms)),
            ..Default::default()
        },
    );
    let mut subscriber = send.subscribe_to_send_progress();
    let progress_task = tokio::spawn(async move {
        while let Some(progress) = subscriber.next().await {
            if progress_tx.send(progress).is_err() {
                break;
            }
        }
    });

    let result = send
        .await
        .map_err(|error| format!("Ошибка отправки вложения: {error}"));
    progress_task.abort();
    result
}

/// Upload an image and send it as the standard Matrix `m.sticker` event.
/// In encrypted rooms the media bytes are encrypted before upload as well,
/// so the homeserver cannot inspect the sticker image.
pub async fn send_sticker_with_progress(
    room_id: &str,
    path: &str,
    mime_type: &str,
    filename: &str,
    progress_tx: UnboundedSender<TransmissionProgress>,
) -> Result<(), String> {
    let _permit = tokio::time::timeout(Duration::from_secs(5), UPLOAD_SEMAPHORE.acquire())
        .await
        .map_err(|_| "Слишком много параллельных загрузок".to_owned())?
        .map_err(|_| "Очередь загрузок закрыта".to_owned())?;

    let bytes = read_bounded_regular_file(path, MAX_MEDIA_BYTES).await?;
    let file_size = bytes.len() as u64;
    let effective_mime = effective_mime_type(path, filename, mime_type);
    if !effective_mime.starts_with("image/") {
        return Err("Стикер должен быть изображением".to_owned());
    }
    let mime = effective_mime
        .parse()
        .map_err(|error| format!("Некорректный MIME type: {error}"))?;
    let safe_filename = Path::new(filename)
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.trim().is_empty())
        .unwrap_or("sticker")
        .to_owned();

    let client = get_client().await?;
    let room_id_parsed = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(room_id_parsed)
        .ok_or_else(|| format!("Комната не найдена в SDK: {room_id_parsed}"))?;

    let media_source = if room
        .latest_encryption_state()
        .await
        .map_err(|error| format!("Не удалось определить шифрование комнаты: {error}"))?
        .is_encrypted()
    {
        let mut cursor = Cursor::new(bytes);
        let upload = client.upload_encrypted_file(&mut cursor);
        let mut subscriber = upload.subscribe_to_send_progress();
        let progress_tx = progress_tx.clone();
        let progress_task = tokio::spawn(async move {
            while let Some(progress) = subscriber.next().await {
                if progress_tx.send(progress).is_err() {
                    break;
                }
            }
        });
        let encrypted_file = upload
            .await
            .map_err(|error| format!("Ошибка загрузки зашифрованного стикера: {error}"));
        progress_task.abort();
        MediaSource::Encrypted(Box::new(encrypted_file?))
    } else {
        let upload = client.media().upload(&mime, bytes, None);
        let mut subscriber = upload.subscribe_to_send_progress();
        let progress_task = tokio::spawn(async move {
            while let Some(progress) = subscriber.next().await {
                if progress_tx.send(progress).is_err() {
                    break;
                }
            }
        });
        let response = upload
            .await
            .map_err(|error| format!("Ошибка загрузки стикера: {error}"));
        progress_task.abort();
        MediaSource::Plain(response?.content_uri)
    };

    let mut info = ImageInfo::new();
    info.mimetype = Some(effective_mime);
    info.size = UInt::try_from(file_size).ok();
    let content = StickerEventContent::with_source(safe_filename, info, media_source.into());
    let timeline = crate::matrix::timeline_manager::get_or_create_timeline(room_id).await?;
    timeline
        .send(AnyMessageLikeEventContent::Sticker(content))
        .await
        .map_err(|error| format!("Ошибка отправки стикера: {error}"))?;
    Ok(())
}

pub async fn send_builtin_sticker(room_id: &str, sticker_id: &str) -> Result<(), String> {
    let _permit = tokio::time::timeout(Duration::from_secs(5), UPLOAD_SEMAPHORE.acquire())
        .await
        .map_err(|_| "Слишком много параллельных загрузок".to_owned())?
        .map_err(|_| "Очередь загрузок закрыта".to_owned())?;

    let (bytes, body, builtin_mime) = render_builtin_payload(sticker_id)?;
    let file_size = bytes.len() as u64;
    let mime = builtin_mime
        .parse()
        .map_err(|error| format!("Некорректный MIME type встроенного стикера: {error}"))?;

    let client = get_client().await?;
    let room_id_parsed = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(room_id_parsed)
        .ok_or_else(|| format!("Комната не найдена в SDK: {room_id_parsed}"))?;

    let source = if room
        .latest_encryption_state()
        .await
        .map_err(|error| format!("Не удалось определить шифрование комнаты: {error}"))?
        .is_encrypted()
    {
        let mut cursor = Cursor::new(bytes);
        MediaSource::Encrypted(Box::new(
            client
                .upload_encrypted_file(&mut cursor)
                .await
                .map_err(|error| format!("Ошибка загрузки встроенного стикера: {error}"))?,
        ))
    } else {
        MediaSource::Plain(
            client
                .media()
                .upload(&mime, bytes, None)
                .await
                .map_err(|error| format!("Ошибка загрузки встроенного стикера: {error}"))?
                .content_uri,
        )
    };

    let mut info = ImageInfo::new();
    info.mimetype = Some(builtin_mime.to_owned());
    info.size = UInt::try_from(file_size).ok();
    let content = StickerEventContent::with_source(body.to_owned(), info, source.into());
    let timeline = crate::matrix::timeline_manager::get_or_create_timeline(room_id).await?;
    timeline
        .send(AnyMessageLikeEventContent::Sticker(content))
        .await
        .map_err(|error| format!("Ошибка отправки встроенного стикера: {error}"))?;
    Ok(())
}

pub async fn send_sticker_reference(
    room_id: &str,
    body: &str,
    media_url: Option<&str>,
    media_file: Option<serde_json::Value>,
    mime_type: Option<&str>,
) -> Result<(), String> {
    let source = if let Some(mut value) = media_file {
        if let Some(object) = value.as_object_mut() {
            // QML receives this private capability token only for the local
            // media proxy. It is not part of Matrix EncryptedFile.
            object.remove("_prism_media_id");
        }
        let file = serde_json::from_value::<EncryptedFile>(value)
            .map_err(|error| format!("Некорректные данные зашифрованного стикера: {error}"))?;
        MediaSource::Encrypted(Box::new(file))
    } else {
        let url = media_url
            .filter(|value| !value.trim().is_empty())
            .ok_or_else(|| "У стикера отсутствует Matrix media URL".to_owned())?;
        let mxc = <&MxcUri>::from(url);
        mxc.validate()
            .map_err(|error| format!("Некорректный mxc URI стикера: {error}"))?;
        MediaSource::Plain(mxc.to_owned())
    };

    let mut info = ImageInfo::new();
    info.mimetype = mime_type
        .filter(|value| value.starts_with("image/"))
        .map(str::to_owned);

    let sticker_body = if body.trim().is_empty() {
        "Стикер".to_owned()
    } else {
        body.to_owned()
    };
    let content = StickerEventContent::with_source(sticker_body, info, source.into());
    let timeline = crate::matrix::timeline_manager::get_or_create_timeline(room_id).await?;
    timeline
        .send(AnyMessageLikeEventContent::Sticker(content))
        .await
        .map_err(|error| format!("Ошибка отправки стикера: {error}"))?;
    Ok(())
}

pub async fn upload_sticker_asset(
    path: &str,
    mime_type: &str,
    filename: &str,
) -> Result<(String, String), String> {
    let _permit = tokio::time::timeout(Duration::from_secs(5), UPLOAD_SEMAPHORE.acquire())
        .await
        .map_err(|_| "Слишком много параллельных загрузок".to_owned())?
        .map_err(|_| "Очередь загрузок закрыта".to_owned())?;

    let bytes = read_bounded_regular_file(path, MAX_MEDIA_BYTES).await?;
    let effective_mime = effective_mime_type(path, filename, mime_type);
    if !effective_mime.starts_with("image/") || effective_mime == "image/svg+xml" {
        return Err("Стикер должен быть PNG, JPEG, WebP, GIF или APNG".to_owned());
    }
    let mime = effective_mime
        .parse()
        .map_err(|error| format!("Некорректный MIME type стикера: {error}"))?;
    let client = get_client().await?;
    let response = client
        .media()
        .upload(&mime, bytes, None)
        .await
        .map_err(|error| format!("Ошибка загрузки стикера в набор: {error}"))?;
    Ok((response.content_uri.to_string(), effective_mime))
}

fn sanitized_sticker_pack(pack: serde_json::Value) -> Result<serde_json::Value, String> {
    let object = pack
        .as_object()
        .ok_or_else(|| "Некорректный набор стикеров".to_owned())?;
    let display_name = object
        .get("display_name")
        .and_then(|v| v.as_str())
        .unwrap_or("Набор стикеров")
        .chars()
        .take(80)
        .collect::<String>();
    let id = object
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("shared-pack")
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        .take(96)
        .collect::<String>();
    let attribution = object
        .get("attribution")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .chars()
        .take(240)
        .collect::<String>();
    let images = object
        .get("images")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "В наборе нет стикеров".to_owned())?;
    let mut cleaned = Vec::new();
    for (index, image) in images.iter().take(120).enumerate() {
        let Some(item) = image.as_object() else {
            continue;
        };
        let Some(media_url) = item.get("media_url").and_then(|v| v.as_str()) else {
            continue;
        };
        let mxc = <&MxcUri>::from(media_url);
        if mxc.validate().is_err() {
            continue;
        }
        let body = item
            .get("body")
            .and_then(|v| v.as_str())
            .unwrap_or("Стикер")
            .chars()
            .take(160)
            .collect::<String>();
        let mut shortcode = item
            .get("shortcode")
            .and_then(|v| v.as_str())
            .unwrap_or("sticker")
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'))
            .take(80)
            .collect::<String>();
        if shortcode.is_empty() {
            shortcode = format!("sticker_{}", index + 1);
        }
        let mime = item
            .get("media_mime_type")
            .and_then(|v| v.as_str())
            .filter(|v| v.starts_with("image/"))
            .unwrap_or("image/webp");
        cleaned.push(serde_json::json!({
            "shortcode": shortcode,
            "body": body,
            "media_url": media_url,
            "media_mime_type": mime,
            "animated": mime == "image/gif" || mime == "image/webp" || mime == "image/apng"
        }));
    }
    if cleaned.is_empty() {
        return Err("В наборе нет корректных Matrix-стикеров".to_owned());
    }
    Ok(serde_json::json!({
        "id": if id.is_empty() { "shared-pack" } else { id.as_str() },
        "display_name": display_name,
        "attribution": attribution,
        "source": "shared",
        "images": cleaned
    }))
}

pub async fn share_sticker_pack(room_id: &str, pack: serde_json::Value) -> Result<(), String> {
    let cleaned = sanitized_sticker_pack(pack)?;
    let display_name = cleaned
        .get("display_name")
        .and_then(|v| v.as_str())
        .unwrap_or("Набор стикеров");
    let images = cleaned
        .get("images")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let mut msc_images = serde_json::Map::new();
    for image in &images {
        let Some(item) = image.as_object() else {
            continue;
        };
        let shortcode = item
            .get("shortcode")
            .and_then(|v| v.as_str())
            .unwrap_or("sticker");
        let url = item.get("media_url").and_then(|v| v.as_str()).unwrap_or("");
        let body = item
            .get("body")
            .and_then(|v| v.as_str())
            .unwrap_or("Стикер");
        let mimetype = item
            .get("media_mime_type")
            .and_then(|v| v.as_str())
            .unwrap_or("image/webp");
        msc_images.insert(
            shortcode.to_owned(),
            serde_json::json!({
                "url": url,
                "body": body,
                "info": { "mimetype": mimetype }
            }),
        );
    }
    let msc_pack = serde_json::json!({
        "pack": {
            "display_name": display_name,
            "usage": ["sticker"],
            "attribution": cleaned.get("attribution").cloned().unwrap_or(serde_json::Value::String(String::new()))
        },
        "images": msc_images
    });
    let content = serde_json::json!({
        "msgtype": "org.prismchat.sticker_pack",
        "body": format!("Набор стикеров «{}» — {} шт.", display_name, images.len()),
        "org.prismchat.sticker_pack": cleaned,
        "org.matrix.msc2545.image_pack": msc_pack
    });

    let client = get_client().await?;
    let room_id_parsed = <&matrix_sdk::ruma::RoomId>::try_from(room_id)
        .map_err(|error| format!("Некорректный room_id: {error}"))?;
    let room = client
        .get_room(room_id_parsed)
        .ok_or_else(|| format!("Комната не найдена в SDK: {room_id_parsed}"))?;
    room.send_raw("m.room.message", content)
        .await
        .map_err(|error| format!("Не удалось поделиться набором стикеров: {error}"))?;
    Ok(())
}

pub async fn read_avatar_file(path: &str) -> Result<Vec<u8>, String> {
    read_bounded_regular_file(path, MAX_AVATAR_BYTES).await
}

pub async fn download_media(
    mxc_url: &str,
    content_type: Option<&str>,
) -> Result<(Vec<u8>, String), String> {
    let client = get_client().await?;
    let request = media_request_from_mxc(mxc_url)?;

    let bytes = client
        .media()
        .get_media_content(&request, true)
        .await
        .map_err(|error| format!("Ошибка скачивания медиа: {error}"))?;
    if bytes.len() > MAX_MEDIA_BYTES {
        return Err("Медиа превышает лимит 100 МиБ".to_owned());
    }
    let content_type = content_type
        .filter(|value| !value.trim().is_empty())
        .unwrap_or("application/octet-stream")
        .to_owned();

    Ok((bytes, content_type))
}

pub async fn download_encrypted_media(
    file: EncryptedFile,
    content_type: Option<&str>,
) -> Result<(Vec<u8>, String), String> {
    let client = get_client().await?;
    let request = MediaRequestParameters {
        source: MediaSource::Encrypted(Box::new(file)),
        format: MediaFormat::File,
    };

    let bytes = client
        .media()
        .get_media_content(&request, true)
        .await
        .map_err(|error| format!("Ошибка скачивания или расшифровки медиа: {error}"))?;
    if bytes.len() > MAX_MEDIA_BYTES {
        return Err("Медиа превышает лимит 100 МиБ".to_owned());
    }
    let content_type = content_type
        .filter(|value| !value.trim().is_empty())
        .unwrap_or("application/octet-stream")
        .to_owned();
    Ok((bytes, content_type))
}

pub fn media_request_from_mxc(mxc_url: &str) -> Result<MediaRequestParameters, String> {
    let mxc = <&MxcUri>::from(mxc_url);
    mxc.validate()
        .map_err(|error| format!("Некорректный mxc URI: {error}"))?;

    Ok(MediaRequestParameters {
        source: MediaSource::Plain(mxc.to_owned()),
        format: MediaFormat::File,
    })
}

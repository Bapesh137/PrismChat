const MAX_CLIPBOARD_FILES: usize = 16;
const MAX_CLIPBOARD_FILE_BYTES: u64 = 100 * 1024 * 1024;
const MAX_CLIPBOARD_IMAGE_SIDE: usize = 4096;
const MAX_CLIPBOARD_IMAGE_BYTES: usize = 64 * 1024 * 1024;
const MAX_CLIPBOARD_TEXT_BYTES: usize = 1024 * 1024;

use std::{
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug)]
pub struct ClipboardAttachment {
    pub path: String,
    pub filename: String,
    pub is_image: bool,
}

pub enum ClipboardPasteOutcome {
    Empty,
    Text(String),
    Attachments(Vec<ClipboardAttachment>),
}

pub fn copy_text(text: &str) -> Result<(), String> {
    let mut clipboard =
        arboard::Clipboard::new().map_err(|error| format!("Буфер обмена недоступен: {error}"))?;
    clipboard
        .set_text(text.to_owned())
        .map_err(|error| format!("Не удалось скопировать текст: {error}"))
}

fn attachment_from_path(path: PathBuf) -> ClipboardAttachment {
    let filename = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "attachment".to_string());
    let is_image = mime_guess::from_path(&path)
        .first_or_octet_stream()
        .essence_str()
        .starts_with("image/");

    ClipboardAttachment {
        path: path.to_string_lossy().into_owned(),
        filename,
        is_image,
    }
}

fn prepare_clipboard() -> Result<ClipboardPasteOutcome, String> {
    let mut clipboard =
        arboard::Clipboard::new().map_err(|error| format!("Буфер обмена недоступен: {error}"))?;

    if let Ok(paths) = clipboard.get().file_list() {
        let attachments: Vec<ClipboardAttachment> = paths
            .into_iter()
            .take(MAX_CLIPBOARD_FILES.saturating_mul(4))
            .filter(|path| {
                std::fs::symlink_metadata(path).is_ok_and(|metadata| {
                    metadata.is_file()
                        && !metadata.file_type().is_symlink()
                        && metadata.len() <= MAX_CLIPBOARD_FILE_BYTES
                })
            })
            .take(MAX_CLIPBOARD_FILES)
            .map(attachment_from_path)
            .collect();

        if !attachments.is_empty() {
            return Ok(ClipboardPasteOutcome::Attachments(attachments));
        }
    }

    let image_error = match clipboard.get_image() {
        Ok(image) => {
            let width = u32::try_from(image.width)
                .map_err(|_| "Изображение из буфера слишком широкое".to_string())?;
            let height = u32::try_from(image.height)
                .map_err(|_| "Изображение из буфера слишком высокое".to_string())?;
            if image.width > MAX_CLIPBOARD_IMAGE_SIDE || image.height > MAX_CLIPBOARD_IMAGE_SIDE {
                return Err("Изображение из буфера превышает 4096×4096".to_owned());
            }
            let expected_len = image
                .width
                .checked_mul(image.height)
                .and_then(|pixels| pixels.checked_mul(4))
                .ok_or_else(|| "Размер изображения из буфера переполнен".to_string())?;
            let bytes = image.bytes.into_owned();
            if expected_len > MAX_CLIPBOARD_IMAGE_BYTES {
                return Err("Изображение из буфера превышает лимит 64 МиБ".to_owned());
            }
            if bytes.len() != expected_len {
                return Err("Буфер обмена вернул повреждённое RGBA-изображение".to_string());
            }

            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let filename = format!("clipboard-{timestamp}.png");
            let path = std::env::temp_dir().join(&filename);
            if let Err(error) = image::save_buffer_with_format(
                &path,
                &bytes,
                width,
                height,
                image::ExtendedColorType::Rgba8,
                image::ImageFormat::Png,
            ) {
                let _ = std::fs::remove_file(&path);
                return Err(format!(
                    "Не удалось подготовить изображение из буфера: {error}"
                ));
            }

            return Ok(ClipboardPasteOutcome::Attachments(vec![
                ClipboardAttachment {
                    path: path.to_string_lossy().into_owned(),
                    filename,
                    is_image: true,
                },
            ]));
        }
        Err(error) => error,
    };

    match clipboard.get_text() {
        Ok(text) if !text.is_empty() && text.len() <= MAX_CLIPBOARD_TEXT_BYTES => {
            Ok(ClipboardPasteOutcome::Text(text))
        }
        Ok(text) if !text.is_empty() => Err("Текст из буфера превышает лимит 1 МиБ".to_owned()),
        Ok(_) => Ok(ClipboardPasteOutcome::Empty),
        Err(text_error)
            if matches!(&image_error, arboard::Error::ContentNotAvailable)
                && matches!(&text_error, arboard::Error::ContentNotAvailable) =>
        {
            Ok(ClipboardPasteOutcome::Empty)
        }
        Err(text_error) => Err(format!(
            "Не удалось прочитать буфер обмена: изображение: {image_error}; текст: {text_error}"
        )),
    }
}

pub async fn paste_clipboard() -> Result<ClipboardPasteOutcome, String> {
    tokio::task::spawn_blocking(prepare_clipboard)
        .await
        .map_err(|error| format!("Ошибка чтения буфера обмена: {error}"))?
}

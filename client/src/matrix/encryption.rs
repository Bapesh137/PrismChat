use std::path::PathBuf;

use super::session::get_client;

const MAX_KEY_EXPORT_SIZE: u64 = 256 * 1024 * 1024;

fn checked_path(path: &str) -> Result<PathBuf, String> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err("Путь к файлу ключей не указан".to_owned());
    }
    Ok(PathBuf::from(trimmed))
}

fn validate_passphrase(passphrase: &str) -> Result<(), String> {
    if passphrase.is_empty() {
        return Err("Кодовая фраза не указана".to_owned());
    }
    Ok(())
}

pub async fn export_room_keys(path: &str, passphrase: &str) -> Result<(), String> {
    validate_passphrase(passphrase)?;
    let path = checked_path(path)?;
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .ok_or_else(|| "Не удалось определить папку для экспорта ключей".to_owned())?;
    if !parent.is_dir() {
        return Err("Папка для экспорта ключей не существует".to_owned());
    }
    if path.exists() {
        return Err("Файл экспорта уже существует; выберите новое имя".to_owned());
    }

    let temporary = parent.join(format!(
        ".prism-room-keys-{}.tmp",
        uuid::Uuid::new_v4().simple()
    ));
    let client = get_client().await?;
    let export_result = client
        .encryption()
        .export_room_keys(temporary.clone(), passphrase, |_| true)
        .await
        .map_err(|error| format!("Не удалось экспортировать ключи шифрования: {error}"));
    if let Err(error) = export_result {
        let _ = std::fs::remove_file(&temporary);
        return Err(error);
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&temporary, std::fs::Permissions::from_mode(0o600));
    }
    let result = std::fs::hard_link(&temporary, &path)
        .map_err(|error| format!("Не удалось безопасно создать файл экспорта: {error}"));
    let _ = std::fs::remove_file(&temporary);
    result
}
pub async fn import_room_keys(path: &str, passphrase: &str) -> Result<(u64, u64), String> {
    validate_passphrase(passphrase)?;
    let path = checked_path(path)?;
    let metadata = std::fs::symlink_metadata(&path)
        .map_err(|error| format!("Не удалось открыть файл ключей: {error}"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err("Выбранный путь не является файлом".to_owned());
    }
    if metadata.len() > MAX_KEY_EXPORT_SIZE {
        return Err("Файл ключей слишком большой".to_owned());
    }

    let client = get_client().await?;
    let result = client
        .encryption()
        .import_room_keys(path, passphrase)
        .await
        .map_err(|error| format!("Не удалось импортировать ключи шифрования: {error}"))?;

    super::timeline_manager::reset().await;
    Ok((result.imported_count as u64, result.total_count as u64))
}

#[cfg(test)]
mod tests {
    use super::{checked_path, validate_passphrase};

    #[test]
    fn rejects_empty_key_path() {
        assert!(checked_path("  ").is_err());
    }

    #[test]
    fn rejects_empty_passphrase() {
        assert!(validate_passphrase("").is_err());
    }
}

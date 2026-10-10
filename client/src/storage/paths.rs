use std::{fs, path::PathBuf};

#[derive(Clone, Debug)]
pub struct AppPaths {
    pub config_root: PathBuf,
    pub data_root: PathBuf,
    pub cache_root: PathBuf,
    pub storage_root: PathBuf,
    pub profiles_root: PathBuf,
    pub active_profile_path: PathBuf,
}

#[derive(Clone, Debug)]
pub struct ProfilePaths {
    pub profile_id: String,
    pub profile_root: PathBuf,
    pub profile_json: PathBuf,
    pub session_json: PathBuf,
    pub store_key_path: PathBuf,
    pub sqlite_dir: PathBuf,
    pub sqlite_cache_dir: PathBuf,
    pub media_cache_dir: PathBuf,
}

const MAX_PROFILE_ID_LEN: usize = 128;

pub fn validate_profile_id(profile_id: &str) -> Result<(), String> {
    if profile_id.is_empty() || profile_id != profile_id.trim() {
        return Err("profile_id не может быть пустым или содержать пробелы по краям".to_string());
    }
    if profile_id.len() > MAX_PROFILE_ID_LEN {
        return Err(format!("profile_id длиннее {MAX_PROFILE_ID_LEN} байт"));
    }
    if matches!(profile_id, "." | "..") {
        return Err("Некорректный profile_id".to_string());
    }
    if !profile_id
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
    {
        return Err("profile_id содержит недопустимые символы".to_string());
    }
    Ok(())
}

pub fn app_paths() -> Result<AppPaths, String> {
    let base_config = dirs::config_dir()
        .ok_or_else(|| "Не удалось определить системную папку config".to_string())?;
    let base_data =
        dirs::data_dir().ok_or_else(|| "Не удалось определить системную папку data".to_string())?;
    let base_cache = dirs::cache_dir()
        .ok_or_else(|| "Не удалось определить системную папку cache".to_string())?;

    let config_root = base_config.join("prismchat");
    let data_root = base_data.join("prismchat");
    let cache_root = base_cache.join("prismchat");
    let storage_root = data_root.join("storage");
    let profiles_root = storage_root.join("profiles");
    let active_profile_path = storage_root.join("active_profile.json");

    let paths = AppPaths {
        config_root,
        data_root,
        cache_root,
        storage_root,
        profiles_root,
        active_profile_path,
    };

    paths.ensure_base_dirs()?;
    Ok(paths)
}

impl AppPaths {
    pub fn ensure_base_dirs(&self) -> Result<(), String> {
        fs::create_dir_all(&self.config_root)
            .map_err(|e| format!("Не удалось создать config dir: {}", e))?;
        fs::create_dir_all(&self.data_root)
            .map_err(|e| format!("Не удалось создать data dir: {}", e))?;
        fs::create_dir_all(&self.cache_root)
            .map_err(|e| format!("Не удалось создать cache dir: {}", e))?;
        fs::create_dir_all(&self.storage_root)
            .map_err(|e| format!("Не удалось создать storage dir: {}", e))?;
        fs::create_dir_all(&self.profiles_root)
            .map_err(|e| format!("Не удалось создать profiles dir: {}", e))?;
        Ok(())
    }

    pub fn profile_paths(&self, profile_id: &str) -> Result<ProfilePaths, String> {
        validate_profile_id(profile_id)?;
        let profile_root = self.profiles_root.join(profile_id);
        let cache_profile_root = self.cache_root.join("profiles").join(profile_id);

        Ok(ProfilePaths {
            profile_id: profile_id.to_string(),
            profile_root: profile_root.clone(),
            profile_json: profile_root.join("profile.json"),
            session_json: profile_root.join("session.json"),
            store_key_path: profile_root.join("store.key"),
            sqlite_dir: profile_root.join("sqlite"),
            sqlite_cache_dir: cache_profile_root.join("sqlite-cache"),
            media_cache_dir: cache_profile_root.join("media"),
        })
    }
}

impl ProfilePaths {
    pub fn ensure_dirs(&self) -> Result<(), String> {
        crate::storage::secure_store::harden_directory(&self.profile_root).map_err(|e| {
            format!(
                "Не удалось создать папку профиля {}: {}",
                self.profile_id, e
            )
        })?;
        fs::create_dir_all(&self.sqlite_dir).map_err(|e| {
            format!(
                "Не удалось создать sqlite dir для {}: {}",
                self.profile_id, e
            )
        })?;
        fs::create_dir_all(&self.sqlite_cache_dir).map_err(|e| {
            format!(
                "Не удалось создать sqlite cache dir для {}: {}",
                self.profile_id, e
            )
        })?;
        fs::create_dir_all(&self.media_cache_dir).map_err(|e| {
            format!(
                "Не удалось создать media cache dir для {}: {}",
                self.profile_id, e
            )
        })?;
        Ok(())
    }

    pub fn remove_legacy_presentation_cache(&self) {
        let legacy_cache = self.profile_root.join("cache");
        for filename in [
            "messages.json",
            "messages.json.tmp",
            "rooms.json",
            "rooms.json.tmp",
        ] {
            let _ = fs::remove_file(legacy_cache.join(filename));
        }
        let _ = fs::remove_dir(legacy_cache);
    }
}

#[cfg(test)]
mod tests {
    use super::validate_profile_id;

    #[test]
    fn accepts_generated_profile_ids() {
        assert!(validate_profile_id("alice_matrix.org").is_ok());
        assert!(validate_profile_id("work-account.2").is_ok());
    }

    #[test]
    fn rejects_profile_path_traversal() {
        for invalid in [
            "",
            ".",
            "..",
            "../secret",
            "..\\secret",
            "C:\\secret",
            "/tmp/x",
        ] {
            assert!(
                validate_profile_id(invalid).is_err(),
                "{invalid} must be rejected"
            );
        }
        assert!(validate_profile_id(&"a".repeat(129)).is_err());
    }
}

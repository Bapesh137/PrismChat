use serde::{Deserialize, Serialize};
use std::{
    fs,
    time::{SystemTime, UNIX_EPOCH},
};

use super::paths::{app_paths, validate_profile_id};

#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct SavedProfile {
    pub profile_id: String,
    pub user_id: Option<String>,
    pub server: Option<String>,
    pub device_id: Option<String>,
    #[serde(default)]
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub last_used_ts: u64,
}

#[derive(Serialize, Deserialize)]
struct ActiveProfileMarker {
    profile_id: String,
}

pub fn resolve_profile_id(
    requested: Option<&str>,
    user_id: &str,
    server: &str,
) -> Result<String, String> {
    if let Some(custom) = requested.map(str::trim).filter(|value| !value.is_empty()) {
        validate_profile_id(custom)?;
        if let Some(existing) = load_profile(custom)? {
            if existing
                .user_id
                .as_deref()
                .is_some_and(|value| value != user_id)
                || existing
                    .server
                    .as_deref()
                    .is_some_and(|value| value != server)
            {
                return Err(
                    "Этот profile_id уже принадлежит другой Matrix-учётной записи".to_owned(),
                );
            }
        }
        return Ok(custom.to_owned());
    }

    if let Some(existing) = list_profiles()?.into_iter().find(|profile| {
        profile.user_id.as_deref() == Some(user_id) && profile.server.as_deref() == Some(server)
    }) {
        return Ok(existing.profile_id);
    }

    let profile_id = uuid::Uuid::new_v4().simple().to_string();
    validate_profile_id(&profile_id)?;
    Ok(profile_id)
}
fn now_ts() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn set_active_profile(profile_id: Option<&str>) -> Result<(), String> {
    let paths = app_paths()?;

    match profile_id {
        Some(profile_id) => {
            let marker = ActiveProfileMarker {
                profile_id: profile_id.to_string(),
            };
            let json = serde_json::to_string_pretty(&marker)
                .map_err(|e| format!("Не удалось сериализовать active profile: {}", e))?;
            crate::storage::secure_store::write_private_atomic(
                &paths.active_profile_path,
                json.as_bytes(),
            )
            .map_err(|e| format!("Не удалось записать active profile: {}", e))?;
        }
        None => {
            let _ = fs::remove_file(&paths.active_profile_path);
        }
    }

    Ok(())
}

pub fn get_active_profile() -> Result<Option<String>, String> {
    let paths = app_paths()?;
    let content = match fs::read_to_string(&paths.active_profile_path) {
        Ok(content) => content,
        Err(_) => return Ok(None),
    };

    let marker: ActiveProfileMarker = serde_json::from_str(&content)
        .map_err(|e| format!("Не удалось прочитать active profile: {}", e))?;

    Ok(Some(marker.profile_id))
}

pub fn save_profile(profile: &SavedProfile) -> Result<(), String> {
    let paths = app_paths()?.profile_paths(&profile.profile_id)?;
    paths.ensure_dirs()?;

    let json = serde_json::to_string_pretty(profile).map_err(|e| {
        format!(
            "Не удалось сериализовать профиль {}: {}",
            profile.profile_id, e
        )
    })?;
    crate::storage::secure_store::write_private_atomic(&paths.profile_json, json.as_bytes())
        .map_err(|e| format!("Не удалось записать профиль {}: {}", profile.profile_id, e))?;

    Ok(())
}

pub fn touch_profile(
    profile_id: &str,
    user_id: Option<String>,
    server: Option<String>,
    device_id: Option<String>,
    avatar_url: Option<String>,
) -> Result<SavedProfile, String> {
    let mut profile = load_profile(profile_id)?.unwrap_or_default();
    profile.profile_id = profile_id.to_string();

    if let (Some(existing), Some(requested)) = (profile.user_id.as_deref(), user_id.as_deref()) {
        if existing != requested {
            return Err("Профиль уже принадлежит другой Matrix-учётной записи".to_owned());
        }
    }
    if let (Some(existing), Some(requested)) = (profile.server.as_deref(), server.as_deref()) {
        if existing != requested {
            return Err("Профиль уже принадлежит другому homeserver".to_owned());
        }
    }
    if let Some(user_id) = user_id {
        profile.user_id = Some(user_id);
    }
    if let Some(server) = server {
        profile.server = Some(server);
    }
    if let Some(device_id) = device_id {
        profile.device_id = Some(device_id);
    }
    if avatar_url.is_some() {
        profile.avatar_url = avatar_url;
    }

    profile.last_used_ts = now_ts();
    save_profile(&profile)?;
    Ok(profile)
}

pub fn update_profile_avatar(profile_id: &str, avatar_url: Option<String>) -> Result<(), String> {
    let mut profile = load_profile(profile_id)?.unwrap_or_default();
    profile.profile_id = profile_id.to_string();
    profile.avatar_url = avatar_url;
    profile.last_used_ts = now_ts();
    save_profile(&profile)
}

pub fn update_profile_identity(
    profile_id: &str,
    display_name: Option<String>,
    avatar_url: Option<String>,
) -> Result<(), String> {
    let mut profile = load_profile(profile_id)?.unwrap_or_default();
    profile.profile_id = profile_id.to_string();
    profile.display_name = display_name;
    profile.avatar_url = avatar_url;
    profile.last_used_ts = now_ts();
    save_profile(&profile)
}

pub fn load_profile(profile_id: &str) -> Result<Option<SavedProfile>, String> {
    let paths = app_paths()?.profile_paths(profile_id)?;

    match fs::read_to_string(&paths.profile_json) {
        Ok(content) => {
            let profile = serde_json::from_str::<SavedProfile>(&content)
                .map_err(|e| format!("Не удалось прочитать профиль {}: {}", profile_id, e))?;
            Ok(Some(profile))
        }
        Err(_) => Ok(None),
    }
}

pub fn list_profiles() -> Result<Vec<SavedProfile>, String> {
    let app = app_paths()?;
    let mut profiles = Vec::new();

    let entries = fs::read_dir(&app.profiles_root)
        .map_err(|e| format!("Не удалось прочитать profiles dir: {}", e))?;

    for entry in entries {
        let entry = entry.map_err(|e| format!("Не удалось прочитать запись профиля: {}", e))?;
        let file_type = entry
            .file_type()
            .map_err(|e| format!("Не удалось получить тип профиля: {}", e))?;

        if !file_type.is_dir() {
            continue;
        }

        let profile_id = entry.file_name().to_string_lossy().to_string();
        let paths = app.profile_paths(&profile_id)?;

        let profile = match fs::read_to_string(&paths.profile_json) {
            Ok(content) => serde_json::from_str::<SavedProfile>(&content)
                .map_err(|e| format!("Не удалось прочитать профиль {}: {}", profile_id, e))?,
            Err(_) => SavedProfile {
                profile_id: profile_id.clone(),
                ..Default::default()
            },
        };

        profiles.push(profile);
    }

    profiles.sort_by(|a, b| {
        b.last_used_ts
            .cmp(&a.last_used_ts)
            .then_with(|| a.profile_id.cmp(&b.profile_id))
    });

    Ok(profiles)
}

pub fn remove_profile(profile_id: &str) -> Result<(), String> {
    let app = app_paths()?;
    let paths = app.profile_paths(profile_id)?;

    if paths.profile_root.exists() {
        fs::remove_dir_all(&paths.profile_root)
            .map_err(|e| format!("Не удалось удалить профиль {}: {}", profile_id, e))?;
    }

    let cache_root = app.cache_root.join("profiles").join(profile_id);
    if cache_root.exists() {
        fs::remove_dir_all(cache_root)
            .map_err(|e| format!("Не удалось удалить cache профиля {}: {}", profile_id, e))?;
    }

    crate::storage::maintenance::discard_pending_cleanup(profile_id)?;

    if get_active_profile()?.as_deref() == Some(profile_id) {
        set_active_profile(None)?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::SavedProfile;

    #[test]
    fn reads_profile_written_before_identity_snapshot_was_added() {
        let profile: SavedProfile = serde_json::from_str(
            r#"{
                "profile_id":"alice",
                "user_id":"@alice:example.org",
                "server":"https://example.org",
                "device_id":"DEVICE",
                "avatar_url":null,
                "last_used_ts":1
            }"#,
        )
        .unwrap();

        assert_eq!(profile.display_name, None);
    }
}

use matrix_sdk::{authentication::matrix::MatrixSession, ruma::UserId, Client};
use std::{
    collections::HashMap,
    sync::LazyLock,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;

use crate::matrix::session::{activate_persistent_client_from_session, get_client};

const AVATAR_CACHE_TTL: Duration = Duration::from_secs(30 * 60);
const NEGATIVE_AVATAR_CACHE_TTL: Duration = Duration::from_secs(30);
const MAX_AVATAR_CACHE_ENTRIES: usize = 256;

struct CachedAvatar {
    avatar: Option<String>,
    created_at: Instant,
    last_access_tick: u64,
}

#[derive(Default)]
struct AvatarCache {
    entries: HashMap<String, CachedAvatar>,
    access_tick: u64,
}

impl AvatarCache {
    fn next_tick(&mut self) -> u64 {
        self.access_tick = self.access_tick.saturating_add(1);
        self.access_tick
    }

    fn remove_expired(&mut self) {
        self.entries.retain(|_, entry| {
            let ttl = if entry.avatar.is_some() {
                AVATAR_CACHE_TTL
            } else {
                NEGATIVE_AVATAR_CACHE_TTL
            };
            entry.created_at.elapsed() <= ttl
        });
    }

    fn evict_if_needed(&mut self) {
        self.remove_expired();
        while self.entries.len() > MAX_AVATAR_CACHE_ENTRIES {
            let victim = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_access_tick)
                .map(|(user_id, _)| user_id.clone());
            let Some(victim) = victim else {
                break;
            };
            self.entries.remove(&victim);
        }
    }
}

static AVATAR_CACHE: LazyLock<Mutex<AvatarCache>> =
    LazyLock::new(|| Mutex::new(AvatarCache::default()));

fn is_explicit_local_http(url: &str) -> bool {
    let authority = url
        .get("http://".len()..)
        .and_then(|rest| rest.split('/').next())
        .unwrap_or_default();

    if authority.is_empty() || authority.contains('@') {
        return false;
    }

    let host = if let Some(ipv6) = authority.strip_prefix('[') {
        ipv6.split(']').next().unwrap_or_default()
    } else {
        authority.split(':').next().unwrap_or_default()
    };

    matches!(
        host.to_ascii_lowercase().as_str(),
        "localhost" | "127.0.0.1" | "::1"
    )
}

pub fn normalize_url(server: &str) -> Result<String, String> {
    let trimmed = server.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return Err("Адрес homeserver не может быть пустым".to_string());
    }

    let lowered = trimmed.to_ascii_lowercase();
    if lowered.starts_with("https://") {
        return Ok(trimmed.to_string());
    }

    if lowered.starts_with("http://") {
        if is_explicit_local_http(&lowered) {
            return Ok(trimmed.to_string());
        }
        return Err(
            "Незащищённый HTTP разрешён только для localhost, 127.0.0.1 или ::1".to_string(),
        );
    }

    if lowered.contains("://") {
        return Err("Homeserver должен использовать схему https://".to_string());
    }

    Ok(format!("https://{trimmed}"))
}

pub async fn fetch_own_avatar() -> Option<String> {
    let client = get_client().await.ok()?;
    client
        .account()
        .get_avatar_url()
        .await
        .ok()
        .flatten()
        .map(|mxc| mxc.to_string())
}

pub async fn fetch_user_avatar(user_id: &str) -> Option<String> {
    {
        let mut cache = AVATAR_CACHE.lock().await;
        cache.remove_expired();
        let tick = cache.next_tick();
        if let Some(entry) = cache.entries.get_mut(user_id) {
            entry.last_access_tick = tick;
            return entry.avatar.clone();
        }
    }

    let client = get_client().await.ok()?;
    let parsed_user_id = <&UserId>::try_from(user_id).ok()?;

    let avatar = client
        .account()
        .fetch_user_profile_of(parsed_user_id)
        .await
        .ok()
        .and_then(|profile| {
            profile
                .get("avatar_url")
                .and_then(|value| value.as_str())
                .map(str::to_owned)
        });

    let mut cache = AVATAR_CACHE.lock().await;
    let tick = cache.next_tick();
    cache.entries.insert(
        user_id.to_string(),
        CachedAvatar {
            avatar: avatar.clone(),
            created_at: Instant::now(),
            last_access_tick: tick,
        },
    );
    cache.evict_if_needed();
    avatar
}

pub async fn clear_avatar_cache() {
    *AVATAR_CACHE.lock().await = AvatarCache::default();
}

pub async fn login(
    server: &str,
    nickname: &str,
    password: &str,
    profile_id: Option<String>,
) -> Result<(String, Option<String>, String), String> {
    let base = normalize_url(server)?;

    let client = Client::builder()
        .homeserver_url(&base)
        .build()
        .await
        .map_err(|e| format!("Не удалось создать Matrix SDK client: {}", e))?;

    println!("[Auth] Логин через Matrix SDK");

    let response = client
        .matrix_auth()
        .login_username(nickname, password)
        .initial_device_display_name("PrismChat")
        .send()
        .await
        .map_err(|e| format!("Ошибка логина: {}", e))?;

    let matrix_session = MatrixSession::from(&response);
    let activated =
        activate_persistent_client_from_session(&base, matrix_session, profile_id.as_deref(), None)
            .await?;

    println!("[Auth] Сессия сохранена");
    Ok((
        response.access_token,
        activated.avatar_url.clone(),
        activated.profile_id,
    ))
}

#[cfg(test)]
mod tests {
    use super::normalize_url;

    #[test]
    fn defaults_to_https() {
        assert_eq!(
            normalize_url("matrix.example.org").unwrap(),
            "https://matrix.example.org"
        );
        assert_eq!(
            normalize_url("https://matrix.example.org/").unwrap(),
            "https://matrix.example.org"
        );
    }

    #[test]
    fn allows_http_only_for_explicit_loopback_hosts() {
        assert_eq!(
            normalize_url("http://localhost:8008").unwrap(),
            "http://localhost:8008"
        );
        assert!(normalize_url("http://127.0.0.1:8008").is_ok());
        assert!(normalize_url("http://[::1]:8008").is_ok());
        assert!(normalize_url("http://matrix.example.org").is_err());
        assert!(normalize_url("ftp://matrix.example.org").is_err());
    }
}

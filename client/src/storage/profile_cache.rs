use std::{
    collections::HashMap,
    sync::LazyLock,
    time::{Duration, Instant},
};

use tokio::sync::Mutex;

use crate::protocol::commands::UserDetails;

const PROFILE_TTL: Duration = Duration::from_secs(60);
const MAX_PROFILE_ENTRIES: usize = 128;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct ProfileCacheKey {
    user_id: String,
    room_id: Option<String>,
}

#[derive(Clone, Debug)]
struct CachedProfile {
    details: UserDetails,
    created_at: Instant,
    last_access_tick: u64,
}

#[derive(Default)]
struct ProfileCache {
    entries: HashMap<ProfileCacheKey, CachedProfile>,
    access_tick: u64,
}

static PROFILE_CACHE: LazyLock<Mutex<ProfileCache>> =
    LazyLock::new(|| Mutex::new(ProfileCache::default()));

impl ProfileCache {
    fn next_tick(&mut self) -> u64 {
        self.access_tick = self.access_tick.saturating_add(1);
        self.access_tick
    }

    fn remove_expired(&mut self) {
        let now = Instant::now();
        self.entries
            .retain(|_, entry| now.duration_since(entry.created_at) <= PROFILE_TTL);
    }

    fn evict_if_needed(&mut self) {
        self.remove_expired();

        while self.entries.len() > MAX_PROFILE_ENTRIES {
            let oldest_key = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_access_tick)
                .map(|(key, _)| key.clone());

            let Some(oldest_key) = oldest_key else {
                break;
            };

            self.entries.remove(&oldest_key);
        }
    }
}

pub async fn get_cached_user_details(user_id: &str, room_id: Option<&str>) -> Option<UserDetails> {
    let mut cache = PROFILE_CACHE.lock().await;
    cache.remove_expired();

    let key = ProfileCacheKey {
        user_id: user_id.to_string(),
        room_id: room_id.map(str::to_owned),
    };

    let tick = cache.next_tick();
    let entry = cache.entries.get_mut(&key)?;
    entry.last_access_tick = tick;
    Some(entry.details.clone())
}

pub async fn store_user_details(details: UserDetails, room_id: Option<&str>) {
    let mut cache = PROFILE_CACHE.lock().await;
    let tick = cache.next_tick();

    let key = ProfileCacheKey {
        user_id: details.user_id.clone(),
        room_id: room_id.map(str::to_owned),
    };

    cache.entries.insert(
        key,
        CachedProfile {
            details,
            created_at: Instant::now(),
            last_access_tick: tick,
        },
    );

    cache.evict_if_needed();
}

pub async fn invalidate_user_details(user_id: &str) {
    let mut cache = PROFILE_CACHE.lock().await;
    cache.entries.retain(|key, _| key.user_id != user_id);
}

pub async fn clear_all() {
    let mut cache = PROFILE_CACHE.lock().await;
    *cache = ProfileCache::default();
}

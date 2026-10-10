use std::{
    collections::HashMap,
    sync::{Arc, LazyLock},
};

use matrix_sdk::ruma::RoomId;
use tokio::sync::Mutex;

use crate::matrix::session::{current_session_epoch, get_client};

#[derive(Default)]
struct TypingCommandState {
    session_epoch: u64,
    latest_generation_by_room: HashMap<String, u64>,
    room_locks: HashMap<String, Arc<Mutex<()>>>,
}

static TYPING_COMMAND_STATE: LazyLock<Mutex<TypingCommandState>> =
    LazyLock::new(|| Mutex::new(TypingCommandState::default()));

fn accept_generation(
    state: &mut TypingCommandState,
    epoch: u64,
    room_id: &str,
    generation: u64,
) -> bool {
    if state.session_epoch != epoch {
        state.session_epoch = epoch;
        state.latest_generation_by_room.clear();
        state.room_locks.clear();
    }
    // Zero is the compatibility value used by clients predating generation
    // ordering. It remains functional without weakening modern clients.
    if generation == 0 {
        return true;
    }
    if state
        .latest_generation_by_room
        .get(room_id)
        .is_some_and(|latest| *latest >= generation)
    {
        return false;
    }
    state
        .latest_generation_by_room
        .insert(room_id.to_owned(), generation);
    true
}

fn generation_is_current(
    state: &TypingCommandState,
    epoch: u64,
    room_id: &str,
    generation: u64,
) -> bool {
    state.session_epoch == epoch
        && (generation == 0 || state.latest_generation_by_room.get(room_id) == Some(&generation))
}

/// Send one room-scoped typing update. SDK requests are serialized per room,
/// while queued generations are coalesced before they reach the homeserver.
/// Thus a slow keepalive can delay one stop request, but a backlog of stale
/// starts cannot run after the newest stop.
pub async fn set_typing(room_id: &str, typing: bool, generation: u64) -> Result<(), String> {
    let epoch = current_session_epoch();
    let room_lock = {
        let mut command_state = TYPING_COMMAND_STATE.lock().await;
        if !accept_generation(&mut command_state, epoch, room_id, generation) {
            return Ok(());
        }
        command_state
            .room_locks
            .entry(room_id.to_owned())
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    };
    let _room_guard = room_lock.lock().await;
    {
        let command_state = TYPING_COMMAND_STATE.lock().await;
        if !generation_is_current(&command_state, epoch, room_id, generation) {
            return Ok(());
        }
    }

    let parsed_room_id =
        <&RoomId>::try_from(room_id).map_err(|error| format!("Некорректный room_id: {error}"))?;
    let client = get_client().await?;
    if current_session_epoch() != epoch {
        return Ok(());
    }
    let room = client
        .get_room(parsed_room_id)
        .ok_or_else(|| "Комната не найдена".to_owned())?;
    room.typing_notice(typing)
        .await
        .map_err(|error| format!("Не удалось обновить индикатор набора: {error}"))
}

#[cfg(test)]
mod tests {
    use super::{accept_generation, generation_is_current, TypingCommandState};

    #[test]
    fn stale_typing_commands_do_not_replace_newer_state() {
        let mut state = TypingCommandState::default();
        assert!(accept_generation(&mut state, 3, "!room:example.org", 10));
        assert!(!accept_generation(&mut state, 3, "!room:example.org", 9));
        assert!(!accept_generation(&mut state, 3, "!room:example.org", 10));
        assert!(accept_generation(&mut state, 3, "!room:example.org", 11));
    }

    #[test]
    fn a_new_session_resets_generation_tracking() {
        let mut state = TypingCommandState::default();
        assert!(accept_generation(&mut state, 3, "!room:example.org", 10));
        assert!(accept_generation(&mut state, 4, "!room:example.org", 1));
    }

    #[test]
    fn legacy_zero_generation_remains_accepted() {
        let mut state = TypingCommandState::default();
        assert!(accept_generation(&mut state, 3, "!room:example.org", 10));
        assert!(accept_generation(&mut state, 3, "!room:example.org", 0));
    }

    #[test]
    fn queued_generation_is_coalesced_before_the_sdk_request() {
        let mut state = TypingCommandState::default();
        assert!(accept_generation(&mut state, 3, "!room:example.org", 10));
        assert!(generation_is_current(&state, 3, "!room:example.org", 10));

        assert!(accept_generation(&mut state, 3, "!room:example.org", 11));
        assert!(!generation_is_current(&state, 3, "!room:example.org", 10));
        assert!(generation_is_current(&state, 3, "!room:example.org", 11));
    }

    #[test]
    fn generations_are_independent_between_rooms() {
        let mut state = TypingCommandState::default();
        assert!(accept_generation(&mut state, 3, "!first:example.org", 20));
        assert!(accept_generation(&mut state, 3, "!second:example.org", 4));

        assert!(generation_is_current(&state, 3, "!first:example.org", 20));
        assert!(generation_is_current(&state, 3, "!second:example.org", 4));
        assert!(!accept_generation(&mut state, 3, "!second:example.org", 3));
        assert!(generation_is_current(&state, 3, "!first:example.org", 20));
    }
}

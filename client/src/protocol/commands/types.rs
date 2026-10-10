//! Shared JSON payloads used by commands, responses and Matrix adapters.
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct VoiceParticipant {
    pub user_id: String,
    pub display_name: String,
    pub avatar_url: Option<String>,
}
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RoomInfo {
    #[serde(default)]
    pub is_voice: bool,
    #[serde(default)]
    pub voice_members: Vec<VoiceParticipant>,
    pub room_id: String,
    pub name: Option<String>,
    pub avatar_url: Option<String>,
    pub topic: Option<String>,
    pub last_message: Option<String>,
    pub last_timestamp: Option<u64>,
    #[serde(default)]
    pub last_event_id: Option<String>,
    pub unread_count: u64,
    pub is_marked_unread: bool,
    pub member_count: u64,
    pub is_dm: bool,
    pub direct_user_id: Option<String>,
    pub is_ignored: bool,
    pub is_space: bool,
    pub parent_space_ids: Vec<String>,
    pub is_encrypted: bool,
    pub room_state: String,
    #[serde(default)]
    pub can_edit: bool,
}
#[derive(Serialize, Debug, Clone)]
pub struct RoomUserPowerLevel {
    pub user_id: String,
    pub display_name: String,
    pub avatar_url: Option<String>,
    pub power_level: i64,
}

#[derive(Serialize, Debug, Clone)]
pub struct RoomDetails {
    pub room_id: String,
    pub name: Option<String>,
    pub display_name: Option<String>,
    pub canonical_alias: Option<String>,
    pub topic: Option<String>,
    pub avatar_url: Option<String>,
    pub room_type: Option<String>,
    pub room_state: String,
    pub join_rule: String,
    pub history_visibility: String,
    pub guest_access: String,
    pub is_dm: bool,
    pub is_space: bool,
    pub is_encrypted: bool,
    pub joined_members_count: u64,
    pub invited_members_count: u64,
    pub active_members_count: u64,
    pub direct_targets_count: u64,
    pub unread_notification_count: u64,
    pub unread_highlight_count: u64,
    pub last_event_timestamp: Option<u64>,
    pub user_power_levels: Vec<RoomUserPowerLevel>,
    pub power_levels_truncated: bool,
    pub can_kick_members: bool,
    pub can_ban_members: bool,
    pub can_manage_power_levels: bool,
    pub current_user_power_level: i64,
}
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct MessageInfo {
    pub event_id: String,
    pub sender: String,
    pub sender_avatar_url: Option<String>,
    #[serde(default)]
    pub sender_display_name: Option<String>,
    #[serde(default)]
    pub sender_is_ignored: bool,
    pub body: String,
    pub msg_type: String,
    pub timestamp: u64,
    pub reply_to: Option<String>,
    pub reply_sender: Option<String>,
    pub reply_body: Option<String>,
    #[serde(default)]
    pub thread_root_id: Option<String>,
    #[serde(default)]
    pub thread_reply_count: u32,
    pub media_url: Option<String>,
    pub media_file: Option<serde_json::Value>,
    pub media_mime_type: Option<String>,
    #[serde(default)]
    pub sticker_pack: Option<serde_json::Value>,
    pub is_system: bool,
    pub system_kind: Option<String>,
    pub is_edited: bool,
    pub is_redacted: bool,
    pub is_encrypted: bool,
    #[serde(default)]
    pub reactions: Vec<ReactionInfo>,
    #[serde(default)]
    pub read_receipts: Vec<ReadReceiptInfo>,
}
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ReadReceiptInfo {
    pub user_id: String,
    pub timestamp: Option<u64>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ThreadSummaryInfo {
    pub root: MessageInfo,
    pub latest_reply: Option<MessageInfo>,
    pub reply_count: u32,
    pub unread: bool,
}
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ReactionInfo {
    pub key: String,
    pub count: u64,
    pub reacted: bool,
    #[serde(default)]
    pub own_event_id: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SyncFreshness {
    Restoring,
    CatchingUp,
    Live,
    Offline,
}

#[derive(Serialize, Debug, Clone)]
pub struct TimelineItemInfo {
    pub timeline_item_id: String,
    pub kind: String,
    pub message: Option<MessageInfo>,
    pub timestamp: Option<u64>,
    pub send_state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub send_error: Option<String>,
    pub send_recoverable: bool,
    pub is_local_echo: bool,
    pub sender_profile_pending: bool,
    pub reply_details_pending: bool,
}

#[derive(Serialize, Debug, Clone)]
pub struct TimelineDiffInfo {
    pub op: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub index: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub length: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub item: Option<TimelineItemInfo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub items: Option<Vec<TimelineItemInfo>>,
}
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SpaceRoomInfo {
    pub room_id: String,
    pub name: Option<String>,
    pub topic: Option<String>,
    pub avatar_url: Option<String>,
    pub joined: bool,
    pub invited: bool,
    pub knocked: bool,
    pub join_rule: String,
    pub world_readable: bool,
    pub member_count: u64,
    pub via: Vec<String>,
}
#[derive(Serialize, Debug, Clone)]
pub struct RoomMemberSummary {
    pub user_id: String,
    pub display_name: String,
    pub avatar_url: Option<String>,
    pub membership: String,
    pub role: String,
    pub power_level: i64,
    pub can_redact_own: bool,
    pub can_redact_other: bool,
    pub membership_event_sender: Option<String>,
    pub membership_event_timestamp: Option<u64>,
}

#[derive(Serialize, Debug, Clone)]
pub struct UserDirectoryEntry {
    pub user_id: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
}

#[derive(Serialize, Debug, Clone)]
pub struct PublicRoomDirectoryEntry {
    pub room_id: String,
    pub name: Option<String>,
    pub canonical_alias: Option<String>,
    pub topic: Option<String>,
    pub avatar_url: Option<String>,
    pub member_count: u64,
    pub join_rule: String,
    pub joined: bool,
    pub invited: bool,
    pub knocked: bool,
    pub is_space: bool,
}

#[derive(Serialize, Debug, Clone)]
pub struct ProfileInfo {
    pub profile_id: String,
    pub user_id: Option<String>,
    pub server: Option<String>,
    pub device_id: Option<String>,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub is_active: bool,
    pub last_used_ts: u64,
}
#[derive(Serialize, Debug, Clone)]
pub struct RoomMemberInfo {
    pub room_id: String,
    pub display_name: Option<String>,
    pub resolved_name: String,
    pub avatar_url: Option<String>,
    pub membership: String,
    pub power_level: String,
    pub normalized_power_level: String,
    pub power_level_int: i64,
    pub normalized_power_level_int: i64,
    pub is_ignored: bool,
    pub can_invite: bool,
    pub can_kick: bool,
    pub can_ban: bool,
    pub can_redact_own: bool,
    pub can_redact_other: bool,
}
#[derive(Serialize, Debug, Clone)]
pub struct UserDetails {
    pub user_id: String,
    pub display_name: String,
    pub global_display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub global_avatar_url: Option<String>,
    pub is_self: bool,
    pub is_ignored: bool,
    pub can_send_dm: bool,
    pub power_level: i64,
    pub is_admin: bool,
    pub is_moderator: bool,
    pub room_member: Option<RoomMemberInfo>,
    pub viewer_power_level: i64,
    pub viewer_can_kick: bool,
    pub viewer_can_ban: bool,
    pub viewer_can_manage_roles: bool,
}

#[derive(Serialize, Debug, Clone)]
pub struct MatrixDeviceInfo {
    pub device_id: String,
    pub display_name: Option<String>,
    pub is_current: bool,
    /// verified / unverified / unknown, derived only from matrix-sdk crypto.
    pub verification_state: String,
    pub is_cross_signed: bool,
    pub first_seen_ts: Option<u64>,
    pub last_seen_ts: Option<u64>,
    pub last_seen_ip: Option<String>,
    pub is_dehydrated: Option<bool>,
    pub ed25519_fingerprint: Option<String>,
    pub can_verify: bool,
    pub can_rename: bool,
    pub can_sign_out: bool,
}

#[derive(Serialize, Debug, Clone)]
pub struct DeviceDeleteAuthFlow {
    pub stages: Vec<String>,
    pub supported: bool,
}

#[derive(Serialize, Debug, Clone)]
pub struct EncryptionOverview {
    /// not_configured / verified / unverified / incomplete / unknown
    pub identity_state: String,
    /// True only when the homeserver already has our public cross-signing identity.
    pub cross_signing_exists: bool,
    pub current_device_verified: bool,
    pub has_other_verified_device: bool,
    /// enabled / incomplete / disabled / unknown
    pub recovery_state: String,
    pub secret_storage_enabled: bool,
    /// enabled / creating / downloading / disabled / unknown
    pub backup_state: String,
    pub backup_exists_on_server: bool,
    pub current_device_id: Option<String>,
    /// True while matrix-sdk is waiting for UIAA/OAuth identity-reset approval.
    /// The approval URL itself is deliberately returned only by the action
    /// response and is never persisted in the overview snapshot.
    pub identity_reset_pending: bool,
}

#[derive(Serialize, Debug, Clone)]
pub struct ClipboardAttachmentInfo {
    pub path: String,
    pub filename: String,
    pub is_image: bool,
}

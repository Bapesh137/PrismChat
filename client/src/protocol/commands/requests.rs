//! Frontend commands and compatibility exports for existing callers.
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum QmlCommand {
    VoiceBegin {
        request_id: String,
        room_id: String,
        call_id: String,
        session_epoch: u64,
        intent: String,
        element_call_url: String,
    },
    VoiceWidget {
        call_id: String,
        session_epoch: u64,
        message: String,
    },
    VoiceEnd {
        request_id: String,
        call_id: String,
    },
    VoiceDecline {
        request_id: String,
        room_id: String,
        notification_event_id: String,
    },
    GetCapabilities {
        request_id: String,
    },
    GetSessionState {
        request_id: String,
    },
    Login {
        request_id: String,
        server: String,
        nickname: String,
        password: String,
        #[serde(default)]
        profile_id: Option<String>,
    },
    Register {
        request_id: String,
        server: String,
        username: String,
        password: String,
        #[serde(default)]
        profile_id: Option<String>,
    },
    Logout {
        request_id: String,
    },
    ShowSystemNotification {
        request_id: String,
        title: String,
        message: String,
    },
    GetRoomList {
        request_id: String,
    },
    GetRoomDetails {
        request_id: String,
        room_id: String,
    },
    GetSpaceHierarchy {
        request_id: String,
        space_id: String,
        #[serde(default)]
        from: Option<String>,
        #[serde(default)]
        limit: Option<u32>,
    },
    JoinSpaceRoom {
        request_id: String,
        room_id: String,
        #[serde(default)]
        knock: bool,
        #[serde(default)]
        via: Vec<String>,
    },
    AddRoomToSpace {
        request_id: String,
        room_id: String,
        space_id: String,
    },
    RemoveRoomFromSpace {
        request_id: String,
        room_id: String,
        space_id: String,
    },
    UpdateRoom {
        request_id: String,
        room_id: String,
        changes: serde_json::Value,
    },
    ModerateRoomMember {
        request_id: String,
        room_id: String,
        user_id: String,
        action: String,
        #[serde(default)]
        power_level: Option<i64>,
        #[serde(default)]
        reason: Option<String>,
    },
    GetPinnedMessages {
        request_id: String,
        room_id: String,
    },
    PinMessage {
        request_id: String,
        room_id: String,
        event_id: String,
        #[serde(default)]
        pinned: bool,
    },
    SendReaction {
        request_id: String,
        room_id: String,
        event_id: String,
        key: String,
        #[serde(default)]
        reacted: bool,
        #[serde(default)]
        reaction_event_id: Option<String>,
    },
    LeaveRoom {
        request_id: String,
        room_id: String,
    },
    AcceptRoomInvite {
        request_id: String,
        room_id: String,
    },
    GetProfileList {
        request_id: String,
    },
    SwitchProfile {
        request_id: String,
        profile_id: String,
    },
    DeleteProfile {
        request_id: String,
        profile_id: String,
    },
    ExportRoomKeys {
        request_id: String,
        path: String,
        passphrase: String,
    },
    ImportRoomKeys {
        request_id: String,
        path: String,
        passphrase: String,
    },
    GetEncryptionOverview {
        request_id: String,
    },
    GetMatrixDevices {
        request_id: String,
    },
    DeleteMatrixDevices {
        request_id: String,
        device_ids: Vec<String>,
    },
    SubmitDeviceDeleteUiaa {
        request_id: String,
        operation_id: String,
        auth_type: String,
        #[serde(default)]
        password: Option<String>,
    },
    CopyText {
        request_id: String,
        text: String,
    },
    RenameMatrixDevice {
        request_id: String,
        device_id: String,
        display_name: String,
    },
    BootstrapCrossSigning {
        request_id: String,
        #[serde(default)]
        password: Option<String>,
        #[serde(default)]
        uiaa_session: Option<String>,
    },
    StartVerification {
        request_id: String,
        #[serde(default)]
        device_id: Option<String>,
    },
    VerificationAction {
        request_id: String,
        flow_id: String,
        action: String,
    },
    EnableRecovery {
        request_id: String,
        #[serde(default)]
        passphrase: Option<String>,
    },
    RecoverEncryption {
        request_id: String,
        recovery_key: String,
    },
    ChangeRecoveryKey {
        request_id: String,
        #[serde(default)]
        old_recovery_key: Option<String>,
        #[serde(default)]
        passphrase: Option<String>,
    },
    RepairKeyBackup {
        request_id: String,
        recovery_key: String,
    },
    EnableKeyBackup {
        request_id: String,
    },
    RecreateKeyBackup {
        request_id: String,
    },
    ResetCryptoIdentity {
        request_id: String,
        #[serde(default)]
        password: Option<String>,
        #[serde(default)]
        uiaa_session: Option<String>,
        #[serde(default)]
        oauth_approved: bool,
    },
    CancelCryptoIdentityReset {
        request_id: String,
    },
    GetMessageContext {
        request_id: String,
        room_id: String,
        limit: Option<u32>,
        event_id: String,
    },
    GetTimelinePreview {
        request_id: String,
        room_id: String,
        limit: Option<u32>,
        from: Option<String>,
    },
    /// Opens or reuses a live matrix-sdk-ui Timeline. The response is a
    /// snapshot followed by incremental `timeline_diffs` events.
    OpenTimeline {
        request_id: String,
        room_id: String,
        /// Monotonic frontend generation. It prevents an older concurrently
        /// handled IPC request from replacing the current Timeline stream.
        #[serde(default)]
        request_generation: u64,
    },
    CloseTimeline {
        request_id: String,
        room_id: String,
        #[serde(default)]
        request_generation: u64,
    },
    PaginateTimelineBackwards {
        request_id: String,
        room_id: String,
        #[serde(default = "default_timeline_page_size")]
        count: u16,
        /// The SDK Timeline identity visible to the frontend when pagination
        /// was requested. Additive defaults preserve older QML clients.
        #[serde(default)]
        session_epoch: u64,
        #[serde(default)]
        generation: u64,
    },
    GetThreadMessages {
        request_id: String,
        room_id: String,
        root_event_id: String,
        #[serde(default = "default_thread_message_limit")]
        limit: u16,
    },
    GetRoomThreads {
        request_id: String,
        room_id: String,
        #[serde(default)]
        from: Option<String>,
        #[serde(default = "default_room_threads_limit")]
        limit: u16,
    },
    GetRoomAttachments {
        request_id: String,
        room_id: String,
        limit: Option<u32>,
        from: Option<String>,
        #[serde(default)]
        category: Option<u8>,
    },
    MarkRoomRead {
        request_id: String,
        room_id: String,
        #[serde(default)]
        public_receipt: Option<bool>,
        #[serde(default)]
        event_id: Option<String>,
    },
    MarkRoomThreadsRead {
        request_id: String,
        room_id: String,
        #[serde(default)]
        public_receipt: Option<bool>,
    },
    MarkThreadRead {
        request_id: String,
        room_id: String,
        root_event_id: String,
        event_id: String,
        #[serde(default)]
        public_receipt: Option<bool>,
    },
    SetTyping {
        request_id: String,
        room_id: String,
        typing: bool,
        /// Monotonic frontend generation. Typing start/stop commands are
        /// handled concurrently, so older generations must never win.
        #[serde(default)]
        generation: u64,
    },
    SetRoomMarkedUnread {
        request_id: String,
        room_id: String,
        unread: bool,
    },
    GetRoomMembers {
        request_id: String,
        room_id: String,
        #[serde(default)]
        from: Option<String>,
        #[serde(default)]
        limit: Option<u32>,
    },
    SearchRoomMessages {
        request_id: String,
        room_id: String,
        query: String,
        limit: Option<u32>,
        next_batch: Option<String>,
    },
    SearchUsers {
        request_id: String,
        query: String,
        limit: Option<u32>,
    },
    SearchPublicRooms {
        request_id: String,
        query: String,
        limit: Option<u32>,
        /// Restrict the homeserver directory request to `m.space` entries.
        /// Defaults to `false` for backwards compatibility with older QML.
        #[serde(default)]
        spaces_only: bool,
    },
    GetUserDetails {
        request_id: String,
        user_id: String,
        #[serde(default)]
        room_id: Option<String>,
    },
    SetUserIgnored {
        request_id: String,
        user_id: String,
        #[serde(default)]
        ignored: bool,
    },
    OpenDirectMessage {
        request_id: String,
        user_id: String,
    },
    CreateRoom {
        request_id: String,
        options: serde_json::Value,
    },
    UpdateOwnProfile {
        request_id: String,
        #[serde(default)]
        display_name: Option<String>,
        #[serde(default)]
        clear_display_name: bool,
    },
    SendMessage {
        request_id: String,
        room_id: String,
        body: String,
        msg_type: Option<String>,
        reply_to: Option<String>,
        #[serde(default)]
        thread_root: Option<String>,
        #[serde(default)]
        mentioned_user_ids: Vec<String>,
    },
    RetryMessage {
        request_id: String,
        room_id: String,
        timeline_item_id: String,
    },
    UploadMedia {
        request_id: String,
        room_id: String,
        path: String,
        mime_type: String,
        filename: String,
        #[serde(default)]
        duration_ms: Option<u64>,
        #[serde(default)]
        as_sticker: bool,
    },
    CancelUpload {
        request_id: String,
        upload_request_id: String,
    },
    SendSticker {
        request_id: String,
        room_id: String,
        body: String,
        #[serde(default)]
        media_url: Option<String>,
        #[serde(default)]
        media_file: Option<serde_json::Value>,
        #[serde(default)]
        mime_type: Option<String>,
    },
    SendBuiltinSticker {
        request_id: String,
        room_id: String,
        sticker_id: String,
    },
    UploadStickerAsset {
        request_id: String,
        path: String,
        mime_type: String,
        filename: String,
    },
    ShareStickerPack {
        request_id: String,
        room_id: String,
        pack: serde_json::Value,
    },
    PasteClipboard {
        request_id: String,
        room_id: String,
    },
    RedactMessage {
        request_id: String,
        room_id: String,
        event_id: String,
    },
    EditMessage {
        request_id: String,
        room_id: String,
        event_id: String,
        new_body: String,
    },
    SetAvatar {
        request_id: String,
        path: String,
        mime_type: String,
    },
    GetStorageStats {
        request_id: String,
    },
    ClearCache {
        request_id: String,
        #[serde(default = "default_true")]
        clear_media: bool,
        #[serde(default)]
        clear_event_cache: bool,
        #[serde(default)]
        clear_sqlite: bool,
    },
    SetStoragePreferences {
        request_id: String,
        #[serde(default)]
        auto_cleanup_days: u32,
        #[serde(default = "default_storage_cache_limit_mb")]
        cache_limit_mb: u64,
        #[serde(default)]
        downloads_dir: String,
        #[serde(default = "default_true")]
        auto_load_images: bool,
        #[serde(default = "default_true")]
        auto_load_videos: bool,
    },
    DownloadMedia {
        request_id: String,
        media_url: String,
        filename: String,
        #[serde(default)]
        media_file: Option<serde_json::Value>,
        #[serde(default)]
        media_mime_type: Option<String>,
    },
    ClearTemporaryData {
        request_id: String,
    },
    ExportDiagnostics {
        request_id: String,
        path: String,
    },
}

fn default_timeline_page_size() -> u16 {
    25
}

fn default_thread_message_limit() -> u16 {
    50
}

fn default_room_threads_limit() -> u16 {
    20
}

fn default_storage_cache_limit_mb() -> u64 {
    1024
}

fn default_true() -> bool {
    true
}

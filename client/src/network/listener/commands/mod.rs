//! Dispatch protocol commands by domain. Connection scheduling stays in listener.
use crate::network::transport::Tx;
use crate::protocol::commands::QmlCommand;

mod devices;
mod directory;
mod encryption;
mod media;
mod rooms;
mod rtc;
mod session;
mod storage;
mod timeline;

pub(super) async fn dispatch(command: QmlCommand, tx: Tx, session_restore_error: Option<String>) {
    match command {
        command @ (QmlCommand::VoiceBegin { .. }
        | QmlCommand::VoiceWidget { .. }
        | QmlCommand::VoiceEnd { .. }
        | QmlCommand::VoiceDecline { .. }) => rtc::handle(command, tx).await,
        command @ (QmlCommand::GetCapabilities { .. }
        | QmlCommand::GetSessionState { .. }
        | QmlCommand::Login { .. }
        | QmlCommand::Register { .. }
        | QmlCommand::Logout { .. }
        | QmlCommand::GetProfileList { .. }
        | QmlCommand::SwitchProfile { .. }
        | QmlCommand::DeleteProfile { .. }) => {
            session::handle(command, tx, session_restore_error).await
        }
        command @ (QmlCommand::ExportRoomKeys { .. }
        | QmlCommand::ImportRoomKeys { .. }
        | QmlCommand::GetEncryptionOverview { .. }
        | QmlCommand::BootstrapCrossSigning { .. }
        | QmlCommand::EnableRecovery { .. }
        | QmlCommand::RecoverEncryption { .. }
        | QmlCommand::ChangeRecoveryKey { .. }
        | QmlCommand::RepairKeyBackup { .. }
        | QmlCommand::EnableKeyBackup { .. }
        | QmlCommand::RecreateKeyBackup { .. }
        | QmlCommand::ResetCryptoIdentity { .. }
        | QmlCommand::CancelCryptoIdentityReset { .. }) => encryption::handle(command, tx).await,
        command @ (QmlCommand::GetMatrixDevices { .. }
        | QmlCommand::DeleteMatrixDevices { .. }
        | QmlCommand::SubmitDeviceDeleteUiaa { .. }
        | QmlCommand::RenameMatrixDevice { .. }
        | QmlCommand::StartVerification { .. }
        | QmlCommand::VerificationAction { .. }) => devices::handle(command, tx).await,
        command @ (QmlCommand::GetRoomList { .. }
        | QmlCommand::GetRoomDetails { .. }
        | QmlCommand::GetSpaceHierarchy { .. }
        | QmlCommand::JoinSpaceRoom { .. }
        | QmlCommand::AddRoomToSpace { .. }
        | QmlCommand::RemoveRoomFromSpace { .. }
        | QmlCommand::UpdateRoom { .. }
        | QmlCommand::ModerateRoomMember { .. }
        | QmlCommand::LeaveRoom { .. }
        | QmlCommand::AcceptRoomInvite { .. }
        | QmlCommand::GetRoomMembers { .. }
        | QmlCommand::OpenDirectMessage { .. }
        | QmlCommand::CreateRoom { .. }) => rooms::handle(command, tx).await,
        command @ (QmlCommand::GetPinnedMessages { .. }
        | QmlCommand::PinMessage { .. }
        | QmlCommand::SendReaction { .. }
        | QmlCommand::GetMessageContext { .. }
        | QmlCommand::GetTimelinePreview { .. }
        | QmlCommand::OpenTimeline { .. }
        | QmlCommand::CloseTimeline { .. }
        | QmlCommand::PaginateTimelineBackwards { .. }
        | QmlCommand::MarkRoomRead { .. }
        | QmlCommand::MarkThreadRead { .. }
        | QmlCommand::MarkRoomThreadsRead { .. }
        | QmlCommand::SetTyping { .. }
        | QmlCommand::SetRoomMarkedUnread { .. }
        | QmlCommand::GetThreadMessages { .. }
        | QmlCommand::GetRoomThreads { .. }
        | QmlCommand::SendMessage { .. }
        | QmlCommand::RetryMessage { .. }
        | QmlCommand::RedactMessage { .. }
        | QmlCommand::EditMessage { .. }) => timeline::handle(command, tx).await,
        command @ (QmlCommand::SearchRoomMessages { .. }
        | QmlCommand::SearchUsers { .. }
        | QmlCommand::SearchPublicRooms { .. }
        | QmlCommand::GetUserDetails { .. }
        | QmlCommand::SetUserIgnored { .. }
        | QmlCommand::UpdateOwnProfile { .. }) => directory::handle(command, tx).await,
        command @ (QmlCommand::GetRoomAttachments { .. }
        | QmlCommand::SendBuiltinSticker { .. }
        | QmlCommand::SendSticker { .. }
        | QmlCommand::UploadStickerAsset { .. }
        | QmlCommand::ShareStickerPack { .. }
        | QmlCommand::CancelUpload { .. }
        | QmlCommand::UploadMedia { .. }
        | QmlCommand::PasteClipboard { .. }
        | QmlCommand::SetAvatar { .. }) => media::handle(command, tx).await,
        command @ (QmlCommand::GetStorageStats { .. }
        | QmlCommand::ClearCache { .. }
        | QmlCommand::SetStoragePreferences { .. }
        | QmlCommand::DownloadMedia { .. }
        | QmlCommand::ClearTemporaryData { .. }
        | QmlCommand::ExportDiagnostics { .. }
        | QmlCommand::ShowSystemNotification { .. }
        | QmlCommand::CopyText { .. }) => storage::handle(command, tx).await,
    }
}

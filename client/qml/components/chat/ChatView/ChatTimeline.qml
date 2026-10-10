import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../../utils/PrismUtils.js" as Utils

Chat.MessageList {
    required property var chat
    readonly property var root: chat
    required property var composerObject
    required property var dividerObject
    required property var imageViewerObject
    required property var menusObject
    required property var typingIndicatorObject
    id: messageList
    timelinePaginationInFlight: root.timelinePaginationInFlight
    anchors.top: dividerObject.bottom
    anchors.bottom: typingIndicatorObject.top
    width: parent.width - root.rightPanelWidth
    visible: root.currentRoomId !== ""
    messageModel: root.messageModel
    roomName: root.roomName
    currentUserId: root.currentUserId
    currentUserAvatar: root.currentUserAvatar
    authorNameResolver: root.authorDisplayName
    authorAvatarResolver: root.authorAvatarUrl
    canRedactOther: root.canRedactOther
    threadsEnabled: root.threadsAvailable
    currentRoomId: root.currentRoomId
    firstUnreadEventId: root.unreadBoundaryEventId
    readingAccountId: root.readingAccountId
    localReadEventIds: root.localReadEventIds
    displayedRoomId: root.displayedRoomId
    restorePosition: root.restorePosition
    openingUnreadCount: root.openingUnreadCount
    readingActive: root.readingActive
    cachedTimeline: root.cachedTimeline
    onViewportSaved: function(accountId, roomId, position) { root.viewportSaved(accountId, roomId, position) }
    onViewportRead: function(roomId, eventId, remaining) { root.viewportRead(roomId, eventId, remaining) }
    unreadBoundaryPending: root.unreadBoundaryPending
    initialTimelineReady: root.timelineInitialPositionReady
    isLoadingMessages: root.isLoadingMessages
    showEmptyState: root.showEmptyState
    mediaProxy: root.mediaProxy
    roundAvatars: root.roundAvatars
    messageDateFormat: root.messageDateFormat
    messageTimeFormat: root.messageTimeFormat
    autoLoadImages: root.autoLoadImages
    autoLoadVideos: root.autoLoadVideos
    activeVoiceEventId: root.activeVoice ? root.activeVoice.event_id || "" : ""
    activeVoicePlaying: root.voicePlayer ? root.voicePlayer.playing : false
    activeVoicePosition: root.voicePlayer ? root.voicePlayer.position : 0
    activeVoiceDuration: root.voicePlayer ? root.voicePlayer.duration : 0
    onVideoOpenRequested: function(details) { root.openVideoPlayer(details) }
    onVoicePlaybackRequested: function(details) { root.toggleVoicePlayback(details) }
    onVoiceSeekRequested: function(position) {
        if (root.voicePlayer && root.voicePlayer.seekable)
            root.voicePlayer.position = Math.round(position)
    }
    accentColor: root.accentColor
    iconColor: root.iconColor
    accentTextColor: root.accentTextColor
    textPrimary: root.textPrimary
    textSecondary: root.textSecondary
    elevatedColor: root.elevatedColor
    dividerColor: root.dividerColor
    authorNameRevision: root.authorNameRevision
    pinnedEventIds: root.pinnedEventIds

    chatViewRoot: root

    onUserProfileRequested: function(userId, roomId, clickX, clickY) {
        // Сохраняем координаты в момент клика, до ответа от Rust
        root.lastUserClickX = clickX
        root.lastUserClickY = clickY

        var requestId = root.nextRequestId("miniprofile")
        root.pendingMiniProfileRequestId = requestId
        root.pendingMiniProfileCacheKey = root.userDetailsCacheKey(userId, roomId)
        root.showMiniProfile(root.cachedOrPreviewUserDetails(userId, roomId))
        root.commandRequested({
            type: "get_user_details",
            request_id: requestId,
            user_id: userId,
            room_id: roomId || ""
        })
    }

    onImageOpenRequested: function(source, caption) {
        imageViewerObject.open(source, caption)
    }

    onReactionToggleRequested: function(eventId, reaction) {
        root.requestReactionToggle(eventId, reaction.key || "", reaction)
    }

    onDownloadRequested: function(mediaUrl, filename, mediaFile, mediaMimeType) {
        root.requestMediaDownload(mediaUrl, filename, mediaFile, mediaMimeType)
    }

    onEventJumpRequested: function(eventId) {
        root.openMessageEvent(eventId)
    }

    onQuickReplyRequested: function(eventId, sender, body) {
        composerObject.startReply(eventId, sender, body)
    }
    onThreadRequested: function(messageData) { root.openThread(messageData) }
    onRetrySendRequested: function(timelineItemId) {
        root.commandRequested({
            type: "retry_message",
            request_id: root.nextRequestId("retry-send"),
            room_id: root.currentRoomId,
            timeline_item_id: timelineItemId
        })
    }

    onCopyRequested: function(text) { root.copyText(text) }

    onRedactRequested: function(eventId) {
        root.commandRequested({
            type: "redact_message",
            request_id: root.nextRequestId("redact"),
            room_id: root.currentRoomId,
            event_id: eventId
        })
    }

    onStickerPackInstallRequested: function(pack) { root.installStickerPack(pack) }

    onContextMenuRequested: function(messageIndex, messageData, multiSelection) {
        if (multiSelection)
            menusObject.openMulti()
        else
            menusObject.openSingle(messageIndex, messageData)
    }

    onOlderMessagesRequested: root.olderMessagesRequested(root.currentRoomId)
}

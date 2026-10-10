import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../../utils/PrismUtils.js" as Utils

Chat.ThreadPanel {
    required property var chat
    readonly property var root: chat
    required property var imageViewerObject
    required property var menusObject
    id: threadPanel
    visible: root.threadPanelOpen
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: root.rightPanelWidth
    z: 8400
    roomId: root.currentRoomId
    rootEventId: root.threadRootEventId
    rootMessage: root.threadRootMessage
    messages: root.threadMessages
    threadSummaries: root.roomThreads
    listLoading: root.roomThreadsLoading
    listHasMore: root.roomThreadsNextFrom !== ""
    listErrorText: root.roomThreadsError
    loading: root.threadLoading
    hasMore: root.threadHasMore
    errorText: root.threadError
    currentUserId: root.currentUserId
    authorNameResolver: root.authorDisplayName
    authorAvatarResolver: root.authorAvatarUrl
    mediaProxy: root.mediaProxy
    roundAvatars: root.roundAvatars
    autoLoadImages: root.autoLoadImages
    autoLoadVideos: root.autoLoadVideos
    accentColor: root.accentColor
    accentTextColor: root.accentTextColor
    iconColor: root.iconColor
    surfaceColor: root.surfaceColor
    elevatedColor: root.elevatedColor
    textPrimary: root.textPrimary
    textSecondary: root.textSecondary
    dividerColor: root.dividerColor
    onCloseRequested: root.closeThread()
    onBackRequested: root.backToThreadList()
    onThreadSelected: function(rootMessage) { root.openThread(rootMessage) }
    onLoadThreadListMoreRequested: root.requestRoomThreads(true)
    onRefreshThreadListRequested: {
        root.roomThreadsNextFrom = ""
        root.requestRoomThreads(false)
    }
    onLoadMoreRequested: {
        root.threadMessageLimit = Math.min(200, root.threadMessageLimit + 50)
        root.requestThreadMessages()
    }
    onSendRequested: function(body, replyTo) {
        root.commandRequested({
            type: "send_message",
            request_id: root.nextRequestId("thread-send"),
            room_id: root.currentRoomId,
            body: body,
            thread_root: root.threadRootEventId,
            reply_to: replyTo || null,
            mentioned_user_ids: []
        })
    }
    onRetryRequested: function(timelineItemId) {
        root.commandRequested({
            type: "retry_message",
            request_id: root.nextRequestId("thread-retry"),
            room_id: root.currentRoomId,
            timeline_item_id: timelineItemId,
            thread_root: root.threadRootEventId
        })
    }
    onReactionRequested: function(eventId, reaction) {
        root.requestReactionToggle(eventId, reaction.key || "", reaction)
    }
    onContextRequested: function(messageIndex, messageData) {
        menusObject.openSingle(messageIndex, messageData)
    }
    onUserRequested: function(userId, clickX, clickY) {
        root.lastUserClickX = threadPanel.x + clickX
        root.lastUserClickY = clickY
        var requestId = root.nextRequestId("thread-miniprofile")
        root.pendingMiniProfileRequestId = requestId
        root.pendingMiniProfileCacheKey = root.userDetailsCacheKey(userId, root.currentRoomId)
        root.showMiniProfile(root.cachedOrPreviewUserDetails(userId, root.currentRoomId))
        root.commandRequested({
            type: "get_user_details",
            request_id: requestId,
            user_id: userId,
            room_id: root.currentRoomId
        })
    }
    onImageRequested: function(source, caption) { imageViewerObject.open(source, caption) }
    onVideoRequested: function(details) { root.openVideoPlayer(details) }
    onVoicePlaybackRequested: function(details) { root.toggleVoicePlayback(details) }
    onVoiceSeekRequested: function(position) {
        if (root.voicePlayer) root.voicePlayer.position = position
    }
    onDownloadRequested: function(mediaUrl, filename, mediaFile, mimeType) {
        root.requestMediaDownload(mediaUrl, filename, mediaFile, mimeType)
    }
    onCopyRequested: function(text) { root.copyText(text) }
}

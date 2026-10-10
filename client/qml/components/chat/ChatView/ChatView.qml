import ".." as Chat
import QtQuick
import Prism.Ipc 1.0 as Native
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    id: root

    readonly property alias attachmentCacheTimerObject: attachmentCacheTimer
    readonly property alias attachmentsPanelLoaderObject: attachmentsPanelLoader
    readonly property alias composerObject: composer
    readonly property alias headerObject: header
    readonly property alias messageListObject: messageList
    readonly property alias threadDirectoryRefreshTimerObject: threadDirectoryRefreshTimer
    readonly property var i18nService: L10n.I18n
    readonly property var stickerCatalogService: L10n.StickerCatalog
    readonly property var stickerPackStoreService: L10n.StickerPackStore

    property var messageModel
    property var requestIdFactory: null
    property int localRequestSequence: 0
    property var pendingEdits: ({})
    property var pendingStickerCreations: ({})
    property var cancelledUploadIds: ({})
    // Temporary sticker packs survive room switches but are not installed.
    property var temporaryStickerLibrary: []
    property var temporarySharedStickerPacks: []
    property string currentRoomId: ""
    property int sessionEpoch: 0
    onSessionEpochChanged: {
        threadReadAllRequests = ({})
        roomThreadsRequestId = ""
        roomThreadsLoading = false
        if (attachmentsPanel) attachmentsPanel.reset()
    }
    property string unreadBoundaryEventId: ""
    property string readingAccountId: ""
    property var localReadEventIds: []
    property string displayedRoomId: ""
    property var restorePosition: null
    property int openingUnreadCount: 0
    property bool readingActive: true
    property bool cachedTimeline: false
    signal viewportSaved(string accountId, string roomId, var position)
    signal viewportRead(string roomId, string eventId, int remainingUnread)
    property bool unreadBoundaryPending: false
    property bool timelineInitialPositionReady: false
    property string currentUserId: ""
    property string currentUserAvatar: ""
    property string currentDisplayName: ""
    property bool currentDisplayNameKnown: false
    property int authorNameRevision: 0
    property string roomName: L10n.I18n.tr("Выберите чат")
    property var voiceSession: null
    property bool roomIsDirect: false
    property int roomEncryptionState: -1
    property bool chatsPanelCollapsed: false
    property bool isLoadingMessages: false
    property bool timelinePaginationInFlight: false
    property bool showEmptyState: false
    property string mediaProxy: ""
    property bool roundAvatars: true
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"
    property bool autoLoadImages: true
    property bool autoLoadVideos: true
    property int draftClearGeneration: 0
    property var draftRoomIds: []
    property bool typingNotificationsEnabled: true
    property bool publicReadReceipts: true
    property bool backendConnected: false
    property var typingUserIds: []

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property Item popupLayer: null
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    property string pendingMiniProfileRequestId: ""
    property string pendingMiniProfileIgnoreRequestId: ""
    property string pendingMiniProfileModerationRequestId: ""
    property string pendingMiniProfileCacheKey: ""
    property var userDetailsCache: ({})
    readonly property int maxUserDetailsCacheEntries: 128
    property var roomMembers: []
    property bool roomMembersLoading: false
    property string roomMembersError: ""
    property int roomMemberCount: 0
    property bool showThreadsInSmallGroups: false
    readonly property bool threadsAvailable: currentRoomId !== ""
        && (roomMemberCount > 5 || showThreadsInSmallGroups)
    onCurrentDisplayNameChanged: authorNameRevision++
    onCurrentDisplayNameKnownChanged: authorNameRevision++
    onRoomMembersChanged: authorNameRevision++
    readonly property bool canRedactOther: {
        var members = root.roomMembers || []
        for (var memberIndex = 0; memberIndex < members.length; memberIndex++) {
            if ((members[memberIndex].user_id || "") === root.currentUserId)
                return !!members[memberIndex].can_redact_other
        }
        return false
    }
    property var searchResults: []
    property string searchNextBatch: ""
    property string activeSearchQuery: ""
    property string searchError: ""
    property bool searchLoading: false
    property bool searchAppendPending: false
    property string pendingSearchEventId: ""
    property string pendingExternalSearchRoomId: ""
    property string pendingExternalSearchEventId: ""
    property string activeSearchRequestId: ""
    readonly property var attachmentsPanel: attachmentsPanelLoader.item
    readonly property var miniProfile: miniProfileLoader.item
    property bool membersPanelCollapsed: false
    property real expandedMembersPanelWidth: 230
    property real membersPanelWidth: currentRoomId !== ""
        ? (membersPanelCollapsed ? 0
            : Math.min(expandedMembersPanelWidth,
                       Math.max(190, root.width * 0.46)))
        : 0
    property string threadRootEventId: ""
    property var threadRootMessage: null
    property var threadMessages: []
    property bool threadsPanelVisible: false
    property var roomThreads: []
    property bool roomThreadsLoading: false
    property string roomThreadsError: ""
    property string roomThreadsNextFrom: ""
    property string roomThreadsRequestId: ""
    property bool roomThreadsAppendPending: false
    property int threadUnreadCount: 0
    property var threadReadAllRequests: ({})
    readonly property bool markingThreadsRead: !!threadReadAllRequests[currentRoomId]
    property bool threadLoading: false
    property bool threadHasMore: false
    property string threadError: ""
    property string threadRequestId: ""
    property int threadMessageLimit: 50
    readonly property bool threadPanelOpen: threadsPanelVisible
    readonly property bool threadDetailOpen: threadRootEventId !== ""
    readonly property real rightPanelWidth: threadPanelOpen
        ? Math.min(390, Math.max(300, root.width * 0.38)) : membersPanelWidth

    onThreadsAvailableChanged: {
        if (!threadsAvailable) {
            threadDirectoryRefreshTimer.stop()
            closeThread()
            roomThreads = []
            roomThreadsNextFrom = ""
            roomThreadsError = ""
            roomThreadsLoading = false
            roomThreadsRequestId = ""
            threadUnreadCount = 0
            return
        }
        if (currentRoomId !== "")
            Qt.callLater(function() { root.requestRoomThreads(false) })
    }

    Behavior on membersPanelWidth {
        enabled: !membersResizeDrag.active
        NumberAnimation { duration: L10n.UiPreferences.duration(220); easing.type: Easing.InOutCubic }
    }

    property real lastUserClickX: 0
    property real lastUserClickY: 0
    property bool fileDragActive: false
    property var pinnedMessages: []
    property var pinnedEventIds: []
    property var seenPinnedEventIdsByRoom: ({})
    property bool hasNewPinnedMessages: false
    property var activeVoice: null
    property real voicePlaybackRate: 1.0
    readonly property var voicePlayer: voicePlayerLoader.item

    function toggleVoicePlayback(details) {
        if (!details || !details.event_id || !details.source) return
        if (root.activeVoice && root.activeVoice.event_id === details.event_id) {
            if (root.voicePlayer) {
                if (root.voicePlayer.playing) root.voicePlayer.pause()
                else root.voicePlayer.play()
            }
            return
        }
        root.activeVoice = details
        voicePlayerLoader.active = true
        Qt.callLater(function() {
            if (!root.voicePlayer) return
            root.voicePlayer.source = details.source
            root.voicePlayer.playbackRate = root.voicePlaybackRate
            root.voicePlayer.play()
        })
    }

    function closeVoicePlayback() {
        if (root.voicePlayer) root.voicePlayer.stop()
        root.activeVoice = null
        voicePlayerLoader.active = false
    }

    function cycleVoiceSpeed() {
        root.voicePlaybackRate = root.voicePlaybackRate < 1.25 ? 1.5
            : root.voicePlaybackRate < 1.75 ? 2.0 : 1.0
        if (root.voicePlayer) root.voicePlayer.playbackRate = root.voicePlaybackRate
    }

    // Display-name priority: own profile, room member, cached event.
    function authorDisplayName(sender, cachedName) {
        if (!sender) return ""
        if (sender === root.currentUserId && root.currentDisplayNameKnown)
            return root.currentDisplayName || Utils.displayName(sender)
        var members = root.roomMembers || []
        for (var i = 0; i < members.length; i++) {
            if ((members[i].user_id || "") !== sender) continue
            var memberName = members[i].display_name || ""
            return memberName !== "" ? memberName : Utils.displayName(sender)
        }
        return cachedName || Utils.displayName(sender)
    }

    function typingIndicatorText() {
        var users = root.typingUserIds || []
        if (users.length === 0) return ""
        var first = root.authorDisplayName(String(users[0] || ""), "")
        if (users.length === 1)
            return L10n.I18n.tr("%1 печатает…").replace("%1", first)
        var second = root.authorDisplayName(String(users[1] || ""), "")
        if (users.length === 2)
            return L10n.I18n.tr("%1 и %2 печатают…")
                .replace("%1", first).replace("%2", second)
        return L10n.I18n.tr("%1, %2 и ещё %3 печатают…")
            .replace("%1", first).replace("%2", second)
            .replace("%3", String(users.length - 2))
    }

    function authorAvatarUrl(sender, cachedAvatar) {
        if (!sender) return ""
        if (sender === root.currentUserId)
            return root.currentUserAvatar
        var members = root.roomMembers || []
        for (var i = 0; i < members.length; i++) {
            if ((members[i].user_id || "") === sender)
                return members[i].avatar_url || cachedAvatar || ""
        }
        return cachedAvatar || ""
    }

    function threadMessageKey(message) {
        return Native.FrontendLogic.invoke("chat.threadMessageKey", root, [message])
    }

    function mergeThreadMessages(incoming) {
        return Native.FrontendLogic.invoke("chat.mergeThreadMessages", root, [incoming])
    }

    function requestThreadMessages() {
        return Native.FrontendLogic.invoke("chat.requestThreadMessages", root, [])
    }

    function openThread(messageData) {
        return Native.FrontendLogic.invoke("chat.openThread", root, [messageData])
    }

    function openThreadsPanel() {
        return Native.FrontendLogic.invoke("chat.openThreadsPanel", root, [])
    }

    function backToThreadList() {
        return Native.FrontendLogic.invoke("chat.backToThreadList", root, [])
    }

    function closeThread() {
        return Native.FrontendLogic.invoke("chat.closeThread", root, [])
    }

    function requestRoomThreads(append) {
        return Native.FrontendLogic.invoke("chat.requestRoomThreads", root, [append])
    }

    function receiveRoomThreads(roomId, threads, nextFrom, unreadCount,
                                errorText, requestId) {
        return Native.FrontendLogic.invoke("chat.receiveRoomThreads", root,
                                           [roomId, threads, nextFrom, unreadCount,
                                            errorText, requestId])
    }

    function markAllThreadsRead() {
        return Native.FrontendLogic.invoke("chat.markAllThreadsRead", root, [])
    }

    function receiveAllThreadsRead(roomId, success, readEvents, errorText, requestId) {
        return Native.FrontendLogic.invoke("chat.receiveAllThreadsRead", root,
                                           [roomId, success, readEvents,
                                            errorText, requestId])
    }

    function markActiveThreadRead() {
        return Native.FrontendLogic.invoke("chat.markActiveThreadRead", root, [])
    }

    function receiveThreadRead(roomId, rootEventId, success, errorText) {
        return Native.FrontendLogic.invoke("chat.receiveThreadRead", root,
                                           [roomId, rootEventId, success, errorText])
    }

    function receiveThreadMessages(roomId, rootEventId, messages, hasMore,
                                   errorText, requestId) {
        return Native.FrontendLogic.invoke("chat.receiveThreadMessages", root,
                                           [roomId, rootEventId, messages,
                                            hasMore, errorText, requestId])
    }

    function receiveLiveTimelineMessages(roomId, messages) {
        return Native.FrontendLogic.invoke("chat.receiveLiveTimelineMessages", root,
                                           [roomId, messages])
    }

    function receiveThreadMutation(roomId, rootEventId) {
        return Native.FrontendLogic.invoke("chat.receiveThreadMutation", root,
                                           [roomId, rootEventId])
    }

    function openVideoPlayer(details) {
        videoPlayerLoader.details = details || ({})
        if (videoPlayerLoader.item) {
            videoPlayerLoader.item.open()
            return
        }
        videoPlayerLoader.active = true
    }

    function openStickerPack(pack) {
        stickerPackDialogLoader.pack = pack || null
        if (stickerPackDialogLoader.item) {
            stickerPackDialogLoader.item.openFor(pack)
            return
        }
        stickerPackDialogLoader.active = true
    }

    signal commandRequested(var command)
    signal typingStateChanged(string roomId, bool typing)
    signal sourceRequested(string jsonText)
    signal olderMessagesRequested(string roomId)

    function rearmOlderMessagesRequest() {
        if (messageList) messageList.olderRequestArmed = true
    }
    signal olderMembersRequested(string roomId)
    signal membersRefreshRequested(string roomId)
    signal searchRequested(string roomId, string query, string nextBatch, string requestId)
    signal messageContextRequested(string roomId, string eventId)
    signal chatsPanelToggleRequested()
    signal roomMarkedUnreadRequested(string roomId, string eventId, int unreadCount)
    signal feedbackRequested(string text, bool isError)
    signal membersPanelResizeCommitted(real panelWidth)

    function requestMediaDownload(mediaUrl, filename, mediaFile, mediaMimeType) {
        if (!mediaUrl || mediaUrl === "") return
        root.commandRequested({
            type: "download_media",
            request_id: root.nextRequestId("download-media"),
            media_url: mediaUrl,
            filename: filename || "attachment",
            media_file: mediaFile || undefined,
            media_mime_type: mediaMimeType || undefined
        })
    }

    function harvestTemporaryStickerData() {
        return Native.FrontendLogic.invoke("chat.harvestTemporaryStickerData", root, [])
    }

    function collectStickerLibrary() {
        return Native.FrontendLogic.invoke("chat.collectStickerLibrary", root, [])
    }

    function collectSharedStickerPacks() {
        return Native.FrontendLogic.invoke("chat.collectSharedStickerPacks", root, [])
    }

    function collectKnownStickerPacks() {
        return Native.FrontendLogic.invoke("chat.collectKnownStickerPacks", root, [])
    }

    function resolveStickerPack(sticker) {
        return Native.FrontendLogic.invoke("chat.resolveStickerPack", root, [sticker])
    }

    function saveStickerToOwn(sticker) {
        return Native.FrontendLogic.invoke("chat.saveStickerToOwn", root, [sticker])
    }

    function installStickerPack(pack) {
        return Native.FrontendLogic.invoke("chat.installStickerPack", root, [pack])
    }

    function shareStickerPack(pack) {
        return Native.FrontendLogic.invoke("chat.shareStickerPack", root, [pack])
    }

    function sendSticker(sticker) {
        return Native.FrontendLogic.invoke("chat.sendSticker", root, [sticker])
    }

    function requestPinnedMessages() {
        pinnedMessages = []
        pinnedEventIds = []
        hasNewPinnedMessages = false
        refreshPinnedMessages()
    }

    function refreshPinnedMessages() {
        if (currentRoomId !== "")
            commandRequested({
                type: "get_pinned_messages",
                request_id: nextRequestId("pinned"),
                room_id: currentRoomId
            })
    }

    function markPinnedMessagesSeen() {
        if (currentRoomId === "") return
        var nextSeenByRoom = Object.assign({}, seenPinnedEventIdsByRoom)
        nextSeenByRoom[currentRoomId] = pinnedEventIds.slice()
        seenPinnedEventIdsByRoom = nextSeenByRoom
        hasNewPinnedMessages = false
    }

    function receivePinnedMessages(roomId, messages, errorText) {
        if (roomId !== currentRoomId) return
        if (errorText !== "") {
            // Keep the last known pins when a background refresh fails.
            if (pinnedPopup.visible) feedbackRequested(errorText, true)
            return
        }

        pinnedMessages = messages || []
        var ids = []
        for (var i = 0; i < pinnedMessages.length; i++) {
            var eventId = pinnedMessages[i].event_id || ""
            if (eventId !== "")
                ids.push(eventId)
        }
        pinnedEventIds = ids

        if (!seenPinnedEventIdsByRoom.hasOwnProperty(roomId)) {
            var initialSeenByRoom = Object.assign({}, seenPinnedEventIdsByRoom)
            initialSeenByRoom[roomId] = ids.slice()
            seenPinnedEventIdsByRoom = initialSeenByRoom
            hasNewPinnedMessages = false
            return
        }

        if (pinnedPopup.visible) {
            markPinnedMessagesSeen()
            return
        }

        var seenIds = seenPinnedEventIdsByRoom[roomId] || []
        hasNewPinnedMessages = false
        for (var pinIndex = 0; pinIndex < ids.length; pinIndex++) {
            if (seenIds.indexOf(ids[pinIndex]) === -1) {
                hasNewPinnedMessages = true
                break
            }
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.visible && root.currentRoomId !== ""
        onTriggered: root.refreshPinnedMessages()
    }

    Timer {
        id: stickerHarvestTimer
        interval: 120
        repeat: false
        onTriggered: root.harvestTemporaryStickerData()
    }

    Connections {
        target: root.messageModel
        ignoreUnknownSignals: true
        function onCountChanged() {
            stickerHarvestTimer.restart()
            attachmentCacheTimer.restart()
        }
        function onDataChanged() { attachmentCacheTimer.restart() }
    }

    Timer {
        id: attachmentCacheTimer
        interval: 100
        onTriggered: if (root.attachmentsPanel && root.currentRoomId === root.displayedRoomId)
            root.attachmentsPanel.reconcileTimeline(root.currentRoomId, root.messageModel)
    }

    Timer {
        id: threadDirectoryRefreshTimer
        interval: 600
        repeat: false
        onTriggered: {
            if (!root.threadsAvailable) return
            if (root.roomThreadsLoading) restart()
            else root.requestRoomThreads(false)
        }
    }

    color: backgroundColor
    focus: true
    onCurrentRoomIdChanged: {
        closeThread()
        roomThreads = []
        roomThreadsNextFrom = ""
        roomThreadsError = ""
        roomThreadsLoading = false
        threadUnreadCount = 0
        roomThreadsRequestId = ""
        if (threadsAvailable)
            Qt.callLater(function() { root.requestRoomThreads(false) })
        requestPinnedMessages()
        imageViewer.close()
        if (attachmentsPanel)
            attachmentsPanel.close()
        if (miniProfile)
            miniProfile.close()
        header.closeSearch()
        pinnedPopup.visible = false
        searchResults = []
        searchNextBatch = ""
        activeSearchQuery = ""
        activeSearchRequestId = ""
        searchError = ""
        searchLoading = false
        searchAppendPending = false
        pendingSearchEventId = ""
        pendingMiniProfileRequestId = ""
        pendingMiniProfileIgnoreRequestId = ""
        if (miniProfile)
            miniProfile.ignoreBusy = false
        pendingMiniProfileCacheKey = ""
        pendingEdits = ({})
        composer.resetForRoomChange()
        messageList.clearSelection()

        if (currentRoomId !== "" && currentRoomId === pendingExternalSearchRoomId) {
            var externalEventId = pendingExternalSearchEventId
            pendingExternalSearchRoomId = ""
            pendingExternalSearchEventId = ""
            Qt.callLater(function() {
                root.requestExternalSearchContext(currentRoomId, externalEventId)
            })
        }
    }

    onCurrentUserIdChanged: {
        userDetailsCache = ({})
        temporaryStickerLibrary = []
        temporarySharedStickerPacks = []
        pendingMiniProfileRequestId = ""
        pendingMiniProfileIgnoreRequestId = ""
        if (miniProfile)
            miniProfile.ignoreBusy = false
        pendingMiniProfileCacheKey = ""
        pendingExternalSearchRoomId = ""
        pendingExternalSearchEventId = ""
        seenPinnedEventIdsByRoom = ({})
        hasNewPinnedMessages = false
    }

    function nextRequestId(suffix) {
        if (requestIdFactory)
            return requestIdFactory(suffix || "chat")
        localRequestSequence++
        return Date.now().toString() + "-" + localRequestSequence
            + (suffix ? "-" + suffix : "")
    }

    function copyText(text) {
        clipboard.text = text || ""
        clipboard.selectAll()
        clipboard.copy()
        clipboard.text = ""
    }

    function matrixToLink(roomId, eventId) {
        var room = String(roomId || "")
        if (room === "") return ""
        var link = "https://matrix.to/#/" + encodeURIComponent(room)
        var event = String(eventId || "")
        if (event !== "")
            link += "/" + encodeURIComponent(event)
        return link
    }

    function reactionForKey(reactions, key) {
        if (!reactions) return ({})
        var count = typeof reactions.length === "number"
            ? reactions.length : Number(reactions.count || 0)
        for (var index = 0; index < count; index++) {
            var reaction = typeof reactions.get === "function"
                ? reactions.get(index) : reactions[index]
            if (reaction && reaction.key === key)
                return reaction
        }
        return ({})
    }

    function requestReactionToggle(eventId, key, reaction) {
        if (!eventId || !key) return
        var currentReaction = reaction || ({})
        if (!currentReaction.reacted)
            L10n.QuickReactionStore.recordUse(key)
        commandRequested({
            type: "send_reaction",
            request_id: nextRequestId("reaction"),
            room_id: currentRoomId,
            event_id: eventId,
            key: key,
            reacted: !!currentReaction.reacted,
            reaction_event_id: currentReaction.own_event_id || ""
        })
    }

    function userDetailsCacheKey(userId, roomId) {
        return Native.FrontendLogic.invoke("chat.userDetailsCacheKey", root, [userId, roomId])
    }

    function cachedOrPreviewUserDetails(userId, roomId) {
        return Native.FrontendLogic.invoke("chat.cachedOrPreviewUserDetails", root,
                                           [userId, roomId])
    }

    function receiveUserDetails(details, requestId, errorText) {
        return Native.FrontendLogic.invoke("chat.receiveUserDetails", root,
                                           [details, requestId, errorText])
    }

    function receiveUserIgnoreResult(userId, ignored, success, errorText, requestId) {
        return Native.FrontendLogic.invoke("chat.receiveUserIgnoreResult", root,
                                           [userId, ignored, success,
                                            errorText, requestId])
    }

    function receiveModerationResult(roomId, userId, action, success,
                                     errorText, requestId) {
        return Native.FrontendLogic.invoke("chat.receiveModerationResult", root,
                                           [roomId, userId, action, success,
                                            errorText, requestId])
    }

    function receiveSearchResults(messages, nextBatch, errorText, requestId) {
        return Native.FrontendLogic.invoke("chat.receiveSearchResults", root,
                                           [messages, nextBatch, errorText, requestId])
    }

    function requestAttachments(roomId, nextFrom, requestId, category, count) {
        return Native.FrontendLogic.invoke("chat.requestAttachments", root,
                                           [roomId, nextFrom, requestId, category, count])
    }

    function receiveAttachments(roomId, messages, nextFrom, errorText, requestId) {
        return Native.FrontendLogic.invoke("chat.receiveAttachments", root,
                                           [roomId, messages, nextFrom,
                                            errorText, requestId])
    }

    function openAttachmentsPanel() {
        return Native.FrontendLogic.invoke("chat.openAttachmentsPanel", root, [])
    }

    function openSearchResult(message) {
        return Native.FrontendLogic.invoke("chat.openSearchResult", root, [message])
    }

    function openMessageEvent(eventId) {
        return Native.FrontendLogic.invoke("chat.openMessageEvent", root, [eventId])
    }

    function requestExternalSearchContext(roomId, eventId) {
        return Native.FrontendLogic.invoke("chat.requestExternalSearchContext", root,
                                           [roomId, eventId])
    }

    function openExternalSearchResult(roomId, eventId) {
        return Native.FrontendLogic.invoke("chat.openExternalSearchResult", root,
                                           [roomId, eventId])
    }

    function receiveMessageContext(roomId, eventId, found) {
        return Native.FrontendLogic.invoke("chat.receiveMessageContext", root,
                                           [roomId, eventId, found])
    }

    function receiveClipboardPasteResult(requestId, success, text, attachments, errorText) {
        return Native.FrontendLogic.invoke("chat.receiveClipboardPasteResult", root,
                                           [requestId, success, text,
                                            attachments, errorText])
    }

    function receiveEditResult(requestId, success, errorText) {
        return Native.FrontendLogic.invoke("chat.receiveEditResult", root,
                                           [requestId, success, errorText])
    }

    function receiveUploadProgress(requestId, current, total) {
        return Native.FrontendLogic.invoke("chat.receiveUploadProgress", root,
                                           [requestId, current, total])
    }

    function receiveUploadResult(requestId, success, errorText) {
        return Native.FrontendLogic.invoke("chat.receiveUploadResult", root,
                                           [requestId, success, errorText])
    }

    function receiveStickerAssetUpload(requestId, success, mediaUrl, mimeType, errorText) {
        return Native.FrontendLogic.invoke("chat.receiveStickerAssetUpload", root,
                                           [requestId, success, mediaUrl,
                                            mimeType, errorText])
    }

    function performSearch(query) {
        return Native.FrontendLogic.invoke("chat.performSearch", root, [query])
    }

    function focusMessageSearch() {
        return Native.FrontendLogic.invoke("chat.focusMessageSearch", root, [])
    }

    TextEdit { id: clipboard; visible: false }

    DropArea {
        id: fileDropArea
        anchors.fill: parent
        z: 19000
        enabled: root.currentRoomId !== ""

        onEntered: function(drag) {
            root.fileDragActive = drag.hasUrls
            if (drag.hasUrls)
                drag.accept(Qt.LinkAction)
        }
        onExited: root.fileDragActive = false
        onDropped: function(drop) {
            root.fileDragActive = false
            if (!drop.hasUrls)
                return
            var urls = drop.urls || []
            for (var i = 0; i < urls.length; i++) {
                var path = Utils.localPath(urls[i])
                if (path === "")
                    continue
                var normalized = path.replace(/\\/g, "/")
                composer.stageAttachment(urls[i], path,
                                         normalized.split("/").pop())
            }
            drop.acceptProposedAction()
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 19001
        visible: root.fileDragActive
        color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                       root.accentColor.b, 0.13)
        border.width: 2
        border.color: root.accentColor

        Text {
            anchors.centerIn: parent
            text: L10n.I18n.tr("Отпустите файлы для добавления")
            color: root.textPrimary
            font.pointSize: 14
            font.bold: true
        }
    }

    Chat.ChatHeader {
        id: header
        z: 400
        anchors.top: parent.top
        width: parent.width - root.rightPanelWidth
        roomId: root.currentRoomId
        roomName: root.roomName
        roomEncryptionState: root.roomEncryptionState
        selectedCount: messageList.selectedCount
        multiSelectMode: messageList.multiSelectMode
        chatsPanelCollapsed: root.chatsPanelCollapsed
        membersPanelCollapsed: root.membersPanelCollapsed
        accentColor: root.accentColor
        iconColor: root.iconColor
        surfaceColor: root.surfaceColor
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        pinnedCount: root.pinnedMessages.length
        hasNewPinnedMessages: root.hasNewPinnedMessages
        threadUnreadCount: root.threadUnreadCount
        threadsPanelOpen: root.threadPanelOpen
        threadsEnabled: root.threadsAvailable
        directCallAvailable: root.roomIsDirect && root.currentRoomId !== ""
        directCallActive: root.voiceSession && root.voiceSession.active
            && root.voiceSession.roomId === root.currentRoomId
        onCallRequested: {
            if (!root.voiceSession) return
            if (directCallActive) root.voiceSession.panelOpen = true
            else root.voiceSession.call(root.currentRoomId, root.roomName)
        }
        markingThreadsRead: root.markingThreadsRead
        onThreadsReadRequested: root.markAllThreadsRead()
        searchMembers: root.roomMembers
        onPinnedRequested: pinnedPopup.visible = !pinnedPopup.visible
        onThreadsRequested: {
            if (root.threadPanelOpen) root.closeThread()
            else root.openThreadsPanel()
        }
        onClearSelectionRequested: messageList.clearSelection()
        onChatsPanelToggleRequested: root.chatsPanelToggleRequested()
        onMembersPanelToggleRequested: {
            if (root.threadPanelOpen) {
                root.closeThread()
                root.membersPanelCollapsed = false
            } else {
                root.membersPanelCollapsed = !root.membersPanelCollapsed
            }
        }
        onSearchRequested: function(query) { root.performSearch(query) }
        onSearchVisibilityChanged: function(visible) {
            if (!visible) {
                root.searchResults = []
                root.searchError = ""
                root.searchLoading = false
                root.searchAppendPending = false
                root.activeSearchRequestId = ""
            }
        }
    }

    Loader {
        id: voicePlayerLoader
        active: false
        sourceComponent: Component {
            Chat.VoiceMessagePlayer {
                playbackRate: root.voicePlaybackRate
                onEnded: root.closeVoicePlayback()
                onPlaybackError: function(errorText) {
                    root.feedbackRequested(errorText || L10n.I18n.tr("Ошибка воспроизведения"), true)
                }
            }
        }
    }

    Rectangle {
        id: voiceMiniPlayer
        visible: !!root.activeVoice
        anchors.top: header.bottom
        width: parent.width - root.rightPanelWidth
        height: visible ? 38 : 0
        color: root.surfaceColor

        Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 10
            Basic.Button {
                width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter
                text: root.voicePlayer && root.voicePlayer.playing ? "Ⅱ" : "▶"
                onClicked: if (root.activeVoice) root.toggleVoicePlayback(root.activeVoice)
                contentItem: Text { text: parent.text; color: root.accentColor; font.pointSize: 9; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 14; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12) }
            }
            Column {
                width: parent.width - 128; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                Text { width: parent.width; text: root.activeVoice ? (root.activeVoice.title || L10n.I18n.tr("Голосовое сообщение")) : ""; color: root.textPrimary; font.pointSize: 8; font.bold: true; elide: Text.ElideRight }
                Rectangle { width: parent.width; height: 2; radius: 1; color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.14); Rectangle { height: parent.height; radius: 1; color: root.accentColor; width: root.voicePlayer && root.voicePlayer.duration > 0 ? parent.width * root.voicePlayer.position / root.voicePlayer.duration : 0 } }
            }
            Basic.Button {
                width: 34; height: 28; anchors.verticalCenter: parent.verticalCenter
                text: root.voicePlaybackRate.toFixed(root.voicePlaybackRate % 1 === 0 ? 0 : 1) + "×"
                onClicked: root.cycleVoiceSpeed()
                contentItem: Text { text: parent.text; color: root.textSecondary; font.pointSize: 8; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 7; color: parent.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.07) : "transparent" }
            }
            Basic.Button {
                width: 28; height: 28; anchors.verticalCenter: parent.verticalCenter; text: "×"
                onClicked: root.closeVoicePlayback()
                contentItem: Text { text: parent.text; color: root.textSecondary; font.pointSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 7; color: parent.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.07) : "transparent" }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.dividerColor }
    }

    Rectangle {
        id: pinnedPopup
        visible: false
        z: 20
        onVisibleChanged: if (visible) root.markPinnedMessagesSeen()
        anchors.top: divider.bottom
        anchors.right: parent.right
        width: Math.min(360, parent.width - 24)
        height: Math.min(300, Math.max(54, pinnedList.contentHeight + 20))
        color: root.elevatedColor
        border.width: 1
        border.color: root.dividerColor
        radius: 10
        ListView {
            id: pinnedList
            anchors.fill: parent
            anchors.margins: 10
            model: root.pinnedMessages
            spacing: 6
            delegate: Rectangle {
                width: pinnedList.width
                height: 42
                radius: 7
                color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.05)
                Column {
                    anchors.fill: parent
                    anchors.margins: 7
                    Text { text: root.authorDisplayName(modelData.sender || "", modelData.sender_display_name || ""); color: root.accentColor; font.pointSize: 8; elide: Text.ElideRight; width: parent.width }
                    Text { text: modelData.sender_is_ignored ? L10n.I18n.tr("Сообщение скрыто · Показать") : (modelData.body || L10n.I18n.tr("Медиа-сообщение")); color: root.textPrimary; font.pointSize: 9; elide: Text.ElideRight; width: parent.width }
                }
                TapHandler {
                    onTapped: {
                        pinnedPopup.visible = false
                        root.openMessageEvent(modelData.event_id || "")
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: pinnedList.count === 0
                text: L10n.I18n.tr("Нет закреплённых сообщений")
                color: root.textSecondary
                font.pointSize: 9
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: voiceMiniPlayer.visible ? voiceMiniPlayer.bottom : header.bottom
        width: parent.width - root.rightPanelWidth
        height: 1
        color: root.dividerColor
        opacity: 0.7
    }

    ChatComposer {
        id: composer
        chat: root
    }

    Item {
        id: typingIndicator
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: root.rightPanelWidth
        anchors.bottom: composer.top
        height: visible ? 24 : 0
        visible: root.currentRoomId !== ""
            && (root.typingUserIds || []).length > 0

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.typingIndicatorText()
            color: root.textSecondary
            font.pointSize: 8
            font.italic: true
            elide: Text.ElideRight
        }
    }

    ChatTimeline {
        id: messageList
        chat: root
        composerObject: composer
        dividerObject: divider
        imageViewerObject: imageViewer
        menusObject: menus
        typingIndicatorObject: typingIndicator
    }

    Connections {
        target: miniProfileLoader.item

        function onSendDmRequested(userId) {
            root.commandRequested({
                type: "open_direct_message",
                request_id: root.nextRequestId("direct-message"),
                user_id: userId
            })
        }

        function onIgnoreRequested(userId, ignored) {
            var requestId = root.nextRequestId("miniprofile-ignore")
            root.pendingMiniProfileIgnoreRequestId = requestId
            if (miniProfile)
                miniProfile.ignoreBusy = true
            root.commandRequested({
                type: "set_user_ignored",
                request_id: requestId,
                user_id: userId,
                ignored: !!ignored
            })
        }


        function onMentionRequested(userId) {
            composer.insertMention(userId)
        }

        function onCopyUserIdRequested(userId) {
            root.copyText(userId)
            root.feedbackRequested(L10n.I18n.tr("Matrix ID скопирован"), false)
        }
    }

    Loader {
        id: stickerPackDialogLoader
        active: false
        property var pack: null
        onLoaded: item.openFor(pack)
        sourceComponent: Component {
            Chat.StickerPackDialog {
                accountId: root.currentUserId
                mediaProxy: root.mediaProxy
                accentColor: root.accentColor
                surfaceColor: root.surfaceColor
                elevatedColor: root.elevatedColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                dividerColor: root.dividerColor
                onInstallRequested: function(pack) {
                    root.installStickerPack(pack)
                    close()
                }
                onShareRequested: function(pack) { root.shareStickerPack(pack) }
                onStickerChosen: function(sticker) { root.sendSticker(sticker) }
                onClosed: Qt.callLater(function() {
                    if (stickerPackDialogLoader.item
                            && stickerPackDialogLoader.item.opened)
                        return
                    stickerPackDialogLoader.pack = null
                    stickerPackDialogLoader.active = false
                })
            }
        }
    }

    Chat.MessageContextMenus {
        id: menus
        selectedCount: messageList.selectedCount
        canDeleteSelected: messageList.canDeleteSelection()
        currentUserId: root.currentUserId
        canRedactOther: root.canRedactOther
        threadsEnabled: root.threadsAvailable
        mediaProxy: root.mediaProxy
        accentColor: root.accentColor
        iconColor: root.iconColor
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        dividerColor: root.dividerColor
        roundAvatars: root.roundAvatars
        messageDateFormat: root.messageDateFormat
        messageTimeFormat: root.messageTimeFormat
        authorNameResolver: function(sender, cached) { return root.authorDisplayName(sender, cached) }
        authorAvatarResolver: function(sender, cached) { return root.authorAvatarUrl(sender, cached) }
        stickerPackResolver: root.resolveStickerPack

        onCopySelectedRequested: messageList.copySelectedMessages()
        onDeleteSelectedRequested: messageList.deleteSelectedMessages()
        onCopySingleRequested: function(text) { root.copyText(text) }
        onCopyLinkRequested: function(messageData) {
            var link = root.matrixToLink(root.currentRoomId,
                                         messageData.event_id || "")
            if (link === "") return
            root.copyText(link)
            root.feedbackRequested(
                L10n.I18n.tr("Ссылка на сообщение скопирована"), false)
        }
        onSourceRequested: function(messageData) {
            root.sourceRequested(JSON.stringify({
                event_id: messageData.event_id,
                sender: messageData.sender,
                body: messageData.body,
                type: messageData.msg_type,
                timestamp: messageData.timestamp,
                is_edited: messageData.is_edited
            }, null, 2))
        }
        onEditRequested: function(messageData) {
            composer.startEditing(messageData.event_id, messageData.body)
        }
        onReplyRequested: function(messageData) {
            if ((messageData.thread_root_id || "") !== "" && root.threadDetailOpen)
                threadPanel.startReply(messageData)
            else
                composer.startReply(messageData.event_id, messageData.sender, messageData.body)
        }
        onThreadRequested: function(messageData) { root.openThread(messageData) }
        onMarkUnreadRequested: function(messageIndex, messageData) {
            var unreadCount = Math.max(1, Number(messageIndex) + 1)
            root.roomMarkedUnreadRequested(root.currentRoomId,
                                           messageData.event_id || "", unreadCount)
        }
        onDeleteSingleRequested: function(messageIndex, messageData) {
            root.commandRequested({
                type: "redact_message",
                request_id: root.nextRequestId("redact"),
                room_id: root.currentRoomId,
                event_id: messageData.event_id
            })
        }
        onPinRequested: function(messageData) {
            root.commandRequested({
                type: "pin_message",
                request_id: root.nextRequestId("pin"),
                room_id: root.currentRoomId,
                event_id: messageData.event_id,
                pinned: !messageData.pinned
            })
        }
        onDownloadRequested: function(messageData) {
            root.requestMediaDownload(messageData.media_url || "",
                                      messageData.body || "attachment",
                                      messageData.media_file || null,
                                      messageData.media_mime_type || "")
        }
        onReactionRequested: function(messageData, key) {
            root.requestReactionToggle(
                messageData.event_id,
                key,
                root.reactionForKey(messageData.reactions, key))
        }
        onStickerSaveRequested: function(messageData) { root.saveStickerToOwn(messageData) }
        onStickerPackViewRequested: function(pack) { root.openStickerPack(pack) }
    }

    Item {
        id: membersResizeHandle
        visible: root.currentRoomId !== "" && !root.membersPanelCollapsed
            && !root.threadPanelOpen
        x: root.width - root.membersPanelWidth - width / 2
        y: 0
        width: 10
        height: root.height
        z: 8500

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: membersResizeDrag.active
                || membersResizeHover.containsMouse ? 2 : 1
            height: parent.height
            color: membersResizeDrag.active || membersResizeHover.containsMouse
                ? root.accentColor : root.dividerColor
            opacity: membersResizeDrag.active
                || membersResizeHover.containsMouse ? 0.72 : 0.32
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(100) }
            }
        }

        HoverHandler { id: membersResizeHover }
        DragHandler {
            id: membersResizeDrag
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            property real startWidth: 230
            cursorShape: Qt.SplitHCursor
            onActiveChanged: {
                if (active) {
                    startWidth = root.expandedMembersPanelWidth
                } else {
                    root.membersPanelResizeCommitted(
                        root.expandedMembersPanelWidth)
                }
            }
            onActiveTranslationChanged: {
                if (!active) return
                var maximum = Math.max(190, Math.min(420, root.width * 0.46))
                root.expandedMembersPanelWidth = Math.max(190,
                    Math.min(maximum, startWidth - activeTranslation.x))
            }
        }
    }

    Loader {
        id: membersPanelLoader
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.membersPanelWidth
        active: root.currentRoomId !== "" && !root.membersPanelCollapsed
            && !root.threadPanelOpen
        sourceComponent: Component {
    Chat.RoomMembersPanel {
        id: membersPanel
        anchors.fill: parent
        members: root.roomMembers || []
        loading: root.roomMembersLoading
        errorText: root.roomMembersError
        totalMemberCount: root.roomMemberCount
        authorNameResolver: root.authorDisplayName
        authorNameRevision: root.authorNameRevision
        currentRoomId: root.currentRoomId
        currentUserId: root.currentUserId
        currentDisplayName: root.currentDisplayName
        currentUserAvatar: root.currentUserAvatar
        collapsed: root.membersPanelCollapsed
        mediaProxy: root.mediaProxy
        roundAvatars: root.roundAvatars
        surfaceColor: root.surfaceColor
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        dividerColor: root.dividerColor
        accentColor: root.accentColor
        iconColor: root.iconColor

        onAttachmentsRequested: root.openAttachmentsPanel()
        onMembersMoreRequested: root.olderMembersRequested(root.currentRoomId)
        onRetryRequested: root.membersRefreshRequested(root.currentRoomId)

        onUserRequested: function(userId, clickX, clickY) {
            var point = membersPanel.mapToItem(root, clickX, clickY)
            root.lastUserClickX = point.x
            root.lastUserClickY = point.y
            var requestId = root.nextRequestId("miniprofile")
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
    }
        }
    }

    ChatThreadPanel {
        id: threadPanel
        chat: root
        imageViewerObject: imageViewer
        menusObject: menus
    }

    SearchResults {
        id: searchPanel
        chat: root
        dividerObject: divider
        headerObject: header
    }

    Loader {
        id: attachmentsPanelLoader
        anchors.fill: parent
        parent: root.popupLayer ? root.popupLayer : root
        z: 9500
        active: false
        property string targetRoomId: ""
        onLoaded: item.openForRoom(targetRoomId)
        sourceComponent: Component {
    Chat.RoomAttachmentsPanel {
        mediaProxy: root.mediaProxy
        authorNameResolver: root.authorDisplayName
        authorNameRevision: root.authorNameRevision
        messageDateFormat: root.messageDateFormat
        messageTimeFormat: root.messageTimeFormat
        autoLoadImages: root.autoLoadImages
        autoLoadVideos: root.autoLoadVideos
        accentColor: root.accentColor
        iconColor: root.iconColor
        accentTextColor: root.accentTextColor
        backgroundColor: root.backgroundColor
        surfaceColor: root.surfaceColor
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        dividerColor: root.dividerColor
        activeVoiceEventId: root.activeVoice ? (root.activeVoice.event_id || "") : ""
        activeVoicePlaying: root.voicePlayer ? root.voicePlayer.playing : false

        onLoadMoreRequested: function(roomId, nextFrom, requestId, category, count) { root.requestAttachments(roomId, nextFrom, requestId, category, count) }
        onVoicePlaybackRequested: function(details) { root.toggleVoicePlayback(details) }
        onImageRequested: function(source, caption) { imageViewer.open(source, caption) }
        onUrlRequested: function(url) { Qt.openUrlExternally(url) }
        onDownloadRequested: function(item) {
            root.requestMediaDownload(item.media_url || "", item.body || "attachment",
                                      item.media_file || null,
                                      item.media_mime_type || "")
        }
        onMessageRequested: function(eventId) { root.openMessageEvent(eventId) }

    }
        }
    }

    // One expanded video player per ChatView.
    Loader {
        id: videoPlayerLoader
        anchors.fill: parent
        z: 11000
        active: false
        property var details: ({})
        onLoaded: item.open()
        sourceComponent: Component {
            Chat.VideoPlayerPopup {
                eventId: String(videoPlayerLoader.details.event_id || "")
                title: String(videoPlayerLoader.details.title || "")
                mediaUrl: String(videoPlayerLoader.details.media_url || "")
                mediaFile: videoPlayerLoader.details.media_file || null
                mediaMimeType: String(videoPlayerLoader.details.media_mime_type || "")
                mediaProxy: root.mediaProxy
                accentColor: root.accentColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                elevatedColor: root.elevatedColor
                dividerColor: root.dividerColor
                onClosed: Qt.callLater(function() {
                    if (videoPlayerLoader.item && videoPlayerLoader.item.opened)
                        return
                    videoPlayerLoader.details = ({})
                    videoPlayerLoader.active = false
                })
            }
        }
    }

    ImageViewer {
        id: imageViewer
        chat: root
    }

    Loader {
        id: miniProfileLoader
        anchors.fill: parent
        z: 9000
        active: false
        property var pendingDetails: null
        property real pendingX: 0
        property real pendingY: 0
        onLoaded: item.open(pendingDetails, pendingX, pendingY)
        sourceComponent: Component {
    Chat.UserMiniProfile {
        accentColor: root.accentColor
        accentTextColor: root.accentTextColor
        backgroundColor: root.backgroundColor
        surfaceColor: root.surfaceColor
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        dividerColor: root.dividerColor
        mediaProxy: root.mediaProxy
        roundAvatars: root.roundAvatars
        currentUserId: root.currentUserId
        currentDisplayName: root.currentDisplayName
        currentUserAvatar: root.currentUserAvatar
        onModerationRequested: function(roomId, userId, action, powerLevel) {
            var requestId = root.requestIdFactory
                ? root.requestIdFactory("miniprofile-moderation")
                : Date.now().toString() + "-miniprofile-moderation"
            root.pendingMiniProfileModerationRequestId = requestId
            var command = {
                type: "moderate_room_member",
                request_id: requestId,
                room_id: roomId,
                user_id: userId,
                action: action
            }
            if (powerLevel !== undefined && powerLevel !== null)
                command.power_level = Number(powerLevel)
            root.commandRequested(command)
        }
        onClosed: Qt.callLater(function() {
            if (miniProfileLoader.item && miniProfileLoader.item.opened)
                return
            miniProfileLoader.pendingDetails = null
            miniProfileLoader.active = false
        })
    }
        }
    }

    function showMiniProfile(details) {
        miniProfileLoader.pendingDetails = details
        miniProfileLoader.pendingX = root.lastUserClickX
        miniProfileLoader.pendingY = root.lastUserClickY
        if (miniProfileLoader.item) {
            miniProfileLoader.item.open(details, root.lastUserClickX, root.lastUserClickY)
            return
        }
        miniProfileLoader.active = true
    }

    Keys.onPressed: function(event) {
        if (imageViewer.opened && event.key === Qt.Key_Escape) {
            imageViewer.close()
            event.accepted = true
            return
        }
        if (attachmentsPanel && attachmentsPanel.opened && event.key === Qt.Key_Escape) {
            attachmentsPanel.close()
            event.accepted = true
            return
        }
        if (miniProfile && miniProfile.opened && event.key === Qt.Key_Escape) {
            miniProfile.close()
            event.accepted = true
            return
        }
        if (header.searchVisible && event.key === Qt.Key_Escape) {
            header.closeSearch()
            event.accepted = true
            return
        }
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_A && messageList.selectedCount > 0) {
            messageList.selectAll()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape && messageList.selectedCount > 0) {
            messageList.clearSelection()
            event.accepted = true
        } else if (event.key === Qt.Key_Delete && messageList.selectedCount > 0) {
            if (messageList.canDeleteSelection()) messageList.deleteSelectedMessages()
            event.accepted = true
        }
    }
}

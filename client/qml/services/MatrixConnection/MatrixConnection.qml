import ".." as Services
import Prism.Ipc 1.0 as Native
import QtQuick
import "../../utils" as L10n

Item {
    id: root

    function tr(text) {
        return L10n.I18n.tr(text)
    }
    readonly property alias cachedMessageModelObject: cachedMessageModel
    readonly property alias emptyMessageModelObject: emptyMessageModel
    readonly property alias encryptedRefreshTimerObject: encryptedRefreshTimer
    readonly property alias roomMembersPrefetchTimerObject: roomMembersPrefetchTimer
    readonly property alias roomMembersRefreshTimerObject: roomMembersRefreshTimer
    readonly property alias roomPreviewPrefetchTimerObject: roomPreviewPrefetchTimer
    readonly property alias socketObject: socket
    readonly property alias timelineInitialFillTimerObject: timelineInitialFillTimer

    property var roomModel
    // Hidden rooms retain their prepared ListModel.
    property var messageModel: emptyMessageModel
    property var preparedRoomModels: ({})
    ListModel { id: emptyMessageModel; dynamicRoles: true }
    Component { id: cachedMessageModel; ListModel { dynamicRoles: true } }
    property string currentRoomId: ""
    property bool isLoadingMessages: false
    property bool showEmptyState: false
    property alias transportAutoConnect: socket.autoConnect
    property color accentColor: "#20D500"
    property var pinnedRoomIds: []
    property var pinnedMessagesCache: ({})
    property var pinnedMessagesRefreshQueued: ({})
    property bool readReceiptsEnabled: true
    property var roomReadReceiptOverrides: ({})
    property var ignoredUserIds: ({})
    property var typingUserIdsByRoom: ({})
    // Reject out-of-order typing updates.
    property double typingRequestGeneration: Date.now() * 1000
    property var knownInvitedRoomIds: ({})
    property string mediaProxyBase: ""

    property var roomMessageCache: ({})
    property var roomMessageCacheUpdatedAt: ({})
    property var roomMessageCacheLastAccess: ({})
    // Room switches cache normalized rows; the SDK Timeline stays authoritative.
    property int maxCachedMessageRooms: 24
    property int maxCachedMessagesPerRoom: 200
    property var messageRequestRooms: ({})
    property var roomPreviewRequests: ({})
    property var roomPreviewCache: ({})
    property var roomPreviewCacheOrder: []
    property var roomPreviewPrefetchQueue: []
    property var roomPreviewPrefetchQueued: ({})
    property var roomPreviewPrefetchTargets: []
    property var roomPreviewPrefetchRoomIds: []
    property var roomPreviewPrefetchState: ({})
    property var roomPreviewPrefetchProgress: ({})
    property var roomPreviewPrefetchResults: []
    property int roomPreviewPrefetchInFlight: 0
    readonly property bool foregroundTimelineBusy: currentRoomId !== ""
        && (displayedRoomId !== currentRoomId || isLoadingMessages
            || !timelineInitialPositionReady || timelineInitialFillActive
            || timelinePaginationInFlight
            || (timelineGeneration === 0 && !!timelineRequestByRoom[currentRoomId]))

    // Completion metadata outlives the prepared-model LRU.
    readonly property int maxCachedRoomPreviews: 256
    readonly property int maxPreparedPrefetchRooms: 20
    readonly property int initialRoomMessageCount: 30
    // Background prefetch is serialized behind the visible timeline.
    readonly property int maxConcurrentRoomPreviewPrefetches: 1
    property var messageRequestTargets: ({})
    property bool timelineDiffsSupported: false
    property var timelineRequestByRoom: ({})
    property var timelineItemIds: []
    property var timelineItems: []
    property int timelineSessionEpoch: 0
    // Drop events from previous account sessions.
    property int activeSessionEpoch: 0
    property int timelineGeneration: 0
    // Order concurrent timeline commands across frontend reconnects.
    property double timelineOpenSequence: Date.now() * 1000
    property int timelineInitialMessageTarget: initialRoomMessageCount
    property bool timelinePaginationInFlight: false
    property string timelinePaginationRoomId: ""
    property string timelinePaginationRequestId: ""
    property bool timelinePaginationWasInitialFill: false
    property int timelinePaginationStartItemCount: 0
    property bool timelineInitialFillActive: false
    property int timelineInitialFillStalledPages: 0
    property bool timelineHasMoreBackwards: false
    property bool timelineInitialPositionReady: false
    property bool showingCachedTimeline: false
    property bool timelineCacheGapPending: false
    property string timelineFreshness: "offline"
    property int syncFreshnessEpoch: 0
    property string syncFreshness: ""
    property var lastReadEventByRoom: ({})
    property var queuedRoomReads: ({})
    property var pendingReadByRoom: ({})
    property var readStateRequestByRoom: ({})
    property var manualUnreadHolds: ({})
    property var manualUnreadEventIds: ({})
    property var manualUnreadCounts: ({})
    property var readingPositionResolver: null
    property var readingRestorePosition: null
    property string restoreEventId: ""
    property string unreadBoundaryEventId: ""
    property bool unreadBoundaryPending: false
    property int openingUnreadCount: 0
    property var roomMembersNextTokens: ({})
    property var roomMembersPaginationInFlight: ({})
    property var roomMembersErrors: ({})
    property var roomMembersLoadedCounts: ({})
    readonly property int roomMembersPageSize: 30
    property var roomMembersPrefetchQueue: []
    property string roomMembersPrefetchInFlightRoomId: ""
    property var roomMembersPrefetchFailedUntil: ({})
    // Coalesce member refreshes emitted in one sync burst.
    property var roomMembersRefreshQueued: ({})
    property string roomMembersRefreshTarget: ""
    property string displayedRoomId: ""
    property string displayedContextEventId: ""
    property int commandRequestSequence: 0
    property string encryptedRefreshRoomId: ""
    property int encryptedRefreshAttempts: 0
    property var pendingCommands: ({})
    property int defaultCommandTimeoutMs: 30000
    property int longCommandTimeoutMs: 130000
    readonly property bool connected: socket.connected

    property var profiles: []
    property string activeProfileId: ""
    property string authenticatedUserId: ""
    property bool profileSwitchInFlight: false
    property bool profileListInFlight: false
    property bool roomsRequestInFlight: false
    property bool roomsRefreshQueued: false
    property var pendingLeaveRoomIds: ({})

    signal connectionStateChanged(string text, var stateColor)
    signal authenticated(string userId, string server, string avatarUrl, string profileId, bool resetUi)
    signal sessionStateResolved(bool authenticated)
    signal roomsLoadFinished(bool success)
    signal loginFailed(string errorText)
    signal registrationFailed(string errorText)
    signal loggedOut()
    signal avatarUpdated(bool success, string errorText, string avatarUrl)
    signal ownProfileUpdated(bool success, var details, string errorText, string requestId)
    signal userProfileChanged(string roomId, string userId, string displayName, string avatarUrl)
    signal pinnedMessagesReceived(string roomId, var messages, string errorText)
    signal pinMessageFinished(string roomId, bool success, string errorText)
    signal reactionFinished(string roomId, bool success, string errorText)
    signal spaceHierarchyReceived(string spaceId, var rooms, string nextBatch, bool append, string errorText)
    signal joinSpaceRoomFinished(string roomId, bool success, bool knocked, string errorText)
    signal roomAddedToSpace(string roomId, string spaceId, bool success, string errorText)
    signal roomRemovedFromSpace(string roomId, string spaceId, bool success, string errorText, string requestId)
    signal roomUpdateFinished(string roomId, bool success, string errorText)
    signal roomMemberModerationFinished(string roomId, string userId, string action,
                                        bool success, string errorText, string requestId)
    signal profilesUpdated(var profiles, string activeProfileId)
    signal profileSwitchStateChanged(bool inFlight)
    signal profileSwitchFailed(string errorText)
    signal profileDeleted(string profileId, bool wasActive, string errorText)
    signal currentProfileUpdated(string userId, string server, string avatarUrl, string profileId)
    signal roomsUpdated()
    signal userDetailsReceived(var details, string requestId, string errorText)
    signal userIgnoreFinished(string userId, bool ignored, bool success, string errorText, string requestId)
    signal directMessageReady(string roomId, string roomName, string avatarUrl, bool created, string errorText, string requestId)
    signal roomCreated(string roomId, string roomName, bool isSpace, string errorText, string requestId)
    signal roomDetailsReceived(var details, string requestId, string errorText)
    signal roomLeaveStarted(string roomId)
    signal roomLeaveFinished(string roomId, bool success, string errorText)
    signal roomInviteFinished(string roomId, bool success, string errorText)
    signal roomInvitationReceived(string roomId, string roomName, string inviter)
    // Used by the notification bridge.
    signal backgroundMessageReceived(string roomId, var message)
    signal roomMembersReceived(string roomId, var members, string nextBatch, bool append, string errorText)
    signal roomSearchReceived(string roomId, var messages, string nextBatch, string errorText, string requestId)
    signal userDirectorySearchReceived(var users, bool limited, string errorText, string requestId)
    signal publicRoomSearchReceived(var rooms, string nextBatch, string errorText, string requestId)
    signal roomAttachmentsReceived(string roomId, var messages, string nextFrom, string errorText, string requestId)
    signal threadMessagesReceived(string roomId, string rootEventId, var messages,
                                  bool hasMore, string errorText, string requestId)
    signal roomThreadsReceived(string roomId, var threads, string nextFrom,
                               int unreadCount, string errorText, string requestId)
    signal allThreadsReadFinished(string roomId, bool success, var readEvents,
                                  string errorText, string requestId)
    signal threadReadFinished(string roomId, string rootEventId, bool success,
                              string errorText)
    signal timelineMessagesUpdated(string roomId, var messages)
    signal threadMutationFinished(string roomId, string rootEventId)
    signal retryMessageFinished(string roomId, string timelineItemId, bool success,
                                string errorText)
    signal messageContextReceived(string roomId, string eventId, bool found)
    signal roomPreviewReceived(string roomId, var messages, string nextFrom, bool append, string errorText, string requestId)
    signal clipboardPasteFinished(string requestId, bool success, string text, var attachments, string errorText)
    signal editMessageFinished(string requestId, bool success, string errorText)
    signal uploadProgressChanged(string requestId, double current, double total)
    signal uploadFinished(string requestId, bool success, string errorText)
    signal stickerAssetUploaded(string requestId, bool success, string mediaUrl, string mimeType, string errorText)
    signal roomKeysTransferFinished(string requestId, string operation, bool success,
                                    double importedCount, double totalCount, string errorText)
    signal encryptionOverviewReceived(var overview, string errorText)
    signal matrixDevicesReceived(var devices, string errorText)
    signal matrixDevicesChanged(var devices, double sessionEpoch)
    signal deviceOperationFinished(string requestId, string operation, bool success,
                                   var deviceIds, string errorText)
    signal deviceDeleteUiaaRequired(string requestId, string operationId, var flows,
                                    bool passwordSupported)
    signal deviceDeleteWebRequired(string requestId, var deviceIds, string url)
    signal e2eeActionFinished(string requestId, bool success, string uiaaSession,
                               string authType, string approvalUrl, string recoveryKey,
                               string flowId, string errorText)
    signal verificationUpdated(var update)
    signal storageStatsReceived(var stats, string errorText)
    signal storageActionFinished(string action, bool success, var details, string errorText)
    signal operationFeedback(string text, bool isError)
    signal timelinePaginationFinished()

    width: 0
    height: 0
    visible: false

    function nextRequestId(suffix) {
        return Native.FrontendLogic.invoke("matrix.nextRequestId", root, [suffix])
    }

    function commandTimeoutMs(commandType) {
        return Native.FrontendLogic.invoke("matrix.commandTimeoutMs", root, [commandType])
    }

    function registerPendingCommand(command) {
        return Native.FrontendLogic.invoke("matrix.registerPendingCommand", root, [command])
    }

    function takePendingCommand(requestId) {
        return Native.FrontendLogic.invoke("matrix.takePendingCommand", root, [requestId])
    }

    function cleanupMessageRequest(requestId, roomId) {
        return Native.FrontendLogic.invoke("matrix.cleanupMessageRequest", root, [requestId, roomId])
    }

    function handleCommandFailure(command, errorText) {
        return Native.FrontendLogic.invoke("matrix.handleCommandFailure", root, [command, errorText])
    }

    function failAllPending(errorText) {
        return Native.FrontendLogic.invoke("matrix.failAllPending", root, [errorText])
    }

    signal voiceEvent(var message)
    function sendVoiceCommand(command) {
        return socket.connected && socket.sendTextMessage(JSON.stringify(command))
    }

    function sendCommand(command) {
        if (!command || !command.type) return false
        if (!command.request_id)
            command.request_id = nextRequestId(command.type)

        var serialized = ""
        try {
            serialized = JSON.stringify(command)
        } catch (error) {
            handleCommandFailure(command, L10n.I18n.tr("Некорректная команда"))
            return false
        }

        if (!socket.connected || !socket.sendTextMessage(serialized)) {
            handleCommandFailure(command, L10n.I18n.tr("Нет связи с бэкендом"))
            return false
        }

        registerPendingCommand(command)
        return true
    }

    function sendTyping(roomId, typing) {
        return Native.FrontendLogic.invoke("matrix.sendTyping", root, [roomId, typing])
    }

    function typingUsersForRoom(roomId) {
        return Native.FrontendLogic.invoke("matrix.typingUsersForRoom", root, [roomId])
    }

    function requestRooms() {
        return Native.FrontendLogic.invoke("matrix.requestRooms", root, [])
    }

    function acceptRoomInvite(roomId) {
        return Native.FrontendLogic.invoke("matrix.acceptRoomInvite", root, [roomId])
    }

    function requestRoomDetails(roomId, requestId) {
        return Native.FrontendLogic.invoke("matrix.requestRoomDetails", root, [roomId, requestId])
    }

    function setRoomLeavePending(roomId, pending) {
        return Native.FrontendLogic.invoke("matrix.setRoomLeavePending", root, [roomId, pending])
    }

    function removeRoomFromVisibleModel(roomId) {
        return Native.FrontendLogic.invoke("matrix.removeRoomFromVisibleModel", root, [roomId])
    }

    function leaveRoom(roomId) {
        return Native.FrontendLogic.invoke("matrix.leaveRoom", root, [roomId])
    }

    function requestProfiles() {
        return Native.FrontendLogic.invoke("matrix.requestProfiles", root, [])
    }

    function switchProfile(profileId) {
        return Native.FrontendLogic.invoke("matrix.switchProfile", root, [profileId])
    }

    function deleteProfile(profileId) {
        return Native.FrontendLogic.invoke("matrix.deleteProfile", root, [profileId])
    }

    function requestUserDetails(userId, roomId) {
        return Native.FrontendLogic.invoke("matrix.requestUserDetails", root, [userId, roomId])
    }

    function setUserIgnored(userId, ignored) {
        return Native.FrontendLogic.invoke("matrix.setUserIgnored", root, [userId, ignored])
    }

    function openDirectMessage(userId) {
        return Native.FrontendLogic.invoke("matrix.openDirectMessage", root, [userId])
    }

    function createRoom(options) {
        return Native.FrontendLogic.invoke("matrix.createRoom", root, [options])
    }

    function requestRoomMembers(roomId, from) {
        return Native.FrontendLogic.invoke("matrix.requestRoomMembers", root, [roomId, from])
    }

    function queueRoomMembersRefresh(roomId) {
        return Native.FrontendLogic.invoke("matrix.queueRoomMembersRefresh", root, [roomId])
    }

    function finishRoomMembersRequest(roomId) {
        return Native.FrontendLogic.invoke("matrix.finishRoomMembersRequest", root, [roomId])
    }

    function requestOlderRoomMembers(roomId) {
        return Native.FrontendLogic.invoke("matrix.requestOlderRoomMembers", root, [roomId])
    }

    function scheduleRoomMembersPrefetch() {
        if (!connected || !roomModel || authenticatedUserId === "")
            return

        var orderedRoomIds = []
        var seenRoomIds = ({})
        var activeRoomId = currentRoomId || ""
        var index
        var room
        var roomId

        // Prefetch the visible room first.
        if (activeRoomId !== "") {
            for (index = 0; index < roomModel.count; ++index) {
                room = roomModel.get(index)
                if ((room.room_id || "") !== activeRoomId)
                    continue
                if (!room.is_invited && !room.is_space
                        && !pendingLeaveRoomIds[activeRoomId]) {
                    orderedRoomIds.push(activeRoomId)
                    seenRoomIds[activeRoomId] = true
                }
                break
            }
        }

        // Then preserve the same top-to-bottom order used by message prefetch.
        for (index = 0; index < roomModel.count; ++index) {
            room = roomModel.get(index)
            roomId = room.room_id || ""
            if (roomId === "" || seenRoomIds[roomId] || room.is_invited
                    || room.is_space || pendingLeaveRoomIds[roomId])
                continue
            orderedRoomIds.push(roomId)
            seenRoomIds[roomId] = true
        }

        var queue = []
        var now = Date.now()
        for (index = 0; index < orderedRoomIds.length; ++index) {
            roomId = orderedRoomIds[index]
            // Zero also marks a completed first page.
            if (roomMembersLoadedCounts[roomId] !== undefined
                    || roomMembersPaginationInFlight[roomId]
                    || Number(roomMembersPrefetchFailedUntil[roomId] || 0) > now)
                continue
            queue.push(roomId)
        }
        roomMembersPrefetchQueue = queue
        if (roomMembersPrefetchInFlightRoomId === "" && queue.length > 0
                && !foregroundTimelineBusy)
            roomMembersPrefetchTimer.start()
    }

    function prefetchQueuedRoomMembers() {
        if (!connected || authenticatedUserId === ""
                || foregroundTimelineBusy
                || roomMembersPrefetchInFlightRoomId !== "")
            return
        // Foreground member pagination has priority.
        if (currentRoomId !== "" && roomMembersPaginationInFlight[currentRoomId])
            return

        var queue = roomMembersPrefetchQueue.slice(0)
        while (queue.length > 0) {
            var roomId = queue.shift()
            if (roomMembersLoadedCounts[roomId] !== undefined
                    || roomMembersPaginationInFlight[roomId])
                continue
            roomMembersPrefetchQueue = queue
            roomMembersPrefetchInFlightRoomId = roomId
            requestRoomMembers(roomId)
            return
        }
        roomMembersPrefetchQueue = []
    }

    function requestPinnedMessages(roomId, forceRefresh) {
        return Native.FrontendLogic.invoke("matrix.requestPinnedMessages", root, [roomId, forceRefresh])
    }

    function finishPinnedMessagesRequest(roomId, messages, errorText) {
        return Native.FrontendLogic.invoke("matrix.finishPinnedMessagesRequest", root, [roomId, messages, errorText])
    }

    function requestSpaceHierarchy(spaceId, from) {
        return Native.FrontendLogic.invoke("matrix.requestSpaceHierarchy", root, [spaceId, from])
    }

    function joinSpaceRoom(room, knock) {
        return Native.FrontendLogic.invoke("matrix.joinSpaceRoom", root, [room, knock])
    }

    function addRoomToSpace(roomId, spaceId) {
        return Native.FrontendLogic.invoke("matrix.addRoomToSpace", root, [roomId, spaceId])
    }

    function removeRoomFromSpace(roomId, spaceId) {
        return Native.FrontendLogic.invoke("matrix.removeRoomFromSpace", root, [roomId, spaceId])
    }

    function updateRoom(roomId, changes) {
        return Native.FrontendLogic.invoke("matrix.updateRoom", root, [roomId, changes])
    }

    function moderateRoomMember(roomId, userId, action, powerLevel, reason) {
        return Native.FrontendLogic.invoke("matrix.moderateRoomMember", root, [roomId, userId, action, powerLevel, reason])
    }

    function searchRoomMessages(roomId, query, nextBatch, requestId) {
        return Native.FrontendLogic.invoke("matrix.searchRoomMessages", root, [roomId, query, nextBatch, requestId])
    }
    function searchUsers(query, requestId) {
        return Native.FrontendLogic.invoke("matrix.searchUsers", root, [query, requestId])
    }

    function searchPublicRooms(query, requestId, spacesOnly) {
        return Native.FrontendLogic.invoke("matrix.searchPublicRooms", root, [query, requestId, spacesOnly])
    }


    function normalizeReactions(value) {
        return Native.FrontendLogic.invoke("matrix.normalizeReactions", root, [value])
    }

    function normalizeReadReceipts(value) {
        return Native.FrontendLogic.invoke("matrix.normalizeReadReceipts", root, [value])
    }

    function normalizeMessage(item) {
        return Native.FrontendLogic.invoke("matrix.normalizeMessage", root, [item])
    }

    function applyUserProfileChanged(roomId, userId, displayName, avatarUrl) {
        return Native.FrontendLogic.invoke("matrix.applyUserProfileChanged", root, [roomId, userId, displayName, avatarUrl])
    }

    function applyUserIgnored(userId, ignored) {
        return Native.FrontendLogic.invoke("matrix.applyUserIgnored", root, [userId, ignored])
    }

    function applyCanonicalIdentity(details) {
        return Native.FrontendLogic.invoke("matrix.applyCanonicalIdentity", root, [details])
    }

    function roomIsPinned(roomId) {
        return Native.FrontendLogic.invoke("matrix.roomIsPinned", root, [roomId])
    }

    function pinnedRoomPosition(roomId) {
        return Native.FrontendLogic.invoke("matrix.pinnedRoomPosition", root, [roomId])
    }

    // Preserve SDK order outside the pinned overlay.
    function applyRoomOrder() {
        return Native.FrontendLogic.invoke("matrix.applyRoomOrder", root, [])
    }

    onPinnedRoomIdsChanged: {
        Qt.callLater(root.applyRoomOrder)
        Qt.callLater(root.scheduleRoomPreviewPrefetch)
        Qt.callLater(root.scheduleRoomMembersPrefetch)
    }
    function normalizeRoom(item) {
        return Native.FrontendLogic.invoke("matrix.normalizeRoom", root, [item])
    }

    function setRoomUnreadCount(roomId, unreadCount) {
        return Native.FrontendLogic.invoke("matrix.setRoomUnreadCount", root, [roomId, unreadCount])
    }

    function roomUnreadCount(roomId) {
        return Native.FrontendLogic.invoke("matrix.roomUnreadCount", root, [roomId])
    }

    function manualUnreadCount(roomId) {
        return Native.FrontendLogic.invoke("matrix.manualUnreadCount", root, [roomId])
    }

    function setManualUnreadDetails(roomId, eventId, unreadCount) {
        return Native.FrontendLogic.invoke("matrix.setManualUnreadDetails", root, [roomId, eventId, unreadCount])
    }

    function manualUnreadEventId(roomId) {
        return Native.FrontendLogic.invoke("matrix.manualUnreadEventId", root, [roomId])
    }

    function refreshManualUnreadCount(roomId, messages) {
        return Native.FrontendLogic.invoke("matrix.refreshManualUnreadCount", root, [roomId, messages])
    }

    function roomIsMarkedUnread(roomId) {
        return Native.FrontendLogic.invoke("matrix.roomIsMarkedUnread", root, [roomId])
    }

    function setRoomMarkedUnreadLocal(roomId, markedUnread) {
        return Native.FrontendLogic.invoke("matrix.setRoomMarkedUnreadLocal", root, [roomId, markedUnread])
    }

    function newestReadableEventId(messages) {
        return Native.FrontendLogic.invoke("matrix.newestReadableEventId", root, [messages])
    }

    function hasManualUnreadHold(roomId) {
        return Native.FrontendLogic.invoke("matrix.hasManualUnreadHold", root, [roomId])
    }

    function setManualUnreadHold(roomId, held) {
        return Native.FrontendLogic.invoke("matrix.setManualUnreadHold", root, [roomId, held])
    }

    function roomReadSnapshot(roomId) {
        return Native.FrontendLogic.invoke("matrix.roomReadSnapshot", root, [roomId])
    }

    function clearPendingRoomRead(roomId) {
        return Native.FrontendLogic.invoke("matrix.clearPendingRoomRead", root, [roomId])
    }

    function trackReadStateRequest(roomId, requestId) {
        return Native.FrontendLogic.invoke("matrix.trackReadStateRequest", root, [roomId, requestId])
    }

    function reconcilePendingRoomRead(room) {
        return Native.FrontendLogic.invoke("matrix.reconcilePendingRoomRead", root, [room])
    }

    function finishRoomRead(roomId, requestId, success) {
        return Native.FrontendLogic.invoke("matrix.finishRoomRead", root, [roomId, requestId, success])
    }

    function markVisibleMessagesRead(roomId, eventId, remainingUnread) {
        return Native.FrontendLogic.invoke("matrix.markVisibleMessagesRead", root, [roomId, eventId, remainingUnread])
    }

    function flushQueuedRoomRead(roomId) {
        return Native.FrontendLogic.invoke("matrix.flushQueuedRoomRead", root, [roomId])
    }

    function markRoomRead(roomId, eventId, explicitAction, remainingUnread) {
        return Native.FrontendLogic.invoke("matrix.markRoomRead", root, [roomId, eventId, explicitAction, remainingUnread])
    }

    function setRoomReadState(roomId, unread, eventId, unreadCount) {
        return Native.FrontendLogic.invoke("matrix.setRoomReadState", root, [roomId, unread, eventId, unreadCount])
    }

    function hasCachedRoom(roomId) {
        return Native.FrontendLogic.invoke("matrix.hasCachedRoom", root, [roomId])
    }

    function touchMessageCacheRoom(roomId) {
        return Native.FrontendLogic.invoke("matrix.touchMessageCacheRoom", root, [roomId])
    }

    function discardPreparedRoom(roomId) {
        return Native.FrontendLogic.invoke("matrix.discardPreparedRoom", root, [roomId])
    }

    function clearPreparedRooms() {
        return Native.FrontendLogic.invoke("matrix.clearPreparedRooms", root, [])
    }

    function preparedModelForRoom(roomId) {
        return Native.FrontendLogic.invoke("matrix.preparedModelForRoom", root, [roomId])
    }

    function trimMessageCache(preferredRoomId) {
        return Native.FrontendLogic.invoke("matrix.trimMessageCache", root, [preferredRoomId])
    }

    function compactInactiveRoom(roomId, model) {
        return Native.FrontendLogic.invoke("matrix.compactInactiveRoom", root, [roomId, model])
    }

    function replaceMessageModel(messages) {
        return Native.FrontendLogic.invoke("matrix.replaceMessageModel", root, [messages])
    }

    function sameMessageValue(previous, next) {
        return Native.FrontendLogic.invoke("matrix.sameMessageValue", root, [previous, next])
    }

    function updateMessageRow(index, message) {
        return Native.FrontendLogic.invoke("matrix.updateMessageRow", root, [index, message])
    }

    function mergeTimelineHistory(messages) {
        return Native.FrontendLogic.invoke("matrix.mergeTimelineHistory", root, [messages])
    }

    function reconcileMessageModel(messages) {
        return Native.FrontendLogic.invoke("matrix.reconcileMessageModel", root, [messages])
    }

    function snapshotDisplayedRoom() {
        return Native.FrontendLogic.invoke("matrix.snapshotDisplayedRoom", root, [])
    }

    function showRoomFromCache(roomId) {
        return Native.FrontendLogic.invoke("matrix.showRoomFromCache", root, [roomId])
    }

    function timelineItemMessage(item) {
        return Native.FrontendLogic.invoke("matrix.timelineItemMessage", root, [item])
    }

    function rebuildVisibleTimeline(includeThreadReplies) {
        return Native.FrontendLogic.invoke("matrix.rebuildVisibleTimeline", root, [includeThreadReplies])
    }

    function propagateReadReceipts(messages) {
        return Native.FrontendLogic.invoke("matrix.propagateReadReceipts", root, [messages])
    }

    function firstEventAfterReadMarker(items) {
        return Native.FrontendLogic.invoke("matrix.firstEventAfterReadMarker", root, [items])
    }

    function needsReadingPosition() {
        return Native.FrontendLogic.invoke("matrix.needsReadingPosition", root, [])
    }

    function updateReadingPositionReady() {
        return Native.FrontendLogic.invoke("matrix.updateReadingPositionReady", root, [])
    }

    function updateTimelineLoadingState() {
        return Native.FrontendLogic.invoke("matrix.updateTimelineLoadingState", root, [])
    }

    function responseTimelineFreshness(message) {
        return Native.FrontendLogic.invoke("matrix.responseTimelineFreshness", root, [message])
    }

    function refreshTimelineReadState(messages) {
        return Native.FrontendLogic.invoke("matrix.refreshTimelineReadState", root, [messages])
    }

    function isIncomingUnreadMessage(message) {
        return Native.FrontendLogic.invoke("matrix.isIncomingUnreadMessage", root, [message])
    }

    function firstUnreadEventFromCount(messages, unreadCount) {
        return Native.FrontendLogic.invoke("matrix.firstUnreadEventFromCount", root, [messages, unreadCount])
    }

    function resolveUnreadBoundary(items, messages) {
        return Native.FrontendLogic.invoke("matrix.resolveUnreadBoundary", root, [items, messages])
    }

    function applyTimelineSnapshot(msg) {
        return Native.FrontendLogic.invoke("matrix.applyTimelineSnapshot", root, [msg])
    }

    function continueInitialTimelineFill() {
        return Native.FrontendLogic.invoke("matrix.continueInitialTimelineFill", root, [])
    }

    function paginateTimelineBackwards(initialFill) {
        return Native.FrontendLogic.invoke("matrix.paginateTimelineBackwards", root, [initialFill])
    }

    function applyTimelineDiffs(msg) {
        return Native.FrontendLogic.invoke("matrix.applyTimelineDiffs", root, [msg])
    }

    function requestMessages(roomId, forceReopen) {
        return Native.FrontendLogic.invoke("matrix.requestMessages", root, [roomId, forceReopen])
    }
    function cachedRoomPreview(roomId, limit) {
        return Native.FrontendLogic.invoke("matrix.cachedRoomPreview", root, [roomId, limit])
    }

    function cacheRoomPreview(roomId, messages) {
        return Native.FrontendLogic.invoke("matrix.cacheRoomPreview", root, [roomId, messages])
    }

    function touchRoomPreviewCache(roomId) {
        return Native.FrontendLogic.invoke("matrix.touchRoomPreviewCache", root, [roomId])
    }

    function roomPrefetchStamp(roomId) {
        return Native.FrontendLogic.invoke("matrix.roomPrefetchStamp", root, [roomId])
    }

    function scheduleRoomPreviewPrefetch() {
        return Native.FrontendLogic.invoke("matrix.scheduleRoomPreviewPrefetch", root, [])
    }

    function nextCachedRoomToPrepare() {
        return Native.FrontendLogic.invoke("matrix.nextCachedRoomToPrepare", root, [])
    }

    function prefetchQueuedRoomPreviews() {
        return Native.FrontendLogic.invoke("matrix.prefetchQueuedRoomPreviews", root, [])
    }

    function finishRoomPreviewPrefetch(request, response) {
        return Native.FrontendLogic.invoke("matrix.finishRoomPreviewPrefetch", root, [request, response])
    }

    function consumeRoomPrefetchResult(request, response, openingRoom) {
        return Native.FrontendLogic.invoke("matrix.consumeRoomPrefetchResult", root, [request, response, openingRoom])
    }

    function preparePrefetchedRoom(roomId, messages) {
        return Native.FrontendLogic.invoke("matrix.preparePrefetchedRoom", root, [roomId, messages])
    }

    function adoptPendingRoomPrefetch(roomId) {
        return Native.FrontendLogic.invoke("matrix.adoptPendingRoomPrefetch", root, [roomId])
    }

    function clearRoomPreviewCache() {
        return Native.FrontendLogic.invoke("matrix.clearRoomPreviewCache", root, [])
    }

    function requestRoomPreview(roomId, from, requestId) {
        return Native.FrontendLogic.invoke("matrix.requestRoomPreview", root, [roomId, from, requestId])
    }


    function requestMessageContext(roomId, eventId) {
        return Native.FrontendLogic.invoke("matrix.requestMessageContext", root, [roomId, eventId])
    }

    function requestOlderMessages(roomId) {
        return Native.FrontendLogic.invoke("matrix.requestOlderMessages", root, [roomId])
    }

    function invalidateMessageCachesAfterKeyImport() {
        emptyStateTimer.stop()
        isLoadingMessages = false
        showEmptyState = false
        showingCachedTimeline = false
        timelineCacheGapPending = false
        timelineInitialPositionReady = false
        roomMessageCache = ({})
        roomMessageCacheUpdatedAt = ({})
        roomMessageCacheLastAccess = ({})
        clearRoomPreviewCache()
        clearPreparedRooms()
        roomPreviewRequests = ({})
        displayedRoomId = ""
        displayedContextEventId = ""
        timelineInitialFillTimer.stop()
        timelineRequestByRoom = ({})
        timelineItemIds = []
        timelineItems = []
        timelineSessionEpoch = 0
        timelineGeneration = 0
        timelinePaginationInFlight = false
        timelinePaginationRoomId = ""
        timelinePaginationRequestId = ""
        timelinePaginationWasInitialFill = false
        timelineInitialFillActive = false
        timelineInitialFillStalledPages = 0
        timelineHasMoreBackwards = false
        if (messageModel) messageModel.clear()
    }

    function resetMessageState() {
        emptyStateTimer.stop()
        isLoadingMessages = false
        showEmptyState = false
        ignoredUserIds = ({})
        typingUserIdsByRoom = ({})
        showingCachedTimeline = false
        timelineCacheGapPending = false
        timelineInitialPositionReady = false
        roomMessageCache = ({})
        roomMessageCacheUpdatedAt = ({})
        roomMessageCacheLastAccess = ({})
        clearRoomPreviewCache()
        clearPreparedRooms()
        messageRequestRooms = ({})
        roomPreviewRequests = ({})
        roomMembersNextTokens = ({})
        roomMembersPaginationInFlight = ({})
        roomMembersErrors = ({})
        roomMembersLoadedCounts = ({})
        roomMembersPrefetchQueue = []
        roomMembersPrefetchInFlightRoomId = ""
        roomMembersPrefetchFailedUntil = ({})
        roomMembersPrefetchTimer.stop()
        roomMembersRefreshQueued = ({})
        roomMembersRefreshTarget = ""
        roomMembersRefreshTimer.stop()
        readingRestorePosition = null
        restoreEventId = ""
        lastReadEventByRoom = ({})
        queuedRoomReads = ({})
        pendingReadByRoom = ({})
        readStateRequestByRoom = ({})
        manualUnreadHolds = ({})
        manualUnreadEventIds = ({})
        manualUnreadCounts = ({})
        displayedRoomId = ""
        timelineInitialFillTimer.stop()
        timelineRequestByRoom = ({})
        timelineItemIds = []
        timelineItems = []
        timelineSessionEpoch = 0
        timelineGeneration = 0
        timelinePaginationInFlight = false
        timelinePaginationRoomId = ""
        timelinePaginationRequestId = ""
        timelinePaginationWasInitialFill = false
        timelinePaginationStartItemCount = 0
        timelineInitialFillActive = false
        timelineInitialFillStalledPages = 0
        timelineHasMoreBackwards = false
        timelineFreshness = "offline"
        syncFreshnessEpoch = 0
        syncFreshness = ""
    }

    function clearUiStateForProfileSwitch() {
        pendingCommands = ({})
        pinnedMessagesCache = ({})
        pinnedMessagesRefreshQueued = ({})
        profileListInFlight = false
        roomsRequestInFlight = false
        roomsRefreshQueued = false
        knownInvitedRoomIds = ({})
        if (roomModel) roomModel.clear()
        if (messageModel) messageModel.clear()
        resetMessageState()
    }

    function applyVoiceParticipants(roomId, participants) {
        if (!roomModel || !roomId) return
        var encoded = JSON.stringify(participants || [])
        for (var i = 0; i < roomModel.count; ++i) {
            var room = roomModel.get(i)
            if (room && room.room_id === roomId) {
                roomModel.setProperty(i, "voice_members_json", encoded)
                return
            }
        }
    }

    Services.BackendTransport {
        id: socket
        accentColor: root.accentColor

        onConnectionStateChanged: function(text, stateColor) {
            root.connectionStateChanged(text, stateColor)
        }

        onConnectedChanged: {
            if (connected)
                root.sendCommand({type: "get_capabilities", request_id: root.nextRequestId("cap")})
            if (!connected) {
                // Session notifications may be missed while IPC is detached.
                root.syncFreshnessEpoch = 0
                root.syncFreshness = ""
                root.mediaProxyBase = ""
                root.typingUserIdsByRoom = ({})
                root.roomsRequestInFlight = false
                root.roomsRefreshQueued = false
                root.failAllPending(L10n.I18n.tr("Связь с бэкендом потеряна"))
            }
        }

        onTextMessageReceived: function(message) {
            try {
                var event = JSON.parse(message)
                if (event.type === "voice_result" || event.type === "voice_widget_message"
                        || event.type === "voice_incoming" || event.type === "voice_incoming_ended"
                        || event.type === "voice_participants_changed") {
                    if (event.type === "voice_participants_changed")
                        root.applyVoiceParticipants(event.room_id, event.participants)
                    root.voiceEvent(event)
                    return
                }
            } catch (_) {}
            Native.FrontendLogic.invoke("matrix.receiveBackend", root, [message])
        }
    }

    Timer {
        id: roomPreviewPrefetchTimer
        interval: 80
        repeat: false
        onTriggered: root.prefetchQueuedRoomPreviews()
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.connected && root.authenticatedUserId !== ""
        onTriggered: {
            root.scheduleRoomPreviewPrefetch()
            root.scheduleRoomMembersPrefetch()
        }
    }
    onConnectedChanged: if (connected) {
        Qt.callLater(root.scheduleRoomPreviewPrefetch)
        Qt.callLater(root.scheduleRoomMembersPrefetch)
    }
    onForegroundTimelineBusyChanged: if (!foregroundTimelineBusy) {
        Qt.callLater(root.scheduleRoomPreviewPrefetch)
        Qt.callLater(root.scheduleRoomMembersPrefetch)
    }
    onCurrentRoomIdChanged: Qt.callLater(root.scheduleRoomMembersPrefetch)
    onRoomsUpdated: Qt.callLater(root.scheduleRoomMembersPrefetch)
    onRoomMembersReceived: function(roomId, members, nextBatch, append, errorText) {
        var failures = Object.assign({}, root.roomMembersPrefetchFailedUntil)
        if (errorText !== "")
            failures[roomId] = Date.now() + 60000
        else
            delete failures[roomId]
        root.roomMembersPrefetchFailedUntil = failures

        if (roomId === root.roomMembersPrefetchInFlightRoomId)
            root.roomMembersPrefetchInFlightRoomId = ""
        Qt.callLater(root.scheduleRoomMembersPrefetch)
    }

    Timer {
        id: roomMembersPrefetchTimer
        interval: 80
        repeat: false
        onTriggered: root.prefetchQueuedRoomMembers()
    }

    Timer {
        id: timelineInitialFillTimer
        interval: 100
        repeat: false
        onTriggered: root.continueInitialTimelineFill()
    }

    Timer {
        id: identityRefreshTimer
        interval: 120000
        repeat: true
        running: root.connected && root.authenticatedUserId !== ""
        triggeredOnStart: false
        onTriggered: root.requestUserDetails(root.authenticatedUserId)
    }

    Timer {
        id: roomMembersRefreshTimer
        interval: 300
        repeat: false
        onTriggered: {
            var roomId = root.roomMembersRefreshTarget
            root.roomMembersRefreshTarget = ""
            if (!roomId || roomId !== root.currentRoomId
                    || !root.roomMembersRefreshQueued[roomId])
                return
            if (root.roomMembersPaginationInFlight[roomId])
                return
            var queued = Object.assign({}, root.roomMembersRefreshQueued)
            delete queued[roomId]
            root.roomMembersRefreshQueued = queued
            root.requestRoomMembers(roomId)
        }
    }

    Timer {
        id: encryptedRefreshTimer
        interval: 1200
        repeat: false
        onTriggered: {
            var roomId = root.encryptedRefreshRoomId
            // Update decrypted rows in place; keep the live timeline.
            if (root.timelineDiffsSupported) {
                root.encryptedRefreshRoomId = ""
                root.encryptedRefreshAttempts = 0
                return
            }
            if (roomId === "" || roomId !== root.currentRoomId) {
                root.encryptedRefreshRoomId = ""
                root.encryptedRefreshAttempts = 0
                return
            }

            root.encryptedRefreshAttempts++
            root.requestMessages(roomId)
            if (root.encryptedRefreshAttempts < 3) {
                interval = root.encryptedRefreshAttempts === 1 ? 2200 : 4500
                restart()
            } else {
                root.encryptedRefreshRoomId = ""
                root.encryptedRefreshAttempts = 0
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            var now = Date.now()
            var pending = root.pendingCommands
            var remaining = Object.assign({}, pending)
            var requestIds = Object.keys(pending)
            var expired = []
            for (var i = 0; i < requestIds.length; i++) {
                var command = pending[requestIds[i]]
                if (Number(command.deadline || 0) <= now) {
                    expired.push(command)
                    delete remaining[requestIds[i]]
                }
            }
            if (expired.length === 0) return
            root.pendingCommands = remaining
            for (var failureIndex = 0; failureIndex < expired.length; failureIndex++)
                root.handleCommandFailure(expired[failureIndex], L10n.I18n.tr("Превышено время ожидания ответа"))
        }
    }

    Timer {
        id: emptyStateTimer
        interval: 900
        onTriggered: {
            if (root.messageModel &&
                root.messageModel.count === 0 &&
                !root.isLoadingMessages &&
                root.currentRoomId !== "") {
                root.showEmptyState = true
            }
        }
    }
}

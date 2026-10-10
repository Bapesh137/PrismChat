import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import "../common"
import "../../utils/PrismUtils.js" as Utils

Item {
    id: root

    signal videoOpenRequested(var details)
    signal voicePlaybackRequested(var details)
    signal voiceSeekRequested(real position)

    property var messageModel
    property string roomName: L10n.I18n.tr("Выберите чат")
    property string currentUserId: ""
    property string currentUserAvatar: ""
    property var authorNameResolver: null
    property var authorAvatarResolver: null
    property int authorNameRevision: 0
    property bool canRedactOther: false
    property bool threadsEnabled: true
    property string currentRoomId: ""
    property string firstUnreadEventId: ""
    property string readingAccountId: ""
    property var localReadEventIds: []
    property string displayedRoomId: currentRoomId
    property var restorePosition: null
    property int openingUnreadCount: 0
    property bool readingActive: true
    property bool cachedTimeline: false
    property bool pendingJumpDown: false
    onCachedTimelineChanged: {
        if (cachedTimeline) followTail = false
        else Qt.callLater(finishCacheRefresh)
    }
    property string trackedRoomId: ""
    property string trackedAccountId: ""
    property var lastViewportState: null
    property string readThroughEventId: ""
    property string lastReportedReadEventId: ""
    property int remainingUnreadCount: 0
    readonly property int localReadBoundaryIndex: {
        // The newest-first model marks index N and older rows as viewed.
        var boundary = -1
        var revision = messageModel ? messageModel.count : 0
        var ids = localReadEventIds || []
        for (var index = 0; index < ids.length; ++index) {
            var candidate = indexOfEventId(String(ids[index] || ""))
            if (candidate >= 0 && (boundary < 0 || candidate < boundary))
                boundary = candidate
        }
        return boundary
    }
    property bool unreadJumpPerformed: false
    property bool followTail: false
    property bool layoutPending: false
    property bool stabilizingLayout: false
    readonly property bool positionReady: !initialPositionPending
        && initialTimelineReady && displayedRoomId === currentRoomId
    property string initialCacheDisplayRoomId: ""
    readonly property bool initialCacheVisible: initialPositionPending
        && initialCacheDisplayRoomId === currentRoomId && currentRoomId !== ""
        && displayedRoomId === currentRoomId && !!messageModel && messageModel.count > 0
    property string pendingAnchorEventId: ""
    property real pendingAnchorOffset: 0
    property int anchorStableFrames: 0
    property int anchorAttempts: 0
    signal viewportSaved(string accountId, string roomId, var position)
    signal viewportRead(string roomId, string eventId, int remainingUnread)
    onReadingActiveChanged: { if (readingActive) viewportTimer.restart() }
    property bool unreadBoundaryPending: false
    property bool initialTimelineReady: false
    property bool isLoadingMessages: false
    property bool showEmptyState: false
    property string mediaProxy: ""
    property bool roundAvatars: true
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"
    property bool autoLoadImages: true
    property bool autoLoadVideos: true
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color elevatedColor: "#102016"
    property color dividerColor: "#29402E"
    property Item chatViewRoot: null
    property string activeVoiceEventId: ""
    property bool activeVoicePlaying: false
    property real activeVoicePosition: 0
    property real activeVoiceDuration: 0

    function toggleVoice(details) { voicePlaybackRequested(details) }
    function seekVoice(position) { voiceSeekRequested(position) }

    property var selectedMessages: ({})
    readonly property int selectedCount: Object.keys(selectedMessages).length
    property bool multiSelectMode: false
    property int dragStartIndex: -1
    property int dragLastIndex: -1
    property bool isDragging: false
    property real lastDragY: 0
    property string selectionGestureMode: ""
    property int selectionGestureButton: Qt.NoButton
    property var selectionGestureBase: ({})
    property bool selectionGestureActivated: false
    property bool olderRequestArmed: true
    property bool timelinePaginationInFlight: false
    property string highlightedEventId: ""
    property bool initialPositionPending: false
    property int initialPositionAttempts: 0
    property var pinnedEventIds: []
    readonly property int messageHeaderIntervalMs: 10 * 60 * 1000

    function atBottom() {
        return !messageList.canScrollVertically || messageList.contentY >= messageList.originY
            + Math.max(0, messageList.contentHeight - messageList.height) - 3
    }

    function unreadMessage(message) {
        return message && !message.is_system && !message.is_redacted
            && !message.sender_is_ignored && message.sender !== currentUserId
            && String(message.event_id || "").indexOf("local:") !== 0
    }

    function edgeIndex(bottom) {
        var y = bottom ? messageList.height - 1 : 1
        for (var attempt = 0; attempt < Math.ceil(messageList.height / 8); attempt++) {
            var index = messageList.indexAt(messageList.width / 2, messageList.contentY + y)
            if (index >= 0) return index
            y += bottom ? -8 : 8
        }
        return -1
    }

    function saveLastViewport() {
        if (lastViewportState && trackedRoomId && trackedAccountId)
            viewportSaved(trackedAccountId, trackedRoomId, lastViewportState)
    }

    function captureViewport(updateRead) {
        if (layoutPending || stabilizingLayout || initialPositionPending || pendingAnchorEventId !== "" || !initialTimelineReady || !visible || !messageModel
                || currentRoomId !== trackedRoomId || displayedRoomId !== currentRoomId
                || readingAccountId !== trackedAccountId
                || scrollToBottomAnimation.running) return
        var topIndex = edgeIndex(false)
        if (topIndex < 0) return
        var topItem = messageList.itemAtIndex(topIndex)
        if (!topItem) return
        if (updateRead === false) {
            // Keep the exit position without persisting every scroll tick.
            lastViewportState = {
                event_id: String(messageModel.get(topIndex).event_id || ""),
                offset: topItem.y - messageList.contentY,
                at_bottom: atBottom(), read_event_id: readThroughEventId,
                unread_count: remainingUnreadCount, updated_at: Date.now()
            }
            return
        }
        var newestIndex = edgeIndex(true)
        if (newestIndex < 0) return
        var newestItem = messageList.itemAtIndex(newestIndex)
        if (!atBottom() && newestItem && newestItem.y + Math.min(newestItem.height, 60)
                > messageList.contentY + messageList.height) newestIndex++
        newestIndex = Math.min(newestIndex, messageModel.count - 1)
        var boundaryIndex = indexOfEventId(firstUnreadEventId)
        var previousReadIndex = indexOfEventId(readThroughEventId)
        // Reading progresses only toward newer messages.
        var mayAdvance = updateRead !== false && readingActive && !cachedTimeline && !unreadBoundaryPending
            && (atBottom() || (boundaryIndex >= 0 && newestIndex <= boundaryIndex))
        if (mayAdvance && (previousReadIndex < 0 || newestIndex < previousReadIndex))
            readThroughEventId = String(messageModel.get(newestIndex).event_id || "")
        var readIndex = indexOfEventId(readThroughEventId)
        var unreadLimit = boundaryIndex >= 0 ? boundaryIndex + 1 : 0
        if (readIndex >= 0) unreadLimit = Math.min(unreadLimit, readIndex)
        var remaining = 0
        for (var i = 0; i < unreadLimit; i++)
            if (unreadMessage(messageModel.get(i))) remaining++
        // Preserve the server count until the unread boundary is loaded.
        if (cachedTimeline || unreadBoundaryPending) remaining = openingUnreadCount
        else if (boundaryIndex < 0 && openingUnreadCount > 0 && !atBottom())
            remaining = remainingUnreadCount
        remainingUnreadCount = remaining
        if (readThroughEventId && updateRead !== false && readingActive && !cachedTimeline && !unreadBoundaryPending) {
            lastReportedReadEventId = readThroughEventId
            viewportRead(currentRoomId, readThroughEventId, remainingUnreadCount)
        }
        lastViewportState = {
            event_id: String(messageModel.get(topIndex).event_id || ""),
            offset: topItem.y - messageList.contentY,
            at_bottom: atBottom(), read_event_id: readThroughEventId,
            unread_count: remainingUnreadCount, updated_at: Date.now()
        }
        saveLastViewport()
    }

    function placeEvent(eventId, offset) {
        var index = indexOfEventId(eventId)
        if (index < 0) return false
        cancelAnchorPlacement()
        followTail = false
        pendingAnchorEventId = eventId
        pendingAnchorOffset = Number(offset || 0)
        settleMessageLayout()
        if (!messageList.itemAtIndex(index))
            messageList.positionViewAtIndex(index, ListView.Center)
        settleMessageLayout()
        var item = messageList.itemAtIndex(index)
        if (!item) { cancelAnchorPlacement(); return false }
        messageList.contentY = messageList.boundedY(item.y - pendingAnchorOffset)
        anchorTimer.start()
        return true
    }

    function settleMessageLayout() {
        // Settle nested positioners before ListView measures variable-height rows.
        messageList.forceLayout()
        var rows = messageList.contentItem.children
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            if (row && !row.pooled && typeof row.settleContentLayout === "function")
                row.settleContentLayout()
        }
        messageList.forceLayout()
    }

    function captureUserViewport() {
        // Settle rows created synchronously by scrolling.
        stabilizingLayout = true
        settleMessageLayout()
        stabilizingLayout = false
        layoutPending = false
        captureViewport(false)
    }

    function scheduleLayoutStabilization() {
        if (stabilizingLayout) return
        layoutPending = true
        Qt.callLater(stabilizeViewport)
    }

    function stabilizeViewport() {
        if (stabilizingLayout) return
        if (initialPositionPending || displayedRoomId !== currentRoomId) {
            if (initialPositionPending) Qt.callLater(positionInitialView)
            return
        }
        if (pendingAnchorEventId !== "") return // The explicit jump owns the anchor.
        if (scrollToBottomAnimation.running) {
            // Re-settle after height estimates change during an animated jump.
            return
        }
        stabilizingLayout = true
        settleMessageLayout()
        if (messageList.moving || chatScrollBar.pressed || isDragging) {
            // Do not correct the viewport during direct manipulation.
        } else if (followTail || !messageList.canScrollVertically) {
            if (!messageList.canScrollVertically) followTail = !cachedTimeline
            messageList.contentY = messageList.bottomY
        } else if (lastViewportState) {
            var index = indexOfEventId(lastViewportState.event_id)
            if (index >= 0) {
                if (!messageList.itemAtIndex(index)) {
                    messageList.positionViewAtIndex(index, ListView.Center)
                    settleMessageLayout()
                }
                var item = messageList.itemAtIndex(index)
                if (item) messageList.contentY = messageList.boundedY(item.y - lastViewportState.offset)
            }
        }
        stabilizingLayout = false
        layoutPending = false
        captureViewport(false)
        viewportTimer.restart()
    }

    function cancelAnchorPlacement() {
        anchorTimer.stop()
        pendingAnchorEventId = ""
        anchorStableFrames = 0
        anchorAttempts = 0
    }

    // Keep the saved row fixed while estimated delegate heights settle.
    Timer {
        id: anchorTimer
        interval: 16
        repeat: true
        onTriggered: {
            root.settleMessageLayout()
            var index = root.indexOfEventId(root.pendingAnchorEventId)
            var item = index >= 0 ? messageList.itemAtIndex(index) : null
            if (!item) {
                root.cancelAnchorPlacement()
                if (root.initialPositionPending) initialPositionTimer.restart()
                return
            }
            var targetY = messageList.boundedY(item.y - root.pendingAnchorOffset)
            root.anchorStableFrames = Math.abs(messageList.contentY - targetY) < 0.5
                ? root.anchorStableFrames + 1 : 0
            messageList.contentY = targetY
            root.anchorAttempts++
            if (root.anchorStableFrames >= 3 || root.anchorAttempts >= 20) {
                root.cancelAnchorPlacement()
                root.initialPositionPending = false
                root.layoutPending = false
                root.followTail = root.atBottom() && !root.cachedTimeline
                root.captureViewport()
                viewportTimer.restart()
            }
        }
    }

    function finishCacheRefresh() {
        if (cachedTimeline || !positionReady) return
        stabilizeViewport()
        followTail = atBottom()
        viewportTimer.restart()
        resumePendingJump()
    }

    function resumePendingJump() {
        if (pendingJumpDown && positionReady
                && (!unreadBoundaryPending || unreadJumpPerformed)) {
            pendingJumpDown = false
            jumpDown()
        }
    }

    onPositionReadyChanged: {
        if (positionReady && pendingJumpDown) Qt.callLater(resumePendingJump)
    }

    function jumpDown() {
        // Navigation waits for placement and the unread boundary, not cache age.
        if (!positionReady || (unreadBoundaryPending && !unreadJumpPerformed)) {
            pendingJumpDown = true
            return
        }
        var boundaryIndex = indexOfEventId(firstUnreadEventId)
        var newestVisible = edgeIndex(true)
        if (!unreadJumpPerformed && remainingUnreadCount > 0
                && boundaryIndex >= 0 && newestVisible > boundaryIndex) {
            unreadJumpPerformed = true
            followTail = false
            placeEvent(firstUnreadEventId, 0)
            viewportTimer.restart()
            return
        }
        unreadJumpPerformed = true
        followTail = true
        scrollToBottom()
    }

    Timer {
        id: viewportTimer
        interval: 120
        onTriggered: root.captureViewport()
    }
    Connections {
        target: root.messageModel
        ignoreUnknownSignals: true
        function onRowsAboutToBeInserted() { root.scheduleLayoutStabilization() }
        function onRowsAboutToBeRemoved() { root.scheduleLayoutStabilization() }
        function onRowsAboutToBeMoved() { root.scheduleLayoutStabilization() }
        function onModelAboutToBeReset() { root.scheduleLayoutStabilization() }
        function onCountChanged() { root.scheduleLayoutStabilization() }
        function onDataChanged() { root.scheduleLayoutStabilization() }
    }
    function bindRoomModel() {
        if (messageList.model === root.messageModel) return
        // Pooled delegates must not retain another room's model roles.
        messageList.reuseItems = false
        messageList.model = null
        messageList.model = root.messageModel
        messageList.reuseItems = true
    }
    onMessageModelChanged: bindRoomModel()
    Component.onCompleted: bindRoomModel()
    Component.onDestruction: saveLastViewport()

    function displayNameFor(sender, fallback) {
        var revision = root.authorNameRevision
        if (authorNameResolver)
            return authorNameResolver(sender || "", fallback || "")
        return fallback || Utils.displayName(sender || "")
    }

    function avatarFor(sender, fallback) {
        if (authorAvatarResolver)
            return authorAvatarResolver(sender || "", fallback || "")
        return fallback || ""
    }

    signal contextMenuRequested(int messageIndex, var messageData, bool multiSelection)
    signal copyRequested(string text)
    signal redactRequested(string eventId)
    signal imageOpenRequested(string source, string caption)
    signal eventJumpRequested(string eventId)
    signal quickReplyRequested(string eventId, string sender, string body)
    signal threadRequested(var messageData)
    signal retrySendRequested(string timelineItemId)
    signal reactionToggleRequested(string eventId, var reaction)
    signal downloadRequested(string mediaUrl, string filename, var mediaFile, string mediaMimeType)
    signal stickerPackInstallRequested(var pack)

    signal userProfileRequested(string userId, string roomId, real clickX, real clickY)
    signal olderMessagesRequested()

    function resetReadingContext() {
        saveLastViewport()
        cancelAnchorPlacement()
        trackedRoomId = currentRoomId
        trackedAccountId = readingAccountId
        lastViewportState = null
        initialCacheDisplayRoomId = ""
        readThroughEventId = ""
        lastReportedReadEventId = ""
        remainingUnreadCount = 0
        unreadJumpPerformed = false
        pendingJumpDown = false
        followTail = false
        scrollToBottomAnimation.stop()
        viewportTimer.stop()
        initialPositionPending = currentRoomId !== ""
        initialPositionAttempts = 0
        layoutPending = initialPositionPending
        if (initialPositionPending)
            Qt.callLater(positionInitialView)
        clearSelection()
        highlightedEventId = ""
        highlightTimer.stop()
        olderRequestArmed = true
        paginationArmTimer.stop()
        autoScrollTimer.speed = 0
    }

    onCurrentRoomIdChanged: resetReadingContext()
    // Read-receipt state is scoped by profile as well as room ID.
    onReadingAccountIdChanged: resetReadingContext()

    onFirstUnreadEventIdChanged: {
        viewportTimer.restart()
        if (initialPositionPending) {
            initialPositionAttempts = 0
            initialPositionTimer.restart()
        }
    }

    onUnreadBoundaryPendingChanged: {
        viewportTimer.restart()
        if (initialPositionPending && !unreadBoundaryPending)
            initialPositionTimer.restart()
        if (!unreadBoundaryPending && pendingJumpDown)
            Qt.callLater(resumePendingJump)
    }

    onInitialTimelineReadyChanged: {
        if (initialPositionPending && initialTimelineReady)
            Qt.callLater(positionInitialView)
    }
    onDisplayedRoomIdChanged: {
        if (initialPositionPending) Qt.callLater(positionInitialView)
    }

    function retryInitialPosition() {
        if (!initialTimelineReady || unreadBoundaryPending) {
            initialPositionTimer.restart()
            return
        }
        initialPositionAttempts++
        if (initialPositionAttempts < 80) {
            initialPositionTimer.restart()
            return
        }
        scrollToBottomAnimation.stop()
        messageList.contentY = messageList.bottomY
        initialPositionPending = false
        layoutPending = false
        followTail = true
        captureViewport(false)
    }

    function positionInitialView() {
        if (!initialPositionPending || pendingAnchorEventId !== "" || currentRoomId === "")
            return
        if (!initialTimelineReady || displayedRoomId !== currentRoomId || !messageModel) {
            if (!initialTimelineReady && cachedTimeline && displayedRoomId === currentRoomId
                    && messageModel && messageModel.count > 0
                    && initialCacheDisplayRoomId !== currentRoomId) {
                // Locating an older anchor must not update reads or saved position.
                settleMessageLayout()
                messageList.contentY = messageList.bottomY
                initialCacheDisplayRoomId = currentRoomId
            }
            retryInitialPosition()
            return
        }
        settleMessageLayout()
        if (messageModel.count === 0) {
            if (!isLoadingMessages && showEmptyState) {
                messageList.settleShortContent()
                initialPositionPending = false
                layoutPending = false
                followTail = true
            } else {
                retryInitialPosition()
            }
            return
        }
        if (messageList.contentHeight <= 0 || messageList.height <= 0) {
            retryInitialPosition()
            return
        }

        var unreadIndex = indexOfEventId(firstUnreadEventId)
        scrollToBottomAnimation.stop()
        remainingUnreadCount = openingUnreadCount
        readThroughEventId = restorePosition ? String(restorePosition.read_event_id || "") : ""
        lastReportedReadEventId = readThroughEventId
        var savedEvent = restorePosition ? String(restorePosition.event_id || "") : ""
        if (savedEvent && placeEvent(savedEvent, restorePosition.offset)) {
            return
        }
        if (!messageList.canScrollVertically) {
            messageList.settleShortContent()
        } else if (unreadIndex >= 0) {
            if (placeEvent(firstUnreadEventId, 0)) return
        } else {
            messageList.contentY = messageList.bottomY
        }
        initialPositionPending = false
        layoutPending = false
        followTail = atBottom() && !cachedTimeline && !unreadBoundaryPending
        captureViewport(false)
        viewportTimer.restart()
    }

    function scrollToBottom(animated) {
        cancelAnchorPlacement()
        followTail = true
        scrollToBottomAnimation.stop()
        settleMessageLayout()
        if (!messageList.canScrollVertically) {
            messageList.settleShortContent()
            captureViewport(false)
            viewportTimer.restart()
            return
        }
        if (animated === false) {
            messageList.contentY = messageList.bottomY
            captureViewport(false)
            viewportTimer.restart()
            return
        }
        scrollToBottomAnimation.from = messageList.contentY
        scrollToBottomAnimation.to = messageList.originY
            + Math.max(0, messageList.contentHeight - messageList.height)
        scrollToBottomAnimation.start()
    }

    function requestOlderIfNeeded() {
        if (!positionReady || pendingAnchorEventId !== "" || !olderRequestArmed
                || timelinePaginationInFlight || !messageList.canScrollVertically) return
        if (messageList.visibleArea.yPosition < 0.08) {
            olderRequestArmed = false
            paginationArmTimer.restart()
            olderMessagesRequested()
        }
    }


    function openImage(mediaUrl, caption, mediaFile, mediaMimeType) {
        var source = Utils.proxyUrl(mediaUrl, root.mediaProxy, mediaFile, mediaMimeType)
        if (source === "") return
        imageOpenRequested(source, caption || "")
    }

    function downloadFile(mediaUrl, filename, mediaFile, mediaMimeType) {
        if (mediaUrl !== "")
            root.downloadRequested(mediaUrl, filename || "attachment",
                                   mediaFile || null, mediaMimeType || "")
    }

    function openUserProfile(userId, roomId, clickX, clickY) {
        userProfileRequested(userId, roomId, clickX, clickY)
    }

    function isSelected(eventId) { return selectedMessages.hasOwnProperty(eventId) }

    function applySelection(nextSelection) {
        selectedMessages = nextSelection
        multiSelectMode = Object.keys(nextSelection).length > 0
    }

    function indexOfEventId(eventId) {
        if (!messageModel || eventId === "") return -1
        for (var i = 0; i < messageModel.count; i++) {
            if (messageModel.get(i).event_id === eventId) return i
        }
        return -1
    }

    function scrollToEvent(eventId) {
        var messageIndex = indexOfEventId(eventId)
        if (messageIndex < 0) return false
        cancelAnchorPlacement()
        followTail = false
        initialPositionPending = false
        settleMessageLayout()
        highlightedEventId = eventId
        if (messageList.canScrollVertically)
            messageList.positionViewAtIndex(messageIndex, ListView.Center)
        else
            messageList.settleShortContent()
        settleMessageLayout()
        layoutPending = false
        captureViewport(false)
        viewportTimer.restart()
        highlightTimer.restart()
        return true
    }

    function jumpToReply(eventId) {
        if (eventId === "") return
        if (!scrollToEvent(eventId))
            eventJumpRequested(eventId)
    }

    function shouldShowHeader(messageIndex) {
        if (messageModel && messageIndex >= 0 && messageIndex < messageModel.count
                && messageModel.get(messageIndex).is_system)
            return false
        return Utils.shouldShowMessageHeader(messageModel, messageIndex, messageHeaderIntervalMs)
    }

    function formatTimestamp(timestamp) {
        return Utils.formatMessageTimestamp(timestamp, messageDateFormat, messageTimeFormat, L10n.I18n.tr("вчера"))
    }

    function formatCompactTimestamp(timestamp) {
        return Utils.formatMessageTime(timestamp, messageTimeFormat)
    }

    function formatFullTimestamp(timestamp) {
        var value = Number(timestamp || 0)
        if (!isFinite(value) || value <= 0) return ""
        return Qt.formatDateTime(new Date(value),
                                 messageDateFormat + " "
                                 + messageTimeFormat + ":ss t")
    }

    function copyCode(text) {
        copyRequested(String(text || ""))
    }

    function dateHeaderForMessage(messageIndex) {
        if (!messageModel || messageIndex < 0 || messageIndex >= messageModel.count)
            return ""

        var currentTimestamp = Number(messageModel.get(messageIndex).timestamp)
        if (!isFinite(currentTimestamp) || currentTimestamp <= 0)
            return ""

        if (messageIndex < messageModel.count - 1) {
            var olderTimestamp = Number(messageModel.get(messageIndex + 1).timestamp)
            var currentDate = new Date(currentTimestamp)
            var olderDate = new Date(olderTimestamp)
            if (currentDate.getFullYear() === olderDate.getFullYear()
                && currentDate.getMonth() === olderDate.getMonth()
                && currentDate.getDate() === olderDate.getDate())
                return ""
        }

        return Utils.formatMessageDate(currentTimestamp, messageDateFormat)
    }

    function selectionModeFor(button, startSelected) {
        // The row pressed first fixes add/remove mode until release.
        if (button !== Qt.LeftButton)
            return ""
        return startSelected ? "remove" : "add"
    }

    function applySelectionGestureRange(targetIndex) {
        if (!messageModel || selectionGestureMode === "" || dragStartIndex < 0
                || targetIndex < 0 || targetIndex >= messageModel.count)
            return

        // Rebuild from the initial selection so shrinking a drag is reversible.
        var nextSelection = Object.assign({}, selectionGestureBase)
        var first = Math.min(dragStartIndex, targetIndex)
        var last = Math.max(dragStartIndex, targetIndex)

        for (var i = first; i <= last; i++) {
            var message = messageModel.get(i)
            var eventId = message.event_id || ""
            if (eventId === "")
                continue

            if (selectionGestureMode === "add") {
                // Already-selected messages keep their state.
                if (!nextSelection.hasOwnProperty(eventId))
                    nextSelection[eventId] = i
            } else if (selectionGestureMode === "remove") {
                // Unselected messages are ignored.
                if (nextSelection.hasOwnProperty(eventId))
                    delete nextSelection[eventId]
            }
        }

        applySelection(nextSelection)
    }

    function startSelectionGesture(messageIndex, selected, button) {
        var mode = selectionModeFor(button, selected)
        if (mode === "" || !messageModel || messageIndex < 0 || messageIndex >= messageModel.count)
            return false

        dragStartIndex = messageIndex
        dragLastIndex = messageIndex
        isDragging = true
        selectionGestureMode = mode
        selectionGestureButton = button
        selectionGestureBase = Object.assign({}, selectedMessages)
        selectionGestureActivated = false

        // Existing selections apply on press; new ones start after a drag.
        if (selectedCount > 0) {
            selectionGestureActivated = true
            applySelectionGestureRange(messageIndex)
        }
        return true
    }

    function continueSelectionGesture(targetIndex) {
        if (!isDragging || dragStartIndex < 0 || targetIndex < 0
                || !messageModel || targetIndex >= messageModel.count)
            return

        if (targetIndex === dragLastIndex) return

        if (!selectionGestureActivated)
            selectionGestureActivated = true

        applySelectionGestureRange(targetIndex)
        dragLastIndex = targetIndex
    }

    function finishSelectionGesture() {
        isDragging = false
        autoScrollTimer.speed = 0
        dragStartIndex = -1
        dragLastIndex = -1
        selectionGestureMode = ""
        selectionGestureButton = Qt.NoButton
        selectionGestureBase = ({})
        selectionGestureActivated = false
    }

    function clearSelection() {
        selectedMessages = {}
        multiSelectMode = false
        finishSelectionGesture()
    }

    function canDeleteSelection() {
        var keys = Object.keys(selectedMessages)
        for (var i = 0; i < keys.length; i++) {
            var eventId = keys[i]
            var index = indexOfEventId(eventId)
            if (index < 0) return false
            var message = messageModel.get(index)
            if (message.is_system || message.is_redacted || eventId.indexOf("local:") === 0)
                return false
            if (message.sender !== currentUserId && !canRedactOther)
                return false
        }
        return keys.length > 0
    }

    function selectedText() {
        var keys = Object.keys(selectedMessages)
        var indices = []
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            var resolvedIndex = indexOfEventId(keys[keyIndex])
            if (resolvedIndex >= 0) indices.push(resolvedIndex)
        }
        indices.sort(function(a, b) { return b - a })
        var parts = []
        for (var i = 0; i < indices.length; i++) {
            var index = indices[i]
            if (messageModel && index >= 0 && index < messageModel.count) {
                var message = messageModel.get(index)
                if (!message.is_redacted && !message.sender_is_ignored && message.body)
                    parts.push(message.body)
            }
        }
        return parts.join("\n\n")
    }

    function copySelectedMessages() {
        var text = selectedText()
        if (text.length > 0) copyRequested(text)
        clearSelection()
    }

    function deleteSelectedMessages() {
        if (!canDeleteSelection()) return
        var keys = Object.keys(selectedMessages)
        for (var i = 0; i < keys.length; i++)
            redactRequested(keys[i])
        clearSelection()
    }

    function markRedacted(messageIndex) {
        if (messageModel && messageIndex >= 0 && messageIndex < messageModel.count) {
            messageModel.setProperty(messageIndex, "is_redacted", true)
            messageModel.setProperty(messageIndex, "is_encrypted", false)
            messageModel.setProperty(messageIndex, "body", "")
        }
    }

    function selectAll() {
        var nextSelection = {}
        if (messageModel) {
            for (var i = 0; i < messageModel.count; i++) {
                var message = messageModel.get(i)
                if (!message.sender_is_ignored)
                    nextSelection[message.event_id] = i
            }
        }
        applySelection(nextSelection)
    }

    function beginDrag(messageIndex, selected, sourceItem, x, y, button) {
        root.forceActiveFocus()
        if (!startSelectionGesture(messageIndex, selected, button)) return false
        lastDragY = sourceItem.mapToItem(root, x, y).y
        return true
    }

    function updateDrag(messageIndex, sourceItem, x, y) {
        if (!isDragging || dragStartIndex < 0) return

        var rootPosition = sourceItem.mapToItem(root, x, y)
        lastDragY = rootPosition.y
        if (rootPosition.y < 40) autoScrollTimer.speed = (rootPosition.y - 40) * 0.2
        else if (rootPosition.y > root.height - 40) autoScrollTimer.speed = (rootPosition.y - root.height + 40) * 0.2
        else autoScrollTimer.speed = 0

        var contentPosition = sourceItem.mapToItem(messageList.contentItem, x, y)
        var targetIndex = messageList.indexAt(contentPosition.x, contentPosition.y)
        if (targetIndex >= 0) continueSelectionGesture(targetIndex)
    }

    function endDrag() {
        finishSelectionGesture()
    }

    function openContext(messageIndex, messageData, selected) {
        // Opening a context menu does not mutate selection.
        contextMenuRequested(messageIndex, messageData, multiSelectMode && selected)
    }

    Keys.onPressed: function(event) {
        if (selectedCount <= 0) return
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_A) {
            selectAll()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            clearSelection()
            event.accepted = true
        } else if (event.key === Qt.Key_Delete) {
            if (canDeleteSelection()) deleteSelectedMessages()
            event.accepted = true
        }
    }

    Timer {
        id: highlightTimer
        interval: 1800
        onTriggered: root.highlightedEventId = ""
    }

    Timer {
        id: initialPositionTimer
        interval: 60
        onTriggered: root.positionInitialView()
    }

    Item {
        id: listContainer
        anchors.fill: parent

        ListView {
            id: messageList
            reuseItems: true
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Reserve the scrollbar gutter to keep wrapping stable.
            anchors.rightMargin: chatScrollBar.width
            opacity: root.positionReady || root.initialCacheVisible ? 1 : 0
            enabled: root.positionReady

            model: null
            clip: true
            verticalLayoutDirection: ListView.BottomToTop
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.AutoFlickIfNeeded
            readonly property bool canScrollVertically: contentHeight > height + 2
            // Multi-select reserves LMB; the wheel remains available for scrolling.
            interactive: root.positionReady && !root.multiSelectMode && !root.isDragging && canScrollVertically
            readonly property real bottomY: originY + contentHeight - height
            function boundedY(y) {
                return Math.max(Math.min(originY, bottomY), Math.min(bottomY, y))
            }

            function settleShortContent() {
                if (canScrollVertically)
                    return
                scrollToBottomAnimation.stop()
                if (Math.abs(contentY - bottomY) > 0.01)
                    contentY = bottomY
            }

            WheelHandler {
                id: fastWheelHandler
                target: null
                acceptedDevices: PointerDevice.Mouse

                onWheel: function(event) {
                    if (!root.positionReady) { event.accepted = true; return }
                    root.stabilizeViewport()
                    root.settleMessageLayout()
                    if (!messageList.canScrollVertically) {
                        messageList.settleShortContent()
                        event.accepted = true
                        return
                    }
                    var delta = event.pixelDelta.y !== 0
                        ? event.pixelDelta.y * 1.8
                        : event.angleDelta.y / 120 * 110
                    var minimumY = messageList.originY
                    var maximumY = minimumY
                        + Math.max(0, messageList.contentHeight - messageList.height)
                    root.cancelAnchorPlacement()
                    scrollToBottomAnimation.stop()
                    root.layoutPending = false
                    root.followTail = false
                    messageList.contentY = Math.max(minimumY,
                        Math.min(maximumY, messageList.contentY - delta))
                    root.followTail = root.atBottom()
                    root.captureUserViewport()
                    root.requestOlderIfNeeded()
                    viewportTimer.restart()
                    chatScrollBar.showTemporarily()
                    event.accepted = true
                }
            }
            onContentYChanged: {
                // Persist only user-driven scroll changes.
                if (moving || chatScrollBar.pressed || root.isDragging) {
                    root.captureViewport(false)
                    root.requestOlderIfNeeded()
                    viewportTimer.restart()
                }
            }
            onMovementStarted: {
                root.cancelAnchorPlacement()
                root.layoutPending = false
                scrollToBottomAnimation.stop()
                root.followTail = false
                if (canScrollVertically) chatScrollBar.showTemporarily()
            }
            onMovementEnded: {
                root.followTail = root.atBottom()
                root.captureUserViewport()
                viewportTimer.restart()
                chatScrollBar.scheduleHide()
            }
            onContentHeightChanged: root.scheduleLayoutStabilization()
            onHeightChanged: root.scheduleLayoutStabilization()
            onWidthChanged: root.scheduleLayoutStabilization()
            onOriginYChanged: root.scheduleLayoutStabilization()

            delegate: MessageDelegate {
                controller: root
                width: messageList.width
                onHeightChanged: root.scheduleLayoutStabilization()

                chatViewRoot: root.chatViewRoot

                messageIndex: index
                eventId: model.event_id || ""
                unreadDivider: root.firstUnreadEventId !== ""
                    && model.event_id === root.firstUnreadEventId
                searchHighlighted: root.highlightedEventId === model.event_id
                sender: model.sender || ""
                senderDisplayName: root.displayNameFor(model.sender || "", model.sender_display_name || "")
                reactions: model.reactions || []
                readReceipts: model.read_receipts || []
                readByOtherLocalProfile: root.localReadBoundaryIndex >= 0
                    && index >= root.localReadBoundaryIndex
                currentUserId: root.currentUserId
                senderAvatarUrl: root.avatarFor(model.sender || "", model.sender_avatar_url || "")
                senderIgnored: !!model.sender_is_ignored
                body: model.body || ""
                messageType: model.msg_type || "m.text"
                timestamp: Number(model.timestamp || 0)
                dateHeader: root.dateHeaderForMessage(index)
                mediaUrl: model.media_url || ""
                mediaFile: model.media_file || null
                mediaMimeType: model.media_mime_type || ""
                stickerPack: model.sticker_pack || null
                edited: !!model.is_edited
                redacted: !!model.is_redacted
                encrypted: !!model.is_encrypted
                replyTo: model.reply_to || ""
                replySender: model.reply_sender || ""
                replySenderDisplayName: root.displayNameFor(model.reply_sender || "", "")
                replyBody: model.reply_body || ""
                systemMessage: !!model.is_system
                systemKind: model.system_kind || ""
                sendState: model.send_state || "sent"
                timelineItemId: model.timeline_item_id || ""
                sendError: model.send_error || ""
                sendRecoverable: !!model.send_recoverable
                threadRootId: model.thread_root_id || ""
                threadReplyCount: root.threadsEnabled
                    ? Number(model.thread_reply_count || 0) : 0
                pinned: root.pinnedEventIds.indexOf(model.event_id) !== -1
                activeVoiceEventId: root.activeVoiceEventId
                activeVoicePlaying: root.activeVoicePlaying
                activeVoicePosition: root.activeVoicePosition
                activeVoiceDuration: root.activeVoiceDuration

                currentRoomId: root.currentRoomId
                mediaProxy: root.mediaProxy
                roundAvatars: root.roundAvatars
                autoLoadImages: root.autoLoadImages
                autoLoadVideos: root.autoLoadVideos
                accentColor: root.accentColor
                iconColor: root.iconColor
                accentTextColor: root.accentTextColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                elevatedColor: root.elevatedColor
                dividerColor: root.dividerColor

                onReactionRequested: function(reaction) {
                    root.reactionToggleRequested(model.event_id || "", reaction)
                }
                onStickerPackInstallRequested: function(pack) {
                    root.stickerPackInstallRequested(pack)
                }
                onVideoOpenRequested: function(details) {
                    root.videoOpenRequested(details)
                }
                onQuickReplyRequested: function(eventId, sender, body) {
                    root.quickReplyRequested(eventId, sender, body)
                }
                onThreadRequested: root.threadRequested(model)
                onRetryRequested: function(timelineItemId) {
                    root.retrySendRequested(timelineItemId)
                }
            }
        }

        PrismScrollBar {
            id: chatScrollBar
            autoHide: true
            autoHideDelay: 2500
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 9
            z: 1000
            orientation: Qt.Vertical
            policy: ScrollBar.AlwaysOn
            interactive: true
            active: visible
            visible: root.positionReady && messageList.contentHeight > messageList.height + 2
            size: messageList.contentHeight > 0 ? Math.min(1, messageList.visibleArea.heightRatio) : 1
            minimumSize: 0.08
            handleColor: root.textSecondary
            handleHoverColor: root.accentColor
            trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.16)

            Binding {
                target: chatScrollBar
                property: "position"
                value: Math.max(0, Math.min(1 - chatScrollBar.size, messageList.visibleArea.yPosition))
                when: !chatScrollBar.pressed
            }

            onPositionChanged: {
                if (!pressed || !root.positionReady) return
                root.cancelAnchorPlacement()
                scrollToBottomAnimation.stop()
                root.layoutPending = false
                var safePosition = Math.max(0, Math.min(1 - size, position))
                root.followTail = false
                messageList.contentY = messageList.originY + safePosition * messageList.contentHeight
                root.followTail = root.atBottom()
                messageList.returnToBounds()
                root.captureUserViewport()
                root.requestOlderIfNeeded()
                viewportTimer.restart()
            }
        }
        Rectangle {
            id: scrollToBottomButton
            property bool shouldShow: root.positionReady && root.currentRoomId !== ""
                && messageList.contentHeight > messageList.height + 2
                && messageList.contentY < messageList.originY
                    + Math.max(0, messageList.contentHeight - messageList.height) - 32

            anchors.right: parent.right
            anchors.rightMargin: chatScrollBar.visible ? 20 : 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            width: 42
            height: 42
            radius: width / 2
            z: 1100
            opacity: shouldShow ? 1 : 0
            scale: shouldShow ? (jumpToBottomMouse.pressed ? 0.88 : 1) : 0.86
            visible: shouldShow || opacity > 0.01
            color: jumpToBottomMouse.containsMouse ? root.accentColor : root.elevatedColor
            border.width: 1
            border.color: jumpToBottomMouse.containsMouse ? root.accentColor : root.dividerColor

            Behavior on opacity {
                NumberAnimation { duration: L10n.UiPreferences.duration(140) }
            }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(jumpToBottomMouse.pressed ? 70 : 160); easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(100) }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.top
                anchors.bottomMargin: -7
                width: Math.max(22, unreadBadgeText.implicitWidth + 12)
                height: 22
                radius: 11
                color: root.accentColor
                visible: root.remainingUnreadCount > 0
                Text {
                    id: unreadBadgeText
                    anchors.centerIn: parent
                    text: root.remainingUnreadCount > 999 ? "999+" : root.remainingUnreadCount
                    color: root.accentTextColor
                    font.bold: true
                    font.pixelSize: 11
                }
            }

            Canvas {
                id: chatDownArrow
                property real arrowOffsetX: 0
                property real arrowOffsetY: 1.5
                anchors.centerIn: parent
                width: 18
                height: 18
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = jumpToBottomMouse.containsMouse
                        ? root.accentTextColor : root.textPrimary
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(4 + arrowOffsetX, 6.5 + arrowOffsetY)
                    ctx.lineTo(9 + arrowOffsetX, 11.5 + arrowOffsetY)
                    ctx.lineTo(14 + arrowOffsetX, 6.5 + arrowOffsetY)
                    ctx.stroke()
                }
                Connections {
                    target: root
                    function onTextPrimaryChanged() { chatDownArrow.requestPaint() }
                    function onAccentTextColorChanged() { chatDownArrow.requestPaint() }
                }
            }

            MouseArea {
                id: jumpToBottomMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: chatDownArrow.requestPaint()
                onClicked: root.jumpDown()
            }
        }

        NumberAnimation {
            id: scrollToBottomAnimation
            onStopped: {
                root.captureViewport(false)
                if (root.layoutPending) Qt.callLater(root.stabilizeViewport)
                viewportTimer.restart()
            }
            target: messageList
            property: "contentY"
            duration: L10n.UiPreferences.duration(260)
            easing.type: Easing.OutCubic
        }

    }

    Column {
        visible: root.isLoadingMessages && (!root.messageModel || root.messageModel.count === 0)
        anchors.centerIn: parent
        spacing: 14

        PrismBusyIndicator {
            running: root.isLoadingMessages
            accentColor: root.accentColor
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: L10n.I18n.tr("Загрузка сообщений...")
            color: root.textSecondary
            font.pointSize: 10
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Column {
        visible: root.showEmptyState && !root.isLoadingMessages
        anchors.centerIn: parent
        spacing: 12
        Text { text: L10n.I18n.tr("Это начало комнаты ") + root.roomName; color: root.textPrimary; font.bold: true; font.pointSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
        Text { text: L10n.I18n.tr("В этой комнате пока нет сообщений."); color: root.textSecondary; font.pointSize: 10; anchors.horizontalCenter: parent.horizontalCenter }
    }

    Timer {
        id: paginationArmTimer
        interval: 650
        onTriggered: root.olderRequestArmed = true
    }

    Timer {
        id: autoScrollTimer
        interval: 16
        repeat: true
        running: root.isDragging && Math.abs(speed) > 0.1
        property real speed: 0
        onTriggered: {
            messageList.contentY += speed
            messageList.returnToBounds()
            if (root.dragStartIndex >= 0) {
                var contentY = root.lastDragY + messageList.contentY
                var targetIndex = messageList.indexAt(messageList.width / 2, contentY)
                if (targetIndex >= 0) root.continueSelectionGesture(targetIndex)
            }
        }
    }
}

import ".." as Chat
import QtQuick
import Prism.Ipc 1.0 as Native
import "../../common"
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtCore
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Column {
    id: root

    readonly property alias draftSaveTimerObject: draftSaveTimer
    readonly property alias draftSettingsObject: draftSettings
    readonly property alias emojiPickerLoaderObject: emojiPickerLoader
    readonly property alias inputBarObject: inputBar
    readonly property alias scheduledDispatchTimerObject: scheduledDispatchTimer
    readonly property alias scheduledMessagesPopupObject: scheduledMessagesPopup
    readonly property alias voiceRecorderLoaderObject: voiceRecorderLoader
    readonly property var platformClipboard: typeof clipboardBridge === "undefined" ? null : clipboardBridge
    readonly property string temporaryDirectory: StandardPaths.writableLocation(StandardPaths.TempLocation)
    readonly property var i18nService: L10n.I18n

    readonly property string emojiFontFamily: L10n.UiPreferences.emojiFontFamily

    property string currentRoomId: ""
    property string currentUserId: ""
    property bool dispatchEnabled: false
    property bool typingNotificationsEnabled: true
    property bool typingActive: false
    property string typingRoomId: ""
    property string mediaProxy: ""
    property var authorNameResolver: null
    property int authorNameRevision: 0
    property var requestIdFactory: null
    property int localRequestSequence: 0
    property int clearDraftsGeneration: 0
    property string editingEventId: ""
    readonly property bool editing: editingEventId !== ""
    property string replyingEventId: ""
    property string replyingSender: ""
    property string replyingBody: ""
    property string pendingPasteRequestId: ""
    property int pendingPasteStart: 0
    property int pendingPasteEnd: 0
    property var nativeClipboardHelper: null
    property var stickerProvider: null
    property var stickerPackProvider: null
    property var pendingAttachments: []
    property var mentionedUserIds: []
    property bool microphoneMode: false
    property bool voicePressActive: false
    property bool voiceStopPending: false
    property bool voiceGestureConsumed: false
    property double voicePressStartedAt: 0
    property bool caretBlinkVisible: true
    property int voiceDurationMs: 0
    property var roomDrafts: ({})
    property var scheduledMessages: []
    readonly property var currentRoomScheduledMessages: {
        var result = []
        var items = scheduledMessages || []
        for (var index = 0; index < items.length; index++) {
            var item = items[index] || ({})
            if (String(item.account_id || "") === currentUserId
                    && String(item.room_id || "") === currentRoomId)
                result.push(item)
        }
        result.sort(function(left, right) {
            return Number(left.scheduled_at || 0) - Number(right.scheduled_at || 0)
        })
        return result
    }
    readonly property var draftRoomIds: {
        var result = []
        var drafts = roomDrafts || ({})
        for (var roomId in drafts) {
            if (drafts.hasOwnProperty(roomId) && draftHasContent(drafts[roomId]))
                result.push(roomId)
        }
        return result
    }
    property string activeDraftRoomId: ""
    property bool restoringDraft: false
    property var activeUploads: []
    readonly property var visibleUploads: uploadsForRoom(currentRoomId)
    readonly property bool hasPendingAttachment: pendingAttachments.length > 0
    readonly property double pendingAttachmentsTotalSize: {
        var total = 0
        for (var sizeIndex = 0; sizeIndex < pendingAttachments.length;
                sizeIndex++) {
            var size = Number(pendingAttachments[sizeIndex].size)
            if (isFinite(size) && size >= 0) total += size
        }
        return total
    }
    readonly property bool pendingAttachmentSizesKnown: {
        if (pendingAttachments.length === 0) return false
        for (var sizeIndex = 0; sizeIndex < pendingAttachments.length;
                sizeIndex++) {
            var size = Number(pendingAttachments[sizeIndex].size)
            if (!isFinite(size) || size < 0) return false
        }
        return true
    }
    readonly property double largeFileWarningBytes: 50 * 1024 * 1024
    readonly property bool hasDraftContent: hasPendingAttachment || inputBar.messageAreaObject.text.trim() !== ""
    readonly property bool microphoneVisible: microphoneMode && !hasDraftContent
    readonly property bool voiceRecording: voiceRecorderLoader.item
        ? voiceRecorderLoader.item.recording : false
    readonly property bool replying: replyingEventId !== ""
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal messageSubmitted(string text, string editEventId, string replyEventId,
                            var mentionedUserIds)
    signal uploadRequested(string path, string filename, string mimeType, int durationMs)
    signal uploadCancelRequested(string requestId)
    signal stickerMediaRequested(var sticker)
    signal stickerAssetCreateRequested(var draft)
    signal stickerPackShareRequested(var pack)
    signal stickerSaveRequested(var sticker)
    signal stickerPackViewRequested(var pack)
    signal clipboardPasteRequested(string requestId)
    signal feedbackRequested(string text, bool isError)
    signal typingStateChanged(string roomId, bool typing)
    signal scheduledMessageDue(var message)

    function replyingAuthorName() {
        var revision = root.authorNameRevision
        if (root.authorNameResolver)
            return root.authorNameResolver(root.replyingSender || "", "")
        return Utils.displayName(root.replyingSender)
    }

    width: parent ? parent.width : 0
    spacing: 0
    onCurrentRoomIdChanged: {
        stopTyping()
        largeFileWarningDialog.close()
        switchDraftRoom(currentRoomId)
    }
    onCurrentUserIdChanged: {
        armScheduledDispatch()
        Qt.callLater(processScheduledMessages)
    }
    onDispatchEnabledChanged: {
        if (dispatchEnabled)
            Qt.callLater(processScheduledMessages)
        else
            scheduledDispatchTimer.stop()
    }
    onScheduledMessagesChanged: {
        scheduledSaveTimer.restart()
        armScheduledDispatch()
    }
    onTypingNotificationsEnabledChanged: {
        if (!typingNotificationsEnabled)
            stopTyping()
    }
    onVoiceRecordingChanged: refreshTypingState()
    onClearDraftsGenerationChanged: clearAllDrafts()

    Settings {
        id: draftSettings
        category: "Composer"
        property string roomDraftsJson: "{}"
        property string scheduledMessagesJson: "[]"
    }

    Timer {
        id: draftSaveTimer
        interval: 250
        onTriggered: root.persistDrafts()
    }

    Timer {
        id: scheduledSaveTimer
        interval: 250
        onTriggered: root.persistScheduledMessages()
    }

    Timer {
        id: scheduledDispatchTimer
        repeat: false
        onTriggered: root.processScheduledMessages()
    }

    Timer {
        id: typingKeepaliveTimer
        interval: 3200
        repeat: true
        onTriggered: {
            if (root.shouldSendTyping() && root.typingRoomId === root.currentRoomId)
                root.typingStateChanged(root.typingRoomId, true)
            else
                root.stopTyping()
        }
    }

    Timer {
        id: typingIdleTimer
        interval: 4000
        onTriggered: root.stopTyping()
    }

    Timer {
        id: caretBlinkTimer
        interval: 500
        repeat: true
        running: inputBar.messageAreaObject.activeFocus
        onRunningChanged: root.caretBlinkVisible = true
        onTriggered: root.caretBlinkVisible = !root.caretBlinkVisible
    }

    Component.onCompleted: {
        try {
            var stored = JSON.parse(draftSettings.roomDraftsJson || "{}")
            roomDrafts = stored && typeof stored === "object" ? stored : ({})
        } catch (error) {
            roomDrafts = ({})
        }
        try {
            var storedScheduled = JSON.parse(
                draftSettings.scheduledMessagesJson || "[]")
            scheduledMessages = Array.isArray(storedScheduled)
                ? storedScheduled : []
        } catch (scheduledError) {
            scheduledMessages = []
        }

        // PrismChatUi provides clipboardBridge as a context property. Direct
        // qml development runs use the same implementation from Prism.Ipc.
        if (typeof clipboardBridge === "undefined" || !clipboardBridge) {
            try {
                nativeClipboardHelper = Qt.createQmlObject(
                    'import "' + Qt.resolvedUrl("../../../Prism/Ipc")
                        + '" as Native\nNative.ClipboardBridge {}',
                    root,
                    "PrismClipboardBridge")
            } catch (clipboardError) {
                nativeClipboardHelper = null
                console.info("Нативный Qt clipboard bridge недоступен:", clipboardError)
            }
        }

        activeDraftRoomId = ""
        switchDraftRoom(currentRoomId)
        Qt.callLater(processScheduledMessages)
    }
    Component.onDestruction: {
        stopTyping()
        saveCurrentDraft()
        persistDrafts()
        persistScheduledMessages()
    }

    function shouldSendTyping() {
        return typingNotificationsEnabled && !restoringDraft
            && currentRoomId !== "" && inputBar.messageAreaObject.activeFocus
            && !voiceRecording && inputBar.messageAreaObject.text.trim() !== ""
    }

    function refreshTypingState() {
        if (!shouldSendTyping()) {
            stopTyping()
            return
        }
        if (!typingActive || typingRoomId !== currentRoomId) {
            stopTyping()
            typingActive = true
            typingRoomId = currentRoomId
            typingStateChanged(typingRoomId, true)
        }
        typingIdleTimer.restart()
        if (!typingKeepaliveTimer.running)
            typingKeepaliveTimer.start()
    }

    function stopTyping() {
        typingKeepaliveTimer.stop()
        typingIdleTimer.stop()
        if (typingActive && typingRoomId !== "")
            typingStateChanged(typingRoomId, false)
        typingActive = false
        typingRoomId = ""
    }

    function nextRequestId(suffix) {
        if (requestIdFactory)
            return requestIdFactory(suffix || "composer")
        localRequestSequence++
        return Date.now().toString() + "-" + localRequestSequence
            + (suffix ? "-" + suffix : "")
    }

    function uploadsForRoom(roomId) {
        return Native.FrontendLogic.invoke("composer.uploadsForRoom", root, [roomId])
    }

    function beginUpload(requestId, roomId, filename) {
        return Native.FrontendLogic.invoke("composer.beginUpload", root,
                                           [requestId, roomId, filename])
    }

    function updateUpload(requestId, current, total) {
        return Native.FrontendLogic.invoke("composer.updateUpload", root,
                                           [requestId, current, total])
    }

    function finishUpload(requestId) {
        return Native.FrontendLogic.invoke("composer.finishUpload", root, [requestId])
    }

    function formatBytes(bytes) {
        return Native.FrontendLogic.invoke("composer.formatBytes", root, [bytes])
    }

    function attachmentCountText(count) {
        return Native.FrontendLogic.invoke("composer.attachmentCountText", root, [count])
    }

    function attachmentSummary() {
        return Native.FrontendLogic.invoke("composer.attachmentSummary", root, [])
    }

    function largestPendingAttachment() {
        return Native.FrontendLogic.invoke("composer.largestPendingAttachment", root, [])
    }

    function clearComposerForRoomChange() {
        return Native.FrontendLogic.invoke("composer.clearComposerForRoomChange", root, [])
    }

    function resetForRoomChange() {
        return Native.FrontendLogic.invoke("composer.resetForRoomChange", root, [])
    }

    function draftSnapshot() {
        return Native.FrontendLogic.invoke("composer.draftSnapshot", root, [])
    }

    function draftHasContent(draft) {
        return Native.FrontendLogic.invoke("composer.draftHasContent", root, [draft])
    }

    function saveCurrentDraft() {
        return Native.FrontendLogic.invoke("composer.saveCurrentDraft", root, [])
    }

    function persistDrafts() {
        return Native.FrontendLogic.invoke("composer.persistDrafts", root, [])
    }

    function persistScheduledMessages() {
        return Native.FrontendLogic.invoke("composer.persistScheduledMessages", root, [])
    }

    function armScheduledDispatch() {
        return Native.FrontendLogic.invoke("composer.armScheduledDispatch", root, [])
    }

    function processScheduledMessages() {
        return Native.FrontendLogic.invoke("composer.processScheduledMessages", root, [])
    }

    function saveScheduledMessage(itemId, body, scheduledAt, attachments,
                                  replyEventId, mentionedIds) {
        return Native.FrontendLogic.invoke("composer.saveScheduledMessage", root,
                                           [itemId, body, scheduledAt, attachments,
                                            replyEventId, mentionedIds])
    }

    function cancelScheduledMessage(itemId) {
        return Native.FrontendLogic.invoke("composer.cancelScheduledMessage", root, [itemId])
    }

    function openScheduledMessages() {
        return Native.FrontendLogic.invoke("composer.openScheduledMessages", root, [])
    }

    function clearAllDrafts() {
        return Native.FrontendLogic.invoke("composer.clearAllDrafts", root, [])
    }

    function removeDraft(roomId) {
        return Native.FrontendLogic.invoke("composer.removeDraft", root, [roomId])
    }

    function switchDraftRoom(roomId) {
        return Native.FrontendLogic.invoke("composer.switchDraftRoom", root, [roomId])
    }

    function restoreEditing(eventId, body) {
        cancelReply()
        editingEventId = eventId || ""
        inputBar.messageAreaObject.text = body || ""
        inputBar.messageAreaObject.forceActiveFocus()
    }

    function startEditing(eventId, body) {
        cancelReply()
        editingEventId = eventId
        inputBar.messageAreaObject.text = body || ""
        inputBar.messageAreaObject.forceActiveFocus()
    }

    function startReply(eventId, sender, body) {
        editingEventId = ""
        replyingEventId = eventId || ""
        replyingSender = sender || ""
        replyingBody = body || ""
        saveCurrentDraft()
        inputBar.messageAreaObject.forceActiveFocus()
    }

    function cancelReply() {
        replyingEventId = ""
        replyingSender = ""
        replyingBody = ""
        saveCurrentDraft()
    }

    function cancelEditing() {
        editingEventId = ""
        inputBar.messageAreaObject.text = ""
    }

    function submit(largeFileConfirmed) {
        var text = inputBar.messageAreaObject.text.trim()
        if ((text === "" && !hasPendingAttachment) || currentRoomId === "")
            return

        var largeAttachment = largestPendingAttachment()
        if (!largeFileConfirmed && largeAttachment) {
            largeFileWarningDialog.filename = largeAttachment.name
                || L10n.I18n.tr("Вложение")
            largeFileWarningDialog.fileSize = Number(largeAttachment.size || 0)
            largeFileWarningDialog.open()
            return
        }

        var editId = editingEventId
        var replyId = replyingEventId
        var submittedMentions = mentionedUserIds.filter(function(userId) {
            return text.indexOf(userId) !== -1
        })
        var attachments = pendingAttachments.slice(0)

        inputBar.messageAreaObject.text = ""
        editingEventId = ""
        microphoneMode = false
        clearPendingAttachment()
        mentionedUserIds = []
        removeDraft(currentRoomId)

        if (text !== "")
            messageSubmitted(text, editId, replyId, submittedMentions)
        for (var attachmentIndex = 0; attachmentIndex < attachments.length; attachmentIndex++)
            uploadRequested(attachments[attachmentIndex].path, attachments[attachmentIndex].name,
                            attachments[attachmentIndex].mime || "",
                            attachments[attachmentIndex].duration_ms || 0)
        cancelReply()
    }

    function refreshStickerPicker() {
        if (stickerPickerLoader.item)
            stickerPickerLoader.item.reload()
    }

    function closeEmojiPicker() {
        if (emojiPickerLoader.item)
            emojiPickerLoader.item.close()
    }

    function closeStickerPicker() {
        if (stickerPickerLoader.item)
            stickerPickerLoader.item.close()
    }

    function toggleEmojiPicker() {
        closeStickerPicker()
        if (emojiPickerLoader.item)
            emojiPickerLoader.item.close()
        else
            emojiPickerLoader.active = true
    }

    function toggleStickerPicker() {
        closeEmojiPicker()
        if (stickerPickerLoader.item)
            stickerPickerLoader.item.close()
        else
            stickerPickerLoader.active = true
    }

    function openAttachmentDialog() {
        if (attachmentDialogLoader.item) {
            attachmentDialogLoader.item.open()
            return
        }
        attachmentDialogLoader.active = true
    }

    function insertEmoji(emoji) {
        var value = String(emoji || "")
        if (value === "" || currentRoomId === "") return
        var start = Math.max(0, Math.min(inputBar.messageAreaObject.selectionStart, inputBar.messageAreaObject.length))
        var end = Math.max(start, Math.min(inputBar.messageAreaObject.selectionEnd, inputBar.messageAreaObject.length))
        if (end > start)
            inputBar.messageAreaObject.remove(start, end)
        inputBar.messageAreaObject.insert(start, value)
        inputBar.messageAreaObject.cursorPosition = start + value.length
        inputBar.messageAreaObject.forceActiveFocus()
    }

    function insertMention(userId) {
        var value = String(userId || "").trim()
        if (value === "" || currentRoomId === "") return
        var start = Math.max(0, Math.min(inputBar.messageAreaObject.selectionStart,
                                         inputBar.messageAreaObject.length))
        var end = Math.max(start, Math.min(inputBar.messageAreaObject.selectionEnd,
                                           inputBar.messageAreaObject.length))
        if (end > start)
            inputBar.messageAreaObject.remove(start, end)

        var prefix = start > 0 && !/\s/.test(inputBar.messageAreaObject.text.charAt(start - 1))
            ? " " : ""
        var suffix = start < inputBar.messageAreaObject.length
            && !/\s/.test(inputBar.messageAreaObject.text.charAt(start)) ? " " : ""
        var insertion = prefix + value + suffix
        inputBar.messageAreaObject.insert(start, insertion)
        inputBar.messageAreaObject.cursorPosition = start + insertion.length
        if (mentionedUserIds.indexOf(value) === -1) {
            var nextMentions = mentionedUserIds.slice(0)
            nextMentions.push(value)
            mentionedUserIds = nextMentions
        }
        inputBar.messageAreaObject.forceActiveFocus()
        saveCurrentDraft()
    }

    function localFileUrl(path) {
        return Native.FrontendLogic.invoke("composer.localFileUrl", root, [path])
    }

    function clipboardProvider() {
        return Native.FrontendLogic.invoke("composer.clipboardProvider", root, [])
    }

    function stageAttachment(fileUrl, path, filename, isImage, explicitMime,
                             durationMs, explicitSize) {
        return Native.FrontendLogic.invoke("composer.stageAttachment", root,
                                           [fileUrl, path, filename, isImage,
                                            explicitMime, durationMs, explicitSize])
    }

    function removePendingAttachment(index) {
        return Native.FrontendLogic.invoke("composer.removePendingAttachment", root, [index])
    }

    function clearPendingAttachment() {
        return Native.FrontendLogic.invoke("composer.clearPendingAttachment", root, [])
    }

    function formatVoiceDuration(durationMs) {
        return Native.FrontendLogic.invoke("composer.formatVoiceDuration", root, [durationMs])
    }

    function startVoiceRecording() {
        return Native.FrontendLogic.invoke("composer.startVoiceRecording", root, [])
    }

    function stopVoiceRecording() {
        return Native.FrontendLogic.invoke("composer.stopVoiceRecording", root, [])
    }

    function finishVoiceRecording() {
        return Native.FrontendLogic.invoke("composer.finishVoiceRecording", root, [])
    }

    function cancelVoiceRecording() {
        return Native.FrontendLogic.invoke("composer.cancelVoiceRecording", root, [])
    }

    function requestClipboardPaste() {
        return Native.FrontendLogic.invoke("composer.requestClipboardPaste", root, [])
    }

    function finishClipboardPaste(requestId, success, text, attachments, errorText) {
        return Native.FrontendLogic.invoke("composer.finishClipboardPaste", root,
                                           [requestId, success, text,
                                            attachments, errorText])
    }

    Loader {
        id: voiceRecorderLoader
        active: false
        property url outputLocation: ""
        onLoaded: item.startAt(outputLocation)
        sourceComponent: Component {
            Chat.VoiceRecorder {
                onDurationUpdated: function(durationMs) {
                    root.voiceDurationMs = Number(durationMs || 0)
                }
                onStopped: {
                    if (root.voiceStopPending)
                        Qt.callLater(root.finishVoiceRecording)
                }
                onRecordingError: function(errorString) {
                root.voicePressActive = false
                root.voiceStopPending = false
                root.microphoneMode = true
                root.feedbackRequested(L10n.I18n.tr("Не удалось записать голосовое: ")
                    + (errorString || L10n.I18n.tr("проверьте доступ к микрофону")), true)
                    voiceRecorderLoader.active = false
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: root.editing ? 28 : 0
        visible: root.editing
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: L10n.I18n.tr("Редактирование сообщения")
                color: root.accentColor
                font.pointSize: 9
            }
            Basic.Button {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                flat: true
                padding: 0
                contentItem: Icons.CloseIcon { color: root.iconColor; width: 16; height: 16 }
                background: Item {}
                onClicked: root.cancelEditing()
            }
        }
    }

    Rectangle {
        width: parent.width
        height: root.replying ? 42 : 0
        visible: root.replying
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            spacing: 8
            Rectangle { Layout.preferredWidth: 3; Layout.fillHeight: true; Layout.topMargin: 8; Layout.bottomMargin: 8; radius: 2; color: root.accentColor }
            Column {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: L10n.I18n.tr("Ответ для ") + root.replyingAuthorName()
                    color: root.accentColor
                    font.bold: true
                    font.pointSize: 8
                }
                Text {
                    width: parent.width
                    text: Utils.singleLinePreview(L10n.I18n.localizedMessagePreview(root.replyingBody))
                    textFormat: Text.PlainText
                    color: root.textPrimary
                    opacity: 0.68
                    font.pointSize: 8
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                    clip: true
                }
            }
            Basic.Button {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                flat: true
                padding: 0
                contentItem: Icons.CloseIcon { color: root.iconColor; width: 16; height: 16 }
                background: Item {}
                onClicked: root.cancelReply()
            }
        }
    }

    PendingAttachments {
        id: pendingAttachmentBar
        composer: root
    }

    UploadProgress {
        id: uploadProgressBar
        composer: root
    }

    LargeFileWarning {
        id: largeFileWarningDialog
        composer: root
    }

    InputBar {
        id: inputBar
        composer: root
        emojiPickerLoaderObject: emojiPickerLoader
        scheduledMessagesPopupObject: scheduledMessagesPopup
        stickerPickerLoaderObject: stickerPickerLoader
    }

    Chat.ScheduledMessagesPopup {
        id: scheduledMessagesPopup
        scheduledItems: root.currentRoomScheduledMessages
        accentColor: root.accentColor
        accentTextColor: root.accentTextColor
        elevatedColor: root.elevatedColor
        surfaceColor: root.surfaceColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        dividerColor: root.dividerColor

        onSaveRequested: function(itemId, body, scheduledAt, attachments,
                                  replyEventId, mentionedIds) {
            root.saveScheduledMessage(itemId, body, scheduledAt, attachments,
                                      replyEventId, mentionedIds)
        }
        onCancelRequested: function(itemId) {
            root.cancelScheduledMessage(itemId)
        }
    }

    Loader {
        id: emojiPickerLoader
        active: false
        onLoaded: item.open()
        sourceComponent: Component {
            Chat.EmojiPicker {
                parent: root
                width: Math.min(380, Math.max(300, root.width - 16))
                x: Math.max(8, Math.min(root.width - width - 8,
                                        inputBar.emojiButtonObject.mapToItem(root, 0, 0).x - 6))
                y: inputBar.emojiButtonObject.mapToItem(root, 0, 0).y - height - 8
                z: 10000
                accentColor: root.accentColor
                accentTextColor: root.accentTextColor
                surfaceColor: root.surfaceColor
                elevatedColor: root.elevatedColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                dividerColor: root.dividerColor
                onEmojiChosen: function(emoji) { root.insertEmoji(emoji) }
                onClosed: Qt.callLater(function() {
                    if (!emojiPickerLoader.item || !emojiPickerLoader.item.opened)
                        emojiPickerLoader.active = false
                })
            }
        }
    }

    Loader {
        id: stickerPickerLoader
        active: false
        onLoaded: item.open()
        sourceComponent: Component {
            Chat.StickerPicker {
                parent: root
                width: Math.min(370, Math.max(300, root.width - 16))
                x: Math.max(8, Math.min(root.width - width - 8,
                                        inputBar.stickerButtonObject.mapToItem(root, 0, 0).x - 6))
                y: inputBar.stickerButtonObject.mapToItem(root, 0, 0).y - height - 8
                z: 10001
                accentColor: root.accentColor
                surfaceColor: root.surfaceColor
                elevatedColor: root.elevatedColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                dividerColor: root.dividerColor
                accountId: root.currentUserId
                mediaProxy: root.mediaProxy
                stickerProvider: root.stickerProvider
                stickerPackProvider: root.stickerPackProvider
                onStickerChosen: function(sticker) { root.stickerMediaRequested(sticker) }
                onStickerAssetCreateRequested: function(draft) { root.stickerAssetCreateRequested(draft) }
                onSharePackRequested: function(pack) { root.stickerPackShareRequested(pack) }
                onSaveStickerRequested: function(sticker) { root.stickerSaveRequested(sticker) }
                onViewPackRequested: function(pack) { root.stickerPackViewRequested(pack) }
                onClosed: Qt.callLater(function() {
                    if (!stickerPickerLoader.item || !stickerPickerLoader.item.opened)
                        stickerPickerLoader.active = false
                })
            }
        }
    }
    Loader {
        id: attachmentDialogLoader
        active: false
        onLoaded: item.open()
        sourceComponent: Component {
            Chat.AttachmentFileDialog {
                onFilesSelected: function(files) {
            for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
                var fileUrl = files[fileIndex]
                var path = Utils.localPath(fileUrl)
                root.stageAttachment(fileUrl, path, path.split("/").pop())
            }
        }
                onFinished: Qt.callLater(function() { attachmentDialogLoader.active = false })
            }
        }
    }

}

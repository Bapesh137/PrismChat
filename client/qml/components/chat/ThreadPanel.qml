import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../common"
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils

Rectangle {
    id: root

    property string roomId: ""
    property string rootEventId: ""
    property var rootMessage: null
    property var messages: []
    property var threadSummaries: []
    property bool loading: false
    property bool hasMore: false
    property string errorText: ""
    property bool listLoading: false
    property bool listHasMore: false
    property string listErrorText: ""
    property string currentUserId: ""
    property var authorNameResolver: null
    property var authorAvatarResolver: null
    property string mediaProxy: ""
    property bool roundAvatars: true
    property bool autoLoadImages: true
    property bool autoLoadVideos: true
    property string activeVoiceEventId: ""
    property bool activeVoicePlaying: false
    property real activeVoicePosition: 0
    property real activeVoiceDuration: 0
    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color iconColor: accentColor
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    property var replyTarget: null
    readonly property bool detailOpen: rootEventId !== ""

    signal closeRequested()
    signal backRequested()
    signal threadSelected(var rootMessage)
    signal sendRequested(string body, string replyTo)
    signal loadMoreRequested()
    signal loadThreadListMoreRequested()
    signal refreshThreadListRequested()
    signal retryRequested(string timelineItemId)
    signal reactionRequested(string eventId, var reaction)
    signal contextRequested(int messageIndex, var messageData)
    signal userRequested(string userId, real x, real y)
    signal imageRequested(string source, string caption)
    signal videoRequested(var details)
    signal downloadRequested(string mediaUrl, string filename, var mediaFile, string mimeType)
    signal replyRequested(string eventId, string sender, string body)
    signal voicePlaybackRequested(var details)
    signal voiceSeekRequested(real position)
    signal copyRequested(string text)

    color: surfaceColor
    border.width: 1
    border.color: dividerColor

    function displayName(message) {
        var sender = String((message && message.sender) || "")
        var cached = String((message && message.sender_display_name) || "")
        return authorNameResolver ? authorNameResolver(sender, cached)
                                  : (cached || Utils.displayName(sender))
    }

    function avatarFor(message) {
        var sender = String((message && message.sender) || "")
        var cached = String((message && message.sender_avatar_url) || "")
        return authorAvatarResolver ? authorAvatarResolver(sender, cached) : cached
    }

    function replyMessages() {
        var result = []
        for (var index = 0; index < (root.messages || []).length; index++) {
            var message = root.messages[index]
            if ((message.event_id || "") !== root.rootEventId) result.push(message)
        }
        return result
    }

    function startReply(messageData) {
        replyTarget = messageData || null
        threadInput.forceActiveFocus()
    }

    QtObject {
        id: threadController
        property bool multiSelectMode: false
        property bool isDragging: false
        property int selectionGestureButton: Qt.NoButton
        function shouldShowHeader(index) { return true }
        function isSelected(eventId) { return false }
        function displayNameFor(sender, fallback) {
            return root.authorNameResolver
                ? root.authorNameResolver(sender || "", fallback || "")
                : (fallback || Utils.displayName(sender || ""))
        }
        function formatTimestamp(timestamp) { return Qt.formatTime(new Date(Number(timestamp || 0)), "HH:mm") }
        function formatCompactTimestamp(timestamp) { return formatTimestamp(timestamp) }
        function formatFullTimestamp(timestamp) { return new Date(Number(timestamp || 0)).toLocaleString() }
        function openContext(index, messageData, selected) { root.contextRequested(index, messageData) }
        function openUserProfile(userId, roomId, x, y) { root.userRequested(userId, x, y) }
        function openImage(mediaUrl, caption, mediaFile, mimeType) {
            var source = Utils.proxyUrl(mediaUrl, root.mediaProxy, mediaFile, mimeType)
            if (source !== "") root.imageRequested(source, caption)
        }
        function downloadFile(url, name, file, mime) { root.downloadRequested(url, name, file, mime) }
        function jumpToReply(eventId) {}
        function toggleVoice(details) { root.voicePlaybackRequested(details) }
        function seekVoice(position) { root.voiceSeekRequested(position) }
        function copyCode(text) { root.copyRequested(text) }
        function beginDrag(index, eventId, y) {}
        function updateDrag(y) {}
        function endDrag() {}
        function finishSelectionGesture() {}
    }

    Rectangle {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 52
        color: root.elevatedColor

        Basic.Button {
            id: backButton
            visible: root.detailOpen
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34
            text: "‹"
            onClicked: root.backRequested()
            contentItem: Text { text: backButton.text; color: root.textPrimary; font.pointSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 8; color: backButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08) : "transparent" }
        }
        Text {
            anchors.left: root.detailOpen ? backButton.right : parent.left
            anchors.leftMargin: root.detailOpen ? 6 : 16
            anchors.verticalCenter: parent.verticalCenter
            text: root.detailOpen ? L10n.I18n.tr("Тред") : L10n.I18n.tr("Треды")
            color: root.textPrimary
            font.pointSize: 11
            font.bold: true
        }
        Basic.Button {
            id: closeButton
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34
            text: "×"
            onClicked: root.closeRequested()
            contentItem: Text { text: closeButton.text; color: root.textSecondary; font.pointSize: 15; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 8; color: closeButton.hovered ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08) : "transparent" }
        }
    }

    ListView {
        id: threadDirectory
        visible: !root.detailOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        clip: true
        spacing: 2
        model: root.threadSummaries || []
        footer: Basic.Button {
            width: threadDirectory.width
            height: root.listHasMore || root.listLoading || root.listErrorText !== "" ? 46 : 10
            visible: height > 10
            enabled: !root.listLoading
            text: root.listLoading ? L10n.I18n.tr("Загрузка…")
                : root.listErrorText !== "" ? L10n.I18n.tr("Повторить")
                : L10n.I18n.tr("Загрузить ещё")
            onClicked: root.listErrorText !== ""
                ? root.refreshThreadListRequested() : root.loadThreadListMoreRequested()
        }
        delegate: Rectangle {
            id: summaryRow
            required property var modelData
            width: threadDirectory.width
            height: 96
            color: summaryMouse.containsMouse
                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.055)
                : "transparent"
            border.width: modelData.unread ? 1 : 0
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
            readonly property var rootEvent: modelData.root || ({})
            readonly property var latest: modelData.latest_reply || ({})

            Column {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 5
                RowLayout {
                    width: parent.width
                    Text { Layout.fillWidth: true; text: root.displayName(summaryRow.rootEvent); color: root.textPrimary; font.pointSize: 9; font.bold: true; elide: Text.ElideRight }
                    Rectangle { visible: summaryRow.modelData.unread; width: 8; height: 8; radius: 4; color: root.accentColor }
                    Text { text: String(summaryRow.modelData.reply_count || 0); color: root.accentColor; font.pointSize: 8; font.bold: true }
                }
                Text { width: parent.width; text: summaryRow.rootEvent.body || L10n.I18n.tr("Вложение"); color: root.textPrimary; font.pointSize: 8; elide: Text.ElideRight }
                Text { width: parent.width; visible: (summaryRow.latest.event_id || "") !== ""; text: root.displayName(summaryRow.latest) + ": " + (summaryRow.latest.body || L10n.I18n.tr("Вложение")); color: root.textSecondary; font.pointSize: 8; elide: Text.ElideRight }
                Text { width: parent.width; text: Qt.formatDateTime(new Date(Number((summaryRow.latest.timestamp || summaryRow.rootEvent.timestamp) || 0)), "dd.MM  HH:mm"); color: root.textSecondary; font.pointSize: 7; horizontalAlignment: Text.AlignRight }
            }
            MouseArea { id: summaryMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.threadSelected(summaryRow.rootEvent) }
        }
        Text { anchors.centerIn: parent; visible: threadDirectory.count === 0 && !root.listLoading; text: root.listErrorText !== "" ? root.listErrorText : L10n.I18n.tr("В этой комнате пока нет тредов"); color: root.textSecondary; width: parent.width - 40; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
        ScrollBar.vertical: PrismScrollBar {
            policy: ScrollBar.AsNeeded
            autoHide: true
            handleColor: root.textSecondary
            handleHoverColor: root.accentColor
            trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                root.textSecondary.b, 0.14)
        }
    }

    Rectangle {
        id: rootCard
        visible: root.detailOpen && root.rootMessage
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        height: visible ? Math.min(210, rootMessageDelegate.height + 16) : 0
        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.055)
        border.width: 1
        border.color: root.dividerColor
        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: rootMessageDelegate.height
            clip: true
            MessageDelegate {
                id: rootMessageDelegate
                width: parent.width
                controller: threadController
                chatViewRoot: root
                messageIndex: -1
                eventId: (root.rootMessage && root.rootMessage.event_id) || ""
                sender: (root.rootMessage && root.rootMessage.sender) || ""
                senderDisplayName: root.displayName(root.rootMessage)
                senderAvatarUrl: root.avatarFor(root.rootMessage)
                body: (root.rootMessage && root.rootMessage.body) || ""
                messageType: (root.rootMessage && root.rootMessage.msg_type) || "m.text"
                timestamp: Number((root.rootMessage && root.rootMessage.timestamp) || 0)
                mediaUrl: (root.rootMessage && root.rootMessage.media_url) || ""
                mediaFile: (root.rootMessage && root.rootMessage.media_file) || null
                mediaMimeType: (root.rootMessage && root.rootMessage.media_mime_type) || ""
                reactions: (root.rootMessage && root.rootMessage.reactions) || []
                readReceipts: (root.rootMessage && root.rootMessage.read_receipts) || []
                currentUserId: root.currentUserId
                currentRoomId: root.roomId
                activeVoiceEventId: root.activeVoiceEventId; activeVoicePlaying: root.activeVoicePlaying; activeVoicePosition: root.activeVoicePosition; activeVoiceDuration: root.activeVoiceDuration
                threadRootId: root.rootEventId
                mediaProxy: root.mediaProxy; roundAvatars: root.roundAvatars
                autoLoadImages: root.autoLoadImages; autoLoadVideos: root.autoLoadVideos
                accentColor: root.accentColor; iconColor: root.iconColor; accentTextColor: root.accentTextColor
                textPrimary: root.textPrimary; textSecondary: root.textSecondary; elevatedColor: root.elevatedColor; dividerColor: root.dividerColor
                onReactionRequested: function(reaction) { root.reactionRequested(eventId, reaction) }
                onVideoOpenRequested: function(details) { root.videoRequested(details) }
                onQuickReplyRequested: function(eventId, sender, body) { root.startReply(root.rootMessage) }
                onRetryRequested: function(id) { root.retryRequested(id) }
            }
        }
    }

    ListView {
        id: replyList
        visible: root.detailOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: rootCard.bottom
        anchors.bottom: composerFrame.top
        clip: true
        model: root.replyMessages()
        verticalLayoutDirection: ListView.BottomToTop
        boundsBehavior: Flickable.StopAtBounds
        header: Basic.Button {
            width: replyList.width
            height: root.hasMore || root.loading || root.errorText !== "" ? 44 : 8
            visible: height > 8
            enabled: !root.loading
            text: root.loading ? L10n.I18n.tr("Загрузка…") : root.errorText !== "" ? L10n.I18n.tr("Повторить загрузку") : L10n.I18n.tr("Загрузить старые ответы")
            onClicked: root.loadMoreRequested()
        }
        delegate: MessageDelegate {
            required property int index
            required property var modelData
            width: replyList.width
            controller: threadController
            chatViewRoot: root
            messageIndex: index
            eventId: modelData.event_id || ""
            sender: modelData.sender || ""
            senderDisplayName: root.displayName(modelData)
            senderAvatarUrl: root.avatarFor(modelData)
            senderIgnored: !!modelData.sender_is_ignored
            body: modelData.body || ""
            messageType: modelData.msg_type || "m.text"
            timestamp: Number(modelData.timestamp || 0)
            mediaUrl: modelData.media_url || ""; mediaFile: modelData.media_file || null; mediaMimeType: modelData.media_mime_type || ""
            stickerPack: modelData.sticker_pack || null
            edited: !!modelData.is_edited; redacted: !!modelData.is_redacted; encrypted: !!modelData.is_encrypted
            replyTo: modelData.reply_to || ""; replySender: modelData.reply_sender || ""; replyBody: modelData.reply_body || ""
            reactions: modelData.reactions || []; readReceipts: modelData.read_receipts || []
            sendState: modelData.send_state || "sent"; timelineItemId: modelData.timeline_item_id || ""; sendError: modelData.send_error || ""; sendRecoverable: !!modelData.send_recoverable
            threadRootId: root.rootEventId
            currentUserId: root.currentUserId; currentRoomId: root.roomId
            activeVoiceEventId: root.activeVoiceEventId; activeVoicePlaying: root.activeVoicePlaying; activeVoicePosition: root.activeVoicePosition; activeVoiceDuration: root.activeVoiceDuration
            mediaProxy: root.mediaProxy; roundAvatars: root.roundAvatars
            autoLoadImages: root.autoLoadImages; autoLoadVideos: root.autoLoadVideos
            accentColor: root.accentColor; iconColor: root.iconColor; accentTextColor: root.accentTextColor
            textPrimary: root.textPrimary; textSecondary: root.textSecondary; elevatedColor: root.elevatedColor; dividerColor: root.dividerColor
            onReactionRequested: function(reaction) { root.reactionRequested(eventId, reaction) }
            onVideoOpenRequested: function(details) { root.videoRequested(details) }
            onQuickReplyRequested: function(eventId, sender, body) { root.startReply(modelData) }
            onRetryRequested: function(id) { root.retryRequested(id) }
        }
        Text { anchors.centerIn: parent; visible: replyList.count === 0 && !root.loading; text: L10n.I18n.tr("Ответов пока нет"); color: root.textSecondary }
        ScrollBar.vertical: PrismScrollBar {
            policy: ScrollBar.AsNeeded
            autoHide: true
            handleColor: root.textSecondary
            handleHoverColor: root.accentColor
            trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                root.textSecondary.b, 0.14)
        }
    }

    Rectangle {
        id: composerFrame
        visible: root.detailOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: visible ? Math.max(58, threadInput.implicitHeight + 24
            + (replyBanner.visible ? replyBanner.height : 0)) : 0
        color: root.elevatedColor
        border.width: 1
        border.color: root.dividerColor
        Rectangle {
            id: replyBanner
            visible: root.replyTarget !== null
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: visible ? 26 : 0
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
            Text {
                anchors.left: parent.left; anchors.leftMargin: 10
                anchors.right: cancelReply.left; anchors.verticalCenter: parent.verticalCenter
                text: root.replyTarget ? L10n.I18n.tr("Ответ для %1").replace("%1", root.displayName(root.replyTarget)) : ""
                color: root.textSecondary; font.pointSize: 7; elide: Text.ElideRight
            }
            Basic.Button {
                id: cancelReply
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 24; text: "×"
                onClicked: root.replyTarget = null
            }
        }
        TextArea {
            id: threadInput
            anchors.left: parent.left; anchors.right: sendButton.left
            anchors.top: replyBanner.visible ? replyBanner.bottom : parent.top
            anchors.bottom: parent.bottom; anchors.margins: 9
            placeholderText: L10n.I18n.tr("Ответить в треде")
            color: root.textPrimary; placeholderTextColor: root.textSecondary; wrapMode: TextEdit.Wrap
            background: Item {}
            Keys.onReturnPressed: function(event) { if (!(event.modifiers & Qt.ShiftModifier) && text.trim() !== "") { root.sendRequested(text.trim(), root.replyTarget ? root.replyTarget.event_id || "" : ""); root.replyTarget = null; text = ""; event.accepted = true } }
        }
        Basic.Button {
            id: sendButton
            anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
            width: 36; height: 36; enabled: threadInput.text.trim() !== ""; text: "➤"
            onClicked: { root.sendRequested(threadInput.text.trim(), root.replyTarget ? root.replyTarget.event_id || "" : ""); root.replyTarget = null; threadInput.text = "" }
            contentItem: Text { text: sendButton.text; color: sendButton.enabled ? root.accentColor : root.textSecondary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 10; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, sendButton.hovered ? 0.18 : 0.10) }
        }
    }
}

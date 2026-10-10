import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Item {
    id: root

    readonly property string emojiFontFamily: L10n.UiPreferences.emojiFontFamily

    property var controller
    property int messageIndex: -1
    property string eventId: ""
    property string sender: ""
    property string senderDisplayName: ""
    property string senderAvatarUrl: ""
    property bool senderIgnored: false
    property bool ignoredContentRevealed: false
    property var reactions: []
    property var readReceipts: []
    property bool readByOtherLocalProfile: false
    readonly property int reactionCount: {
        if (!reactions)
            return 0
        if (typeof reactions.length === "number")
            return reactions.length
        if (typeof reactions.count === "number")
            return reactions.count
        return 0
    }
    readonly property int readReceiptCount: {
        if (!readReceipts)
            return 0
        if (typeof readReceipts.length === "number")
            return readReceipts.length
        if (typeof readReceipts.count === "number")
            return readReceipts.count
        return 0
    }
    property string body: ""
    property string messageType: "m.text"
    property double timestamp: 0
    property string dateHeader: ""
    property string mediaUrl: ""
    property var mediaFile: null
    property string mediaMimeType: ""
    property var stickerPack: null
    property bool edited: false
    property bool redacted: false
    property bool encrypted: false
    property bool searchHighlighted: false
    property string replyTo: ""
    property string replySender: ""
    property string replySenderDisplayName: ""
    property string replyBody: ""
    property bool systemMessage: false
    property string systemKind: ""
    property string sendState: "sent"
    property string timelineItemId: ""
    property string sendError: ""
    property bool sendRecoverable: false
    property string threadRootId: ""
    property int threadReplyCount: 0
    property bool pinned: false
    property string mediaProxy: ""
    property bool roundAvatars: true
    property bool autoLoadImages: true
    property bool autoLoadVideos: true
    property bool mediaLoadRequested: false
    property bool videoLoadRequested: false
    property int mediaRetryToken: 0
    property int videoRetryToken: 0
    property bool pooled: false
    readonly property bool shouldLoadImage: autoLoadImages || mediaLoadRequested
    readonly property bool shouldLoadVideo: autoLoadVideos || videoLoadRequested
    readonly property bool videoAttachment: messageType === "m.video"
        || (messageType === "m.file"
            && (String(mediaMimeType || "").toLowerCase().indexOf("video/") === 0
                || Utils.guessMime(body || "").indexOf("video/") === 0))
    readonly property var textSegments: messageType === "m.text"
        ? Utils.fencedCodeSegments(body) : []
    readonly property bool hasCodeBlocks: {
        for (var segmentIndex = 0; segmentIndex < textSegments.length;
                segmentIndex++) {
            if (textSegments[segmentIndex].kind === "code") return true
        }
        return false
    }
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    readonly property color messageContentColor: sendState === "sending"
        ? Qt.rgba(textPrimary.r, textPrimary.g, textPrimary.b, 0.46)
        : textPrimary
    property color elevatedColor: "#102016"
    property color dividerColor: "#29402E"
    property string currentRoomId: ""
    property string currentUserId: ""
    property bool unreadDivider: false
    property string activeVoiceEventId: ""
    property bool activeVoicePlaying: false
    property real activeVoicePosition: 0
    property real activeVoiceDuration: 0

    signal reactionRequested(var reaction)
    signal stickerPackInstallRequested(var pack)
    signal videoOpenRequested(var details)
    signal quickReplyRequested(string eventId, string sender, string body)
    signal threadRequested()
    signal retryRequested(string timelineItemId)

    property Item chatViewRoot: null

    property real pressX: 0
    property real pressY: 0
    property bool pointerMoved: false
    property bool suppressRightContext: false

    readonly property bool showAvatar: !systemMessage && (replyTo !== ""
        || (controller ? controller.shouldShowHeader(messageIndex) : true))
    readonly property bool selected: controller ? controller.isSelected(eventId) : false
    readonly property bool contentHidden: senderIgnored && !ignoredContentRevealed && !systemMessage
    readonly property bool awaitingReadReceipt: !systemMessage && sender === currentUserId
        && readReceiptCount === 0 && !readByOtherLocalProfile && sendState === "sent"
    readonly property bool noticeMessage: messageType === "m.notice"
    readonly property int dateHeaderHeight: dateHeader !== "" ? 24 : 0
    readonly property int unreadDividerHeight: unreadDivider ? 30 : 0
    readonly property int leadingHeaderHeight: unreadDividerHeight + dateHeaderHeight
    readonly property real replyConnectorStartX: avatarItem.x
        + avatarItem.width / 2 - messageColumn.x
    readonly property real replyConnectorStartY: avatarItem.y - messageColumn.y

    onEventIdChanged: {
        ignoredContentRevealed = false
        mediaLoadRequested = false
        videoLoadRequested = false
        mediaRetryToken = 0
        videoRetryToken = 0
    }
    ListView.onPooled: root.pooled = true
    ListView.onReused: {
        root.pooled = false
        root.settleContentLayout()
    }
    onSenderIgnoredChanged: ignoredContentRevealed = false

    // Reused rows need their new layout before ListView measures them.
    function settleContentLayout() {
        senderMetaRow.forceLayout()
        reactionFlow.forceLayout()
        messageColumn.forceLayout()
    }

    Component.onCompleted: settleContentLayout()

    function reactionAt(index) {
        if (!reactions || index < 0)
            return ({})
        if (typeof reactions.get === "function")
            return reactions.get(index) || ({})
        return reactions[index] || ({})
    }

    width: parent ? parent.width : 0
    height: messageColumn.height + leadingHeaderHeight + (showAvatar ? 14 : 4)

    HoverHandler {
        id: messageHover
    }

    Text {
        visible: root.dateHeader !== ""
        anchors.top: parent.top
        anchors.topMargin: root.unreadDividerHeight + 4
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.dateHeader
        color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.45)
        font.pointSize: 8
        font.bold: true
    }

    Item {
        visible: root.unreadDivider
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.unreadDividerHeight
        z: 2

        Text {
            id: unreadDividerLabel
            anchors.centerIn: parent
            text: L10n.I18n.tr("Новые сообщения")
            color: root.accentColor
            font.pointSize: 8
            font.bold: true
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: unreadDividerLabel.left
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: root.accentColor
            opacity: 0.65
        }

        Rectangle {
            anchors.left: unreadDividerLabel.right
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: root.accentColor
            opacity: 0.65
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.selected
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
            : root.searchHighlighted
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
                : root.awaitingReadReceipt
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.075)
                    : messageHover.hovered && root.controller
                        && !root.controller.multiSelectMode
                        && !root.controller.isDragging
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.06)
                            : "transparent"
        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(80) } }
    }

    Rectangle {
        visible: root.controller ? root.controller.multiSelectMode : false
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        width: 20
        height: 20
        radius: 4
        color: root.selected ? root.accentColor : "transparent"
        border.color: root.selected ? root.accentColor : root.dividerColor
        border.width: 1.5
        Icons.CheckIcon {
            visible: root.selected
            anchors.centerIn: parent
            width: 13
            height: 13
            color: root.accentTextColor
        }
    }

    Text {
        id: compactTimestampText
        visible: !root.systemMessage && messageHover.hovered && root.controller
            && !root.controller.multiSelectMode && !root.controller.isDragging && !root.showAvatar
        text: root.controller ? root.controller.formatCompactTimestamp(root.timestamp) : ""
        color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.35)
        font.pointSize: 7
        anchors.right: messageColumn.left
        anchors.rightMargin: 6
        anchors.top: messageColumn.top
        anchors.topMargin: 2

    }

    AvatarItem {
        id: avatarItem
        visible: root.showAvatar
        x: root.controller && root.controller.multiSelectMode ? 42 : 12
        y: root.leadingHeaderHeight + 10 + (root.replyTo !== "" && !root.systemMessage && !root.contentHidden ? 31 : 0)
        mxcUrl: root.senderAvatarUrl
        fallbackId: root.sender
        mediaProxy: root.mediaProxy
        roundAvatars: root.roundAvatars
        size: 36
        scale: avatarClickArea.pressed ? 0.92 : 1
        Behavior on x { NumberAnimation { duration: L10n.UiPreferences.duration(150); easing.type: Easing.OutCubic } }
        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: avatarClickArea
        visible: root.showAvatar
        x: root.controller && root.controller.multiSelectMode ? 42 : 12
        y: root.leadingHeaderHeight + 10 + (root.replyTo !== "" && !root.systemMessage && !root.contentHidden ? 31 : 0)
        width: 36
        height: 36
        z: 11
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            mouse.accepted = true
            if (root.controller && !root.controller.multiSelectMode) {
                var pt = root.chatViewRoot ? avatarClickArea.mapToItem(root.chatViewRoot, mouse.x, mouse.y) : avatarClickArea.mapToItem(root, mouse.x, mouse.y)
                root.controller.openUserProfile(root.sender, root.currentRoomId, pt.x, pt.y)
            }
        }
        onPressed: function(mouse) {
            mouse.accepted = true
        }
    }

    Column {
        id: messageColumn
        z: root.senderIgnored ? 11
            : root.messageType === "m.audio" || root.messageType === "m.text"
            || root.messageType === "m.notice"
            || root.reactionCount > 0
            || (root.mediaUrl !== "" && root.messageType !== "m.image"
                && root.messageType !== "m.sticker") ? 11 : 0
        x: root.systemMessage ? 12
            : root.controller && root.controller.multiSelectMode ? 88 : 58
        y: root.leadingHeaderHeight + (root.showAvatar ? 10 : 4)
        width: root.systemMessage ? parent.width - 24 : parent.width - x - 12
        spacing: 3
        Behavior on x { NumberAnimation { duration: L10n.UiPreferences.duration(150); easing.type: Easing.OutCubic } }

        ReplyPreview {
            id: replyPreview
            message: root
        }


        Row {
            id: senderMetaRow
            visible: root.showAvatar
            width: parent.width
            spacing: 6
            clip: true

            Text {
                id: senderNameText
                width: Math.min(implicitWidth, Math.max(0,
                    senderMetaRow.width - timestampText.implicitWidth
                    - (editedText.visible ? editedText.implicitWidth + senderMetaRow.spacing : 0)
                    - senderMetaRow.spacing))
                text: root.senderDisplayName !== ""
                    ? root.senderDisplayName : Utils.displayName(root.sender)
                color: Utils.avatarColor(root.sender)
                font.bold: true
                font.pointSize: 10
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                scale: nameMouse.pressed ? 0.92 : 1
                transformOrigin: Item.Left
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
            }

            Text {
                id: editedText
                visible: root.edited
                text: L10n.I18n.tr("(изменено)")
                color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.45)
                font.pointSize: 8
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: timestampText
                text: root.controller ? root.controller.formatTimestamp(root.timestamp) : ""
                color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.35)
                font.pointSize: 7
                anchors.verticalCenter: parent.verticalCenter

            }
        }

        Rectangle {
            visible: root.senderIgnored && !root.systemMessage
            width: Math.min(220, parent.width)
            height: visible ? 32 : 0
            radius: 9
            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.055)
            border.width: 1
            border.color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.13)

            Text {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                text: root.contentHidden ? L10n.I18n.tr("Сообщение скрыто · Показать")
                    : L10n.I18n.tr("Скрыть сообщение")
                color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.58)
                font.pointSize: 8
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.ignoredContentRevealed = !root.ignoredContentRevealed
            }
        }

        Text {
            visible: root.systemMessage
            width: parent.width
            text: L10n.I18n.localizedSystemMessage(root.systemKind, root.body, root.sender)
            horizontalAlignment: Text.AlignHCenter
            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.62)
            font.pointSize: 9
            font.italic: true
            wrapMode: Text.Wrap
        }

        Text {
            visible: root.redacted && !root.contentHidden
            text: L10n.I18n.tr("🗑 Сообщение удалено")
            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.35)
            font.pointSize: 9
            font.italic: true
        }

        Text {
            visible: !root.redacted && root.encrypted && !root.contentHidden
            text: L10n.I18n.tr("🔒 Сообщение зашифровано")
            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.4)
            font.pointSize: 9
            font.italic: true
        }

        Text {
            id: messageText
            visible: !root.systemMessage && !root.redacted && !root.encrypted
                && !root.contentHidden
                && (root.messageType === "m.text" || root.messageType === "m.notice")
                && !root.hasCodeBlocks
            text: Utils.flagStyledText(Utils.linkifiedText(root.body), root.emojiFontFamily, false)
            color: root.noticeMessage ? root.textSecondary : root.messageContentColor
            linkColor: root.sendState === "sending" ? root.messageContentColor : "#4da3ff"
            font.pointSize: 10
            font.italic: root.noticeMessage
            wrapMode: Text.Wrap
            width: parent.width
            textFormat: Text.RichText
            onLinkActivated: function(link) { Qt.openUrlExternally(link) }

            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(120) }
            }

            HoverHandler {
                cursorShape: messageText.hoveredLink !== ""
                    ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }

        CodeMessageBody {
            id: segmentedMessageText
            message: root
        }

        StickerPackCard {
            id: stickerPackCard
            message: root
            messageColumnObject: messageColumn
        }

        ImageAttachment {
            id: imageAttachment
            message: root
            messageColumnObject: messageColumn
        }

        VoiceAttachment {
            id: voiceMessageLoader
            message: root
            messageColumnObject: messageColumn
        }

        Loader {
            id: videoMessageLoader
            readonly property bool isVideoMessage: !root.systemMessage && !root.redacted
                && !root.encrypted && !root.contentHidden && root.videoAttachment
                && !root.pooled
            visible: isVideoMessage
            active: isVideoMessage
            width: Math.min(340, messageColumn.width)
            height: visible ? Math.max(150, Math.min(195, width * 9 / 16)) : 0

            sourceComponent: Component {
        VideoAttachment {
            id: videoBubble
            message: root
        }
            }
        }

        FileAttachment {
            id: fileBubble
            message: root
            messageColumnObject: messageColumn
        }

        Flow {
            id: reactionFlow
            width: parent.width
            visible: !root.systemMessage && !root.redacted && !root.encrypted && !root.contentHidden
                && root.reactionCount > 0
            spacing: 4
            Repeater {
                id: reactionRepeater
                model: root.reactionCount
                delegate: Rectangle {
                    required property int index
                    readonly property var reaction: root.reactionAt(index) || ({})
                    height: 24
                    width: reactionLabel.implicitWidth + 14
                    radius: 8
                    scale: reactionMouse.pressed ? 0.94 : 1
                    color: reaction && reaction.reacted
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        : Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.07)
                    border.width: 1
                    border.color: reaction && reaction.reacted
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.6)
                        : Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.14)
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
                    }
                    Text {
                        id: reactionLabel
                        anchors.centerIn: parent
                        text: ((reaction && reaction.key) || "") + "  "
                            + Number((reaction && reaction.count) || 0)
                        color: root.textPrimary
                        font.pointSize: 9
                    }

                    MouseArea {
                        id: reactionMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.controller || !root.controller.multiSelectMode)
                                root.reactionRequested(reaction)
                        }
                    }
                }
            }
        }
        Rectangle {
            visible: root.threadRootId === "" && root.threadReplyCount > 0
                && !root.systemMessage && !root.redacted
            width: threadLabel.implicitWidth + 20
            height: visible ? 26 : 0
            radius: 8
            color: threadMouse.containsMouse
                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                          root.accentColor.b, 0.16)
                : Qt.rgba(root.accentColor.r, root.accentColor.g,
                          root.accentColor.b, 0.08)
            Text {
                id: threadLabel
                anchors.centerIn: parent
                text: L10n.I18n.tr("Ответы: %1").replace("%1",
                    String(root.threadReplyCount))
                color: root.accentColor
                font.pointSize: 8
                font.bold: true
            }
            MouseArea {
                id: threadMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.threadRequested()
            }
        }
        Row {
            visible: root.sender === root.currentUserId && root.sendState !== "sent"
            spacing: 7
            Text {
                text: root.sendState === "failed"
                    ? L10n.I18n.tr("Не отправлено")
                    : L10n.I18n.tr("Отправляется…")
                color: root.sendState === "failed" ? "#ff6b6b" : root.textSecondary
                font.pointSize: 7
            }
            Text {
                visible: root.sendState === "failed" && root.timelineItemId !== ""
                text: L10n.I18n.tr("Повторить")
                color: root.accentColor
                font.pointSize: 7
                font.underline: sendRetryMouse.containsMouse
                MouseArea {
                    id: sendRetryMouse
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.retryRequested(root.timelineItemId)
                }
                ToolTip.visible: sendRetryMouse.containsMouse && root.sendError !== ""
                ToolTip.text: root.sendError
            }
        }
    }

    // Keep the sender hit area above the row-wide interaction layer.
    Item {
        id: nameClickArea
        visible: root.showAvatar && !root.systemMessage
        z: 11

        x: messageColumn.x + senderMetaRow.x + senderNameText.x
        y: messageColumn.y + senderMetaRow.y + senderNameText.y
        width: senderNameText.width
        height: senderNameText.height

        MouseArea {
            id: nameMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: function(mouse) {
                mouse.accepted = true // Останавливаем всплытие, чтобы не сработал drag

                if (root.controller && !root.controller.multiSelectMode) {
                    var pt = root.chatViewRoot ? nameClickArea.mapToItem(root.chatViewRoot, mouse.x, mouse.y) : nameClickArea.mapToItem(root, mouse.x, mouse.y)
                    root.controller.openUserProfile(root.sender, root.currentRoomId, pt.x, pt.y)
                }
            }
        }
    }

    MouseArea {
        id: interaction
        anchors.fill: parent
        z: 10 // Меньше, чем у nameClickArea и avatar MouseArea
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.controller && root.controller.multiSelectMode ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: !root.systemMessage && !root.contentHidden

        onPressed: function(mouse) {
            root.pressX = mouse.x
            root.pressY = mouse.y
            root.pointerMoved = false
            root.suppressRightContext = false

            if (!root.controller) return

            if (mouse.button === Qt.LeftButton) {
                // A selection drag keeps the mode chosen on press.
                root.controller.beginDrag(root.messageIndex, root.selected, root, mouse.x, mouse.y, Qt.LeftButton)
            }
        }

        onPositionChanged: function(mouse) {
            if (Math.abs(mouse.x - root.pressX) > 6 || Math.abs(mouse.y - root.pressY) > 6) {
                root.pointerMoved = true
            }
            if (root.controller && root.controller.isDragging) {
                root.controller.updateDrag(root.messageIndex, root, mouse.x, mouse.y)
            }
        }

        onReleased: function(mouse) {
            if (root.controller && root.controller.isDragging
                    && mouse.button === root.controller.selectionGestureButton) {
                root.controller.endDrag()
            }
        }

        onCanceled: {
            if (root.controller && root.controller.isDragging)
                root.controller.endDrag()
            root.suppressRightContext = false
        }

        onDoubleClicked: function(mouse) {
            if (mouse.button !== Qt.LeftButton || !root.controller
                    || root.controller.multiSelectMode || root.systemMessage
                    || root.redacted || root.encrypted
                    || root.eventId === ""
                    || root.eventId.indexOf("local:") === 0)
                return
            mouse.accepted = true
            root.controller.finishSelectionGesture()
            root.quickReplyRequested(root.eventId, root.sender, root.body)
        }

        onClicked: function(mouse) {
            if (!root.controller) return

            if (mouse.button === Qt.RightButton) {
                if (root.suppressRightContext) {
                    root.suppressRightContext = false
                    return
                }
                root.controller.openContext(root.messageIndex, {
                    event_id: root.eventId,
                    sender: root.sender,
                    body: root.body,
                    msg_type: root.messageType,
                    timestamp: root.timestamp,
                    is_edited: root.edited,
                    is_redacted: root.redacted,
                    pinned: root.pinned,
                    media_file: root.mediaFile,
                    media_mime_type: root.mediaMimeType,
                    media_url: root.mediaUrl,
                    reactions: root.reactions,
                    read_receipts: root.readReceipts,
                    is_system: root.systemMessage,
                    reply_to: root.replyTo,
                    reply_sender: root.replySender,
                    reply_body: root.replyBody,
                    is_encrypted: root.encrypted,
                    send_state: root.sendState,
                    timeline_item_id: root.timelineItemId,
                    send_error: root.sendError,
                    send_recoverable: root.sendRecoverable,
                    thread_root_id: root.threadRootId,
                    thread_reply_count: root.threadReplyCount
                }, root.selected)
                return
            }

            if (mouse.button !== Qt.LeftButton || root.pointerMoved || root.controller.multiSelectMode || (root.messageType !== "m.image" && root.messageType !== "m.sticker")
                    || root.mediaUrl === "") {
                return
            }

            var imagePosition = interaction.mapToItem(imageAttachment.thumbnailImageObject, mouse.x, mouse.y)
            var insideImage = imagePosition.x >= 0 && imagePosition.y >= 0 && imagePosition.x <= imageAttachment.thumbnailImageObject.width && imagePosition.y <= imageAttachment.thumbnailImageObject.height

            if (insideImage) {
                if (!root.shouldLoadImage) {
                    root.mediaLoadRequested = true
                    return
                }
                if (imageAttachment.thumbnailImageObject.status === Image.Error) {
                    root.mediaRetryToken++
                    return
                }
                root.controller.openImage(root.mediaUrl, root.body,
                                          root.mediaFile, root.mediaMimeType)
            }
        }
    }
}

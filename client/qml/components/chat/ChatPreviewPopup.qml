import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../common"
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils

Basic.Popup {
    id: root

    property string roomId: ""
    property string roomName: ""
    property var messages: []
    property string nextFrom: ""
    property string activeRequestId: ""
    property bool pageLoading: false
    property bool paginationArmed: true
    property int previewSequence: 0
    property string loadError: ""
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    property string currentUserId: ""
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"
    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal pageRequested(string roomId, string from, string requestId)

    function nextPreviewRequestId() {
        previewSequence++
        return Date.now().toString() + "-room-preview-" + previewSequence
    }

    function openForRoom(targetRoomId, targetRoomName, cachedMessages) {
        if (!targetRoomId) return
        roomId = targetRoomId
        roomName = targetRoomName || targetRoomId
        messages = cachedMessages ? cachedMessages.slice(0) : []
        nextFrom = ""
        activeRequestId = ""
        pageLoading = false
        paginationArmed = true
        loadError = ""
        previewMoveArea.resetMotion()
        dragOffsetX = 0
        dragOffsetY = 0
        open()
        requestPage("")
    }

    function requestPage(fromToken) {
        if (!roomId || pageLoading) return
        if (fromToken && fromToken !== nextFrom) return
        pageLoading = true
        loadError = ""
        paginationArmed = false
        var requestId = nextPreviewRequestId()
        activeRequestId = requestId
        pageRequested(roomId, fromToken || "", requestId)
    }

    function requestOlder() {
        if (!pageLoading && paginationArmed && nextFrom)
            requestPage(nextFrom)
    }
    function scrollToBottom() {
        previewScrollAnimation.stop()
        previewScrollAnimation.from = previewList.contentY
        previewScrollAnimation.to = previewList.originY
            + Math.max(0, previewList.contentHeight - previewList.height)
        previewScrollAnimation.start()
    }


    function receivePage(responseRoomId, page, responseNextFrom, append, errorText, requestId) {
        if (!opened || responseRoomId !== roomId || requestId !== activeRequestId) return
        pageLoading = false
        activeRequestId = ""
        loadError = errorText || ""
        if (loadError !== "") {
            paginationArmTimer.restart()
            return
        }

        var incoming = page || []
        var merged = append ? messages.slice(0) : []
        for (var pageIndex = 0; pageIndex < incoming.length; pageIndex++) {
            var candidate = incoming[pageIndex]
            var duplicate = false
            for (var existingIndex = 0; existingIndex < merged.length; existingIndex++) {
                if (merged[existingIndex].event_id === candidate.event_id) {
                    duplicate = true
                    break
                }
            }
            if (!duplicate) merged.push(candidate)
        }

        var previousHeight = previewList.contentHeight
        var previousY = previewList.contentY
        messages = merged
        nextFrom = responseNextFrom || ""
        if (append) {
            Qt.callLater(function() {
                var addedHeight = Math.max(0, previewList.contentHeight - previousHeight)
                previewList.contentY = Math.min(previewList.originY
                    + Math.max(0, previewList.contentHeight - previewList.height),
                    previousY + addedHeight)
            })
        } else {
            Qt.callLater(function() { previewList.positionViewAtBeginning() })
        }
        paginationArmTimer.restart()
        ensureFilledTimer.restart()
    }

    function authorName(message) {
        return message.sender_display_name
            || Utils.displayName(message.sender || "")
    }

    function timestampText(timestamp) {
        return Utils.formatMessageTimestamp(
            Number(timestamp || 0), messageDateFormat, messageTimeFormat,
            L10n.I18n.tr("вчера"))
    }

    function messageText(message) {
        if (message.is_redacted)
            return L10n.I18n.tr("🗑 Сообщение удалено")
        if (message.is_encrypted)
            return L10n.I18n.tr("🔒 Зашифрованное сообщение")
        if (message.is_system)
            return L10n.I18n.localizedSystemMessage(
                message.system_kind || "", message.body || "", message.sender || "")
        if (message.msg_type === "m.sticker")
            return L10n.I18n.tr("Стикер")
        if (message.body)
            return L10n.I18n.localizedMessagePreview(message.body)
        if (message.msg_type === "m.image")
            return L10n.I18n.tr("Изображение")
        if (message.msg_type === "m.audio")
            return L10n.I18n.tr("Голосовое сообщение")
        if (message.msg_type === "m.video")
            return L10n.I18n.tr("Видео")
        return L10n.I18n.tr("Файлы")
    }

    parent: Overlay.overlay
    width: Math.min(520, Math.max(360, parent ? parent.width - 32 : 520))
    height: Math.min(640, Math.max(440, parent ? parent.height - 40 : 640))
    x: parent ? Math.round((parent.width - width) / 2 + dragOffsetX) : 0
    y: parent ? Math.round((parent.height - height) / 2 + dragOffsetY) : 0
    padding: 0
    modal: true
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: previewMoveArea.resetMotion()

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(140) }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: L10n.UiPreferences.duration(160); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(100) }
            NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: L10n.UiPreferences.duration(100) }
        }
    }

    background: Rectangle {
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(previewMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }
        color: root.surfaceColor
        radius: 16
        border.width: 1
        border.color: root.dividerColor
    }

    Timer {
        id: paginationArmTimer
        interval: 220
        onTriggered: root.paginationArmed = true
    }

    Timer {
        id: ensureFilledTimer
        interval: 280
        onTriggered: {
            if (root.opened && root.nextFrom && !root.pageLoading
                    && previewList.contentHeight <= previewList.height)
                root.requestOlder()
        }
    }

    contentItem: Item {
        clip: true
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(previewMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }

        Rectangle {
            id: previewHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 64
            color: root.elevatedColor
            radius: 16

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.radius
                color: parent.color
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.right: closeButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.roomName
                    color: root.textPrimary
                    font.bold: true
                    font.pointSize: 12
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Предпросмотр чата")
                    color: root.textSecondary
                    font.pointSize: 8
                    elide: Text.ElideRight
                }
            }

            PopupMoveArea {
                id: previewMoveArea
                anchors.left: parent.left
                anchors.right: closeButton.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                moveTarget: root
                movementBoundary: root.parent
            }

            Basic.Button {
                id: closeButton
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                padding: 0
                transformOrigin: Item.Center
                scale: down ? 0.86 : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(closeButton.down ? 70 : 130)
                        easing.type: Easing.OutCubic
                    }
                }

                text: "×"
                onClicked: root.close()
                contentItem: Text {
                    text: closeButton.text
                    color: root.textPrimary
                    font.pixelSize: 24
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    transform: Translate {
                        x: 0.5
                        y: -2
                    }
                }
                background: Rectangle {
                    radius: 10
                    color: closeButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                        : closeButton.hovered
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                            : "transparent"
                }
            }
        }

        Rectangle {
            id: unreadNotice
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: previewHeader.bottom
            height: 38
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)

            Text {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                text: L10n.I18n.tr("Предпросмотр не отмечает сообщения как прочитанные")
                color: root.textSecondary
                font.pointSize: 8
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        ListView {
            id: previewList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: unreadNotice.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 8
            clip: true
            model: root.messages
            spacing: 2
            verticalLayoutDirection: ListView.BottomToTop
            boundsBehavior: Flickable.StopAtBounds

            onContentYChanged: {
                if (contentHeight > height && visibleArea.yPosition < 0.08)
                    root.requestOlder()
            }

            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
                trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                    root.textSecondary.b, 0.14)
            }

            delegate: Item {
                id: previewDelegate
                required property var modelData
                property var message: modelData || ({})
                property bool ignoredContentRevealed: false

                width: previewList.width
                height: messageCard.implicitHeight + 6

                Rectangle {
                    id: messageCard
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: messageContent.implicitHeight + 20
                    radius: 11
                    color: message.sender === root.currentUserId
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                        : root.elevatedColor
                    border.width: 1
                    border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                          root.dividerColor.b, 0.75)

                    Column {
                        id: messageContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 5

                        RowLayout {
                            width: parent.width
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: root.authorName(previewDelegate.message)
                                color: root.accentColor
                                font.bold: true
                                font.pointSize: 8
                                elide: Text.ElideRight
                            }
                            Text {
                                text: root.timestampText(previewDelegate.message.timestamp)
                                color: root.textSecondary
                                font.pointSize: 7
                            }
                        }

                        Text {
                            width: parent.width
                            text: previewDelegate.message.sender_is_ignored
                                && !previewDelegate.ignoredContentRevealed
                                ? L10n.I18n.tr("Сообщение скрыто · Показать")
                                : root.messageText(previewDelegate.message)
                            color: previewDelegate.message.sender_is_ignored
                                && !previewDelegate.ignoredContentRevealed
                                ? root.textSecondary : root.textPrimary
                            font.pointSize: 9
                            wrapMode: Text.Wrap
                            maximumLineCount: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: previewDelegate.message.sender_is_ignored
                                && previewDelegate.ignoredContentRevealed
                            text: L10n.I18n.tr("Скрыть сообщение")
                            color: root.accentColor
                            font.pointSize: 8
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !!previewDelegate.message.sender_is_ignored
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: previewDelegate.ignoredContentRevealed =
                            !previewDelegate.ignoredContentRevealed
                    }
                }
            }

            footer: Item {
                width: previewList.width
                height: root.messages.length > 0
                    && (root.pageLoading || root.loadError !== "") ? 42 : 0
                PrismBusyIndicator {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    running: root.pageLoading && parent.height > 0
                    visible: running
                    accentColor: root.accentColor
                    strokeWidth: 2
                }
                Basic.Button {
                    anchors.centerIn: parent
                    visible: root.loadError !== "" && !root.pageLoading
                    text: L10n.I18n.tr("Повторить")
                    onClicked: root.requestPage(root.nextFrom)
                }
            }
        }

        Rectangle {
            id: previewScrollDownButton
            property bool shouldShow: previewList.contentHeight > previewList.height + 2
                && previewList.contentY < previewList.originY
                    + Math.max(0, previewList.contentHeight - previewList.height) - 32

            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18

            width: 42
            height: 42
            radius: width / 2
            z: 30
            opacity: shouldShow ? 1 : 0
            scale: shouldShow ? (previewJumpMouse.pressed ? 0.88 : 1) : 0.86
            visible: shouldShow || opacity > 0.01
            color: previewJumpMouse.containsMouse ? root.accentColor : root.elevatedColor
            border.width: 1
            border.color: previewJumpMouse.containsMouse ? root.accentColor : root.dividerColor

            Behavior on opacity {
                NumberAnimation { duration: L10n.UiPreferences.duration(140) }
            }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(previewJumpMouse.pressed ? 70 : 160); easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: L10n.UiPreferences.duration(100) }
            }

            Canvas {
                id: previewDownArrow
                property real arrowOffsetX: 1
                property real arrowOffsetY: 2
                anchors.centerIn: parent
                width: 18
                height: 18
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = previewJumpMouse.containsMouse
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
                    function onTextPrimaryChanged() { previewDownArrow.requestPaint() }
                    function onAccentTextColorChanged() { previewDownArrow.requestPaint() }
                }
            }

            MouseArea {
                id: previewJumpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: previewDownArrow.requestPaint()
                onClicked: root.scrollToBottom()
            }
        }

        NumberAnimation {
            id: previewScrollAnimation
            target: previewList
            property: "contentY"
            duration: L10n.UiPreferences.duration(260)
            easing.type: Easing.OutCubic
        }

        Column {
            anchors.centerIn: previewList
            spacing: 10
            visible: root.messages.length === 0

            PrismBusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 30
                height: 30
                running: root.pageLoading
                visible: running
                accentColor: root.accentColor
                strokeWidth: 2.2
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(320, previewList.width - 32)
                visible: !root.pageLoading
                text: root.loadError !== ""
                    ? L10n.I18n.tr("Не удалось загрузить предпросмотр")
                    : L10n.I18n.tr("Здесь пока нет сообщений")
                color: root.loadError !== "" ? "#ff6b6b" : root.textSecondary
                font.pointSize: 9
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Basic.Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.loadError !== ""
                text: L10n.I18n.tr("Повторить")
                onClicked: root.requestPage("")
            }
        }
    }
}

import ".." as Chat
import QtQuick
import "../../common"
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtCore
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    required property var composer
    readonly property var root: composer
    required property var emojiPickerLoaderObject
    required property var scheduledMessagesPopupObject
    required property var stickerPickerLoaderObject
    readonly property alias emojiButtonObject: emojiButton
    readonly property alias messageAreaObject: messageArea
    readonly property alias stickerButtonObject: stickerButton
    id: inputBar
    width: parent.width
    height: Math.max(58, Math.min(messageArea.implicitHeight + 26, 150))
    color: root.backgroundColor

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        color: root.surfaceColor
        radius: 12
        border.color: messageArea.activeFocus
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
            : Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.65)
        border.width: 1
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 3

            Basic.Button {
                id: attachmentButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                enabled: root.currentRoomId !== ""
                hoverEnabled: true
                scale: down ? 0.88 : 1
                padding: 0
                contentItem: Item {
                    implicitWidth: 20
                    implicitHeight: 20

                    Icons.PaperclipIcon {
                        anchors.centerIn: parent
                        width: 19
                        height: 19
                        color: attachmentButton.down || attachmentButton.hovered
                            ? root.textPrimary : root.iconColor
                        Behavior on color {
                            ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                        }
                    }
                }
                flat: true
                onClicked: {
                    if (root.currentRoomId !== "") {
                        root.openAttachmentDialog()
                    }
                }
                background: Rectangle {
                    color: attachmentButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        : attachmentButton.hovered
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                            : "transparent"
                    radius: 8
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
            }
            Basic.Button {
                id: stickerButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                enabled: root.currentRoomId !== ""
                hoverEnabled: true
                scale: down ? 0.88 : 1
                padding: 0
                flat: true

                contentItem: Item {
                    Canvas {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        property color strokeColor: stickerButton.down || stickerButton.hovered
                            ? root.textPrimary : root.iconColor
                        onStrokeColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = strokeColor
                            ctx.fillStyle = strokeColor
                            ctx.lineWidth = 1.4
                            ctx.lineJoin = "round"
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(3, 2)
                            ctx.lineTo(17, 2)
                            ctx.lineTo(17, 12)
                            ctx.lineTo(11, 18)
                            ctx.lineTo(3, 18)
                            ctx.closePath()
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(11, 18)
                            ctx.lineTo(11, 12)
                            ctx.lineTo(17, 12)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(7.2, 8.1, 0.8, 0, Math.PI * 2)
                            ctx.arc(12.7, 8.1, 0.8, 0, Math.PI * 2)
                            ctx.fill()
                            ctx.beginPath()
                            ctx.arc(10, 8.8, 3.3, Math.PI * 0.25, Math.PI * 0.75)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                PrismToolTip {
                    visible: stickerButton.hovered
                        && !(stickerPickerLoaderObject.item && stickerPickerLoaderObject.item.opened)
                    text: L10n.I18n.tr("Стикеры")
                    surfaceColor: root.elevatedColor
                    textColor: root.textPrimary
                    dividerColor: root.dividerColor
                }

                background: Rectangle {
                    radius: 8
                    color: stickerButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.20)
                        : stickerButton.hovered
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.10)
                            : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: L10n.UiPreferences.duration(110) }
                    }
                }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
                onClicked: {
                    if (root.currentRoomId !== "")
                        root.toggleStickerPicker()
                }
            }
            Basic.Button {
                id: emojiButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                enabled: root.currentRoomId !== ""
                padding: 0
                hoverEnabled: true
                scale: down ? 0.88 : 1
                property color iconColor: down
                    ? root.textPrimary
                    : hovered ? root.textPrimary : root.iconColor

                contentItem: Item {
                    Canvas {
                        id: emojiIcon
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        property color strokeColor: emojiButton.iconColor

                        onStrokeColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = strokeColor
                            ctx.fillStyle = strokeColor
                            ctx.lineWidth = 1.4
                            ctx.lineCap = "round"

                            ctx.beginPath()
                            ctx.arc(10, 10, 8, 0, Math.PI * 2)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(7.3, 8.2, 0.9, 0, Math.PI * 2)
                            ctx.fill()
                            ctx.beginPath()
                            ctx.arc(12.7, 8.2, 0.9, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(10, 10.3, 4.2, Math.PI * 0.22, Math.PI * 0.78)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                ToolTip {
                    id: emojiToolTip
                    visible: emojiButton.hovered
                        && !(emojiPickerLoaderObject.item && emojiPickerLoaderObject.item.opened)
                    text: L10n.I18n.tr("Эмодзи")
                    delay: 300
                    timeout: 2500
                    y: -height - 4
                    x: Math.round((emojiButton.width - width) / 2)
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 7
                    bottomPadding: 7
                    contentItem: Text {
                        text: emojiToolTip.text
                        color: root.textPrimary
                        font.pointSize: 8
                    }
                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                              root.dividerColor.b, 0.72)
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: emojiButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                        : emojiButton.hovered
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                            : "transparent"
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
                onClicked: {
                    root.toggleEmojiPicker()
                }
            }
            Basic.TextArea {
                id: messageArea
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                placeholderText: root.voiceRecording
                    ? L10n.I18n.tr("Запись • ") + root.formatVoiceDuration(root.voiceDurationMs)
                    : L10n.I18n.tr("Написать сообщение...")
                placeholderTextColor: root.voiceRecording ? "#ff6b6b" : root.textSecondary
                color: "transparent"
                cursorDelegate: Rectangle {
                    width: 1
                    radius: 0.5
                    color: "white"
                    visible: messageArea.activeFocus && root.caretBlinkVisible
                }
                background: Rectangle { color: "transparent" }
                font.pointSize: 10
                wrapMode: TextArea.Wrap
                selectByMouse: true
                persistentSelection: true
                topPadding: 10
                bottomPadding: 10
                leftPadding: 2
                rightPadding: 2
                readOnly: root.voiceRecording

                Text {
                    id: messageTextOverlay
                    z: -0.5
                    x: messageArea.leftPadding
                    y: messageArea.topPadding
                    width: Math.max(0, messageArea.width - messageArea.leftPadding - messageArea.rightPadding)
                    height: Math.max(0, messageArea.height - messageArea.topPadding - messageArea.bottomPadding)
                    visible: messageArea.text !== ""
                    text: Utils.flagStyledText(messageArea.text, root.emojiFontFamily, true)
                    textFormat: Text.RichText
                    color: root.textPrimary
                    font.pointSize: messageArea.font.pointSize
                    wrapMode: Text.Wrap
                }

                onTextChanged: {
                    if (!root.voiceRecording && text.trim() !== "")
                        root.microphoneMode = false
                    root.saveCurrentDraft()
                    root.refreshTypingState()
                }

                onActiveFocusChanged: root.refreshTypingState()

                onCursorPositionChanged: {
                    if (!root.restoringDraft)
                        root.saveCurrentDraft()
                }

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if ((event.modifiers & Qt.ControlModifier)
                                && (event.modifiers & Qt.ShiftModifier)) {
                            event.accepted = true
                            root.openScheduledMessages()
                        } else if (event.modifiers & Qt.ShiftModifier)
                            event.accepted = false
                        else {
                            event.accepted = true
                            root.submit()
                        }
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                        event.accepted = true
                        root.requestClipboardPaste()
                    } else {
                        event.accepted = false
                    }
                }
            }

            Basic.Button {
                id: scheduleButton
                Layout.preferredWidth: 30
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                enabled: root.currentRoomId !== ""
                hoverEnabled: true
                padding: 0
                flat: true
                scale: down ? 0.88 : 1

                contentItem: Item {
                    Icons.ClockIcon {
                        anchors.centerIn: parent
                        width: 19
                        height: 19
                        color: scheduleButton.down || scheduleButton.hovered
                            ? root.textPrimary : root.iconColor
                        Behavior on color {
                            ColorAnimation {
                                duration: L10n.UiPreferences.duration(100)
                            }
                        }
                    }

                    Rectangle {
                        visible: root.currentRoomScheduledMessages.length > 0
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: Math.max(13, scheduledCount.implicitWidth + 5)
                        height: 13
                        radius: 6.5
                        color: root.accentColor

                        Text {
                            id: scheduledCount
                            anchors.centerIn: parent
                            text: root.currentRoomScheduledMessages.length > 9
                                ? "9+" : String(root.currentRoomScheduledMessages.length)
                            color: root.accentTextColor
                            font.pixelSize: 8
                            font.bold: true
                        }
                    }
                }

                PrismToolTip {
                    visible: scheduleButton.hovered
                        && !scheduledMessagesPopupObject.opened
                    text: L10n.I18n.tr("Отложенная отправка")
                        + " · Ctrl+Shift+Enter"
                    surfaceColor: root.elevatedColor
                    textColor: root.textPrimary
                    dividerColor: root.dividerColor
                }

                onClicked: root.openScheduledMessages()

                background: Rectangle {
                    radius: 8
                    color: scheduleButton.down
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.20)
                        : scheduleButton.hovered
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.10)
                            : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: L10n.UiPreferences.duration(110)
                        }
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(100)
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Basic.Button {
                id: sendButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                enabled: root.currentRoomId !== ""
                hoverEnabled: true
                padding: 0
                property bool pointerPressed: false
                scale: pointerPressed ? 0.88 : 1
                flat: true

                contentItem: Item {
                    Icons.SendIcon {
                        visible: !root.microphoneVisible
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        color: sendButton.pointerPressed || sendButton.hovered
                            ? root.textPrimary : root.iconColor
                        Behavior on color {
                            ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                        }
                    }

                    Canvas {
                        id: microphoneIcon
                        visible: root.microphoneVisible
                        anchors.centerIn: parent
                        width: 20
                        height: 22
                        property color strokeColor: root.voiceRecording
                            ? "#ff5a5f" : root.iconColor

                        onStrokeColorChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = strokeColor
                            ctx.lineWidth = 1.5
                            ctx.lineCap = "round"

                            ctx.beginPath()
                            ctx.moveTo(10, 2)
                            ctx.bezierCurveTo(8.3, 2, 7, 3.3, 7, 5)
                            ctx.lineTo(7, 10)
                            ctx.bezierCurveTo(7, 11.7, 8.3, 13, 10, 13)
                            ctx.bezierCurveTo(11.7, 13, 13, 11.7, 13, 10)
                            ctx.lineTo(13, 5)
                            ctx.bezierCurveTo(13, 3.3, 11.7, 2, 10, 2)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.moveTo(4.5, 9)
                            ctx.quadraticCurveTo(4.5, 16, 10, 16)
                            ctx.quadraticCurveTo(15.5, 16, 15.5, 9)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(10, 16)
                            ctx.lineTo(10, 20)
                            ctx.moveTo(7, 20)
                            ctx.lineTo(13, 20)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                ToolTip {
                    id: sendToolTip
                    visible: sendButton.hovered && !sendButton.pointerPressed
                    text: root.microphoneVisible
                        ? L10n.I18n.tr("Удерживайте для записи")
                        : root.hasDraftContent ? L10n.I18n.tr("Отправить") : L10n.I18n.tr("Включить микрофон")
                    delay: 350
                    timeout: 2500
                    y: -height - 4
                    x: Math.round((sendButton.width - width) / 2)
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 7
                    bottomPadding: 7
                    contentItem: Text {
                        text: sendToolTip.text
                        color: root.textPrimary
                        font.pointSize: 8
                    }
                    background: Rectangle {
                        radius: 8
                        color: root.elevatedColor
                        border.width: 1
                        border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                              root.dividerColor.b, 0.72)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: 20
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onPressed: function(mouse) {
                        sendButton.pointerPressed = true
                        if (root.microphoneVisible) {
                            root.voiceGestureConsumed = true
                            root.voicePressStartedAt = Date.now()
                            root.startVoiceRecording()
                        } else {
                            root.voiceGestureConsumed = false
                        }
                        mouse.accepted = true
                    }

                    onReleased: function(mouse) {
                        sendButton.pointerPressed = false
                        if (root.voiceGestureConsumed) {
                            var heldMs = Date.now() - root.voicePressStartedAt
                            if (heldMs >= 500)
                                root.stopVoiceRecording()
                            else {
                                root.cancelVoiceRecording()
                                root.microphoneMode = false
                            }
                            root.voiceGestureConsumed = false
                        } else if (root.hasDraftContent) {
                            root.submit()
                        } else {
                            root.microphoneMode = true
                        }
                        mouse.accepted = true
                    }

                    onCanceled: {
                        sendButton.pointerPressed = false
                        if (root.voiceGestureConsumed)
                            root.cancelVoiceRecording()
                        root.voiceGestureConsumed = false
                    }
                }

                background: Rectangle {
                    color: root.voiceRecording
                        ? Qt.rgba(1, 0.28, 0.30, 0.18)
                        : sendButton.pointerPressed
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.20)
                            : sendButton.hovered
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.12)
                                : "transparent"
                    radius: 8
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }
            }
        }
    }
}

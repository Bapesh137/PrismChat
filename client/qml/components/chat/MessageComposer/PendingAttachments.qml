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
    id: pendingAttachmentBar
    width: parent.width
    height: root.hasPendingAttachment ? 92 : 0
    visible: root.hasPendingAttachment
    color: root.backgroundColor
    clip: true

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.top: parent.top
        anchors.topMargin: 4
        text: root.attachmentSummary()
        color: root.textSecondary
        font.pointSize: 8
        font.bold: true
    }

    ListView {
        id: attachmentStrip
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 25
        anchors.bottomMargin: 5
        orientation: ListView.Horizontal
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.pendingAttachments
        interactive: contentWidth > width + 2

        WheelHandler {
            id: attachmentWheelHandler
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: function(event) {
                var maximumX = Math.max(0, attachmentStrip.contentWidth - attachmentStrip.width)
                if (maximumX <= 0) {
                    event.accepted = false
                    return
                }

                var delta = 0
                if (event.pixelDelta.x !== 0)
                    delta = -event.pixelDelta.x
                else if (event.pixelDelta.y !== 0)
                    delta = -event.pixelDelta.y
                else if (event.angleDelta.x !== 0)
                    delta = -event.angleDelta.x / 120 * 110
                else
                    delta = -event.angleDelta.y / 120 * 110

                attachmentStrip.contentX = Math.max(0, Math.min(maximumX,
                    attachmentStrip.contentX + delta))
                event.accepted = true
            }
        }

        delegate: Rectangle {
            required property var modelData
            required property int index

            width: Math.min(250, Math.max(190, attachmentStrip.width - 8))
            height: attachmentStrip.height
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                  root.dividerColor.b, 0.68)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 9

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: 8
                    clip: true
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                   root.accentColor.b, 0.10)

                    Image {
                        anchors.fill: parent
                        visible: !!modelData.image
                        source: modelData.source || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Canvas {
                        id: pendingAudioIcon
                        visible: !!modelData.audio
                        anchors.centerIn: parent
                        width: 20
                        height: 22

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = root.accentColor
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

                    Icons.PaperclipIcon {
                        visible: !modelData.image && !modelData.audio
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        color: root.iconColor
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: modelData.name || L10n.I18n.tr("Вложение")
                        color: root.textPrimary
                        font.bold: true
                        font.pointSize: 9
                        elide: Text.ElideMiddle
                    }
                    Text {
                        width: parent.width
                        text: root.pendingAttachments.length > 1
                            ? L10n.I18n.tr("Вложение ") + (index + 1) + L10n.I18n.tr(" из ") + root.pendingAttachments.length
                            : L10n.I18n.tr("Будет отправлено по нажатию на самолётик")
                        color: root.textSecondary
                        font.pointSize: 7
                        elide: Text.ElideRight
                    }
                }

                Basic.Button {
                    id: removeAttachmentButton
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    Layout.alignment: Qt.AlignVCenter
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.82 : 1

                    contentItem: Icons.CloseIcon {
                        rotation: removeAttachmentButton.hovered ? 90 : 0
                        color: removeAttachmentButton.down || removeAttachmentButton.hovered
                            ? root.iconColor : root.textSecondary
                        Behavior on rotation {
                            NumberAnimation { duration: L10n.UiPreferences.duration(130); easing.type: Easing.OutCubic }
                        }
                    }

                    background: Rectangle {
                        radius: 8
                        color: removeAttachmentButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.18)
                            : removeAttachmentButton.hovered
                                ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                          root.textPrimary.b, 0.08)
                                : "transparent"
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                    }
                    onClicked: root.removePendingAttachment(index)
                }
            }
        }
    }
}

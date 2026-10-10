import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Rectangle {
    required property var message
    readonly property var root: message
    required property var messageColumnObject
    id: fileBubble
    visible: !root.systemMessage && !root.redacted && !root.encrypted && !root.contentHidden
        && !root.videoAttachment
        && root.messageType !== "m.image" && root.messageType !== "m.sticker"
        && root.messageType !== "m.text" && root.messageType !== "m.audio"
    width: Math.min(300, messageColumnObject.width)
    height: 58
    radius: 12
    scale: fileMouse.pressed ? 0.97 : 1
    color: fileMouse.pressed
        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
        : fileMouse.containsMouse
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.09)
    border.width: 1
    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                          root.accentColor.b, 0.22)

    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
    Behavior on scale {
        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 9
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 10
            color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                           root.accentColor.b, 0.13)

            Canvas {
                anchors.centerIn: parent
                width: 20
                height: 22
                antialiasing: true
                property color iconColor: root.accentColor
                onIconColorChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = iconColor
                    ctx.lineWidth = 1.4
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.moveTo(4, 1.5)
                    ctx.lineTo(12.5, 1.5)
                    ctx.lineTo(17, 6)
                    ctx.lineTo(17, 20.5)
                    ctx.lineTo(4, 20.5)
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(12.5, 1.5)
                    ctx.lineTo(12.5, 6)
                    ctx.lineTo(17, 6)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(10.5, 8.5)
                    ctx.lineTo(10.5, 15)
                    ctx.moveTo(7.5, 12.5)
                    ctx.lineTo(10.5, 15.5)
                    ctx.lineTo(13.5, 12.5)
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.body || L10n.I18n.tr("Вложение")
                color: root.textPrimary
                font.pointSize: 9
                font.bold: true
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                text: root.messageType === "m.video" ? L10n.I18n.tr("Открыть видео")
                    : root.messageType === "m.file" ? L10n.I18n.tr("Открыть файл")
                    : L10n.I18n.tr("Открыть вложение")
                color: root.mediaUrl !== "" ? "#4da3ff"
                    : Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                              root.textPrimary.b, 0.42)
                font.pointSize: 8
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: fileMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.mediaUrl !== ""
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.messageType === "m.file") {
                if (root.controller)
                    root.controller.downloadFile(root.mediaUrl, root.body,
                                                 root.mediaFile, root.mediaMimeType)
                return
            }
            if (root.messageType === "m.video") {
                root.videoOpenRequested({
                    event_id: root.eventId,
                    title: root.body,
                    media_url: root.mediaUrl,
                    media_file: root.mediaFile,
                    media_mime_type: root.mediaMimeType
                })
                return
            }
            var source = Utils.proxyUrl(root.mediaUrl, root.mediaProxy,
                                        root.mediaFile, root.mediaMimeType)
            Qt.openUrlExternally(source)
        }
    }
}

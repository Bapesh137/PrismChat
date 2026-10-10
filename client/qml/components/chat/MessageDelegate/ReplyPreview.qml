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
    required property var message
    readonly property var root: message
    id: replyPreview
    visible: root.replyTo !== "" && !root.systemMessage && !root.contentHidden
    width: parent.width
    height: visible ? 28 : 0

    MouseArea {
        anchors.fill: parent
        z: 2
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.controller)
                root.controller.jumpToReply(root.replyTo)
        }
    }

    Canvas {
        id: replyConnector
        objectName: "replyConnector"
        x: root.replyConnectorStartX - 1
        y: 0
        width: 26 - x
        height: root.replyConnectorStartY + 1

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onTextPrimaryChanged() { replyConnector.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.28)
            ctx.lineWidth = 1.5
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(1, height - 1)
            ctx.lineTo(1, 20)
            ctx.quadraticCurveTo(1, 14, 7, 14)
            ctx.lineTo(7 + Math.max(0, width - 8) / 2, 14)
            ctx.stroke()
        }
    }

    Row {
        x: replyConnector.x + 10 + Math.max(0, replyConnector.width - 8) / 2
        width: parent.width - x
        height: parent.height
        spacing: 6
        clip: true

        Text {
            id: replySenderText
            width: Math.min(implicitWidth, parent.width * 0.4)
            text: root.replySender !== ""
                ? (root.replySenderDisplayName !== ""
                    ? root.replySenderDisplayName : Utils.displayName(root.replySender))
                : L10n.I18n.tr("Сообщение")
            color: root.replySender !== "" ? Utils.avatarColor(root.replySender) : root.textPrimary
            font.bold: true
            font.pointSize: 8
            elide: Text.ElideRight
            maximumLineCount: 1
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignVCenter
            height: parent.height
        }

        Text {
            width: Math.max(0, parent.width - replySenderText.width - parent.spacing)
            height: parent.height
            text: Utils.singleLinePreview(
                root.replyBody !== ""
                    ? L10n.I18n.localizedMessagePreview(root.replyBody)
                    : L10n.I18n.tr("Исходное сообщение не загружено"))
            textFormat: Text.PlainText
            color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.52)
            font.pointSize: 8
            elide: Text.ElideRight
            maximumLineCount: 1
            wrapMode: Text.NoWrap
            verticalAlignment: Text.AlignVCenter
            clip: true
        }
    }
}

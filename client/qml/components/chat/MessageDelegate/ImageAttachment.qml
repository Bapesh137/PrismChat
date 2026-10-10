import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Column {
    required property var message
    readonly property var root: message
    required property var messageColumnObject
    readonly property alias thumbnailImageObject: thumbnailImage
    id: imageAttachment
    visible: !root.systemMessage && !root.redacted && !root.encrypted
        && !root.contentHidden
        && (root.messageType === "m.image" || root.messageType === "m.sticker")
    spacing: 4
    AnimatedImage {
        id: thumbnailImage
        source: (root.messageType === "m.image" || root.messageType === "m.sticker")
                && !root.contentHidden && root.shouldLoadImage
            ? Utils.withRetryToken(
                Utils.proxyUrl(root.mediaUrl, root.mediaProxy,
                               root.mediaFile, root.mediaMimeType),
                root.mediaRetryToken) : ""
        width: Math.min(root.messageType === "m.sticker" ? 240 : 300, messageColumnObject.width)
        height: status === Image.Ready && sourceSize.width > 0
            ? Math.min(root.messageType === "m.sticker" ? 240 : 260,
                       width * sourceSize.height / sourceSize.width)
            : width * 0.6
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignLeft
        asynchronous: true
        playing: root.messageType === "m.sticker" && visible

        Rectangle {
            visible: thumbnailImage.status === Image.Loading
            anchors.fill: parent
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
            radius: 8

            PrismBusyIndicator {
                running: parent.visible
                accentColor: root.accentColor
                anchors.centerIn: parent
                width: 32
                height: 32
            }
        }

        Rectangle {
            visible: !root.shouldLoadImage && root.mediaUrl !== ""
            anchors.fill: parent
            color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                           root.accentColor.b, 0.08)
            radius: 8
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                  root.accentColor.b, 0.22)

            Text {
                anchors.centerIn: parent
                width: parent.width - 24
                text: root.messageType === "m.sticker"
                    ? L10n.I18n.tr("Нажмите, чтобы загрузить стикер")
                    : L10n.I18n.tr("Нажмите, чтобы загрузить изображение")
                color: root.textPrimary
                font.pointSize: 8
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Rectangle {
            visible: root.shouldLoadImage
                && (thumbnailImage.status === Image.Error || root.mediaUrl === "")
            anchors.fill: parent
            color: Qt.rgba(1, 0.32, 0.32, 0.10)
            radius: 8

            Column {
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 8

                Text {
                    width: parent.width
                    text: root.messageType === "m.sticker"
                        ? L10n.I18n.tr("Не удалось загрузить стикер")
                        : L10n.I18n.tr("Не удалось загрузить изображение")
                    color: "#ff6b6b"
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: retryImageLabel.implicitWidth + 22
                    height: 28
                    radius: 8
                    color: Qt.rgba(root.accentColor.r,
                                   root.accentColor.g,
                                   root.accentColor.b, 0.16)
                    border.width: 1
                    border.color: Qt.rgba(root.accentColor.r,
                                          root.accentColor.g,
                                          root.accentColor.b, 0.46)
                    Text {
                        id: retryImageLabel
                        anchors.centerIn: parent
                        text: L10n.I18n.tr("Повторить")
                        color: root.accentColor
                        font.pointSize: 8
                        font.bold: true
                    }
                }
            }
        }
    }
    Text {
        visible: root.messageType === "m.image"
        text: root.body
        color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.5)
        font.pointSize: 8
        wrapMode: Text.Wrap
        width: messageColumnObject.width
    }
}

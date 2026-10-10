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
    id: stickerPackCard
    visible: !root.systemMessage && !root.redacted && !root.encrypted
        && !root.contentHidden && root.messageType === "org.prismchat.sticker_pack"
        && !!root.stickerPack
    width: Math.min(320, messageColumnObject.width)
    height: visible ? 154 : 0
    radius: 14
    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
    border.width: 1
    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)

    Column {
        anchors.fill: parent
        anchors.margins: 11
        spacing: 7

        Row {
            width: parent.width
            spacing: 8
            Text {
                width: parent.width - installPackButton.width - 10
                text: String((root.stickerPack || {}).display_name || L10n.I18n.tr("Набор стикеров"))
                color: root.textPrimary
                font.pointSize: 10
                font.bold: true
                elide: Text.ElideRight
            }
            Basic.Button {
                id: installPackButton
                width: 92
                height: 30
                padding: 0
                hoverEnabled: true
                scale: down ? 0.92 : 1.0
                onClicked: root.stickerPackInstallRequested(root.stickerPack)
                contentItem: Text {
                    text: L10n.I18n.tr("Установить")
                    color: root.accentColor
                    font.pointSize: 8
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 9
                    color: installPackButton.down ? Qt.rgba(0,0,0,0.25)
                        : installPackButton.hovered ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13)
                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.07)
                    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                }
                Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
            }
        }

        Row {
            spacing: 5
            Repeater {
                model: Math.min(4, ((root.stickerPack || {}).images || []).length)
                delegate: Rectangle {
                    required property int index
                    width: 55
                    height: 55
                    radius: 9
                    color: Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.04)
                    property var stickerData: ((root.stickerPack || {}).images || [])[index] || ({})
                    AnimatedImage {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: Utils.proxyUrl(parent.stickerData.media_url || "", root.mediaProxy,
                                               undefined, parent.stickerData.media_mime_type || "image/webp")
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        playing: visible
                    }
                }
            }
        }

        Text {
            text: L10n.I18n.tr("Стикеров: ") + String(((root.stickerPack || {}).images || []).length)
            color: root.textSecondary
            font.pointSize: 7.5
        }
    }
}

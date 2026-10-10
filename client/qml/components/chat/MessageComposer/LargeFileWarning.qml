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

Basic.Popup {
    required property var composer
    readonly property var root: composer
    id: largeFileWarningDialog
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: Basic.Popup.CloseOnEscape
        | Basic.Popup.CloseOnPressOutside
    width: Math.min(420, parent ? parent.width - 32 : 420)
    padding: 18
    property string filename: ""
    property double fileSize: 0

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.48)
    }
    background: Rectangle {
        radius: 14
        color: root.elevatedColor
        border.width: 1
        border.color: root.dividerColor
    }
    contentItem: Column {
        spacing: 12

        Text {
            width: parent.width
            text: L10n.I18n.tr("Отправить большой файл?")
            color: root.textPrimary
            font.pointSize: 13
            font.bold: true
        }
        Text {
            width: parent.width
            text: largeFileWarningDialog.filename + " · "
                + root.formatBytes(largeFileWarningDialog.fileSize)
                + "\n" + L10n.I18n.tr(
                    "Загрузка может занять много времени и использовать дополнительную память.")
            color: root.textSecondary
            font.pointSize: 9
            wrapMode: Text.Wrap
        }
        Row {
            anchors.right: parent.right
            spacing: 8

            Basic.Button {
                width: 92
                height: 36
                text: L10n.I18n.tr("Отмена")
                onClicked: largeFileWarningDialog.close()
                contentItem: Text {
                    text: parent.text
                    color: root.textPrimary
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 9
                    color: parent.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                  root.textPrimary.b, 0.08)
                        : "transparent"
                }
            }
            Basic.Button {
                width: 108
                height: 36
                text: L10n.I18n.tr("Отправить")
                onClicked: {
                    largeFileWarningDialog.close()
                    root.submit(true)
                }
                contentItem: Text {
                    text: parent.text
                    color: root.accentTextColor
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 9
                    color: parent.down
                        ? Qt.darker(root.accentColor, 1.12)
                        : root.accentColor
                }
            }
        }
    }
}

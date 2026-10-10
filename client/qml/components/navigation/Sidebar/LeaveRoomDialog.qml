import ".." as Navigation
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Basic.Dialog {
    required property var sidebar
    readonly property var root: sidebar
    id: leaveConfirmDialog
    property string roomId: ""
    property string roomName: ""
    property bool isSpace: false
    parent: Overlay.overlay
    modal: true
    dim: true
    padding: 0
    width: 380
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    closePolicy: Popup.CloseOnEscape
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(45) }
            NumberAnimation { property: "scale"; from: 0.985; to: 1; duration: L10n.UiPreferences.duration(55); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(35) }
    }

    background: Rectangle {
        radius: 12
        color: root.surfaceColor
        border.color: Qt.rgba(1, 0.35, 0.35, 0.35)
        border.width: 1
    }

    contentItem: Item {
        implicitHeight: leaveConfirmContent.implicitHeight + 40

        Column {
            id: leaveConfirmContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Item {
                width: parent.width
                height: 34
                Canvas {
                    anchors.centerIn: parent
                    width: 28; height: 28
                    onPaint: root.drawIcon(getContext("2d"), "leave", "#ff6b6b", width, height)
                }
            }
            Text {
                width: parent.width
                text: leaveConfirmDialog.isSpace
                    ? L10n.I18n.tr("Покинуть пространство?")
                    : L10n.I18n.tr("Покинуть комнату?")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 14
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: leaveConfirmDialog.isSpace
                    ? L10n.I18n.tr("Пространство исчезнет из списка, но входящие в него комнаты останутся доступными, если вы состоите в них.")
                    : L10n.I18n.tr("Вы больше не будете получать сообщения из «") + leaveConfirmDialog.roomName + "»."
                color: root.textSecondary
                font.pointSize: 9
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
            Row {
                width: parent.width
                spacing: 10
                Basic.Button {
                    id: cancelLeaveButton
                    width: (parent.width - 10) / 2; height: 36; text: L10n.I18n.tr("Отмена")
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.96 : 1
                    onClicked: leaveConfirmDialog.close()
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic } }
                    background: Rectangle {
                        radius: 7
                        color: cancelLeaveButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : cancelLeaveButton.hovered
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                                : root.elevatedColor
                        border.width: 1
                        border.color: cancelLeaveButton.hovered || cancelLeaveButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.38)
                            : Qt.rgba(root.dividerColor.r, root.dividerColor.g, root.dividerColor.b, 0.7)
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                        Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    }
                    contentItem: Text { text: parent.text; color: root.textPrimary; font.pointSize: 9; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
                Basic.Button {
                    id: confirmLeaveButton
                    width: (parent.width - 10) / 2; height: 36; text: L10n.I18n.tr("Покинуть")
                    padding: 0
                    hoverEnabled: true
                    scale: down ? 0.96 : 1
                    onClicked: { leaveConfirmDialog.close(); root.leaveRoomRequested(leaveConfirmDialog.roomId) }
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic } }
                    background: Rectangle {
                        radius: 7
                        color: confirmLeaveButton.down ? "#a9252a"
                            : confirmLeaveButton.hovered ? "#ee4d50" : "#d83c3e"
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                    }
                    contentItem: Text { text: parent.text; color: "white"; font.bold: true; font.pointSize: 9; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
        }
    }
}

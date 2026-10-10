import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../utils" as L10n

Basic.Popup {
    id: root

    property var device: null
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"


    signal verifyRequested()
    signal renameRequested()
    signal detailsRequested()
    signal signOutRequested()

    function toggle(anchorItem) {
        if (root.opened) {
            root.close()
            return
        }
        root.show(anchorItem)
    }

    function show(anchorItem) {
        if (!anchorItem)
            return
        root.parent = anchorItem
        root.x = anchorItem.width - root.width
        root.y = anchorItem.height + 4
        root.open()
    }

    parent: Overlay.overlay
    width: 204
    height: menuColumn.implicitHeight + 12
    padding: 6
    margins: 8
    modal: false
    dim: false
    focus: true
    popupType: Basic.Popup.Item
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside

    background: Rectangle {
        radius: 10
        color: root.elevatedColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                              root.textSecondary.b, 0.20)
    }

    contentItem: Column {
        id: menuColumn
        width: root.availableWidth
        spacing: 2

        Basic.Button {
            id: verifyItem
            visible: root.device && root.device.can_verify
            width: parent.width
            height: visible ? 34 : 0
            text: L10n.I18n.tr("Подтвердить")
            hoverEnabled: true
            onClicked: {
                root.close()
                root.verifyRequested()
            }
            contentItem: Text {
                text: verifyItem.text
                color: root.textPrimary
                font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 7
                color: verifyItem.hovered
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                              root.textPrimary.b, 0.08)
                    : "transparent"
            }
        }

        Basic.Button {
            id: renameItem
            visible: root.device && root.device.can_rename
            width: parent.width
            height: visible ? 34 : 0
            text: L10n.I18n.tr("Переименовать")
            hoverEnabled: true
            scale: renameItem.down ? 0.96 : 1
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
            }
            onClicked: {
                root.close()
                root.renameRequested()
            }
            contentItem: Text {
                text: renameItem.text
                color: root.textPrimary
                font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 7
                color: renameItem.down || renameItem.hovered
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                              root.textPrimary.b, renameItem.down ? 0.16 : 0.08)
                    : "transparent"
                Behavior on color {
                    ColorAnimation { duration: L10n.UiPreferences.duration(90) }
                }
            }
        }

        Basic.Button {
            id: detailsItem
            width: parent.width
            height: 34
            text: L10n.I18n.tr("Подробнее")
            hoverEnabled: true
            scale: detailsItem.down ? 0.96 : 1
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
            }
            onClicked: {
                root.close()
                root.detailsRequested()
            }
            contentItem: Text {
                text: detailsItem.text
                color: root.textPrimary
                font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 7
                color: detailsItem.down || detailsItem.hovered
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                              root.textPrimary.b, detailsItem.down ? 0.16 : 0.08)
                    : "transparent"
                Behavior on color {
                    ColorAnimation { duration: L10n.UiPreferences.duration(90) }
                }
            }
        }

        Rectangle {
            visible: root.device && root.device.can_sign_out
            width: parent.width
            height: visible ? 1 : 0
            color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                           root.textSecondary.b, 0.16)
        }

        Basic.Button {
            id: logoutItem
            visible: root.device && root.device.can_sign_out
            width: parent.width
            height: visible ? 34 : 0
            text: L10n.I18n.tr("Выйти на этом устройстве")
            hoverEnabled: true
            onClicked: {
                root.close()
                root.signOutRequested()
            }
            contentItem: Text {
                text: logoutItem.text
                color: "#ff7777"
                font.pointSize: 8
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 7
                color: logoutItem.hovered
                    ? Qt.rgba(1, 0.3, 0.3, 0.11)
                    : "transparent"
            }
        }
    }
}

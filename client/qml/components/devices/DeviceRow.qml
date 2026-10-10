import QtQuick
import QtQuick.Controls
import "../../utils" as L10n
import "../common"

Rectangle {
    id: root
    property var device: null
    property bool selected: false
    property bool expanded: false
    property bool operationBusy: false
    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal selectionToggled()
    signal verifyRequested()
    signal renameRequested()
    signal signOutRequested()
    signal copyRequested(string text)

    function openDeviceMenu() {
        if (contextMenu.opened) {
            contextMenu.close()
            return
        }
        if (!Overlay.overlay) return
        var point = menuButton.mapToItem(Overlay.overlay, 0,
                                         menuButton.height + 4)
        var menuWidth = Math.max(contextMenu.implicitWidth,
                                 contextMenu.width)
        var menuHeight = Math.max(contextMenu.implicitHeight,
                                  contextMenu.height)
        contextMenu.x = Math.max(8, Math.min(
            Overlay.overlay.width - menuWidth - 8,
            point.x + menuButton.width - menuWidth))
        contextMenu.y = Math.max(8, Math.min(
            Overlay.overlay.height - menuHeight - 8, point.y))
        contextMenu.open()
    }

    width: parent ? parent.width : 520
    implicitHeight: header.height + (expanded ? detailsWrap.height + 10 : 0)
    radius: 9
    color: rowMouse.containsMouse ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.045) : root.surfaceColor
    border.width: selected ? 1 : 0
    border.color: root.accentColor

    Item {
        id: header
        width: parent.width; height: 66

        Rectangle {
            id: selector
            visible: root.device && !root.device.is_current
            anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 5
            color: root.selected ? root.accentColor : "transparent"
            border.width: 1; border.color: root.selected ? root.accentColor : root.textSecondary
            Canvas {
                id: selectionMark
                anchors.centerIn: parent
                width: 12
                height: 12
                visible: root.selected
                antialiasing: true
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = "#071007"
                    ctx.lineWidth = 1.8
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(2.0, 6.2)
                    ctx.lineTo(4.8, 8.8)
                    ctx.lineTo(10.0, 3.5)
                    ctx.stroke()
                }
            }
            MouseArea { anchors.fill: parent; enabled: !root.operationBusy; cursorShape: Qt.PointingHandCursor; onClicked: root.selectionToggled() }
        }

        Canvas {
            id: deviceIcon
            anchors.left: selector.visible ? selector.right : parent.left
            anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; antialiasing: true
            property color iconColor: root.textSecondary
            onIconColorChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.clearRect(0, 0, width, height)
                c.strokeStyle = iconColor; c.lineWidth = 1.7; c.lineCap = "round"; c.lineJoin = "round"
                c.beginPath(); c.rect(5, 4, 20, 17); c.stroke()
                c.beginPath(); c.moveTo(10, 26); c.lineTo(20, 26); c.moveTo(15, 21); c.lineTo(15, 26); c.stroke()
            }
        }

        Column {
            anchors.left: deviceIcon.right; anchors.leftMargin: 12
            anchors.right: menuButton.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter; spacing: 3
            Text { width: parent.width; elide: Text.ElideRight; text: root.device ? (root.device.display_name || L10n.I18n.tr("Устройство без названия")) : ""; color: root.textPrimary; font.pointSize: 9; font.bold: true }
            Text { visible: root.device && root.device.last_seen_ts; width: parent.width; elide: Text.ElideRight; text: L10n.I18n.tr("Последняя активность: ") + new Date(Number(root.device.last_seen_ts)).toLocaleString(Qt.locale()); color: root.textSecondary; font.pointSize: 7 }
            DeviceSecurityBadge { verificationState: root.device ? root.device.verification_state : "unknown"; accentColor: root.accentColor; textSecondary: root.textSecondary }
        }

        Rectangle {
            id: menuButton
            anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 8
            scale: menuMouse.pressed ? 0.88 : 1
            color: menuMouse.pressed
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
                : menuMouse.containsMouse
                    ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                    : "transparent"
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
            Text {
                anchors.centerIn: parent
                visible: !root.operationBusy
                text: "⋮"
                color: menuMouse.containsMouse ? root.textPrimary : root.textSecondary
                font.pointSize: 15
                Behavior on color {
                    ColorAnimation { duration: L10n.UiPreferences.duration(100) }
                }
            }
            PrismBusyIndicator { anchors.centerIn: parent; visible: root.operationBusy; running: visible; width: 16; height: 16; accentColor: root.accentColor }
            MouseArea {
                id: menuMouse
                anchors.fill: parent
                enabled: !root.operationBusy
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openDeviceMenu()
            }
        }
        MouseArea { id: rowMouse; anchors.left: deviceIcon.left; anchors.right: menuButton.left; anchors.top: parent.top; anchors.bottom: parent.bottom; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.expanded = !root.expanded }
    }

    Item {
        id: detailsWrap
        visible: root.expanded
        anchors.top: header.bottom; anchors.left: parent.left; anchors.right: parent.right
        height: details.implicitHeight + 12
        DeviceDetails { id: details; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 14; device: root.device; accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; onCopyRequested: function(value) { root.copyRequested(value) } }
    }

    DeviceContextMenu {
        id: contextMenu
        parent: Overlay.overlay
        device: root.device
        elevatedColor: root.elevatedColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        onVerifyRequested: root.verifyRequested()
        onRenameRequested: root.renameRequested()
        onDetailsRequested: root.expanded = true
        onSignOutRequested: root.signOutRequested()
    }
}

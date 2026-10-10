import QtQuick
import QtQuick.Controls.Basic as Basic
import "../utils" as L10n

Basic.Button {
    id: root

    property color accentColor: "#20D500"
    property color surfaceColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property bool primary: false
    property bool destructive: false
    property bool softPress: false

    height: 36
    leftPadding: 14
    rightPadding: 14
    hoverEnabled: true
    scale: down ? (softPress ? 0.96 : 0.95) : hovered && enabled && !softPress ? 1.015 : 1

    function blend(base: color, overlay: color, amount: real): color {
        var a = Math.max(0, Math.min(1, Number(amount || 0)))
        return Qt.rgba(base.r * (1 - a) + overlay.r * a,
                       base.g * (1 - a) + overlay.g * a,
                       base.b * (1 - a) + overlay.b * a, 1)
    }

    contentItem: Text {
        text: root.text
        color: !root.enabled ? root.textSecondary
            : root.destructive ? "#ff7777"
            : root.primary ? "#071007" : root.textPrimary
        font.pointSize: 8
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 8
        color: !root.enabled ? root.blend(root.surfaceColor, root.textSecondary, 0.06)
            : root.primary ? (root.down ? root.blend(root.accentColor, softPress ? "#ffffff" : "#000000", softPress ? 0.18 : 0.16)
                                          : root.hovered ? (root.softPress ? root.blend(root.accentColor, "#ffffff", 0.10) : Qt.lighter(root.accentColor, 1.28))
                                                         : root.accentColor)
            : root.down ? root.blend(root.surfaceColor, root.accentColor, 0.22)
            : root.hovered ? root.blend(root.surfaceColor, root.accentColor, 0.11)
                           : root.surfaceColor
        border.width: root.primary ? 0 : 1
        border.color: root.destructive ? Qt.rgba(1, 0.35, 0.35, 0.55)
            : Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                      root.textSecondary.b, 0.18)
        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
    }

    Behavior on scale {
        NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic }
    }
}

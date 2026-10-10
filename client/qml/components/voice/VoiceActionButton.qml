import QtQuick
import QtQuick.Controls.Basic as Basic
import "../common"
import "../../utils" as L10n

Basic.Button {
    id: root

    property color accentColor: "#20D500"
    property color surfaceColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    property bool primary: false
    property bool destructive: false
    property bool selected: false
    property bool flatVisual: false
    property bool changePrimaryColorOnPress: true
    property string toolTipText: ""
    property Component iconComponent: null
    readonly property color foregroundColor: !enabled ? textSecondary
        : destructive ? "#ff7777"
        : primary ? (0.2126 * accentColor.r + 0.7152 * accentColor.g + 0.0722 * accentColor.b > 0.55
                     ? "#101710" : "#ffffff")
        : selected ? accentColor : textPrimary

    implicitWidth: Math.max(40, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: 42
    leftPadding: 14
    rightPadding: 14
    topPadding: 7
    bottomPadding: 7
    hoverEnabled: true
    transformOrigin: Item.Center
    scale: down ? 0.92 : hovered && enabled ? 1.025 : 1

    Behavior on scale {
        NumberAnimation {
            duration: L10n.UiPreferences.duration(down ? 70 : 110)
            easing.type: Easing.OutCubic
        }
    }

    // Keep the hit rectangle fixed throughout a press/release.
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.48
    Accessible.name: toolTipText || text
    HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

    PrismToolTip {
        visible: root.hovered && root.toolTipText !== ""
        text: root.toolTipText
        surfaceColor: root.surfaceColor
        textColor: root.textPrimary
        dividerColor: root.dividerColor
    }

    function blend(base, overlay, amount) {
        var a = Math.max(0, Math.min(1, Number(amount || 0)))
        return Qt.rgba(base.r * (1 - a) + overlay.r * a,
                       base.g * (1 - a) + overlay.g * a,
                       base.b * (1 - a) + overlay.b * a, 1)
    }

    contentItem: Item {
        implicitWidth: root.iconComponent ? 20 : label.implicitWidth
        implicitHeight: 20
        Loader {
            anchors.centerIn: parent
            width: 20; height: 20
            sourceComponent: root.iconComponent
        }
        Text {
            id: label
            anchors.fill: parent
            visible: !root.iconComponent
            text: root.text
            color: root.foregroundColor
            font.pointSize: 9
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    background: Rectangle {
        radius: 12
        color: {
            if (root.flatVisual) {
                if (root.down)
                    return Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                if (root.hovered && root.enabled)
                    return Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.08)
                return "transparent"
            }
            if (!root.enabled)
                return root.blend(root.surfaceColor, root.textSecondary, 0.06)
            if (root.primary) {
                if (root.down && root.changePrimaryColorOnPress)
                    return root.blend(root.accentColor, "#000000", 0.16)
                if (root.hovered)
                    return Qt.lighter(root.accentColor, 1.28)
                return root.accentColor
            }
            if (root.destructive) {
                if (root.down)
                    return Qt.rgba(1, 0.28, 0.28, 0.20)
                if (root.hovered)
                    return Qt.rgba(1, 0.28, 0.28, 0.12)
                return Qt.rgba(1, 0.28, 0.28, 0.06)
            }
            if (root.down)
                return root.blend(root.surfaceColor, root.accentColor, 0.22)
            if (root.hovered)
                return root.blend(root.surfaceColor, root.accentColor, 0.11)
            if (root.selected)
                return root.blend(root.surfaceColor, root.accentColor, 0.14)
            return root.surfaceColor
        }
        border.width: root.visualFocus ? 2 : root.flatVisual || root.primary ? 0 : 1
        border.color: root.visualFocus ? root.accentColor : root.destructive
            ? Qt.rgba(1, 0.35, 0.35, root.hovered ? 0.40 : 0.22)
            : root.selected
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.42)
                : Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                          root.textSecondary.b, root.hovered ? 0.30 : 0.18)

        Behavior on color {
            ColorAnimation { duration: L10n.UiPreferences.duration(110) }
        }
        Behavior on border.color {
            ColorAnimation { duration: L10n.UiPreferences.duration(110) }
        }
    }

    Behavior on opacity {
        NumberAnimation { duration: L10n.UiPreferences.duration(90) }
    }
}

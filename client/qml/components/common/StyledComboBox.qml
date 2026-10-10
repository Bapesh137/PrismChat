import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../assets/icons" as Icons

Basic.ComboBox {
    id: root

    property color accentColor: "#20D500"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"

    implicitWidth: 170
    implicitHeight: 36
    font.pointSize: 9
    leftPadding: 12
    rightPadding: 34
    hoverEnabled: true
    scale: down ? 0.94 : 1

    Behavior on scale {
        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
    }

    delegate: Basic.ItemDelegate {
        id: itemDelegate
        width: root.width
        height: 34
        highlighted: root.highlightedIndex === index
        hoverEnabled: true
        scale: down ? 0.97 : 1

        Behavior on scale {
            NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
        }

        contentItem: Text {
            text: root.textAt(index)
            color: itemDelegate.highlighted ? root.accentColor : root.textPrimary
            font: root.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            leftPadding: 8
            rightPadding: 8
        }

        background: Rectangle {
            radius: 7
            color: itemDelegate.down
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
                : itemDelegate.highlighted
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                    : itemDelegate.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                        : "transparent"
            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
        }
    }

    indicator: Icons.ChevronIcon {
        width: 12
        height: 12
        direction: "right"
        strokeWidth: 1.5
        rotation: root.popup.visible ? 90 : 0
        transformOrigin: Item.Center
        color: root.enabled ? root.accentColor : root.textSecondary
        anchors.right: parent.right
        anchors.rightMargin: 11
        anchors.verticalCenter: parent.verticalCenter

        Behavior on rotation {
            NumberAnimation {
                duration: L10n.UiPreferences.duration(140)
                easing.type: Easing.OutCubic
            }
        }
    }

    contentItem: Text {
        text: root.displayText
        color: root.textPrimary
        font: root.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        leftPadding: root.leftPadding
        rightPadding: root.rightPadding
    }

    background: Rectangle {
        radius: 8
        color: root.down
            ? Qt.darker(root.surfaceColor, 1.22)
            : root.hovered
                ? Qt.darker(root.surfaceColor, 1.10)
                : root.surfaceColor
        border.width: 1
        border.color: root.activeFocus || root.down
            ? root.accentColor
            : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.20)
        Behavior on color {
            ColorAnimation { duration: L10n.UiPreferences.duration(110) }
        }
    }

    popup: Basic.Popup {
        y: root.height + 5
        width: root.width
        padding: 4
        implicitHeight: Math.min(popupList.contentHeight + topPadding + bottomPadding, 190)

        background: Rectangle {
            radius: 10
            color: root.elevatedColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.20)
        }

        contentItem: ListView {
            id: popupList
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            highlightMoveDuration: 0
            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
                trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                    root.textSecondary.b, 0.14)
            }
        }
    }
}

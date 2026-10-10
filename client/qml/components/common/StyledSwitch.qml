import QtQuick
import "../../utils" as L10n

Rectangle {
    id: root

    property bool checked: false
    property color accentColor: "#20D500"
    property color inactiveColor: "#7A8A7D"
    readonly property bool hovered: switchMouse.containsMouse
    signal toggled()

    implicitWidth: 44
    implicitHeight: 24
    radius: height / 2
    opacity: enabled ? 1.0 : 0.4
    scale: switchMouse.pressed ? 0.90 : 1
    color: checked ? accentColor : Qt.rgba(inactiveColor.r, inactiveColor.g, inactiveColor.b, 0.5)

    Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(150) } }
    Behavior on scale {
        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
    }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        Behavior on x {
            NumberAnimation { duration: L10n.UiPreferences.duration(150); easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: switchMouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked
            root.toggled()
        }
    }
}

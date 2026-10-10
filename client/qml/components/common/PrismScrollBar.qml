import QtQuick
import "../../utils" as L10n
import QtQuick.Controls.Basic as Basic

Basic.ScrollBar {
    id: control

    property color handleColor: "#657A69"
    property color handleHoverColor: "#20D500"
    property color trackColor: "#18261C"

    // Автоматическое скрытие отключено по умолчанию.
    property bool autoHide: false

    // Время до исчезновения после ухода мыши.
    property int autoHideDelay: 2500

    property bool revealed: true

    orientation: Qt.Vertical
    policy: Basic.ScrollBar.AsNeeded

    width: 9
    padding: 3
    minimumSize: 0.08
    hoverEnabled: true

    opacity: !autoHide || revealed || hovered || pressed ? 1.0 : 0.0

    function showTemporarily() {
        revealed = true

        if (autoHide && !hovered && !pressed)
            hideTimer.restart()
    }

    function scheduleHide() {
        if (!autoHide || hovered || pressed)
            return

        hideTimer.restart()
    }

    onHoveredChanged: {
        if (hovered) {
            revealed = true
            hideTimer.stop()
        } else {
            scheduleHide()
        }
    }

    onPressedChanged: {
        if (pressed) {
            revealed = true
            hideTimer.stop()
        } else {
            scheduleHide()
        }
    }

    property bool revealOnActive: false

    onActiveChanged: {
    if (revealOnActive && active)
        showTemporarily()
}

    onAutoHideChanged: {
        hideTimer.stop()
        revealed = true

        if (autoHide)
            scheduleHide()
    }

    Component.onCompleted: {
        if (autoHide)
            scheduleHide()
    }

    Timer {
        id: hideTimer

        interval: control.autoHideDelay
        repeat: false

        onTriggered: {
            if (!control.hovered && !control.pressed)
                control.revealed = false
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: L10n.UiPreferences.duration(180)
            easing.type: Easing.OutQuad
        }
    }

    background: Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter

        width: 4
        height: parent.height
        radius: width / 2

        color: control.trackColor
        opacity: 0.7
    }

    contentItem: Rectangle {
        implicitWidth: 6
        radius: width / 2

        color: control.pressed || control.hovered
            ? control.handleHoverColor
            : control.handleColor

        opacity: control.active || control.hovered ? 1.0 : 0.82

        Behavior on color {
            ColorAnimation {
                duration: L10n.UiPreferences.duration(100)
            }
        }
    }
}

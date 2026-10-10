import QtQuick
import QtQuick.Controls.Basic as Basic
import "../../utils" as L10n

Basic.Button {
    id: control

    property color accentColor: "#20D500"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"

    implicitWidth: 34
    implicitHeight: 34
    width: implicitWidth
    height: implicitHeight
    padding: 0
    hoverEnabled: true
    scale: down ? 0.86 : 1

    Behavior on scale {
        NumberAnimation {
            duration: L10n.UiPreferences.duration(100)
            easing.type: Easing.OutCubic
        }
    }

    contentItem: Item {
        Canvas {
            id: crossCanvas
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 1
            width: 16
            height: 16
            antialiasing: true
            property color strokeColor: control.hovered
                ? control.textPrimary : control.textSecondary

            onStrokeColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = strokeColor
                ctx.lineWidth = 1.4
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(3, 3)
                ctx.lineTo(13, 13)
                ctx.moveTo(13, 3)
                ctx.lineTo(3, 13)
                ctx.stroke()
            }
        }
    }

    background: Rectangle {
        radius: 11
        color: control.down
            ? Qt.rgba(control.accentColor.r, control.accentColor.g,
                      control.accentColor.b, 0.18)
            : control.hovered
                ? Qt.rgba(control.textPrimary.r, control.textPrimary.g,
                          control.textPrimary.b, 0.08)
                : "transparent"

        Behavior on color {
            ColorAnimation { duration: L10n.UiPreferences.duration(100) }
        }
    }
}

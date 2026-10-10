import QtQuick
import QtQuick.Controls.Basic as Basic
import "../../utils" as L10n
import "../../assets/icons" as Icons

Basic.Button {
    id: control

    property string iconKind: ""
    property color accentColor: "#20D500"
    property color textColor: "#F2FFF4"
    property color dangerColor: "#ff5252"
    property bool destructive: false
    property bool showArrow: false
    property bool expanded: false

    implicitWidth: 232
    implicitHeight: 38
    width: parent ? parent.width : implicitWidth
    height: visible ? implicitHeight : 0
    padding: 0
    hoverEnabled: true
    scale: down ? 0.97 : 1
    opacity: enabled ? 1 : 0.38

    Behavior on scale {
        NumberAnimation {
            duration: L10n.UiPreferences.duration(90)
            easing.type: Easing.OutCubic
        }
    }

    contentItem: Item {
        Canvas {
            id: actionIcon
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            property color drawColor: control.destructive
                ? control.dangerColor : control.accentColor

            onDrawColorChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = drawColor
                ctx.fillStyle = drawColor
                ctx.lineWidth = 1.6
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                if (control.iconKind === "reaction") {
                    ctx.beginPath()
                    ctx.arc(10, 10, 7, 0, Math.PI * 2)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(7.5, 8, 0.8, 0, Math.PI * 2)
                    ctx.arc(12.5, 8, 0.8, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.beginPath()
                    ctx.arc(10, 10.5, 3.5, 0.2, Math.PI - 0.2)
                    ctx.stroke()
                } else if (control.iconKind === "reply") {
                    ctx.beginPath()
                    ctx.moveTo(9, 5)
                    ctx.lineTo(4, 10)
                    ctx.lineTo(9, 15)
                    ctx.moveTo(4, 10)
                    ctx.lineTo(11.5, 10)
                    ctx.quadraticCurveTo(16, 10, 17, 15)
                    ctx.stroke()
                } else if (control.iconKind === "copy") {
                    ctx.strokeRect(6, 5, 10, 12)
                    ctx.beginPath()
                    ctx.moveTo(4, 14)
                    ctx.lineTo(3, 14)
                    ctx.lineTo(3, 3)
                    ctx.lineTo(13, 3)
                    ctx.lineTo(13, 4)
                    ctx.stroke()
                } else if (control.iconKind === "link") {
                    ctx.beginPath()
                    ctx.arc(7, 10, 4.2, -Math.PI * 0.72, Math.PI * 0.72)
                    ctx.moveTo(13, 10)
                    ctx.arc(13, 10, 4.2, Math.PI * 0.28, Math.PI * 1.72)
                    ctx.moveTo(7.5, 10)
                    ctx.lineTo(12.5, 10)
                    ctx.stroke()
                } else if (control.iconKind === "source") {
                    ctx.beginPath()
                    ctx.moveTo(7.5, 5)
                    ctx.lineTo(3, 10)
                    ctx.lineTo(7.5, 15)
                    ctx.moveTo(12.5, 5)
                    ctx.lineTo(17, 10)
                    ctx.lineTo(12.5, 15)
                    ctx.moveTo(11.5, 3.5)
                    ctx.lineTo(8.5, 16.5)
                    ctx.stroke()
                } else if (control.iconKind === "pin") {
                    ctx.beginPath()
                    ctx.moveTo(5, 4)
                    ctx.lineTo(15, 4)
                    ctx.lineTo(13, 9)
                    ctx.lineTo(16, 12)
                    ctx.lineTo(11, 12)
                    ctx.lineTo(10, 18)
                    ctx.lineTo(9, 12)
                    ctx.lineTo(4, 12)
                    ctx.lineTo(7, 9)
                    ctx.closePath()
                    ctx.stroke()
                } else if (control.iconKind === "edit") {
                    ctx.beginPath()
                    ctx.moveTo(4, 16)
                    ctx.lineTo(5.5, 11.5)
                    ctx.lineTo(13.5, 3.5)
                    ctx.lineTo(16.5, 6.5)
                    ctx.lineTo(8.5, 14.5)
                    ctx.closePath()
                    ctx.moveTo(5.5, 11.5)
                    ctx.lineTo(8.5, 14.5)
                    ctx.stroke()
                } else if (control.iconKind === "delete") {
                    ctx.beginPath()
                    ctx.moveTo(4, 6)
                    ctx.lineTo(16, 6)
                    ctx.moveTo(7, 6)
                    ctx.lineTo(8, 3.5)
                    ctx.lineTo(12, 3.5)
                    ctx.lineTo(13, 6)
                    ctx.moveTo(6, 8)
                    ctx.lineTo(7, 17)
                    ctx.lineTo(13, 17)
                    ctx.lineTo(14, 8)
                    ctx.moveTo(9, 9)
                    ctx.lineTo(9, 14.5)
                    ctx.moveTo(11, 9)
                    ctx.lineTo(11, 14.5)
                    ctx.stroke()
                } else if (control.iconKind === "unread") {
                    ctx.beginPath()
                    ctx.arc(10, 10, 7, 0, Math.PI * 2)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(10, 10, 2.2, 0, Math.PI * 2)
                    ctx.fill()
                } else if (control.iconKind === "readers") {
                    ctx.beginPath()
                    ctx.moveTo(2.5, 10)
                    ctx.quadraticCurveTo(6.2, 5.1, 10, 5.1)
                    ctx.quadraticCurveTo(13.8, 5.1, 17.5, 10)
                    ctx.quadraticCurveTo(13.8, 14.9, 10, 14.9)
                    ctx.quadraticCurveTo(6.2, 14.9, 2.5, 10)
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(10, 10, 2.4, 0, Math.PI * 2)
                    ctx.stroke()
                } else if (control.iconKind === "download") {
                    ctx.beginPath()
                    ctx.moveTo(10, 3)
                    ctx.lineTo(10, 13)
                    ctx.moveTo(6, 10)
                    ctx.lineTo(10, 14)
                    ctx.lineTo(14, 10)
                    ctx.moveTo(4, 17)
                    ctx.lineTo(16, 17)
                    ctx.stroke()
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 39
            anchors.right: arrow.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: control.text
            color: control.destructive ? control.dangerColor : control.textColor
            font.pointSize: 9
            elide: Text.ElideRight
        }

        Icons.ChevronIcon {
            id: arrow
            visible: control.showArrow
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: control.textColor
            width: 18
            height: 18
            direction: "right"
            rotation: control.expanded ? 90 : 0
            Behavior on rotation {
                NumberAnimation {
                    duration: L10n.UiPreferences.duration(110)
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    background: Rectangle {
        radius: 7
        color: control.down
            ? (control.destructive
                ? Qt.rgba(1, 0.32, 0.32, 0.25)
                : Qt.rgba(control.accentColor.r, control.accentColor.g,
                          control.accentColor.b, 0.23))
            : control.hovered
                ? (control.destructive
                    ? Qt.rgba(1, 0.32, 0.32, 0.15)
                    : Qt.rgba(control.accentColor.r, control.accentColor.g,
                              control.accentColor.b, 0.12))
                : "transparent"
        Behavior on color {
            ColorAnimation { duration: L10n.UiPreferences.duration(100) }
        }
    }
}

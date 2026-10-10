import QtQuick
import "../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

Basic.Button {
    id: root

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"

    implicitWidth: 32
    implicitHeight: 32
    flat: true
    hoverEnabled: true
    scale: down ? 0.88 : 1

    ToolTip {
        id: settingsToolTip
        visible: root.hovered
        text: L10n.I18n.tr("Настройки")
        delay: 300
        timeout: 3000
        x: Math.round((root.width - width) / 2)
        y: -height - 4
        leftPadding: 10
        rightPadding: 10
        topPadding: 7
        bottomPadding: 7

        contentItem: Text {
            text: settingsToolTip.text
            color: root.textPrimary
            font.pointSize: 8
        }

        background: Rectangle {
            radius: 8
            color: root.elevatedColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.38)
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(110) }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(90) }
        }
    }

    contentItem: Item {
        implicitWidth: 20
        implicitHeight: 20

        Canvas {
            id: gear
            width: 20
            height: 20
            anchors.centerIn: parent
            property color gearColor: root.down || root.hovered
                ? root.textPrimary : root.iconColor
            Behavior on gearColor {
                ColorAnimation { duration: L10n.UiPreferences.duration(100) }
            }

            onGearColorChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cx = width / 2
                var cy = height / 2
                var teeth = 8
                var step = Math.PI * 2 / teeth
                var outerRadius = 9
                var rootRadius = 6

                ctx.fillStyle = gearColor
                ctx.beginPath()
                for (var i = 0; i < teeth; i++) {
                    var centerAngle = i * step - Math.PI / 2
                    var angles = [
                        centerAngle - step * 0.42,
                        centerAngle - step * 0.22,
                        centerAngle + step * 0.22,
                        centerAngle + step * 0.42
                    ]
                    var radiuses = [rootRadius, outerRadius, outerRadius, rootRadius]
                    for (var j = 0; j < angles.length; j++) {
                        var x = cx + Math.cos(angles[j]) * radiuses[j]
                        var y = cy + Math.sin(angles[j]) * radiuses[j]
                        if (i === 0 && j === 0)
                            ctx.moveTo(x, y)
                        else
                            ctx.lineTo(x, y)
                    }
                }
                ctx.closePath()
                ctx.fill()

                ctx.globalCompositeOperation = "destination-out"
                ctx.beginPath()
                ctx.arc(cx, cy, 3.2, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalCompositeOperation = "source-over"
            }
        }
    }

    background: Rectangle {
        radius: 16
        color: root.down
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.20)
            : root.hovered
                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                : "transparent"
        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
    }

    Behavior on scale {
        NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
    }
}

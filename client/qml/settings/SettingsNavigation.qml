import QtQuick
import "../utils" as L10n
import QtQuick.Controls
import "../components/common"

Rectangle {
    id: root

    property int currentTab: 0
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property var moveTarget: null
    property Item movementBoundary: null
    readonly property real moveShearAngle: moveArea.visualShearAngle

    signal tabSelected(int tabIndex)
    signal logoutRequested()

    implicitWidth: 180
    implicitHeight: navigationColumn.implicitHeight + 20
    color: elevatedColor
    radius: 14

    function tabLabel(i) {
        return [L10n.I18n.tr("Профиль"), L10n.I18n.tr("Внешний вид"), L10n.I18n.tr("Язык"), L10n.I18n.tr("Шифрование"), L10n.I18n.tr("Устройства"), L10n.I18n.tr("Уведомления"), L10n.I18n.tr("Хранилище"), L10n.I18n.tr("О программе"), L10n.I18n.tr("Приватность")][i]
    }

    function tabIcon(i) {
        return ["profile", "appearance", "language", "encryption", "devices", "notifications", "storage", "about", "privacy"][i]
    }

    function resetMoveMotion() { moveArea.resetMotion() }

    Rectangle {
        width: 14
        height: parent.height
        color: parent.color
        anchors.right: parent.right
    }

    Column {
        id: navigationColumn
        x: 10
        y: 10
        width: parent.width - 20
        spacing: 3

        Item {
            width: parent.width
            height: 28

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.I18n.tr("Настройки")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 11
            }

            PopupMoveArea {
                id: moveArea
                anchors.fill: parent
                moveTarget: root.moveTarget
                movementBoundary: root.movementBoundary
                enabled: root.moveTarget !== null && root.movementBoundary !== null
            }
        }

        Repeater {
            model: 9

            delegate: Rectangle {
                id: tabItem
                width: parent.width
                height: 34
                radius: 8
                scale: tabMouse.pressed ? 0.97 : 1

                color: tabMouse.pressed
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.24)
                    : root.currentTab === index
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                        : tabMouse.containsMouse
                            ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06)
                            : "transparent"

                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 12
                    spacing: 8

                    Item {
                        width: 18
                        height: 18
                        anchors.verticalCenter: parent.verticalCenter

                        Canvas {
                            id: navIcon
                            anchors.fill: parent
                            antialiasing: true

                            property color iconColor: root.currentTab === index
                                ? root.iconColor
                                : Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.88)

                            onIconColorChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)

                                var w = width
                                var h = height
                                var cx = w / 2
                                var cy = h / 2
                                var s = Math.min(w, h)

                                ctx.strokeStyle = iconColor
                                ctx.fillStyle = iconColor
                                ctx.lineWidth = 1.35
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"

                                function circle(x, y, r, fill) {
                                    ctx.beginPath()
                                    ctx.arc(x, y, r, 0, Math.PI * 2)
                                    if (fill) ctx.fill()
                                    else ctx.stroke()
                                }

                                function line(x1, y1, x2, y2) {
                                    ctx.beginPath()
                                    ctx.moveTo(x1, y1)
                                    ctx.lineTo(x2, y2)
                                    ctx.stroke()
                                }

                                function roundedRect(x, y, ww, hh, rr, fill) {
                                    rr = Math.min(rr, ww / 2, hh / 2)
                                    ctx.beginPath()
                                    ctx.moveTo(x + rr, y)
                                    ctx.lineTo(x + ww - rr, y)
                                    ctx.quadraticCurveTo(x + ww, y, x + ww, y + rr)
                                    ctx.lineTo(x + ww, y + hh - rr)
                                    ctx.quadraticCurveTo(x + ww, y + hh, x + ww - rr, y + hh)
                                    ctx.lineTo(x + rr, y + hh)
                                    ctx.quadraticCurveTo(x, y + hh, x, y + hh - rr)
                                    ctx.lineTo(x, y + rr)
                                    ctx.quadraticCurveTo(x, y, x + rr, y)
                                    if (fill) ctx.fill()
                                    else ctx.stroke()
                                }

                                var kind = root.tabIcon(index)

                                if (kind === "profile") {
                                    circle(cx, s * 0.34, s * 0.16, false)
                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.22, s * 0.80)
                                    ctx.quadraticCurveTo(cx, s * 0.56, s * 0.78, s * 0.80)
                                    ctx.stroke()
                                } else if (kind === "appearance") {
                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.26, s * 0.28)
                                    ctx.quadraticCurveTo(s * 0.52, s * 0.12, s * 0.74, s * 0.28)
                                    ctx.quadraticCurveTo(s * 0.90, s * 0.42, s * 0.78, s * 0.60)
                                    ctx.quadraticCurveTo(s * 0.70, s * 0.70, s * 0.58, s * 0.66)
                                    ctx.quadraticCurveTo(s * 0.48, s * 0.63, s * 0.44, s * 0.70)
                                    ctx.quadraticCurveTo(s * 0.38, s * 0.84, s * 0.24, s * 0.76)
                                    ctx.quadraticCurveTo(s * 0.12, s * 0.68, s * 0.14, s * 0.52)
                                    ctx.quadraticCurveTo(s * 0.16, s * 0.38, s * 0.26, s * 0.28)
                                    ctx.stroke()

                                    circle(s * 0.36, s * 0.38, s * 0.035, true)
                                    circle(s * 0.53, s * 0.30, s * 0.035, true)
                                    circle(s * 0.67, s * 0.40, s * 0.035, true)
                                } else if (kind === "language") {
                                    circle(cx, cy, s * 0.34, false)

                                    ctx.beginPath()
                                    ctx.moveTo(cx, s * 0.16)
                                    ctx.bezierCurveTo(s * 0.34, s * 0.16, s * 0.34, s * 0.84, cx, s * 0.84)
                                    ctx.bezierCurveTo(s * 0.66, s * 0.84, s * 0.66, s * 0.16, cx, s * 0.16)
                                    ctx.stroke()

                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.18, cy)
                                    ctx.lineTo(s * 0.82, cy)
                                    ctx.stroke()

                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.24, s * 0.34)
                                    ctx.quadraticCurveTo(cx, s * 0.44, s * 0.76, s * 0.34)
                                    ctx.stroke()

                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.24, s * 0.66)
                                    ctx.quadraticCurveTo(cx, s * 0.56, s * 0.76, s * 0.66)
                                    ctx.stroke()
                                } else if (kind === "encryption") {
                                    roundedRect(s * 0.24, s * 0.42, s * 0.52, s * 0.38, s * 0.10, false)

                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.34, s * 0.42)
                                    ctx.lineTo(s * 0.34, s * 0.32)
                                    ctx.quadraticCurveTo(s * 0.34, s * 0.18, cx, s * 0.18)
                                    ctx.quadraticCurveTo(s * 0.66, s * 0.18, s * 0.66, s * 0.32)
                                    ctx.lineTo(s * 0.66, s * 0.42)
                                    ctx.stroke()

                                    circle(cx, s * 0.58, s * 0.04, true)
                                    line(cx, s * 0.62, cx, s * 0.70)
                                } else if (kind === "devices") {
                                    // Distinct devices icon: desktop monitor + phone.
                                    roundedRect(s * 0.13, s * 0.20, s * 0.54, s * 0.43, s * 0.07, false)
                                    line(s * 0.28, s * 0.71, s * 0.52, s * 0.71)
                                    line(s * 0.40, s * 0.63, s * 0.40, s * 0.71)
                                    roundedRect(s * 0.62, s * 0.42, s * 0.25, s * 0.40, s * 0.06, false)
                                    circle(s * 0.745, s * 0.75, s * 0.018, true)
                                } else if (kind === "notifications") {
                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.28, s * 0.66)
                                    ctx.quadraticCurveTo(s * 0.34, s * 0.58, s * 0.34, s * 0.44)
                                    ctx.quadraticCurveTo(s * 0.34, s * 0.20, cx, s * 0.20)
                                    ctx.quadraticCurveTo(s * 0.66, s * 0.20, s * 0.66, s * 0.44)
                                    ctx.quadraticCurveTo(s * 0.66, s * 0.58, s * 0.72, s * 0.66)
                                    ctx.lineTo(s * 0.28, s * 0.66)
                                    ctx.stroke()

                                    line(s * 0.24, s * 0.70, s * 0.76, s * 0.70)

                                    ctx.beginPath()
                                    ctx.moveTo(s * 0.42, s * 0.74)
                                    ctx.quadraticCurveTo(cx, s * 0.84, s * 0.58, s * 0.74)
                                    ctx.stroke()

                                    line(cx, s * 0.16, cx, s * 0.12)
                                } else if (kind === "storage") {
                                    // Новая иконка хранилища: NAS / накопитель
                                    roundedRect(s * 0.20, s * 0.24, s * 0.60, s * 0.56, s * 0.10, false)

                                    // Разделитель между двумя секциями
                                    line(s * 0.24, s * 0.52, s * 0.76, s * 0.52)

                                    // Верхний слот
                                    line(s * 0.30, s * 0.40, s * 0.56, s * 0.40)
                                    circle(s * 0.68, s * 0.40, s * 0.028, true)

                                    // Нижний слот
                                    line(s * 0.30, s * 0.64, s * 0.56, s * 0.64)
                                    circle(s * 0.68, s * 0.64, s * 0.028, true)

                                    // Нижняя линия корпуса для объема
                                    line(s * 0.28, s * 0.78, s * 0.72, s * 0.78)
                                } else if (kind === "about") {
                                    circle(cx, cy, s * 0.34, false)
                                    circle(cx, s * 0.31, s * 0.035, true)
                                    line(cx, s * 0.43, cx, s * 0.67)
                                } else if (kind === "privacy") {
                                    ctx.beginPath()
                                    ctx.moveTo(cx, s * 0.13)
                                    ctx.lineTo(s * 0.79, s * 0.26)
                                    ctx.lineTo(s * 0.75, s * 0.58)
                                    ctx.quadraticCurveTo(s * 0.70, s * 0.76, cx, s * 0.87)
                                    ctx.quadraticCurveTo(s * 0.30, s * 0.76, s * 0.25, s * 0.58)
                                    ctx.lineTo(s * 0.21, s * 0.26)
                                    ctx.closePath()
                                    ctx.stroke()
                                } else {
                                    roundedRect(s * 0.22, s * 0.22, s * 0.56, s * 0.56, s * 0.10, false)
                                }
                            }

                            Component.onCompleted: requestPaint()
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tabLabel(index)
                        color: root.currentTab === index
                            ? root.textPrimary
                            : Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.85)
                        font.pointSize: 10
                        font.bold: root.currentTab === index
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tabSelected(index)
                }
            }
        }

        Item { width: 1; height: 4 }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.12)
        }

        Rectangle {
            id: logoutItem
            width: parent.width
            height: 34
            radius: 8
            scale: logoutMouse.pressed ? 0.97 : 1
            color: logoutMouse.pressed
                ? Qt.rgba(1, 0.3, 0.3, 0.20)
                : logoutMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.12) : "transparent"

            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
            Behavior on scale {
                NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 12
                spacing: 8

                Item {
                    width: 18
                    height: 18
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        id: logoutIcon
                        anchors.fill: parent
                        antialiasing: true
                        property color iconColor: logoutMouse.containsMouse ? "#ff8080" : "#ff6666"

                        onIconColorChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)

                            var s = Math.min(width, height)
                            var cy = height / 2

                            ctx.strokeStyle = iconColor
                            ctx.lineWidth = 1.35
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            function line(x1, y1, x2, y2) {
                                ctx.beginPath()
                                ctx.moveTo(x1, y1)
                                ctx.lineTo(x2, y2)
                                ctx.stroke()
                            }

                            function roundedRect(x, y, ww, hh, rr) {
                                rr = Math.min(rr, ww / 2, hh / 2)
                                ctx.beginPath()
                                ctx.moveTo(x + rr, y)
                                ctx.lineTo(x + ww - rr, y)
                                ctx.quadraticCurveTo(x + ww, y, x + ww, y + rr)
                                ctx.lineTo(x + ww, y + hh - rr)
                                ctx.quadraticCurveTo(x + ww, y + hh, x + ww - rr, y + hh)
                                ctx.lineTo(x + rr, y + hh)
                                ctx.quadraticCurveTo(x, y + hh, x, y + hh - rr)
                                ctx.lineTo(x, y + rr)
                                ctx.quadraticCurveTo(x, y, x + rr, y)
                                ctx.stroke()
                            }

                            roundedRect(s * 0.16, s * 0.20, s * 0.34, s * 0.60, s * 0.08)
                            line(s * 0.42, cy, s * 0.78, cy)
                            line(s * 0.62, s * 0.34, s * 0.78, cy)
                            line(s * 0.62, s * 0.66, s * 0.78, cy)
                        }

                        Component.onCompleted: requestPaint()
                    }
                }

                Text {
                    width: Math.max(0, parent.width - 18 - parent.spacing)
                    anchors.verticalCenter: parent.verticalCenter
                    text: L10n.I18n.tr("Выйти из аккаунта")
                    color: logoutMouse.containsMouse ? "#ff8080" : "#ff6666"
                    font.pointSize: 10
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: logoutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.logoutRequested()
            }
        }
    }
}

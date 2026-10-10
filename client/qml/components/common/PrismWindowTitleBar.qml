import QtQuick

Item {
    id: root

    required property var window
    property color backgroundColor: "#0B1710"
    property color textColor: "#F2FFF4"
    property color secondaryTextColor: "#A7B8AA"
    property color accentColor: "#20D500"
    property color dividerColor: "#29402E"
    property bool pinned: false

    signal pinToggled()

    implicitHeight: 32
    clip: true

    component TitleButton: Rectangle {
        id: control

        required property string kind
        property color foregroundColor: root.textColor
        property bool checked: false
        signal clicked()

        width: 44
        height: root.height
        color: {
            if (control.kind === "close") {
                if (buttonMouse.pressed) return "#B91C2C"
                if (buttonMouse.containsMouse) return "#E23B4B"
            }
            if (buttonMouse.pressed)
                return Qt.rgba(root.accentColor.r, root.accentColor.g,
                               root.accentColor.b, 0.28)
            if (buttonMouse.containsMouse || control.checked)
                return Qt.rgba(root.accentColor.r, root.accentColor.g,
                               root.accentColor.b, control.checked ? 0.18 : 0.13)
            return "transparent"
        }

        Behavior on color { ColorAnimation { duration: 90 } }

        Canvas {
            id: controlIcon
            anchors.centerIn: parent
            width: 16
            height: 16
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = control.kind === "close"
                    && buttonMouse.containsMouse ? "#FFFFFF" : control.foregroundColor
                ctx.fillStyle = ctx.strokeStyle
                ctx.lineWidth = 1.35
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()

                if (control.kind === "minimize") {
                    ctx.moveTo(3, 11.5)
                    ctx.lineTo(13, 11.5)
                } else if (control.kind === "maximize") {
                    ctx.rect(3.5, 3.5, 9, 9)
                } else if (control.kind === "restore") {
                    ctx.rect(2.5, 5, 8.5, 8)
                    ctx.moveTo(5, 5)
                    ctx.lineTo(5, 2.5)
                    ctx.lineTo(13.5, 2.5)
                    ctx.lineTo(13.5, 10.5)
                    ctx.lineTo(11, 10.5)
                } else if (control.kind === "close") {
                    ctx.moveTo(3.5, 3.5)
                    ctx.lineTo(12.5, 12.5)
                    ctx.moveTo(12.5, 3.5)
                    ctx.lineTo(3.5, 12.5)
                } else if (control.kind === "pin") {
                    ctx.moveTo(5.5, 3)
                    ctx.lineTo(10.5, 3)
                    ctx.lineTo(9.5, 6.5)
                    ctx.lineTo(12, 9)
                    ctx.lineTo(8.7, 9)
                    ctx.lineTo(8, 13.5)
                    ctx.lineTo(7.3, 9)
                    ctx.lineTo(4, 9)
                    ctx.lineTo(6.5, 6.5)
                    ctx.closePath()
                }
                if (control.kind === "pin" && control.checked)
                    ctx.fill()
                else
                    ctx.stroke()
            }

            Connections {
                target: control
                function onKindChanged() { controlIcon.requestPaint() }
                function onForegroundColorChanged() { controlIcon.requestPaint() }
                function onCheckedChanged() { controlIcon.requestPaint() }
            }
            Connections {
                target: buttonMouse
                function onContainsMouseChanged() { controlIcon.requestPaint() }
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: control.clicked()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.dividerColor
            opacity: 0.72
        }
    }

    Image {
        id: appIcon
        anchors.left: parent.left
        anchors.leftMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        source: "qrc:/app/prismchat.png"
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    TitleButton {
        id: pinButton
        anchors.left: appIcon.right
        anchors.leftMargin: 1
        width: 32
        kind: "pin"
        checked: root.pinned
        foregroundColor: checked ? root.accentColor : root.secondaryTextColor
        onClicked: root.pinToggled()
    }

    Row {
        id: systemButtons
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        TitleButton {
            kind: "minimize"
            foregroundColor: root.secondaryTextColor
            onClicked: root.window.showMinimized()
        }
        TitleButton {
            kind: root.window.visibility === Window.Maximized ? "restore" : "maximize"
            foregroundColor: root.secondaryTextColor
            onClicked: {
                if (root.window.visibility === Window.Maximized)
                    root.window.showNormal()
                else
                    root.window.showMaximized()
            }
        }
        TitleButton {
            kind: "close"
            foregroundColor: root.secondaryTextColor
            onClicked: root.window.close()
        }
    }

    Item {
        id: moveArea
        anchors.left: pinButton.right
        anchors.right: systemButtons.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: {
                if (active)
                    root.window.startSystemMove()
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: {
                if (root.window.visibility === Window.Maximized)
                    root.window.showNormal()
                else
                    root.window.showMaximized()
            }
        }
    }

    Text {
        anchors.centerIn: parent
        width: Math.max(0, moveArea.width - 32)
        text: root.window.title
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: root.textColor
        font.pixelSize: 13
        font.weight: Font.Medium
    }
}

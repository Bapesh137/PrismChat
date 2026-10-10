import QtQuick
import "../../utils" as L10n

Item {
    id: root

    property bool running: true
    property color accentColor: "#20D500"
    property color trackColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.16)
    property real strokeWidth: 3

    width: 42
    height: 42
    visible: running

    Canvas {
        id: spinnerCanvas
        anchors.fill: parent
        antialiasing: true
        transformOrigin: Item.Center

        onPaint: {
            const context = getContext("2d")
            const centerX = width / 2
            const centerY = height / 2
            const radius = Math.max(1, Math.min(width, height) / 2 - root.strokeWidth)

            context.clearRect(0, 0, width, height)
            context.lineWidth = root.strokeWidth
            context.lineCap = "round"

            context.beginPath()
            context.strokeStyle = root.trackColor
            context.arc(centerX, centerY, radius, 0, Math.PI * 2, false)
            context.stroke()

            context.beginPath()
            context.strokeStyle = root.accentColor
            context.arc(centerX, centerY, radius, -Math.PI / 2, Math.PI * 0.78, false)
            context.stroke()
        }

        NumberAnimation on rotation {
            from: 0
            to: 360
            duration: L10n.UiPreferences.duration(820)
            loops: Animation.Infinite
            running: root.running && L10n.UiPreferences.animationsEnabled
        }
    }

    onAccentColorChanged: spinnerCanvas.requestPaint()
    onTrackColorChanged: spinnerCanvas.requestPaint()
    onStrokeWidthChanged: spinnerCanvas.requestPaint()
    Component.onCompleted: spinnerCanvas.requestPaint()
}

import QtQuick

Canvas {
    id: root

    // -1 = unknown, 0 = unencrypted, 1 = encrypted.
    property int encryptionState: -1
    property color color: "white"
    property real strokeWidth: 1.6

    implicitWidth: 20
    implicitHeight: 20
    antialiasing: true

    onEncryptionStateChanged: requestPaint()
    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var context = getContext("2d")
        context.reset()
        context.save()
        context.scale(width / 20, height / 20)
        context.strokeStyle = root.color
        context.fillStyle = root.color
        context.lineWidth = root.strokeWidth * 20 / Math.min(width, height)
        context.lineCap = "round"
        context.lineJoin = "round"

        // Lock body.
        context.beginPath()
        context.roundedRect(3.5, 8.5, 13, 9, 2, 2)
        context.stroke()

        // A closed shackle means Matrix E2EE is enabled. The open right side
        // remains visibly detached from the body for unencrypted rooms.
        context.beginPath()
        context.moveTo(6.3, 8.5)
        context.lineTo(6.3, 7)
        context.bezierCurveTo(6.3, 4.3, 7.8, 2.8, 10.3, 2.8)
        context.bezierCurveTo(12.8, 2.8, 14.3, 4.3, 14.3, 7)
        context.lineTo(14.3, root.encryptionState === 0 ? 7.2 : 8.5)
        context.stroke()

        if (root.encryptionState < 0) {
            context.font = "bold 8px sans-serif"
            context.textAlign = "center"
            context.textBaseline = "middle"
            context.fillText("?", 10, 13.2)
        } else {
            context.beginPath()
            context.arc(10, 12.2, 1.05, 0, Math.PI * 2)
            context.fill()
            context.beginPath()
            context.moveTo(10, 13.2)
            context.lineTo(10, 15.2)
            context.stroke()
        }
        context.restore()
    }
}

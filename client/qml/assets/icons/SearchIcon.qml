import QtQuick

Canvas {
    property color color: "white"
    property real strokeWidth: 1.5

    implicitWidth: 16
    implicitHeight: 16

    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        const scale = Math.min(width, height) / 16
        ctx.save()
        ctx.scale(scale, scale)
        ctx.strokeStyle = color
        ctx.lineWidth = strokeWidth / scale
        ctx.lineCap = "round"
        ctx.beginPath()
        // Keep the visual bounds centred on the 16 x 16 canvas.
        ctx.arc(6.25, 6.25, 4.5, 0, Math.PI * 2)
        ctx.moveTo(9.75, 9.75)
        ctx.lineTo(14.25, 14.25)
        ctx.stroke()
        ctx.restore()
    }
}

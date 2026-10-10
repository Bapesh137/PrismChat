import QtQuick

Canvas {
    id: root

    property color color: "white"
    property real strokeWidth: 1.6

    implicitWidth: 20
    implicitHeight: 20
    antialiasing: true

    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = root.color
        ctx.lineWidth = root.strokeWidth
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        var cx = width / 2
        ctx.beginPath()
        ctx.moveTo(cx, height * 0.16)
        ctx.lineTo(cx, height * 0.66)
        ctx.moveTo(width * 0.30, height * 0.49)
        ctx.lineTo(cx, height * 0.70)
        ctx.lineTo(width * 0.70, height * 0.49)
        ctx.moveTo(width * 0.22, height * 0.86)
        ctx.lineTo(width * 0.78, height * 0.86)
        ctx.stroke()
    }
}

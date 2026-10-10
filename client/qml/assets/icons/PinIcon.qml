import QtQuick

Canvas {
    id: root

    property color color: "white"
    property bool filled: false
    property real strokeWidth: 1.5

    implicitWidth: 20
    implicitHeight: 20
    antialiasing: true

    onColorChanged: requestPaint()
    onFilledChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.save()
        ctx.scale(width / 18, height / 18)
        ctx.strokeStyle = root.color
        ctx.fillStyle = root.color
        ctx.lineWidth = root.strokeWidth * 18 / Math.min(width, height)
        ctx.lineCap = "round"
        ctx.lineJoin = "miter"
        ctx.beginPath()
        ctx.moveTo(4, 2)
        ctx.lineTo(14, 2)
        ctx.lineTo(12, 7)
        ctx.lineTo(15, 10)
        ctx.lineTo(10, 10)
        ctx.lineTo(9, 16)
        ctx.lineTo(8, 10)
        ctx.lineTo(3, 10)
        ctx.lineTo(6, 7)
        ctx.closePath()
        if (root.filled)
            ctx.fill()
        else
            ctx.stroke()
        ctx.restore()
    }
}

import QtQuick

Canvas {
    id: root

    property color color: "white"
    property real strokeWidth: 1.5

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
        ctx.save()
        ctx.scale(width / 24, height / 24)
        ctx.strokeStyle = root.color
        ctx.lineWidth = root.strokeWidth * 24 / Math.min(width, height)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(22, 2)
        ctx.lineTo(15, 22)
        ctx.lineTo(11, 13)
        ctx.lineTo(2, 9)
        ctx.closePath()
        ctx.moveTo(22, 2)
        ctx.lineTo(11, 13)
        ctx.stroke()
        ctx.restore()
    }
}

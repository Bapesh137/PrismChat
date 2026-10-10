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
        ctx.moveTo(16, 6)
        ctx.lineTo(7.586, 14.586)
        ctx.bezierCurveTo(6.805, 15.367, 6.805, 16.633, 7.586, 17.414)
        ctx.bezierCurveTo(8.367, 18.195, 9.633, 18.195, 10.414, 17.414)
        ctx.lineTo(18.828, 8.828)
        ctx.bezierCurveTo(20.39, 7.266, 20.39, 4.734, 18.828, 3.172)
        ctx.bezierCurveTo(17.266, 1.61, 14.734, 1.61, 13.172, 3.172)
        ctx.lineTo(4.793, 11.723)
        ctx.bezierCurveTo(2.45, 14.066, 2.45, 17.934, 4.793, 20.277)
        ctx.bezierCurveTo(7.136, 22.62, 10.864, 22.62, 13.207, 20.277)
        ctx.lineTo(21.586, 11.728)
        ctx.stroke()
        ctx.restore()
    }
}

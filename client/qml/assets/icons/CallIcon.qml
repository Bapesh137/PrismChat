import QtQuick

Canvas {
    property color color: "white"
    property real strokeWidth: 1.5
    implicitWidth: 18; implicitHeight: 18
    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var s = Math.min(width, height) / 18
        ctx.save(); ctx.scale(s, s)
        ctx.strokeStyle = color; ctx.lineWidth = strokeWidth / s
        ctx.lineCap = "round"; ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(4.1, 2.7); ctx.lineTo(6.2, 2.2); ctx.lineTo(8.0, 6.0)
        ctx.lineTo(6.1, 7.3)
        ctx.bezierCurveTo(7.2, 9.5, 8.5, 10.8, 10.7, 11.9)
        ctx.lineTo(12.0, 10.0); ctx.lineTo(15.8, 11.8); ctx.lineTo(15.3, 13.9)
        ctx.bezierCurveTo(14.9, 15.5, 13.4, 16.1, 11.8, 15.5)
        ctx.bezierCurveTo(6.9, 13.7, 4.3, 11.1, 2.5, 6.2)
        ctx.bezierCurveTo(1.9, 4.6, 2.5, 3.1, 4.1, 2.7)
        ctx.stroke(); ctx.restore()
    }
}

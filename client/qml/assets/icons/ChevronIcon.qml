import QtQuick

Canvas {
    id: root

    property color color: "white"
    property string direction: "right"
    property real strokeWidth: 1.7

    implicitWidth: 20
    implicitHeight: 20
    antialiasing: true

    onColorChanged: requestPaint()
    onDirectionChanged: requestPaint()
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
        var cy = height / 2
        var dx = width * 0.18
        var dy = height * 0.27
        ctx.beginPath()
        if (root.direction === "left") {
            ctx.moveTo(cx + dx, cy - dy)
            ctx.lineTo(cx - dx, cy)
            ctx.lineTo(cx + dx, cy + dy)
        } else if (root.direction === "up") {
            ctx.moveTo(cx - dx, cy + dy)
            ctx.lineTo(cx, cy - dy)
            ctx.lineTo(cx + dx, cy + dy)
        } else if (root.direction === "down") {
            ctx.moveTo(cx - dx, cy - dy)
            ctx.lineTo(cx, cy + dy)
            ctx.lineTo(cx + dx, cy - dy)
        } else {
            ctx.moveTo(cx - dx, cy - dy)
            ctx.lineTo(cx + dx, cy)
            ctx.lineTo(cx - dx, cy + dy)
        }
        ctx.stroke()
    }
}

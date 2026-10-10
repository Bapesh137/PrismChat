import QtQuick

Canvas {
    property color color: "white"
    implicitWidth: 18
    implicitHeight: 18
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = color
        ctx.lineWidth = 1.5
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(width * 0.15, height * 0.48)
        ctx.lineTo(width * 0.5, height * 0.18)
        ctx.lineTo(width * 0.85, height * 0.48)
        ctx.moveTo(width * 0.25, height * 0.43)
        ctx.lineTo(width * 0.25, height * 0.82)
        ctx.lineTo(width * 0.75, height * 0.82)
        ctx.lineTo(width * 0.75, height * 0.43)
        ctx.stroke()
    }
}

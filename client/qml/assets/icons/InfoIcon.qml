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
        ctx.fillStyle = color
        ctx.lineWidth = 1.4
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.arc(width / 2, height / 2, Math.min(width, height) * 0.38, 0, Math.PI * 2)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(width / 2, height * 0.34, 0.9, 0, Math.PI * 2)
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(width / 2, height * 0.47)
        ctx.lineTo(width / 2, height * 0.69)
        ctx.stroke()
    }
}

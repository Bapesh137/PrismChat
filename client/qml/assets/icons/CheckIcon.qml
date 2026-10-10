import QtQuick

Canvas {
    property color color: "white"
    property string capStyle: "round"
    implicitWidth: 14
    implicitHeight: 14
    onColorChanged: requestPaint()
    onCapStyleChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = color
        ctx.lineWidth = Math.max(1.5, Math.min(width, height) * 0.13)
        ctx.lineCap = capStyle
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(width * 0.18, height * 0.52)
        ctx.lineTo(width * 0.42, height * 0.75)
        ctx.lineTo(width * 0.83, height * 0.27)
        ctx.stroke()
    }
}

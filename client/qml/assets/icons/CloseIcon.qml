import QtQuick

Canvas {
    id: root

    property color color: "white"
    property real strokeWidth: 1.6
    property string capStyle: "round"

    implicitWidth: 20
    implicitHeight: 20
    antialiasing: true

    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onCapStyleChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = root.color
        ctx.lineWidth = root.strokeWidth
        ctx.lineCap = root.capStyle
        var inset = Math.min(width, height) * 0.27
        ctx.beginPath()
        ctx.moveTo(inset, inset)
        ctx.lineTo(width - inset, height - inset)
        ctx.moveTo(width - inset, inset)
        ctx.lineTo(inset, height - inset)
        ctx.stroke()
    }
}

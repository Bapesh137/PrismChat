import QtQuick

Canvas {
    id: root

    property color color: "white"
    property real strokeWidth: 1.7

    implicitWidth: 20
    implicitHeight: 20
    antialiasing: true

    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = root.color
        ctx.lineWidth = root.strokeWidth
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(width * 0.18, height * 0.5)
        ctx.lineTo(width * 0.82, height * 0.5)
        ctx.moveTo(width * 0.5, height * 0.18)
        ctx.lineTo(width * 0.5, height * 0.82)
        ctx.stroke()
    }
}


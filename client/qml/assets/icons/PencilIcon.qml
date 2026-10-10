import QtQuick

Canvas {
    id: root

    property color color: "white"
    property real strokeWidth: 1.6

    implicitWidth: 16
    implicitHeight: 16
    antialiasing: true

    onColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        var context = getContext("2d")
        context.reset()
        context.strokeStyle = root.color
        context.lineWidth = root.strokeWidth
        context.lineCap = "round"
        context.lineJoin = "round"

        context.beginPath()
        context.moveTo(width * 0.23, height * 0.73)
        context.lineTo(width * 0.30, height * 0.49)
        context.lineTo(width * 0.70, height * 0.09)
        context.lineTo(width * 0.91, height * 0.30)
        context.lineTo(width * 0.51, height * 0.70)
        context.closePath()
        context.stroke()

        context.beginPath()
        context.moveTo(width * 0.23, height * 0.73)
        context.lineTo(width * 0.16, height * 0.84)
        context.lineTo(width * 0.27, height * 0.77)
        context.moveTo(width * 0.34, height * 0.45)
        context.lineTo(width * 0.55, height * 0.66)
        context.stroke()
    }
}

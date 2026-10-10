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
    Component.onCompleted: requestPaint()

    onPaint: {
        var context = getContext("2d")
        context.reset()
        context.save()
        context.scale(width / 20, height / 20)
        context.strokeStyle = root.color
        context.lineWidth = root.strokeWidth * 20 / Math.min(width, height)
        context.lineCap = "round"
        context.lineJoin = "round"

        context.beginPath()
        context.arc(10, 10, 7.2, 0, Math.PI * 2)
        context.stroke()

        context.beginPath()
        context.moveTo(10, 5.7)
        context.lineTo(10, 10.2)
        context.lineTo(13.2, 12)
        context.stroke()
        context.restore()
    }
}

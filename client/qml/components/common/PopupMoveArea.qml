import QtQuick
import "../../utils" as L10n

MouseArea {
    id: root

    required property var moveTarget
    required property Item movementBoundary
    property real leftEdge: 8
    property real topEdge: 8
    property real rightEdge: 8
    property real bottomEdge: 8

    property point pressPosition: Qt.point(0, 0)
    property real pressTargetX: 0
    property real pressTargetY: 0
    property real pressOffsetX: 0
    property real pressOffsetY: 0
    property real desiredOffsetX: 0
    property real desiredOffsetY: 0
    property real minimumOffsetX: 0
    property real maximumOffsetX: 0
    property real minimumOffsetY: 0
    property real maximumOffsetY: 0
    property real velocityX: 0
    property real velocityY: 0
    property real previousDesiredOffsetX: 0
    property real visualShearAngle: 0
    property real targetShearAngle: 0
    readonly property string wobbleMode: L10n.UiPreferences.animationsEnabled
        ? L10n.UiPreferences.windowWobbleMode : "off"
    readonly property bool springWobbleEnabled: wobbleMode === "spring"
    readonly property bool linuxWobbleEnabled: wobbleMode === "linux"
    readonly property real springStrength: Math.max(0, Math.min(1,
        Number(L10n.UiPreferences.windowSpringStrength) / 100))
    readonly property real linuxWobbleStrength: Math.max(0, Math.min(1,
        Number(L10n.UiPreferences.windowWobbleStrength) / 100))

    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    preventStealing: true
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

    onPressed: function(mouse) {
        pressPosition = mapToItem(movementBoundary, mouse.x, mouse.y)
        pressTargetX = moveTarget.x
        pressTargetY = moveTarget.y
        pressOffsetX = moveTarget.dragOffsetX
        pressOffsetY = moveTarget.dragOffsetY
        desiredOffsetX = pressOffsetX
        desiredOffsetY = pressOffsetY
        previousDesiredOffsetX = pressOffsetX
        velocityX = 0
        velocityY = 0
        springTimer.stop()
        targetShearAngle = 0
        linuxShearTimer.stop()
        mouse.accepted = true
    }

    onPositionChanged: function(mouse) {
        if (!(mouse.buttons & Qt.LeftButton))
            return

        var pointer = mapToItem(movementBoundary, mouse.x, mouse.y)
        var desiredX = pressTargetX + pointer.x - pressPosition.x
        var desiredY = pressTargetY + pointer.y - pressPosition.y
        var minimumX = Math.min(leftEdge,
                                (movementBoundary.width - moveTarget.width) / 2)
        var minimumY = Math.min(topEdge,
                                (movementBoundary.height - moveTarget.height) / 2)
        var maximumX = Math.max(minimumX,
                                movementBoundary.width - moveTarget.width - rightEdge)
        var maximumY = Math.max(minimumY,
                                movementBoundary.height - moveTarget.height - bottomEdge)
        var boundedX = Math.max(minimumX, Math.min(maximumX, desiredX))
        var boundedY = Math.max(minimumY, Math.min(maximumY, desiredY))

        minimumOffsetX = pressOffsetX + minimumX - pressTargetX
        maximumOffsetX = pressOffsetX + maximumX - pressTargetX
        minimumOffsetY = pressOffsetY + minimumY - pressTargetY
        maximumOffsetY = pressOffsetY + maximumY - pressTargetY
        desiredOffsetX = pressOffsetX + boundedX - pressTargetX
        desiredOffsetY = pressOffsetY + boundedY - pressTargetY

        var horizontalDelta = desiredOffsetX - previousDesiredOffsetX
        previousDesiredOffsetX = desiredOffsetX

        if (springWobbleEnabled && springStrength > 0.001) {
            if (!springTimer.running)
                springTimer.start()
        } else {
            springTimer.stop()
            moveTarget.dragOffsetX = desiredOffsetX
            moveTarget.dragOffsetY = desiredOffsetY
            if (linuxWobbleEnabled && linuxWobbleStrength > 0.001) {
                var maximumAngle = 17.0 * linuxWobbleStrength
                targetShearAngle = Math.max(-maximumAngle,
                    Math.min(maximumAngle,
                             -horizontalDelta * 1.70 * linuxWobbleStrength))
                if (!linuxShearTimer.running)
                    linuxShearTimer.start()
            } else {
                targetShearAngle = 0
                visualShearAngle = 0
            }
        }
        mouse.accepted = true
    }

    function finishPointerGesture() {
        targetShearAngle = 0
        if (Math.abs(visualShearAngle) > 0.01 && !linuxShearTimer.running)
            linuxShearTimer.start()
    }

    function resetMotion() {
        springTimer.stop()
        linuxShearTimer.stop()
        velocityX = 0
        velocityY = 0
        targetShearAngle = 0
        visualShearAngle = 0
    }

    onReleased: finishPointerGesture()
    onCanceled: finishPointerGesture()
    onWobbleModeChanged: resetMotion()

    Timer {
        id: springTimer
        interval: 16
        repeat: true

        onTriggered: {
            var deltaX = root.desiredOffsetX - root.moveTarget.dragOffsetX
            var deltaY = root.desiredOffsetY - root.moveTarget.dragOffsetY
            var stiffness = 0.42 - root.springStrength * 0.14
            var damping = 0.48 + root.springStrength * 0.24
            root.velocityX = (root.velocityX + deltaX * stiffness)
                * damping
            root.velocityY = (root.velocityY + deltaY * stiffness)
                * damping

            var nextX = root.moveTarget.dragOffsetX + root.velocityX
            var nextY = root.moveTarget.dragOffsetY + root.velocityY
            var boundedX = Math.max(root.minimumOffsetX,
                                    Math.min(root.maximumOffsetX, nextX))
            var boundedY = Math.max(root.minimumOffsetY,
                                    Math.min(root.maximumOffsetY, nextY))
            if (boundedX !== nextX)
                root.velocityX = 0
            if (boundedY !== nextY)
                root.velocityY = 0
            root.moveTarget.dragOffsetX = boundedX
            root.moveTarget.dragOffsetY = boundedY

            if (Math.abs(deltaX) < 0.05 && Math.abs(deltaY) < 0.05
                    && Math.abs(root.velocityX) < 0.05
                    && Math.abs(root.velocityY) < 0.05) {
                root.moveTarget.dragOffsetX = root.desiredOffsetX
                root.moveTarget.dragOffsetY = root.desiredOffsetY
                root.velocityX = 0
                root.velocityY = 0
                stop()
            }
        }
    }

    Timer {
        id: linuxShearTimer
        interval: 16
        repeat: true

        onTriggered: {
            root.visualShearAngle +=
                (root.targetShearAngle - root.visualShearAngle) * 0.44
            root.targetShearAngle *= root.pressed ? 0.92 : 0.62

            if (Math.abs(root.visualShearAngle) < 0.015
                    && Math.abs(root.targetShearAngle) < 0.015) {
                root.visualShearAngle = 0
                root.targetShearAngle = 0
                stop()
            }
        }
    }
}

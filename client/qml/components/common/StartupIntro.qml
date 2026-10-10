import QtQuick
import Qt5Compat.GraphicalEffects
import "../../utils" as L10n

Item {
    id: root

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property bool animationsEnabled: true
    property bool previewMode: false
    property int introVariant: 0
    readonly property int normalizedVariant: Math.max(0, Math.min(10, introVariant))

    signal finished()

    function introSubtitle() {
        return L10n.I18n.tr([
            "Загрузка PrismChat",
            "Matrix, преломлённый по-новому",
            "Входим в орбиту общения",
            "Соединение оживает",
            "Настраиваем спектр",
            "На одной волне",
            "Преломляем пространство",
            "Собираем Matrix",
            "Открываем портал",
            "Ничего лишнего",
            "Соединяем точки"
        ][normalizedVariant])
    }

    opacity: 1
    visible: opacity > 0

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
    }

    Rectangle {
        id: halo
        x: root.previewMode ? 18 : (root.width - width) / 2
        y: (root.height - height) / 2
        width: root.previewMode ? 60 : Math.min(root.width, root.height) * 0.58
        height: width
        radius: width / 2
        color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                       root.accentColor.b, 0.10)
        scale: 0.88

        SequentialAnimation on scale {
            running: root.animationsEnabled
            loops: Animation.Infinite
            NumberAnimation {
                from: 0.88
                to: 1.04
                duration: 1100
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                from: 1.04
                to: 0.88
                duration: 1100
                easing.type: Easing.InOutSine
            }
        }
    }

    Item {
        id: introContent
        anchors.centerIn: parent
        width: root.previewMode ? root.width : Math.min(360, Math.max(240, root.width - 48))
        height: root.previewMode ? root.height : 220
        opacity: root.previewMode || !root.animationsEnabled ? 1 : 0
        scale: root.previewMode || !root.animationsEnabled ? 1 : 0.94

        Item {
            id: prismMark
            anchors.horizontalCenter: root.previewMode ? undefined : parent.horizontalCenter
            anchors.left: root.previewMode ? parent.left : undefined
            anchors.verticalCenter: root.previewMode ? parent.verticalCenter : undefined
            anchors.top: root.previewMode ? undefined : parent.top
            width: 96
            height: 96
            scale: root.previewMode ? 0.56 : 1

            Canvas {
                id: markCanvas
                anchors.fill: parent
                antialiasing: true
                property real phase: 0

                onPhaseChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()

                Connections {
                    target: root
                    function onIntroVariantChanged() { markCanvas.requestPaint() }
                    function onAccentColorChanged() { markCanvas.requestPaint() }
                    function onIconColorChanged() { markCanvas.requestPaint() }
                    function onSurfaceColorChanged() { markCanvas.requestPaint() }
                }

                NumberAnimation on phase {
                    running: root.animationsEnabled
                    from: 0
                    to: 1
                    duration: 1800
                    loops: Animation.Infinite
                }

                onPaint: {
                    var ctx = getContext("2d")
                    var cx = width / 2
                    var cy = height / 2
                    var tau = Math.PI * 2
                    var t = phase * tau
                    var variant = root.normalizedVariant - 1
                    ctx.clearRect(0, 0, width, height)
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"

                    if (root.normalizedVariant === 0) {
                        for (var logoRing = 0; logoRing < 3; logoRing++) {
                            var ringPhase = (phase + logoRing / 3) % 1
                            ctx.globalAlpha = (1 - ringPhase) * 0.42
                            ctx.strokeStyle = logoRing === 1
                                ? root.iconColor : root.accentColor
                            ctx.lineWidth = 1.4
                            ctx.beginPath()
                            ctx.arc(cx, cy, 29 + ringPhase * 16,
                                    t + logoRing * 1.8,
                                    t + logoRing * 1.8 + Math.PI * 1.25)
                            ctx.stroke()
                        }
                        for (var spark = 0; spark < 6; spark++) {
                            var sparkAngle = t * (spark % 2 ? -0.55 : 0.7)
                                + spark * Math.PI / 3
                            var sparkRadius = 39 + Math.sin(t + spark) * 4
                            ctx.globalAlpha = 0.38 + 0.34
                                * Math.abs(Math.sin(t + spark * 0.9))
                            ctx.fillStyle = spark % 2
                                ? root.iconColor : root.accentColor
                            ctx.beginPath()
                            ctx.arc(cx + Math.cos(sparkAngle) * sparkRadius,
                                    cy + Math.sin(sparkAngle) * sparkRadius,
                                    spark % 3 === 0 ? 2.2 : 1.4, 0, tau)
                            ctx.fill()
                        }
                    } else if (variant === 0) {
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.rotate(Math.PI / 4 + Math.sin(t) * 0.045)
                        ctx.globalAlpha = 0.86
                        ctx.fillStyle = root.surfaceColor
                        ctx.strokeStyle = root.accentColor
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.roundedRect(-31, -31, 62, 62, 11, 11)
                        ctx.fill()
                        ctx.stroke()
                        ctx.globalAlpha = 0.78
                        ctx.strokeStyle = root.iconColor
                        ctx.lineWidth = 1.5
                        ctx.beginPath()
                        ctx.roundedRect(-20, -20, 40, 40, 7, 7)
                        ctx.stroke()
                        ctx.restore()
                        ctx.fillStyle = root.accentColor
                        ctx.beginPath()
                        ctx.arc(cx, cy, 6, 0, tau)
                        ctx.fill()
                    } else if (variant === 1) {
                        ctx.strokeStyle = root.iconColor
                        ctx.lineWidth = 1.6
                        ctx.globalAlpha = 0.55
                        ctx.beginPath()
                        ctx.arc(cx, cy, 31, 0, tau)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.arc(cx, cy, 19, 0, tau)
                        ctx.stroke()
                        ctx.globalAlpha = 1
                        ctx.fillStyle = root.accentColor
                        ctx.beginPath()
                        ctx.arc(cx + Math.cos(t) * 31, cy + Math.sin(t) * 31,
                                6, 0, tau)
                        ctx.fill()
                        ctx.beginPath()
                        ctx.arc(cx - Math.cos(t * 1.35) * 19,
                                cy - Math.sin(t * 1.35) * 19, 3.5, 0, tau)
                        ctx.fill()
                    } else if (variant === 2) {
                        for (var pulse = 0; pulse < 3; pulse++) {
                            var pulsePhase = (phase + pulse / 3) % 1
                            ctx.globalAlpha = 1 - pulsePhase
                            ctx.strokeStyle = root.accentColor
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            ctx.arc(cx, cy, 10 + pulsePhase * 36, 0, tau)
                            ctx.stroke()
                        }
                        ctx.globalAlpha = 1
                        ctx.fillStyle = root.iconColor
                        ctx.beginPath()
                        ctx.arc(cx, cy, 8 + Math.sin(t) * 2, 0, tau)
                        ctx.fill()
                    } else if (variant === 3) {
                        ctx.fillStyle = root.accentColor
                        for (var bar = 0; bar < 9; bar++) {
                            var barHeight = 18 + (Math.sin(t + bar * 0.72) + 1) * 19
                            ctx.globalAlpha = 0.38 + bar * 0.065
                            ctx.fillRect(13 + bar * 9, cy - barHeight / 2, 5, barHeight)
                        }
                    } else if (variant === 4) {
                        for (var wave = 0; wave < 3; wave++) {
                            ctx.globalAlpha = 0.35 + wave * 0.25
                            ctx.strokeStyle = wave === 1 ? root.iconColor : root.accentColor
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            for (var px = 5; px <= width - 5; px += 3) {
                                var py = cy + (wave - 1) * 13
                                    + Math.sin(px * 0.10 + t + wave) * 8
                                if (px === 5) ctx.moveTo(px, py)
                                else ctx.lineTo(px, py)
                            }
                            ctx.stroke()
                        }
                    } else if (variant === 5) {
                        var split = 4 + Math.abs(Math.sin(t)) * 7
                        ctx.fillStyle = root.surfaceColor
                        ctx.strokeStyle = root.accentColor
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.moveTo(cx - split, 10)
                        ctx.lineTo(14, cy)
                        ctx.lineTo(cx - split, 86)
                        ctx.closePath()
                        ctx.fill()
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(cx + split, 10)
                        ctx.lineTo(82, cy)
                        ctx.lineTo(cx + split, 86)
                        ctx.closePath()
                        ctx.fill()
                        ctx.stroke()
                    } else if (variant === 6) {
                        for (var column = 0; column < 7; column++) {
                            for (var row = 0; row < 7; row++) {
                                var cellPhase = (phase + column * 0.11 + row * 0.07) % 1
                                ctx.globalAlpha = 0.16 + (1 - cellPhase) * 0.84
                                ctx.fillStyle = cellPhase < 0.24
                                    ? root.iconColor : root.accentColor
                                ctx.fillRect(17 + column * 10,
                                             12 + ((row * 10 + phase * 20) % 70),
                                             3, 6)
                            }
                        }
                    } else if (variant === 7) {
                        ctx.lineWidth = 3
                        for (var ring = 0; ring < 3; ring++) {
                            ctx.globalAlpha = 0.42 + ring * 0.23
                            ctx.strokeStyle = ring === 1 ? root.iconColor : root.accentColor
                            ctx.beginPath()
                            ctx.arc(cx, cy, 15 + ring * 12,
                                    t * (ring % 2 ? -1 : 1) + ring,
                                    t * (ring % 2 ? -1 : 1) + ring + Math.PI * 1.25)
                            ctx.stroke()
                        }
                    } else if (variant === 8) {
                        ctx.globalAlpha = 0.95
                        ctx.fillStyle = root.accentColor
                        ctx.font = "600 58px sans-serif"
                        ctx.textAlign = "center"
                        ctx.textBaseline = "middle"
                        ctx.fillText("P", cx, cy + 2)
                        ctx.globalAlpha = 0.25 + Math.abs(Math.sin(t)) * 0.35
                        ctx.strokeStyle = root.iconColor
                        ctx.lineWidth = 1
                        ctx.strokeRect(20, 12, 56, 72)
                    } else {
                        var nodes = [
                            [15, 55], [29, 22], [45, 42], [60, 15],
                            [78, 34], [70, 69], [42, 80], [24, 70]
                        ]
                        ctx.strokeStyle = root.iconColor
                        ctx.lineWidth = 1.3
                        ctx.globalAlpha = 0.45
                        ctx.beginPath()
                        for (var edge = 0; edge < nodes.length; edge++) {
                            var next = (edge + 1) % nodes.length
                            ctx.moveTo(nodes[edge][0], nodes[edge][1])
                            ctx.lineTo(nodes[next][0], nodes[next][1])
                        }
                        ctx.moveTo(nodes[1][0], nodes[1][1])
                        ctx.lineTo(nodes[5][0], nodes[5][1])
                        ctx.moveTo(nodes[2][0], nodes[2][1])
                        ctx.lineTo(nodes[7][0], nodes[7][1])
                        ctx.stroke()
                        for (var node = 0; node < nodes.length; node++) {
                            ctx.globalAlpha = 0.55
                                + Math.sin(t + node * 0.8) * 0.35
                            ctx.fillStyle = node % 3 === 0
                                ? root.iconColor : root.accentColor
                            ctx.beginPath()
                            ctx.arc(nodes[node][0], nodes[node][1],
                                    3 + (node % 2), 0, tau)
                            ctx.fill()
                        }
                    }
                    ctx.globalAlpha = 1
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 76
                height: width
                radius: width / 2
                visible: root.normalizedVariant === 0
                color: root.accentColor
                opacity: 0.12

                SequentialAnimation on scale {
                    running: root.animationsEnabled && root.normalizedVariant === 0
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.78; to: 1.12; duration: 920; easing.type: Easing.OutCubic }
                    NumberAnimation { from: 1.12; to: 0.78; duration: 920; easing.type: Easing.InCubic }
                }
            }

            Image {
                id: logoImage
                anchors.centerIn: parent
                width: 88
                height: 88
                visible: root.normalizedVariant === 0
                source: "qrc:/app/prismchat.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                opacity: 0.98
                transformOrigin: Item.Center
                layer.enabled: true
                layer.effect: ColorOverlay {
                    color: root.iconColor
                }

                SequentialAnimation on rotation {
                    running: root.animationsEnabled && root.normalizedVariant === 0
                    loops: Animation.Infinite
                    NumberAnimation { from: -3; to: 3; duration: 1200; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 3; to: -3; duration: 1200; easing.type: Easing.InOutSine }
                }

                SequentialAnimation on scale {
                    running: root.animationsEnabled && root.normalizedVariant === 0
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.92; to: 1.04; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.04; to: 0.92; duration: 900; easing.type: Easing.InOutSine }
                }
            }
        }

        Text {
            id: titleText
            anchors.top: root.previewMode ? parent.top : prismMark.bottom
            anchors.topMargin: root.previewMode ? 13 : 18
            x: root.previewMode ? 88 : (parent.width - width) / 2
            text: "PrismChat"
            color: root.textPrimary
            font.pixelSize: root.previewMode ? 13 : 30
            font.weight: Font.DemiBold
            font.letterSpacing: root.previewMode ? 0.4 : 1.2
        }

        Text {
            anchors.top: root.previewMode ? titleText.bottom : undefined
            anchors.topMargin: root.previewMode ? 2 : 0
            anchors.bottom: root.previewMode ? undefined : progressTrack.top
            anchors.bottomMargin: root.previewMode ? 0 : 18
            x: root.previewMode ? 88 : (parent.width - width) / 2
            width: root.previewMode ? Math.max(0, parent.width - 98) : implicitWidth
            text: root.introSubtitle()
            color: root.textSecondary
            font.pixelSize: root.previewMode ? 8 : 12
            elide: root.previewMode ? Text.ElideRight : Text.ElideNone
        }

        Rectangle {
            id: progressTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.previewMode ? 9 : 0
            anchors.leftMargin: root.previewMode ? 88 : 54
            anchors.rightMargin: root.previewMode ? 10 : 54
            height: 2
            radius: 1
            color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                           root.textSecondary.b, 0.16)

            Rectangle {
                id: progressFill
                height: parent.height
                radius: parent.radius
                width: root.animationsEnabled ? 0 : parent.width
                color: root.accentColor
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.previewMode
        acceptedButtons: Qt.AllButtons
    }

    ParallelAnimation {
        running: root.animationsEnabled && !root.previewMode

        NumberAnimation {
            target: introContent
            property: "opacity"
            from: 0
            to: 1
            duration: 420
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: introContent
            property: "scale"
            from: 0.94
            to: 1
            duration: 520
            easing.type: Easing.OutBack
        }

        NumberAnimation {
            target: progressFill
            property: "width"
            from: 0
            to: progressTrack.width
            duration: 2650
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation {
        running: root.previewMode && root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            target: progressFill
            property: "width"
            from: 0
            to: progressTrack.width
            duration: 2200
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation {
        running: !root.previewMode

        PauseAnimation {
            duration: root.animationsEnabled ? 2650 : 3000
        }

        NumberAnimation {
            target: root
            property: "opacity"
            from: 1
            to: 0
            duration: root.animationsEnabled ? 350 : 0
            easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: root.finished()
        }
    }
}

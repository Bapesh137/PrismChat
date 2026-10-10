import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../common"
import "../../assets/icons" as Icons
import "../../utils" as L10n

Rectangle {
    id: root
    required property var session
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color dividerColor: "#29402E"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color accentColor: "#20D500"
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    readonly property bool leaving: session.phase === "leaving" || session.phase === "ending"
    readonly property bool connected: session.phase === "connected"
    width: 440
    height: 470
    x: session.panelFullscreen ? 0
        : parent ? Math.round(parent.width - width - 16 + dragOffsetX) : 0
    y: session.panelFullscreen ? 0
        : parent ? Math.round(parent.height - height - 16 + dragOffsetY) : 0
    radius: session.panelFullscreen ? 0 : 18
    color: surfaceColor
    border.color: connected
        ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.34)
        : Qt.rgba(dividerColor.r, dividerColor.g, dividerColor.b, 0.92)
    border.width: 1
    Behavior on border.color {
        ColorAnimation { duration: L10n.UiPreferences.duration(140) }
    }
    // Hiding the panel must preserve the WebEngine and the active call.
    visible: session.panelOpen && (session.active || session.errorText !== "")

    // Consume empty-space clicks before they reach the chat behind the panel.
    MouseArea { anchors.fill: parent; onWheel: function(wheel) { wheel.accepted = true } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        Rectangle {
            id: callHeader
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            radius: 14
            color: root.elevatedColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.12)
            // Transform only the header; transforming WebEngine breaks hit testing.
            transform: Matrix4x4 {
                matrix: PlanarTransform.fromShear(
                            Math.tan(callMoveArea.visualShearAngle * Math.PI / 180),
                            0, callHeader.width / 2, 0)
            }

            PopupMoveArea {
                id: callMoveArea
                anchors.fill: parent
                anchors.rightMargin: 54
                moveTarget: root
                movementBoundary: root.parent
                leftEdge: 10
                topEdge: 10
                rightEdge: 10
                bottomEdge: 10
                enabled: !root.session.panelFullscreen
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 13
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                   root.accentColor.b, root.connected ? 0.16 : 0.08)
                    border.width: 1
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, root.connected ? 0.34 : 0.16)

                    Icons.CallIcon {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        color: root.connected ? root.accentColor : root.textSecondary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 4

                    Label {
                        Layout.fillWidth: true
                        text: root.session.roomName || L10n.I18n.tr("Звонок")
                        color: root.textPrimary
                        font.pointSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 4
                            color: root.session.errorText !== "" ? "#ff6b6b"
                                : root.connected ? root.accentColor : root.textSecondary
                            opacity: root.leaving ? 0.45 : 1

                            Behavior on color {
                                ColorAnimation { duration: L10n.UiPreferences.duration(140) }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.session.errorText !== "" ? L10n.I18n.tr("Не удалось подключиться")
                                : root.leaving ? L10n.I18n.tr("Завершение звонка…")
                                : root.session.reconnecting ? L10n.I18n.tr("Восстанавливаем соединение…")
                                : root.connected ? L10n.I18n.tr("Зашифрованный звонок")
                                : L10n.I18n.tr("Подключение…")
                            color: root.textSecondary
                            font.pointSize: 8
                            elide: Text.ElideRight
                        }
                    }
                }

                VoiceActionButton {
                    id: fullscreenButton
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    padding: 0
                    flatVisual: true
                    toolTipText: root.session.panelFullscreen
                        ? L10n.I18n.tr("Уменьшить демонстрацию") : L10n.I18n.tr("На весь экран PrismChat")
                    contentItem: Item {
                        implicitWidth: 20
                        implicitHeight: 20

                        Canvas {
                            id: fullscreenIcon
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            property bool contracted: root.session.panelFullscreen
                            property color strokeColor: fullscreenButton.foregroundColor

                            onContractedChanged: requestPaint()
                            onStrokeColorChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = strokeColor
                                ctx.lineWidth = 1.8
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.beginPath()
                                if (contracted) {
                                    ctx.moveTo(3, 8); ctx.lineTo(8, 8); ctx.lineTo(8, 3)
                                    ctx.moveTo(17, 8); ctx.lineTo(12, 8); ctx.lineTo(12, 3)
                                    ctx.moveTo(3, 12); ctx.lineTo(8, 12); ctx.lineTo(8, 17)
                                    ctx.moveTo(17, 12); ctx.lineTo(12, 12); ctx.lineTo(12, 17)
                                } else {
                                    ctx.moveTo(8, 3); ctx.lineTo(3, 3); ctx.lineTo(3, 8)
                                    ctx.moveTo(12, 3); ctx.lineTo(17, 3); ctx.lineTo(17, 8)
                                    ctx.moveTo(8, 17); ctx.lineTo(3, 17); ctx.lineTo(3, 12)
                                    ctx.moveTo(12, 17); ctx.lineTo(17, 17); ctx.lineTo(17, 12)
                                }
                                ctx.stroke()
                            }
                        }
                    }
                    accentColor: root.accentColor
                    surfaceColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    dividerColor: root.dividerColor
                    onClicked: root.session.panelFullscreen = !root.session.panelFullscreen
                }

                VoiceActionButton {
                    id: collapseButton
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    padding: 0
                    flatVisual: true
                    toolTipText: root.session.active ? L10n.I18n.tr("Свернуть звонок") : L10n.I18n.tr("Закрыть")
                    iconComponent: Icons.CloseIcon { color: collapseButton.foregroundColor }
                    accentColor: root.accentColor
                    surfaceColor: root.elevatedColor
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    dividerColor: root.dividerColor
                    onClicked: root.session.panelOpen = false
                }
            }
        }
        ScrollView {
            id: errorScroll
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(100, errorLabel.implicitHeight)
            visible: root.session.errorText !== ""
            clip: true
            contentWidth: availableWidth
            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
                trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                    root.textSecondary.b, 0.14)
            }
            Label {
                id: errorLabel
                width: errorScroll.availableWidth
                text: root.session.errorText
                color: root.textPrimary
                font.pointSize: 9
                wrapMode: Text.Wrap
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            color: root.elevatedColor
            radius: 8
            clip: true
            Loader {
                id: web
                anchors.fill: parent
                active: root.session.widgetUrl !== ""
                onActiveChanged: {
                    if (active) setSource("VoiceWebView.qml", {session: root.session})
                    else source = ""
                }
            }
        }
        // Element Call owns media controls; this row is only a loading fallback.
        RowLayout {
            Layout.fillWidth: true
            visible: root.session.active && root.session.widgetUrl === ""
            spacing: 8
            VoiceActionButton {
                id: hangupButton
                Layout.fillWidth: true
                text: root.leaving ? L10n.I18n.tr("Завершение звонка…") : L10n.I18n.tr("Отменить звонок")
                destructive: true
                enabled: root.session.active && !root.leaving
                accentColor: root.accentColor
                surfaceColor: root.elevatedColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.session.leave()
            }
        }
    }
}

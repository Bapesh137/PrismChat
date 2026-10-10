import QtQuick
import QtQuick.Layouts
import "../../assets/icons" as Icons
import "../../utils" as L10n

Rectangle {
    id: root
    property var session: null
    property color surfaceColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color accentColor: "#20D500"
    readonly property bool connected: session && session.phase === "connected"
    readonly property bool leaving: session && (session.phase === "leaving" || session.phase === "ending")
    height: session && session.active ? 104 : 0
    visible: height > 0
    color: surfaceColor

    Rectangle {
        width: parent.width; height: 1
        color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.18)
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6
        VoiceActionButton {
            id: expandButton
            Layout.fillWidth: true
            implicitHeight: 40
            flatVisual: true
            toolTipText: root.session && root.session.panelOpen ? L10n.I18n.tr("Свернуть звонок") : L10n.I18n.tr("Открыть звонок")
            accentColor: root.accentColor
            surfaceColor: root.surfaceColor
            textPrimary: root.textPrimary
            textSecondary: root.textSecondary
            contentItem: RowLayout {
                spacing: 8
                Icons.CallIcon {
                    Layout.preferredWidth: 18; Layout.preferredHeight: 18
                    color: root.connected ? root.accentColor : root.textSecondary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: root.session ? root.session.roomName : ""
                        color: root.textPrimary
                        font.pointSize: 9
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.leaving ? L10n.I18n.tr("Завершение…")
                            : root.session && root.session.reconnecting ? L10n.I18n.tr("Переподключение…")
                            : root.connected ? L10n.I18n.tr("В звонке") : L10n.I18n.tr("Подключение…")
                        color: root.textSecondary
                        font.pointSize: 8
                        elide: Text.ElideRight
                    }
                }
                Icons.ChevronIcon {
                    Layout.preferredWidth: 16; Layout.preferredHeight: 16
                    direction: root.session && root.session.panelOpen ? "down" : "up"
                    color: root.textSecondary
                }
            }
            onClicked: root.session.panelOpen = !root.session.panelOpen
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            VoiceActionButton {
                Layout.fillWidth: true
                text: root.session && root.session.panelOpen ? L10n.I18n.tr("Звонок открыт") : L10n.I18n.tr("Открыть управление звонком")
                enabled: root.session && root.session.active && !root.leaving
                accentColor: root.accentColor
                surfaceColor: root.surfaceColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.session.panelOpen = true
            }
            VoiceActionButton {
                id: hangupButton
                Layout.preferredWidth: 40
                padding: 0
                toolTipText: root.leaving ? L10n.I18n.tr("Завершение звонка…") : L10n.I18n.tr("Завершить звонок")
                iconComponent: Icons.CallIcon { color: hangupButton.foregroundColor; rotation: 135 }
                destructive: true
                enabled: root.session && root.session.active && !root.leaving
                accentColor: root.accentColor
                surfaceColor: root.surfaceColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.session.leave()
            }
        }
    }
}

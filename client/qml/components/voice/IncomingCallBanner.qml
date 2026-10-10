import QtQuick
import QtQuick.Layouts
import "../common"
import "../../assets/icons" as Icons
import "../../utils" as L10n

Rectangle {
    id: root
    required property var session
    property string mediaProxy: ""
    property bool roundAvatars: true
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color accentColor: "#20D500"
    visible: session.hasIncoming
    width: Math.max(0, Math.min(380, parent ? parent.width - 32 : 380))
    implicitHeight: content.implicitHeight + 28
    height: implicitHeight
    radius: 12
    color: elevatedColor
    border.width: 1
    border.color: Qt.rgba(textSecondary.r, textSecondary.g, textSecondary.b, 0.24)

    MouseArea { anchors.fill: parent; onWheel: function(wheel) { wheel.accepted = true } }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            AvatarItem {
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                size: 40
                mxcUrl: root.session.incomingCallerAvatar
                fallbackId: root.session.incomingCallerName || root.session.incomingCallerId
                mediaProxy: root.mediaProxy
                roundAvatars: root.roundAvatars
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 3
                Text {
                    Layout.fillWidth: true
                    text: root.session.incomingCallerName || root.session.incomingCallerId
                    color: root.textPrimary
                    font.weight: Font.DemiBold
                    font.pointSize: 10
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: L10n.I18n.tr("Входящий звонок")
                    color: root.textSecondary
                    font.pointSize: 9
                    elide: Text.ElideRight
                }
            }
            Icons.CallIcon {
                Layout.preferredWidth: 20; Layout.preferredHeight: 20
                color: root.accentColor
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            VoiceActionButton {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: L10n.I18n.tr("Отклонить")
                destructive: true
                enabled: root.session.hasIncoming
                accentColor: root.accentColor
                surfaceColor: root.surfaceColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.session.declineIncoming()
            }
            VoiceActionButton {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: L10n.I18n.tr("Принять")
                primary: true
                // Keep the same scale press animation as the other actions,
                // without flashing the green accept button dark.
                changePrimaryColorOnPress: false
                enabled: root.session.hasIncoming
                accentColor: root.accentColor
                surfaceColor: root.surfaceColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.session.acceptIncoming()
            }
        }
    }
}

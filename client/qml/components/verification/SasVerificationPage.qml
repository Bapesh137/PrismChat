import QtQuick
import "../../settings"
import "../../utils" as L10n

Column {
    id: root
    property var emojis: []
    property var emojiDescriptions: []
    property var decimals: []
    property bool showDecimals: false
    property color accentColor: "#20D500"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal confirmed()
    signal mismatched()
    spacing: 12

    Text { text: L10n.I18n.tr("Сравните эмодзи"); color: root.textPrimary; font.bold: true; font.pointSize: 13 }
    Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Убедитесь, что на обоих устройствах показана одинаковая последовательность."); color: root.textSecondary; font.pointSize: 8 }
    Grid {
        visible: !root.showDecimals; columns: 4; spacing: 10
        Repeater {
            model: root.emojis || []
            delegate: Column {
                required property string modelData
                required property int index
                width: 72; spacing: 3
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData; font.pointSize: 24 }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: root.emojiDescriptions && index < root.emojiDescriptions.length ? root.emojiDescriptions[index] : ""; color: root.textSecondary; font.pointSize: 7 }
            }
        }
    }
    Text { visible: root.showDecimals; text: (root.decimals || []).join("   "); color: root.textPrimary; font.family: "monospace"; font.bold: true; font.pointSize: 18 }
    Text { visible: root.decimals && root.decimals.length > 0; text: root.showDecimals ? L10n.I18n.tr("Сравнить эмодзи") : L10n.I18n.tr("Сравнить числа вместо эмодзи"); color: root.accentColor; font.pointSize: 8; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showDecimals = !root.showDecimals } }
    Row {
        spacing: 8
        SettingsActionButton { destructive: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Не совпадают"); onClicked: root.mismatched() }
        SettingsActionButton { primary: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Совпадают"); onClicked: root.confirmed() }
    }
}

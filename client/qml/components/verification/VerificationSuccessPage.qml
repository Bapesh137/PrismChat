import QtQuick
import "../../settings"
import "../../utils" as L10n
import "../../assets/icons" as Icons

Column {
    id: root
    property color accentColor: "#20D500"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal done()
    spacing: 12
    Icons.CheckIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 48; height: 48; color: root.accentColor; capStyle: "butt" }
    Text { anchors.horizontalCenter: parent.horizontalCenter; text: L10n.I18n.tr("Устройство подтверждено"); color: root.textPrimary; font.pointSize: 13; font.bold: true }
    Text { width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; text: L10n.I18n.tr("Теперь этой сессии можно доверять для защищённого обмена сообщениями."); color: root.textSecondary; font.pointSize: 8 }
    SettingsActionButton { anchors.horizontalCenter: parent.horizontalCenter; primary: true; accentColor: root.accentColor; surfaceColor: root.elevatedColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; text: L10n.I18n.tr("Готово"); onClicked: root.done() }
}

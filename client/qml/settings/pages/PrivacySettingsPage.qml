import QtQuick
import QtQuick.Controls.Basic as Basic
import "../../utils" as L10n

Item {
    id: root
    property bool sendReadReceipts: true
    property bool sendTypingNotifications: true
    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal preferencesChanged(bool sendReadReceipts,
                              bool sendTypingNotifications)

    Column {
        width: parent.width; spacing: 14
        Text { text: L10n.I18n.tr("Приватность"); color: root.textPrimary; font.bold: true; font.pointSize: 13 }
        Rectangle {
            width: parent.width; implicitHeight: privacyContent.implicitHeight + 24
            radius: 9; color: root.surfaceColor
            Column {
                id: privacyContent; anchors.fill: parent; anchors.margins: 12; spacing: 8
                Text { text: L10n.I18n.tr("Отметки о прочтении"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Сообщать участникам комнат, до какого сообщения вы дочитали. Для отдельных комнат настройку можно изменить в «Редактировать комнату»."); color: root.textSecondary; font.pointSize: 8 }
                Basic.Switch {
                    checked: root.sendReadReceipts
                    text: checked ? L10n.I18n.tr("Отправлять отметки о прочтении") : L10n.I18n.tr("Не отправлять отметки о прочтении")
                    onToggled: {
                        root.sendReadReceipts = checked
                        root.preferencesChanged(root.sendReadReceipts,
                                                root.sendTypingNotifications)
                    }
                }
            }
        }
        Rectangle {
            width: parent.width; implicitHeight: typingPrivacyContent.implicitHeight + 24
            radius: 9; color: root.surfaceColor
            Column {
                id: typingPrivacyContent; anchors.fill: parent; anchors.margins: 12; spacing: 8
                Text { text: L10n.I18n.tr("Индикатор набора текста"); color: root.textPrimary; font.bold: true; font.pointSize: 10 }
                Text { width: parent.width; wrapMode: Text.Wrap; text: L10n.I18n.tr("Сообщать участникам комнаты, когда вы набираете сообщение. Для отдельных комнат настройку можно изменить в «Редактировать комнату»."); color: root.textSecondary; font.pointSize: 8 }
                Basic.Switch {
                    checked: root.sendTypingNotifications
                    text: checked ? L10n.I18n.tr("Отправлять индикатор набора текста") : L10n.I18n.tr("Не отправлять индикатор набора текста")
                    onToggled: {
                        root.sendTypingNotifications = checked
                        root.preferencesChanged(root.sendReadReceipts,
                                                root.sendTypingNotifications)
                    }
                }
            }
        }
    }
}

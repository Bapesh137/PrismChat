import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components/common"
import "../../utils" as L10n

Flickable {
    id: root

    property string title: L10n.I18n.tr("Уведомления")
    property bool systemNotificationsEnabled: true
    property bool systemInvitationNotificationsEnabled: true
    property bool systemMentionNotificationsEnabled: true

    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal preferencesChanged(bool enabled, bool invitationsEnabled,
                              bool mentionsEnabled)

    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + 8
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: contentColumn
        width: root.width
        spacing: 12

        Text {
            width: parent.width
            text: root.title
            color: root.textPrimary
            font.bold: true
            font.pointSize: 13
        }

        Text {
            width: parent.width
            text: L10n.I18n.tr("Выберите, какие события PrismChat может показывать через системные уведомления Windows.")
            color: root.textSecondary
            font.pointSize: 8
            wrapMode: Text.Wrap
        }

        Rectangle {
            width: parent.width
            implicitHeight: masterRow.implicitHeight + 24
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.14)

            RowLayout {
                id: masterRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Column {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        width: parent.width
                        text: L10n.I18n.tr("Системные уведомления")
                        color: root.textPrimary
                        font.pointSize: 10
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: L10n.I18n.tr("Отключите, чтобы PrismChat вообще не отправлял уведомления Windows.")
                        color: root.textSecondary
                        font.pointSize: 8
                        wrapMode: Text.Wrap
                    }
                }

                StyledSwitch {
                    id: masterNotificationSwitch
                    checked: root.systemNotificationsEnabled
                    accentColor: root.accentColor
                    inactiveColor: root.textSecondary
                    onToggled: root.preferencesChanged(
                        checked,
                        root.systemInvitationNotificationsEnabled,
                        root.systemMentionNotificationsEnabled)
                }
            }
        }

        Rectangle {
            width: parent.width
            implicitHeight: typeColumn.implicitHeight + 24
            radius: 10
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                  root.textSecondary.b, 0.14)

            Column {
                id: typeColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Text {
                    width: parent.width
                    text: L10n.I18n.tr("Типы системных уведомлений")
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: true
                }

                Column {
                    width: parent.width
                    spacing: 3
                    opacity: root.systemNotificationsEnabled ? 1 : 0.48

                    RowLayout {
                        width: parent.width
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: L10n.I18n.tr("Приглашения в комнаты")
                            color: root.textPrimary
                            font.pointSize: 9
                        }

                        StyledSwitch {
                            Layout.alignment: Qt.AlignVCenter
                            checked: root.systemInvitationNotificationsEnabled
                            enabled: root.systemNotificationsEnabled
                            accentColor: root.accentColor
                            inactiveColor: root.textSecondary
                            onToggled: root.preferencesChanged(
                                root.systemNotificationsEnabled,
                                checked,
                                root.systemMentionNotificationsEnabled)
                        }
                    }

                    Text {
                        width: parent.width - 56
                        text: L10n.I18n.tr("Когда вас приглашают в новую комнату или чат.")
                        color: root.textSecondary
                        font.pointSize: 8
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.dividerColor
                    opacity: 0.65
                }

                Column {
                    width: parent.width
                    spacing: 3
                    opacity: root.systemNotificationsEnabled ? 1 : 0.48

                    RowLayout {
                        width: parent.width
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: L10n.I18n.tr("Упоминания в чатах")
                            color: root.textPrimary
                            font.pointSize: 9
                        }

                        StyledSwitch {
                            Layout.alignment: Qt.AlignVCenter
                            checked: root.systemMentionNotificationsEnabled
                            enabled: root.systemNotificationsEnabled
                            accentColor: root.accentColor
                            inactiveColor: root.textSecondary
                            onToggled: root.preferencesChanged(
                                root.systemNotificationsEnabled,
                                root.systemInvitationNotificationsEnabled,
                                checked)
                        }
                    }

                    Text {
                        width: parent.width - 56
                        text: L10n.I18n.tr("Только сообщения с вашим Matrix ID, @именем или упоминанием @room.")
                        color: root.textSecondary
                        font.pointSize: 8
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: L10n.I18n.tr("Эти параметры не очищают внутренние вкладки колокольчика — они управляют только системными уведомлениями.")
            color: root.textSecondary
            opacity: 0.78
            font.pointSize: 8
            wrapMode: Text.Wrap
        }
    }
}

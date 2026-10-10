import QtQuick
import "../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

Basic.Dialog {
    id: root

    property color backgroundColor: "#07100A"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal confirmed()

    title: L10n.I18n.tr("Выйти из аккаунта?")
    modal: true
    implicitWidth: 360
    width: implicitWidth

    background: Rectangle {
        color: root.backgroundColor
        radius: 12
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.15)
        border.width: 1
    }

    contentItem: Column {
        spacing: 12
        Text {
            text: L10n.I18n.tr("Сессия будет удалена с устройства.")
            color: root.textPrimary
            font.pointSize: 10
        }
        Row {
            spacing: 10
            Basic.Button {
                text: L10n.I18n.tr("Выйти")
                height: 36
                background: Rectangle { radius: 8; color: "#ff5252" }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.bold: true
                }
                onClicked: {
                    root.close()
                    root.confirmed()
                }
            }
            Basic.Button { text: L10n.I18n.tr("Отмена"); height: 36; flat: true; onClicked: root.close() }
        }
    }
}

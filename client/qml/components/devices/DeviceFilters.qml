import QtQuick
import QtQuick.Controls.Basic as Basic
import "../../utils" as L10n

Column {
    id: root
    property string query: ""
    property string filter: "all"
    property color accentColor: "#20D500"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    signal queryEdited(string value)
    signal filterSelected(string value)
    spacing: 8

    Basic.TextField {
        width: parent.width; height: 36
        placeholderText: L10n.I18n.tr("Поиск по названию или Device ID")
        text: root.query
        color: root.textPrimary; placeholderTextColor: root.textSecondary
        leftPadding: 12; rightPadding: 12; selectByMouse: true
        onTextEdited: root.queryEdited(text)
        background: Rectangle {
            radius: 8; color: root.elevatedColor; border.width: 1
            border.color: parent.activeFocus ? root.accentColor
                : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.16)
        }
    }
    Row {
        spacing: 6
        Repeater {
            model: [
                { key: "all", label: L10n.I18n.tr("Все") },
                { key: "verified", label: L10n.I18n.tr("Подтверждённые") },
                { key: "unverified", label: L10n.I18n.tr("Не подтверждённые") },
                { key: "inactive", label: L10n.I18n.tr("Неактивные") }
            ]
            delegate: Rectangle {
                required property var modelData
                height: 29; width: filterLabel.implicitWidth + 20; radius: 8
                color: root.filter === modelData.key
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.17)
                    : filterMouse.containsMouse ? Qt.rgba(root.textPrimary.r, root.textPrimary.g, root.textPrimary.b, 0.06) : "transparent"
                border.width: 1
                border.color: root.filter === modelData.key ? root.accentColor
                    : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.14)
                Text { id: filterLabel; anchors.centerIn: parent; text: modelData.label; color: root.filter === modelData.key ? root.accentColor : root.textSecondary; font.pointSize: 8 }
                MouseArea { id: filterMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filterSelected(modelData.key) }
            }
        }
    }
}

import QtQuick
import "../../utils" as L10n
import "../../assets/icons" as Icons

Row {
    id: root
    property string verificationState: "unknown"
    property color accentColor: "#20D500"
    property color textSecondary: "#A7B8AA"
    spacing: 5

    Icons.CheckIcon {
        visible: root.verificationState === "verified"
        anchors.verticalCenter: parent.verticalCenter
        width: 12; height: 12
        color: root.accentColor
        capStyle: "butt"
    }
    Text {
        visible: root.verificationState !== "verified"
        text: root.verificationState === "unverified" ? "⚠" : "?"
        color: root.verificationState === "verified" ? root.accentColor
            : root.verificationState === "unverified" ? "#f0b35a" : root.textSecondary
        font.bold: true
        font.pointSize: 8
    }
    Text {
        text: root.verificationState === "verified" ? L10n.I18n.tr("Подтверждено")
            : root.verificationState === "unverified" ? L10n.I18n.tr("Не подтверждено")
            : L10n.I18n.tr("Статус неизвестен")
        color: root.verificationState === "verified" ? root.accentColor
            : root.verificationState === "unverified" ? "#f0b35a" : root.textSecondary
        font.pointSize: 8
    }
}

import QtQuick
import "../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../components/common"

Basic.Dialog {
    id: root

    property string messageText: ""
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color textPrimary: "#F2FFF4"

    title: L10n.I18n.tr("Исходник сообщения")
    width: 420
    height: 320
    modal: true

    background: Rectangle { color: root.backgroundColor; radius: 12 }

    contentItem: ScrollView {
        ScrollBar.vertical: PrismScrollBar {
            policy: ScrollBar.AsNeeded
            autoHide: true
        }
        Basic.TextArea {
            text: root.messageText
            readOnly: true
            color: root.textPrimary
            font.family: "monospace"
            font.pointSize: 9
            wrapMode: TextArea.Wrap
            background: Rectangle { color: root.surfaceColor; radius: 8 }
        }
    }

    footer: DialogButtonBox {
        Basic.Button {
            text: L10n.I18n.tr("Закрыть")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }
}

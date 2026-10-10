import QtQuick
import "../../utils" as L10n

Column {
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"

    spacing: 12
    Text { text: "PrismChat"; color: parent.textPrimary; font.bold: true; font.pointSize: 16 }
    Text {
        text: L10n.I18n.tr("Минималистичный Matrix-клиент • Rust + QML")
        color: parent.textSecondary
        font.pointSize: 9
    }
    Text {
        text: L10n.I18n.tr("Версия: 0.2.0-dev\nБэкенд: Rust + tokio + axum\nПротокол: Matrix Client-Server v1.11+")
        color: parent.textPrimary
        font.pointSize: 9
    }
}

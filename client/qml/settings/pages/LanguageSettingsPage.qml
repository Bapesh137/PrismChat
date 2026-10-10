import QtQuick
import QtQuick.Controls
import "../../components/common"
import "../../utils" as L10n

Item {
    id: root

    property string currentLanguage: L10n.I18n.language
    property color accentColor: "#20D500"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"

    signal languageSelected(string code)

    // The picker always needs its bundled CJK labels.
    FontLoader {
        id: cjkLanguageListFont
        source: Qt.resolvedUrl("../../assets/NotoSansCJK-Regular.ttc")
    }

    readonly property var availableFontFamilies: Qt.fontFamilies()

    function firstAvailableFont(candidates) {
        for (var candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
            var candidate = candidates[candidateIndex]
            for (var familyIndex = 0; familyIndex < availableFontFamilies.length; familyIndex++) {
                if (String(availableFontFamilies[familyIndex]).toLowerCase() === candidate.toLowerCase())
                    return availableFontFamilies[familyIndex]
            }
        }
        return ""
    }

    function languageFontFamily(code) {
        if (code === "zh" && cjkLanguageListFont.status === FontLoader.Ready)
            return "Noto Sans CJK SC"
        if (code === "ja" && cjkLanguageListFont.status === FontLoader.Ready)
            return "Noto Sans CJK JP"
        if (code === "ko" && cjkLanguageListFont.status === FontLoader.Ready)
            return "Noto Sans CJK KR"

        // Prefer fonts that cover each native language label.
        if (code === "hi")
            return firstAvailableFont(["Noto Sans Devanagari UI", "Noto Sans Devanagari",
                                       "Nirmala UI", "Kohinoor Devanagari", "Mangal"])
        if (code === "ta")
            return firstAvailableFont(["Noto Sans Tamil UI", "Noto Sans Tamil",
                                       "Nirmala UI", "Tamil MN", "Latha"])
        if (code === "te")
            return firstAvailableFont(["Noto Sans Telugu UI", "Noto Sans Telugu",
                                       "Nirmala UI", "Gautami"])
        if (code === "bn")
            return firstAvailableFont(["Noto Sans Bengali UI", "Noto Sans Bengali",
                                       "Nirmala UI", "Bangla Sangam MN", "Vrinda"])
        if (code === "th")
            return firstAvailableFont(["Noto Sans Thai UI", "Noto Sans Thai",
                                       "Leelawadee UI", "Thonburi", "Tahoma"])
        return ""
    }

    function blendedItemColor(base, overlay, amount) {
        var alpha = Math.max(0, Math.min(1, amount))
        return Qt.rgba(base.r * (1 - alpha) + overlay.r * alpha,
                       base.g * (1 - alpha) + overlay.g * alpha,
                       base.b * (1 - alpha) + overlay.b * alpha, 1)
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Text {
            width: parent.width
            text: L10n.I18n.tr("Язык")
            color: root.textPrimary
            font.bold: true
            font.pointSize: 13
        }

        Text {
            width: parent.width
            text: L10n.I18n.tr("Язык интерфейса")
            color: root.textPrimary
            font.bold: true
            font.pointSize: 10
        }

        Text {
            width: parent.width
            text: L10n.I18n.tr("Изменения применяются сразу. При первом запуске используется язык системы.")
            color: root.textSecondary
            font.pointSize: 8
            wrapMode: Text.WordWrap
        }

        Item { width: 1; height: 4 }

        ListView {
            id: languageList
            width: parent.width
            height: parent.height - y
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: L10n.I18n.supportedLanguages
            currentIndex: L10n.I18n.languageIndex(root.currentLanguage)

            delegate: Rectangle {
                id: languageItem
                required property var modelData
                required property int index

                width: languageList.width - 12
                height: 42
                radius: 9
                scale: languageMouse.pressed ? 0.98 : 1
                color: languageMouse.pressed
                    ? root.blendedItemColor(root.surfaceColor, root.accentColor,
                                            modelData.code === root.currentLanguage ? 0.22 : 0.12)
                    : modelData.code === root.currentLanguage
                        ? root.blendedItemColor(root.surfaceColor, root.accentColor, 0.16)
                        : languageMouse.containsMouse
                            ? root.blendedItemColor(root.surfaceColor, root.textPrimary, 0.06)
                            : root.surfaceColor
                border.width: 1
                border.color: modelData.code === root.currentLanguage
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.72)
                    : Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.14)

                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(110) } }
                Behavior on scale {
                    NumberAnimation { duration: L10n.UiPreferences.duration(95); easing.type: Easing.OutCubic }
                }

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    Rectangle {
                        id: selectionIndicator
                        width: 16
                        height: 16
                        radius: 8
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"
                        border.width: 1.5
                        border.color: languageItem.modelData.code === root.currentLanguage
                            ? root.accentColor : root.textSecondary

                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
                            color: root.accentColor
                            visible: languageItem.modelData.code === root.currentLanguage
                        }
                    }

                    Text {
                        anchors.left: selectionIndicator.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: languageItem.modelData.name
                        color: root.textPrimary
                        font.family: root.languageFontFamily(languageItem.modelData.code)
                        // Let Qt choose a script-wide fallback font.
                        font.contextFontMerging: true
                        font.pointSize: 10
                        font.bold: languageItem.modelData.code === root.currentLanguage
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(languageItem.modelData.code).toUpperCase()
                        color: root.textSecondary
                        font.pointSize: 8
                    }
                }

                MouseArea {
                    id: languageMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.languageSelected(languageItem.modelData.code)
                }
            }

            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
            }
        }
    }
}

import QtQuick
import "../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Prism.Ipc 1.0 as Native
import "../../components/common"
import "../../themes" as Themes

Item {
    id: root

    property string themeMode: "dark"
    property string darkThemeId: "green"
    property string lightThemeId: "green"
    property int automaticLightStartMinutes: 420
    property int automaticDarkStartMinutes: 1140
    property bool roundAvatars: true
    property bool showSpaceRoomsInHome: false
    property bool showThreadsInSmallGroups: false
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"
    property real uiScale: 1.0
    property bool animationsEnabled: true
    property string windowWobbleMode: "off"
    property int windowSpringStrength: 100
    property int windowWobbleStrength: 50
    property int startupIntroVariant: 0

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color surfaceColor: "#0B1710"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color elevatedColor: "#102016"
    property color backgroundColor: "#07100A"
    property color dividerColor: "#29402E"
    property color customAccentColor: "#20D500"
    property color customIconColor: customAccentColor
    property color customBackgroundColor: "#07100A"
    property color customSurfaceColor: "#0B1710"
    property color customElevatedColor: "#102016"
    property color customTextPrimary: "#F2FFF4"
    property color customTextSecondary: "#A7B8AA"
    property color customDividerColor: "#29402E"
    property string selectedCustomColorKey: ""
    property string selectedCustomColorLabel: ""
    property string desktopShortcutStatus: ""
    property bool desktopShortcutError: false

    function createDesktopShortcut() {
        var result = Native.FrontendLogic.invoke(
            "window.createDesktopShortcut", root, [])
        if (result && result.ok) {
            desktopShortcutError = false
            desktopShortcutStatus = L10n.I18n.tr(
                "Ярлык создан на рабочем столе")
        } else {
            desktopShortcutError = true
            desktopShortcutStatus = L10n.I18n.tr(
                "Не удалось создать ярлык")
        }
    }

    readonly property var customColorRows: [
        { key: "accent", label: L10n.I18n.tr("Цвет акцента"), value: customAccentColor },
        { key: "icons", label: L10n.I18n.tr("Цвет иконок"), value: customIconColor },
        { key: "background", label: L10n.I18n.tr("Основной фон"), value: customBackgroundColor },
        { key: "surface", label: L10n.I18n.tr("Поверхность панелей"), value: customSurfaceColor },
        { key: "elevated", label: L10n.I18n.tr("Всплывающие элементы"), value: customElevatedColor },
        { key: "text_primary", label: L10n.I18n.tr("Основной текст"), value: customTextPrimary },
        { key: "text_secondary", label: L10n.I18n.tr("Вторичный текст"), value: customTextSecondary },
        { key: "divider", label: L10n.I18n.tr("Разделители"), value: customDividerColor }
    ]

    signal themeModeSelected(string mode)
    signal themeVariantSelected(string mode, string themeId)
    signal automaticScheduleSelected(int lightStartMinutes, int darkStartMinutes)
    signal roundAvatarsSelected(bool enabled)
    signal spaceRoomsInHomeSelected(bool enabled)
    signal threadsInSmallGroupsSelected(bool enabled)
    signal dateFormatSelected(string format)
    signal timeFormatSelected(string format)
    signal uiScaleSelected(real scale)
    signal animationsSelected(bool enabled)
    signal windowWobbleModeSelected(string mode)
    signal windowSpringStrengthSelected(int strength)
    signal windowWobbleStrengthSelected(int strength)
    signal startupIntroVariantSelected(int variant)
    signal startupIntroPickerRequested()
    signal customColorSelected(string key, string colorValue)

    component ChoiceRow: Rectangle {
        id: choiceRow

        property string labelText: ""
        property string helpText: ""
        property var choices: []
        property int choiceIndex: 0

        signal selected(int index)

        height: 58
        radius: 8
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                              root.textSecondary.b, 0.10)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: choiceRow.labelText
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: choiceRow.helpText
                    color: root.textSecondary
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                }
            }

            StyledComboBox {
                Layout.preferredWidth: 190
                model: choiceRow.choices
                currentIndex: choiceRow.choiceIndex
                accentColor: root.accentColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                surfaceColor: root.surfaceColor
                elevatedColor: root.elevatedColor
                onActivated: function(index) { choiceRow.selected(index) }
            }
        }
    }

    component StrengthRow: Rectangle {
        id: strengthRow

        property string labelText: ""
        property string helpText: ""
        property int strengthValue: 100

        signal selected(int value)

        height: 82
        radius: 8
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                              root.textSecondary.b, 0.10)

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Row {
                width: parent.width

                Column {
                    width: parent.width - strengthPercent.width
                    spacing: 1

                    Text {
                        text: strengthRow.labelText
                        color: root.textPrimary
                        font.pointSize: 10
                        font.bold: true
                    }
                    Text {
                        text: strengthRow.helpText
                        color: root.textSecondary
                        font.pointSize: 8
                    }
                }

                Text {
                    id: strengthPercent
                    text: Math.round(strengthRow.strengthValue) + "%"
                    color: root.accentColor
                    font.pointSize: 9
                    font.bold: true
                }
            }

            Slider {
                width: parent.width
                from: 0
                to: 100
                stepSize: 1
                value: strengthRow.strengthValue
                onMoved: strengthRow.selected(Math.round(value))
            }
        }
    }

    function openColorEditor(key, label, value) {
        selectedCustomColorKey = key
        selectedCustomColorLabel = label
        customColorDialog.selectedColor = value
        customColorDialog.open()
    }

    function themeModeIndex(mode) {
        var index = ["system", "automatic", "dark", "light", "custom"].indexOf(String(mode || ""))
        return index >= 0 ? index : 2
    }

    function syncThemeModeCombo() {
        if (!themeModeCombo)
            return
        var index = themeModeIndex(root.themeMode)
        if (themeModeCombo.currentIndex !== index)
            themeModeCombo.currentIndex = index
    }

    onThemeModeChanged: Qt.callLater(syncThemeModeCombo)
    onVisibleChanged: {
        if (visible)
            Qt.callLater(syncThemeModeCombo)
    }
    Component.onCompleted: Qt.callLater(syncThemeModeCombo)

    function themeIndex(mode, themeId) {
        var themes = Themes.ThemeCatalog.themesFor(mode)
        for (var index = 0; index < themes.length; ++index) {
            if (String(themes[index].id) === String(themeId))
                return index
        }
        return 0
    }

    readonly property var hourLabels: {
        var values = []
        for (var hour = 0; hour < 24; ++hour)
            values.push((hour < 10 ? "0" : "") + hour)
        return values
    }

    readonly property var minuteLabels: {
        var values = []
        for (var minute = 0; minute < 60; ++minute)
            values.push((minute < 10 ? "0" : "") + minute)
        return values
    }

    function normalizedMinutes(value) {
        return Math.max(0, Math.min(1439, Number(value || 0)))
    }

    function hourIndex(value) {
        return Math.floor(normalizedMinutes(value) / 60)
    }

    function minuteIndex(value) {
        return normalizedMinutes(value) % 60
    }

    function minutesFrom(hourIndexValue, minuteIndexValue) {
        return Math.max(0, Math.min(23, Number(hourIndexValue))) * 60
            + Math.max(0, Math.min(59, Number(minuteIndexValue)))
    }

    ColorDialog {
        id: customColorDialog
        title: L10n.I18n.tr("Выберите цвет") + ": " + root.selectedCustomColorLabel
        onAccepted: root.customColorSelected(
            root.selectedCustomColorKey, selectedColor.toString())
    }

    Flickable {
        id: settingsFlickable

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: settingsScrollArea.visible
            ? settingsScrollArea.width
            : 0

        clip: true
        interactive: true

        contentWidth: width
        contentHeight: contentColumn.implicitHeight

        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        onContentYChanged: {
            if (settingsScrollArea.visible)
                settingsScrollBar.showTemporarily()
        }

        onMovementStarted: {
            settingsScrollBar.showTemporarily()
        }

        onMovementEnded: {
            settingsScrollBar.scheduleHide()
        }

        Column {
            id: contentColumn

            width: settingsFlickable.width
            spacing: 14

            Text {
                text: L10n.I18n.tr("Внешний вид")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 13
            }

            Rectangle {
                width: parent.width
                height: 60
                radius: 8

                color: root.surfaceColor

                border.color: Qt.rgba(
                    root.textSecondary.r,
                    root.textSecondary.g,
                    root.textSecondary.b,
                    0.10
                )
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Column {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: L10n.I18n.tr("Тема")
                            color: root.textPrimary
                            font.pointSize: 10
                            font.bold: true
                        }
                    }

                    StyledComboBox {
                        id: themeModeCombo
                        Layout.preferredWidth: 190

                        model: [
                            L10n.I18n.tr("Системная"),
                            L10n.I18n.tr("Автоматическая"),
                            L10n.I18n.tr("Тёмная"),
                            L10n.I18n.tr("Светлая"),
                            L10n.I18n.tr("Пользовательская")
                        ]

                        accentColor: root.accentColor
                        textPrimary: root.textPrimary
                        textSecondary: root.textSecondary
                        surfaceColor: root.surfaceColor
                        elevatedColor: root.elevatedColor

                        onActivated: function(index) {
                            root.themeModeSelected(
                                ["system", "automatic", "dark", "light", "custom"][index]
                            )
                        }
                    }
                }
            }

            Rectangle {
                visible: root.themeMode === "automatic"
                width: parent.width
                height: visible ? automaticThemesColumn.implicitHeight + 24 : 0
                radius: 8
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.10)
                clip: true

                Column {
                    id: automaticThemesColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 10

                    Text {
                        text: L10n.I18n.tr("Автоматическая смена темы")
                        color: root.textPrimary
                        font.pointSize: 10
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: L10n.I18n.tr("Выберите светлую и тёмную темы и время их включения")
                        color: root.textSecondary
                        font.pointSize: 8
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: L10n.I18n.tr("Дневная тема")
                            color: root.textPrimary
                            font.pointSize: 9
                        }

                        StyledComboBox {
                            Layout.preferredWidth: 210
                            model: Themes.ThemeCatalog.themesFor("light")
                            textRole: "name"
                            currentIndex: root.themeIndex("light", root.lightThemeId)
                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor
                            onActivated: function(index) {
                                var themes = Themes.ThemeCatalog.themesFor("light")
                                if (index >= 0 && index < themes.length)
                                    root.themeVariantSelected("light", themes[index].id)
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 12

                        Text {
                            Layout.fillWidth: true
                            text: L10n.I18n.tr("Ночная тема")
                            color: root.textPrimary
                            font.pointSize: 9
                        }

                        StyledComboBox {
                            Layout.preferredWidth: 210
                            model: Themes.ThemeCatalog.themesFor("dark")
                            textRole: "name"
                            currentIndex: root.themeIndex("dark", root.darkThemeId)
                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor
                            onActivated: function(index) {
                                var themes = Themes.ThemeCatalog.themesFor("dark")
                                if (index >= 0 && index < themes.length)
                                    root.themeVariantSelected("dark", themes[index].id)
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: L10n.I18n.tr("Светлая тема с")
                            color: root.textPrimary
                            font.pointSize: 9
                        }

                        StyledComboBox {
                            id: lightStartHour
                            Layout.preferredWidth: 84
                            leftPadding: 4
                            rightPadding: 22
                            model: root.hourLabels
                            currentIndex: root.hourIndex(root.automaticLightStartMinutes)
                            displayText: currentIndex >= 0 && currentIndex < root.hourLabels.length
                                ? root.hourLabels[currentIndex] : "00"
                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor
                            onActivated: root.automaticScheduleSelected(
                                root.minutesFrom(currentIndex, lightStartMinute.currentIndex),
                                root.automaticDarkStartMinutes)
                        }
                        Text { text: ":"; color: root.textPrimary; font.pointSize: 10; font.bold: true }
                        StyledComboBox {
                            id: lightStartMinute
                            Layout.preferredWidth: 84
                            leftPadding: 4
                            rightPadding: 22
                            model: root.minuteLabels
                            currentIndex: root.minuteIndex(root.automaticLightStartMinutes)
                            displayText: currentIndex >= 0 && currentIndex < root.minuteLabels.length
                                ? root.minuteLabels[currentIndex] : "00"
                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor
                            onActivated: root.automaticScheduleSelected(
                                root.minutesFrom(lightStartHour.currentIndex, currentIndex),
                                root.automaticDarkStartMinutes)
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: L10n.I18n.tr("Тёмная тема с")
                            color: root.textPrimary
                            font.pointSize: 9
                        }

                        StyledComboBox {
                            id: darkStartHour
                            Layout.preferredWidth: 84
                            leftPadding: 4
                            rightPadding: 22
                            model: root.hourLabels
                            currentIndex: root.hourIndex(root.automaticDarkStartMinutes)
                            displayText: currentIndex >= 0 && currentIndex < root.hourLabels.length
                                ? root.hourLabels[currentIndex] : "00"
                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor
                            onActivated: root.automaticScheduleSelected(
                                root.automaticLightStartMinutes,
                                root.minutesFrom(currentIndex, darkStartMinute.currentIndex))
                        }
                        Text { text: ":"; color: root.textPrimary; font.pointSize: 10; font.bold: true }
                        StyledComboBox {
                            id: darkStartMinute
                            Layout.preferredWidth: 84
                            leftPadding: 4
                            rightPadding: 22
                            model: root.minuteLabels
                            currentIndex: root.minuteIndex(root.automaticDarkStartMinutes)
                            displayText: currentIndex >= 0 && currentIndex < root.minuteLabels.length
                                ? root.minuteLabels[currentIndex] : "00"
                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor
                            onActivated: root.automaticScheduleSelected(
                                root.automaticLightStartMinutes,
                                root.minutesFrom(darkStartHour.currentIndex, currentIndex))
                        }
                    }

                }
            }

            Rectangle {
                id: builtInThemePicker

                visible: root.themeMode === "dark" || root.themeMode === "light"
                width: parent.width
                height: visible ? 82 : 0
                radius: 8
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.10)
                clip: true

                readonly property string selectedThemeId: root.themeMode === "light"
                    ? root.lightThemeId : root.darkThemeId
                readonly property var availableThemes:
                    Themes.ThemeCatalog.themesFor(root.themeMode)

                Flickable {
                    id: themeVariantsFlickable

                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7

                    clip: true
                    interactive: contentWidth > width
                    contentWidth: Math.max(width, themeVariantsRow.implicitWidth)
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: themeVariantsRow

                        x: Math.max(0,
                            (themeVariantsFlickable.width - implicitWidth) / 2)
                        y: Math.max(0,
                            (themeVariantsFlickable.height - height) / 2 - 2)
                        spacing: 12

                        Repeater {
                            model: builtInThemePicker.availableThemes

                            delegate: Item {
                                id: themeButton

                                required property var modelData

                                width: 44
                                height: 50
                                scale: themeMouse.pressed ? 0.88
                                    : themeMouse.containsMouse ? 1.08 : 1

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: L10n.UiPreferences.duration(100)
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                Rectangle {
                                    id: selectionRing

                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: themeMouse.containsMouse
                                        ? Qt.rgba(root.accentColor.r,
                                                  root.accentColor.g,
                                                  root.accentColor.b, 0.10)
                                        : "transparent"
                                    border.width: themeButton.modelData.id
                                        === builtInThemePicker.selectedThemeId ? 3 : 1
                                    border.color: themeButton.modelData.id
                                        === builtInThemePicker.selectedThemeId
                                        ? root.textPrimary
                                        : Qt.rgba(root.textPrimary.r,
                                                  root.textPrimary.g,
                                                  root.textPrimary.b, 0.24)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: L10n.UiPreferences.duration(90)
                                        }
                                    }

                                    Canvas {
                                        id: yinYangIcon

                                        anchors.centerIn: parent
                                        width: 28
                                        height: 28

                                        property color firstColor:
                                            themeButton.modelData.accent
                                        property color secondColor:
                                            themeButton.modelData.background

                                        onFirstColorChanged: requestPaint()
                                        onSecondColorChanged: requestPaint()

                                        onPaint: {
                                            const context = getContext("2d")
                                            const centerX = width / 2
                                            const centerY = height / 2
                                            const radius = Math.min(width, height) / 2
                                            const halfRadius = radius / 2
                                            const dotRadius = radius * 0.13

                                            context.clearRect(0, 0, width, height)

                                            // Base circle.
                                            context.beginPath()
                                            context.arc(centerX, centerY, radius,
                                                        0, Math.PI * 2, false)
                                            context.fillStyle = String(firstColor)
                                            context.fill()

                                            // Opposite half.
                                            context.beginPath()
                                            context.moveTo(centerX, centerY - radius)
                                            context.arc(centerX, centerY, radius,
                                                        -Math.PI / 2, Math.PI / 2, true)
                                            context.closePath()
                                            context.fillStyle = String(secondColor)
                                            context.fill()

                                            // The two circles form the classic S curve.
                                            context.beginPath()
                                            context.arc(centerX,
                                                        centerY - halfRadius,
                                                        halfRadius,
                                                        0, Math.PI * 2, false)
                                            context.fillStyle = String(secondColor)
                                            context.fill()

                                            context.beginPath()
                                            context.arc(centerX,
                                                        centerY + halfRadius,
                                                        halfRadius,
                                                        0, Math.PI * 2, false)
                                            context.fillStyle = String(firstColor)
                                            context.fill()

                                            // Inverted dots.
                                            context.beginPath()
                                            context.arc(centerX,
                                                        centerY - halfRadius,
                                                        dotRadius,
                                                        0, Math.PI * 2, false)
                                            context.fillStyle = String(firstColor)
                                            context.fill()

                                            context.beginPath()
                                            context.arc(centerX,
                                                        centerY + halfRadius,
                                                        dotRadius,
                                                        0, Math.PI * 2, false)
                                            context.fillStyle = String(secondColor)
                                            context.fill()
                                        }
                                    }
                                }

                                MouseArea {
                                    id: themeMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.themeVariantSelected(
                                        root.themeMode, themeButton.modelData.id)
                                }

                                PrismToolTip {
                                    visible: themeMouse.containsMouse
                                    text: themeButton.modelData.name
                                    surfaceColor: root.elevatedColor
                                    textColor: root.textPrimary
                                    dividerColor: root.dividerColor
                                    x: Math.round((parent.width - width) / 2)
                                    y: parent.height + 4
                                }
                            }
                        }
                    }

                    WheelHandler {
                        target: null
                        acceptedDevices: PointerDevice.Mouse
                            | PointerDevice.TouchPad

                        onWheel: function(event) {
                            const maximumX = Math.max(0,
                                themeVariantsFlickable.contentWidth
                                - themeVariantsFlickable.width)
                            if (maximumX <= 0) {
                                event.accepted = false
                                return
                            }

                            let delta = event.pixelDelta.y !== 0
                                ? event.pixelDelta.y : event.pixelDelta.x
                            if (delta === 0) {
                                delta = (event.angleDelta.y !== 0
                                    ? event.angleDelta.y
                                    : event.angleDelta.x) / 2
                            }

                            themeVariantsFlickable.contentX = Math.max(0,
                                Math.min(maximumX,
                                    themeVariantsFlickable.contentX - delta))
                            event.accepted = true
                        }
                    }

                    ScrollBar.horizontal: Basic.ScrollBar {
                        id: themeVariantsScrollBar

                        policy: ScrollBar.AsNeeded
                        height: 4
                        active: themeVariantsFlickable.movingHorizontally
                            || hovered

                        contentItem: Rectangle {
                            implicitHeight: 4
                            radius: 2
                            color: root.accentColor
                            opacity: themeVariantsScrollBar.active ? 0.72 : 0.42
                        }

                        background: Rectangle {
                            implicitHeight: 4
                            radius: 2
                            color: Qt.rgba(root.textSecondary.r,
                                           root.textSecondary.g,
                                           root.textSecondary.b, 0.14)
                        }
                    }
                }
            }

            Rectangle {
                visible: root.themeMode === "custom"
                width: parent.width
                height: visible ? customColorsColumn.implicitHeight + 24 : 0
                radius: 8
                color: root.surfaceColor
                border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.14)
                border.width: 1
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(150)
                        easing.type: Easing.OutCubic
                    }
                }

                Column {
                    id: customColorsColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 4

                    Text {
                        text: L10n.I18n.tr("Цветовая палитра")
                        color: root.textPrimary
                        font.pointSize: 10
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: L10n.I18n.tr("Настройте основные цвета интерфейса")
                        color: root.textSecondary
                        font.pointSize: 8
                    }

                    Item { width: 1; height: 3 }

                    Repeater {
                        model: root.customColorRows

                        delegate: Rectangle {
                            required property var modelData
                            id: colorRow
                            width: customColorsColumn.width
                            height: 38
                            radius: 7
                            color: colorMouse.containsMouse
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.10)
                                : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: L10n.UiPreferences.duration(90) }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: colorRow.modelData.label
                                color: root.textPrimary
                                font.pointSize: 9
                            }

                            Text {
                                anchors.right: colorSwatch.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(colorRow.modelData.value).toUpperCase()
                                color: root.textSecondary
                                font.pointSize: 8
                            }

                            Rectangle {
                                id: colorSwatch
                                anchors.right: parent.right
                                anchors.rightMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                width: 54
                                height: 24
                                radius: 6
                                color: colorRow.modelData.value
                                border.width: 1
                                border.color: Qt.rgba(root.textPrimary.r,
                                                      root.textPrimary.g,
                                                      root.textPrimary.b, 0.34)
                                scale: colorMouse.pressed ? 0.90 : 1
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: L10n.UiPreferences.duration(90)
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            MouseArea {
                                id: colorMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openColorEditor(
                                    colorRow.modelData.key,
                                    colorRow.modelData.label,
                                    colorRow.modelData.value)
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 78
                radius: 8
                color: root.surfaceColor
                border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.10)
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 7

                    Row {
                        width: parent.width
                        Text {
                            width: parent.width - scaleValue.width
                            text: L10n.I18n.tr("Масштаб интерфейса")
                            color: root.textPrimary
                            font.pointSize: 10
                            font.bold: true
                        }
                        Text {
                            id: scaleValue
                            text: Math.round(root.uiScale * 100) + "%"
                            color: root.accentColor
                            font.pointSize: 9
                            font.bold: true
                        }
                    }

                    Slider {
                        id: interfaceScaleSlider
                        width: parent.width
                        from: 0.8
                        to: 1.4
                        stepSize: 0.05
                        value: root.uiScale
                        onMoved: root.uiScaleSelected(Math.round(value * 20) / 20)
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 68
                radius: 8
                color: root.surfaceColor
                border.color: Qt.rgba(root.textSecondary.r,
                                      root.textSecondary.g,
                                      root.textSecondary.b, 0.10)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Column {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: L10n.I18n.tr("Дублировать комнаты пространств")
                            color: root.textPrimary
                            font.pointSize: 10
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            text: L10n.I18n.tr("Показывать комнаты из пространств также в разделе «Чаты»")
                            color: root.textSecondary
                            font.pointSize: 8
                            wrapMode: Text.Wrap
                        }
                    }

                    StyledSwitch {
                        checked: root.showSpaceRoomsInHome
                        Layout.alignment: Qt.AlignVCenter
                        accentColor: root.accentColor
                        inactiveColor: root.textSecondary
                        onToggled: root.spaceRoomsInHomeSelected(checked)
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 68
                radius: 8
                color: root.surfaceColor
                border.color: Qt.rgba(root.textSecondary.r,
                                      root.textSecondary.g,
                                      root.textSecondary.b, 0.10)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Column {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: L10n.I18n.tr("Треды в небольших чатах")
                            color: root.textPrimary
                            font.pointSize: 10
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            text: L10n.I18n.tr("Показывать треды в чатах с 5 участниками или меньше")
                            color: root.textSecondary
                            font.pointSize: 8
                            wrapMode: Text.Wrap
                        }
                    }

                    StyledSwitch {
                        objectName: "smallGroupThreadsSwitch"
                        checked: root.showThreadsInSmallGroups
                        Layout.alignment: Qt.AlignVCenter
                        accentColor: root.accentColor
                        inactiveColor: root.textSecondary
                        onToggled: root.threadsInSmallGroupsSelected(checked)
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 60
                radius: 8

                color: root.surfaceColor

                border.color: Qt.rgba(
                    root.textSecondary.r,
                    root.textSecondary.g,
                    root.textSecondary.b,
                    0.10
                )
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Column {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: L10n.I18n.tr("Круглые аватары")
                            color: root.textPrimary
                            font.pointSize: 10
                            font.bold: true
                        }

                        Text {
                            text: L10n.I18n.tr("Форма аватаров пользователей и комнат")
                            color: root.textSecondary
                            font.pointSize: 8
                        }
                    }

                    StyledSwitch {
                        checked: root.roundAvatars
                        Layout.alignment: Qt.AlignVCenter

                        accentColor: root.accentColor
                        inactiveColor: root.textSecondary

                        onToggled: {
                            root.roundAvatarsSelected(checked)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 118
                radius: 8

                color: root.surfaceColor

                border.color: Qt.rgba(
                    root.textSecondary.r,
                    root.textSecondary.g,
                    root.textSecondary.b,
                    0.10
                )
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        width: parent.width
                        spacing: 12

                        Column {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: L10n.I18n.tr("Формат даты")
                                color: root.textPrimary
                                font.pointSize: 10
                                font.bold: true
                            }

                            Text {
                                text: L10n.I18n.tr("Для старых сообщений")
                                color: root.textSecondary
                                font.pointSize: 8
                            }
                        }

                        StyledComboBox {
                            Layout.preferredWidth: 150

                            model: [
                                "31.12.2026",
                                "12/31/2026",
                                "2026-12-31"
                            ]

                            currentIndex:
                                root.messageDateFormat === "MM/dd/yyyy"
                                    ? 1
                                    : root.messageDateFormat === "yyyy-MM-dd"
                                        ? 2
                                        : 0

                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor

                            onActivated: function(index) {
                                root.dateFormatSelected(
                                    [
                                        "dd.MM.yyyy",
                                        "MM/dd/yyyy",
                                        "yyyy-MM-dd"
                                    ][index]
                                )
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 12

                        Column {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: L10n.I18n.tr("Формат времени")
                                color: root.textPrimary
                                font.pointSize: 10
                                font.bold: true
                            }

                            Text {
                                text: L10n.I18n.tr("12- или 24-часовой формат")
                                color: root.textSecondary
                                font.pointSize: 8
                            }
                        }

                        StyledComboBox {
                            Layout.preferredWidth: 150

                            model: [
                                "14:30",
                                "14:30:45",
                                "2:30 PM"
                            ]

                            currentIndex:
                                root.messageTimeFormat === "HH:mm:ss"
                                    ? 1
                                    : root.messageTimeFormat === "h:mm AP"
                                        ? 2
                                        : 0

                            accentColor: root.accentColor
                            textPrimary: root.textPrimary
                            textSecondary: root.textSecondary
                            surfaceColor: root.surfaceColor
                            elevatedColor: root.elevatedColor

                            onActivated: function(index) {
                                root.timeFormatSelected(
                                    [
                                        "HH:mm",
                                        "HH:mm:ss",
                                        "h:mm AP"
                                    ][index]
                                )
                            }
                        }
                    }
                }
            }

            Repeater {
                model: [
                    {
                        key: "compact",
                        title: L10n.I18n.tr("Компактный режим"),
                        description: L10n.I18n.tr("Уменьшить отступы сообщений"),
                        available: false
                    },
                    {
                        key: "animations",
                        title: L10n.I18n.tr("Анимации"),
                        description: L10n.I18n.tr("Плавные переходы"),
                        available: true
                    }
                ]

                delegate: Rectangle {
                    required property var modelData

                    width: contentColumn.width
                    height: 48
                    radius: 8

                    color: root.surfaceColor

                    border.color: Qt.rgba(
                        root.textSecondary.r,
                        root.textSecondary.g,
                        root.textSecondary.b,
                        0.10
                    )
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Column {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: modelData.title
                                    + (modelData.available ? "" : L10n.I18n.tr(" • скоро"))
                                color: root.textPrimary
                                font.pointSize: 10
                                font.bold: true
                            }

                            Text {
                                text: modelData.description
                                color: root.textSecondary
                                font.pointSize: 8
                            }
                        }

                        StyledSwitch {
                            enabled: modelData.available
                            Layout.alignment: Qt.AlignVCenter
                            checked: modelData.key === "animations"
                                ? root.animationsEnabled : false
                            accentColor: root.accentColor
                            inactiveColor: root.textSecondary
                            onToggled: {
                                if (modelData.key === "animations")
                                    root.animationsSelected(checked)
                            }
                        }
                    }
                }
            }

            ChoiceRow {
                width: contentColumn.width
                labelText: L10n.I18n.tr("Колыхание окон")
                helpText: L10n.I18n.tr("Способ движения перетаскиваемых окон")
                choices: [
                    L10n.I18n.tr("Отключено"),
                    L10n.I18n.tr("Пружинное"),
                    L10n.I18n.tr("Как в Linux")
                ]
                choiceIndex: root.windowWobbleMode === "spring"
                    ? 1 : root.windowWobbleMode === "linux" ? 2 : 0
                onSelected: function(index) {
                    root.windowWobbleModeSelected(["off", "spring", "linux"][index])
                }
            }

            StrengthRow {
                width: contentColumn.width
                labelText: L10n.I18n.tr("Сила запружинивания")
                helpText: L10n.I18n.tr("Насколько заметно окно догоняет указатель")
                strengthValue: root.windowSpringStrength
                onSelected: function(value) {
                    root.windowSpringStrengthSelected(value)
                }
            }

            StrengthRow {
                width: contentColumn.width
                labelText: L10n.I18n.tr("Сила колыхания")
                helpText: L10n.I18n.tr("Насколько сильно низ окна отстаёт при движении")
                strengthValue: root.windowWobbleStrength
                onSelected: function(value) {
                    root.windowWobbleStrengthSelected(value)
                }
            }

            Rectangle {
                width: contentColumn.width
                height: 62
                radius: 8
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(root.textSecondary.r,
                                      root.textSecondary.g,
                                      root.textSecondary.b, 0.10)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: L10n.I18n.tr("Загрузка PrismChat")
                            color: root.textPrimary
                            font.pointSize: 10
                            font.bold: true
                        }
                        Text {
                            text: L10n.I18n.tr("Анимация, показываемая при запуске")
                            color: root.textSecondary
                            font.pointSize: 8
                        }
                    }

                    Basic.Button {
                        id: chooseIntroButton
                        Layout.preferredWidth: 190
                        Layout.preferredHeight: 34
                        text: L10n.I18n.tr("Выбрать анимацию")
                            + " · " + (root.startupIntroVariant + 1)
                        hoverEnabled: true
                        onClicked: root.startupIntroPickerRequested()

                        background: Rectangle {
                            radius: 8
                            color: chooseIntroButton.down
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                          root.accentColor.b, 0.20)
                                : chooseIntroButton.hovered
                                    ? root.elevatedColor : root.surfaceColor
                            border.width: 1
                            border.color: root.accentColor
                        }
                        contentItem: Text {
                            text: chooseIntroButton.text
                            color: root.textPrimary
                            font.pointSize: 8
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Rectangle {
                width: contentColumn.width
                height: root.desktopShortcutStatus !== "" ? 78 : 62
                radius: 8
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(root.textSecondary.r,
                                      root.textSecondary.g,
                                      root.textSecondary.b, 0.10)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: L10n.I18n.tr("Ярлык на рабочем столе")
                            color: root.textPrimary
                            font.pointSize: 10
                            font.bold: true
                        }
                        Text {
                            text: root.desktopShortcutStatus !== ""
                                ? root.desktopShortcutStatus
                                : L10n.I18n.tr(
                                    "Запуск PrismChat без терминала")
                            color: root.desktopShortcutError
                                ? "#FF6B6B" : root.textSecondary
                            font.pointSize: 8
                        }
                    }

                    Basic.Button {
                        id: createShortcutButton
                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 34
                        text: L10n.I18n.tr("Создать ярлык")
                        hoverEnabled: true
                        onClicked: root.createDesktopShortcut()

                        background: Rectangle {
                            radius: 8
                            color: createShortcutButton.down
                                ? Qt.rgba(root.accentColor.r,
                                          root.accentColor.g,
                                          root.accentColor.b, 0.20)
                                : createShortcutButton.hovered
                                    ? root.elevatedColor : root.surfaceColor
                            border.width: 1
                            border.color: root.accentColor
                        }
                        contentItem: Text {
                            text: createShortcutButton.text
                            color: root.textPrimary
                            font.pointSize: 8
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    Item {
        id: settingsScrollArea

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right

        width: 16
        z: 1000

        visible: settingsFlickable.contentHeight
                 > settingsFlickable.height + 2

        HoverHandler {
            onHoveredChanged: {
                if (hovered)
                    settingsScrollBar.showTemporarily()
                else
                    settingsScrollBar.scheduleHide()
            }
        }

        PrismScrollBar {
            id: settingsScrollBar

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right

            width: 9

            autoHide: true
            autoHideDelay: 2500

            orientation: Qt.Vertical
            policy: ScrollBar.AlwaysOn
            interactive: true

            size: settingsFlickable.contentHeight > 0
                ? Math.min(
                      1,
                      settingsFlickable.visibleArea.heightRatio
                  )
                : 1

            minimumSize: 0.08

            handleColor: root.textSecondary
            handleHoverColor: root.accentColor

            trackColor: Qt.rgba(
                root.textSecondary.r,
                root.textSecondary.g,
                root.textSecondary.b,
                0.16
            )

            Binding {
                target: settingsScrollBar
                property: "position"

                value: Math.max(
                    0,
                    Math.min(
                        1 - settingsScrollBar.size,
                        settingsFlickable.visibleArea.yPosition
                    )
                )

                when: !settingsScrollBar.pressed
            }

            onPositionChanged: {
                if (!pressed)
                    return

                var safePosition = Math.max(
                    0,
                    Math.min(1 - size, position)
                )

                settingsFlickable.contentY =
                    settingsFlickable.originY
                    + safePosition
                    * settingsFlickable.contentHeight

                settingsFlickable.returnToBounds()
            }
        }
    }
}

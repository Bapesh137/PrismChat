import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../common"
import "../../assets/icons" as Icons
import "../../utils" as L10n

Dialog {
    id: root

    property bool creating: false
    property bool creatingSpace: false
    property bool creatingVoice: false
    property string errorText: ""
    property int pageIndex: 0
    property var selectedInviteUsers: []
    property string currentUserId: ""
    property var helpSource: null
    property string helpText: ""
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    signal createRequested(var options)
    signal userPickerRequested(var selectedUsers)

    component HelpLabel: Item {
        id: helpLabel
        property string labelText: ""
        property string helpText: ""
        property color labelColor: root.textSecondary
        property bool bold: false
        property real pointSize: 8
        implicitHeight: 22

        Text {
            id: label
            anchors.left: parent.left
            anchors.right: helpButton.visible ? helpButton.left : parent.right
            anchors.rightMargin: helpButton.visible ? 10 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: helpLabel.labelText
            color: helpLabel.labelColor
            font.bold: helpLabel.bold
            font.pointSize: helpLabel.pointSize
            elide: Text.ElideRight
        }

        Basic.ToolButton {
            id: helpButton
            visible: helpLabel.helpText !== ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            padding: 0
            hoverEnabled: true

            contentItem: Text {
                text: "?"
                color: helpButton.hovered || root.helpSource === helpButton
                    ? root.accentColor : root.textSecondary
                font.bold: true
                font.pointSize: 9
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: width / 2
                color: helpButton.hovered || root.helpSource === helpButton
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                    : "transparent"
                border.width: 1
                border.color: helpButton.hovered || root.helpSource === helpButton
                    ? root.accentColor : root.dividerColor
                Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                Behavior on border.color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
            }
            onClicked: root.toggleHelp(helpButton, helpLabel.helpText)
        }
    }

    component PowerLevelField: ColumnLayout {
        id: powerLevelField
        property string labelText: ""
        property string helpText: ""
        property string placeholderText: ""
        property alias text: valueField.text
        spacing: 7

        HelpLabel {
            Layout.fillWidth: true
            labelText: powerLevelField.labelText
            helpText: powerLevelField.helpText
            pointSize: 7
        }

        Basic.TextField {
            id: valueField
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            horizontalAlignment: Text.AlignHCenter
            color: root.textPrimary
            placeholderText: powerLevelField.placeholderText
            placeholderTextColor: root.textSecondary
            background: Rectangle {
                radius: 8
                color: root.elevatedColor
                border.width: parent.activeFocus ? 1 : 0
                border.color: root.accentColor
            }
        }
    }

    width: Math.min(760, parent ? parent.width - 32 : 760)
    height: Math.min(700, parent ? parent.height - 32 : 700)
    x: parent ? Math.round((parent.width - width) / 2 + dragOffsetX) : 0
    y: parent ? Math.round((parent.height - height) / 2 + dragOffsetY) : 0
    modal: true
    focus: true
    padding: 0
    closePolicy: creating ? Popup.NoAutoClose
                          : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onPageIndexChanged: hideHelp()
    onClosed: hideHelp()

    function hideHelp() {
        helpHideTimer.stop()
        helpBubble.shown = false
        helpSource = null
    }

    function toggleHelp(source, text) {
        if (helpBubble.shown && helpSource === source) {
            hideHelp()
            return
        }

        helpSource = source
        helpText = text
        var point = source.mapToItem(formFlick.contentItem, 0, source.height)
        helpBubble.x = Math.max(10, Math.min(formFlick.contentWidth - helpBubble.width - 10,
                                             point.x + source.width - helpBubble.width))
        helpBubble.y = point.y + 6
        helpBubble.shown = true
        helpHideTimer.restart()
    }

    function hideHelpOutsideViewport() {
        if (!helpBubble.shown || !helpSource)
            return
        var point = helpSource.mapToItem(formFlick, 0, 0)
        if (point.y + helpSource.height <= 0 || point.y >= formFlick.height)
            hideHelp()
    }

    function resetForm() {
        hideHelp()
        dragOffsetX = 0
        dragOffsetY = 0
        createRoomMoveArea.resetMotion()
        creating = false
        errorText = ""
        pageIndex = 0
        creatingVoice = false
        nameField.text = ""
        topicField.text = ""
        aliasField.text = ""
        inviteField.text = ""
        selectedInviteUsers = []
        visibilityCombo.currentIndex = 0
        presetCombo.currentIndex = 0
        roomVersionField.text = ""
        directSwitch.checked = false
        federationSwitch.checked = true
        encryptionSwitch.checked = !creatingSpace
        joinRuleCombo.currentIndex = 0
        historyCombo.currentIndex = 0
        guestCombo.currentIndex = 0
        avatarField.text = ""
        usersDefaultField.text = ""
        eventsDefaultField.text = ""
        stateDefaultField.text = ""
        inviteLevelField.text = ""
        kickLevelField.text = ""
        banLevelField.text = ""
        redactLevelField.text = ""
        notificationLevelField.text = ""
        usersPowerField.text = "{}"
        eventsPowerField.text = "{}"
        invite3pidField.text = "[]"
        creationContentField.text = "{}"
        initialStateField.text = "[]"
        Qt.callLater(function() { nameField.forceActiveFocus() })
    }

    function openForCreation() {
        creatingSpace = false
        resetForm()
        open()
    }

    function openForSpaceCreation() {
        creatingSpace = true
        resetForm()
        open()
    }

    function setSelectedInviteUsers(users) {
        var copy = []
        var source = users || []
        for (var index = 0; index < source.length; index++) {
            var user = source[index] || {}
            var userId = String(user.user_id || "")
            if (userId === "" || userId === currentUserId) continue
            copy.push({
                user_id: userId,
                display_name: String(user.display_name || ""),
                avatar_url: String(user.avatar_url || "")
            })
        }
        selectedInviteUsers = copy
    }

    function selectedInviteSummary() {
        if (selectedInviteUsers.length === 0)
            return L10n.I18n.tr("Никто не выбран")
        var names = []
        for (var index = 0; index < selectedInviteUsers.length; index++) {
            var user = selectedInviteUsers[index] || {}
            names.push(user.display_name || user.user_id || "")
        }
        return names.join(", ")
    }

    function receiveResult(success, error) {
        creating = false
        if (success) {
            close()
            return
        }
        errorText = error || (creatingSpace
            ? L10n.I18n.tr("Не удалось создать пространство")
            : L10n.I18n.tr("Не удалось создать комнату"))
    }

    function parseJson(text, expectedType, label) {
        var source = String(text || "").trim()
        if (source === "")
            source = expectedType === "array" ? "[]" : "{}"
        var value
        try {
            value = JSON.parse(source)
        } catch (error) {
            throw label + ": " + L10n.I18n.tr("некорректный JSON")
        }
        if (expectedType === "array" && !Array.isArray(value))
            throw label + ": " + L10n.I18n.tr("ожидается JSON-массив")
        if (expectedType === "object"
                && (value === null || Array.isArray(value) || typeof value !== "object"))
            throw label + ": " + L10n.I18n.tr("ожидается JSON-объект")
        return value
    }

    function optionalInteger(field, label) {
        var source = String(field.text || "").trim()
        if (source === "")
            return undefined
        var value = Number(source)
        if (!isFinite(value) || Math.floor(value) !== value)
            throw label + ": " + L10n.I18n.tr("введите целое число")
        if (value > 100)
            throw label + ": " + L10n.I18n.tr("уровень доступа не может быть больше 100")
        return value
    }

    function validatePowerValue(value, label, path) {
        var location = path || ""
        if (typeof value === "number") {
            if (!isFinite(value) || Math.floor(value) !== value)
                throw label + location + ": " + L10n.I18n.tr("введите целое число")
            if (value > 100)
                throw label + location + ": "
                    + L10n.I18n.tr("уровень доступа не может быть больше 100")
            return
        }
        if (value !== null && typeof value === "object" && !Array.isArray(value)) {
            var keys = Object.keys(value)
            for (var index = 0; index < keys.length; ++index) {
                var key = keys[index]
                validatePowerValue(value[key], label, location + " (" + key + ")")
            }
            return
        }
        throw label + location + ": " + L10n.I18n.tr("введите целое число")
    }

    function validatePowerMap(values, label) {
        validatePowerValue(values || ({}), label, "")
    }

    function parseInvites() {
        var source = String(inviteField.text || "")
        var pieces = source.split(/[\s,;]+/)
        var result = []
        var seen = ({})
        for (var selectedIndex = 0; selectedIndex < selectedInviteUsers.length; selectedIndex++) {
            var selectedId = String((selectedInviteUsers[selectedIndex] || {}).user_id || "")
            if (selectedId !== "" && !seen[selectedId]) {
                seen[selectedId] = true
                result.push(selectedId)
            }
        }
        for (var index = 0; index < pieces.length; index++) {
            var userId = pieces[index].trim()
            if (userId === "")
                continue
            if (userId.charAt(0) !== "@" || userId.indexOf(":") < 2)
                throw L10n.I18n.tr("Некорректный Matrix ID приглашённого: ") + userId
            if (!seen[userId]) {
                seen[userId] = true
                result.push(userId)
            }
        }
        return result
    }

    function putState(states, type, stateKey, content) {
        for (var index = 0; index < states.length; index++) {
            var entry = states[index] || {}
            if (entry.type === type && String(entry.state_key || "") === stateKey) {
                states[index] = { type: type, state_key: stateKey, content: content }
                return
            }
        }
        states.push({ type: type, state_key: stateKey, content: content })
    }

    function buildOptions() {
        var options = ({})
        var name = nameField.text.trim()
        var topic = topicField.text.trim()
        var alias = aliasField.text.trim()
        var roomVersion = roomVersionField.text.trim()
        if (alias.charAt(0) === "#")
            alias = alias.substring(1)
        if (alias.indexOf(":") >= 0 || /\s/.test(alias))
            throw L10n.I18n.tr("Алиас должен содержать только локальную часть без # и сервера")

        if (name !== "") options.name = name
        if (topic !== "") options.topic = topic
        if (alias !== "") options.room_alias_name = alias
        if (roomVersion !== "") options.room_version = roomVersion

        options.visibility = visibilityCombo.currentIndex === 1 ? "public" : "private"
        var presets = ["private_chat", "public_chat", "trusted_private_chat"]
        options.preset = presets[presetCombo.currentIndex]
        options.is_direct = !creatingSpace && !creatingVoice && directSwitch.checked

        var invites = parseInvites()
        if (invites.length > 0)
            options.invite = invites

        var invite3pid = parseJson(
            invite3pidField.text, "array", L10n.I18n.tr("Приглашения по 3PID"))
        if (invite3pid.length > 0)
            options.invite_3pid = invite3pid

        var creationContent = parseJson(
            creationContentField.text, "object", L10n.I18n.tr("Дополнительный creation_content"))
        creationContent["m.federate"] = federationSwitch.checked
        if (creatingSpace)
            creationContent.type = "m.space"
        else if (creatingVoice)
            creationContent.type = "io.prismchat.voice"
        else if (creationContent.type === "m.space" || creationContent.type === "io.prismchat.voice")
            delete creationContent.type
        if (Object.keys(creationContent).length > 0)
            options.creation_content = creationContent

        var states = parseJson(
            initialStateField.text, "array", L10n.I18n.tr("Дополнительный initial_state"))
        for (var stateIndex = 0; stateIndex < states.length; ++stateIndex) {
            var stateEvent = states[stateIndex] || ({})
            if (stateEvent.type === "m.room.power_levels")
                validatePowerValue(stateEvent.content || ({}),
                                   L10n.I18n.tr("Уровни доступа в initial_state"), "")
        }
        if (!creatingSpace && (creatingVoice || encryptionSwitch.checked)) {
            putState(states, "m.room.encryption", "", {
                algorithm: "m.megolm.v1.aes-sha2"
            })
        }

        var joinRules = ["", "invite", "public", "knock", "restricted", "knock_restricted"]
        var joinRule = joinRules[joinRuleCombo.currentIndex]
        if (joinRule !== "")
            putState(states, "m.room.join_rules", "", { join_rule: joinRule })

        var historyValues = ["", "invited", "joined", "shared", "world_readable"]
        var history = historyValues[historyCombo.currentIndex]
        if (history !== "")
            putState(states, "m.room.history_visibility", "", { history_visibility: history })

        var guestValues = ["", "forbidden", "can_join"]
        var guestAccess = guestValues[guestCombo.currentIndex]
        if (guestAccess !== "")
            putState(states, "m.room.guest_access", "", { guest_access: guestAccess })

        var avatarUrl = avatarField.text.trim()
        if (avatarUrl !== "") {
            if (avatarUrl.indexOf("mxc://") !== 0)
                throw L10n.I18n.tr("Аватар должен быть ссылкой mxc://")
            putState(states, "m.room.avatar", "", { url: avatarUrl })
        }
        if (states.length > 0)
            options.initial_state = states

        var powerLevels = ({})
        var usersDefault = optionalInteger(usersDefaultField, L10n.I18n.tr("Уровень обычных участников"))
        var eventsDefault = optionalInteger(eventsDefaultField, L10n.I18n.tr("Уровень отправки сообщений"))
        var stateDefault = optionalInteger(stateDefaultField, L10n.I18n.tr("Уровень изменения состояния"))
        var inviteLevel = optionalInteger(inviteLevelField, L10n.I18n.tr("Уровень приглашения"))
        var kickLevel = optionalInteger(kickLevelField, L10n.I18n.tr("Уровень исключения"))
        var banLevel = optionalInteger(banLevelField, L10n.I18n.tr("Уровень блокировки"))
        var redactLevel = optionalInteger(redactLevelField, L10n.I18n.tr("Уровень удаления событий"))
        var notificationLevel = optionalInteger(notificationLevelField, L10n.I18n.tr("Уровень упоминания комнаты"))
        if (usersDefault !== undefined) powerLevels.users_default = usersDefault
        if (eventsDefault !== undefined) powerLevels.events_default = eventsDefault
        if (stateDefault !== undefined) powerLevels.state_default = stateDefault
        if (inviteLevel !== undefined) powerLevels.invite = inviteLevel
        if (kickLevel !== undefined) powerLevels.kick = kickLevel
        if (banLevel !== undefined) powerLevels.ban = banLevel
        if (redactLevel !== undefined) powerLevels.redact = redactLevel
        if (notificationLevel !== undefined)
            powerLevels.notifications = { room: notificationLevel }

        var usersPower = parseJson(
            usersPowerField.text, "object", L10n.I18n.tr("Уровни пользователей"))
        var eventsPower = parseJson(
            eventsPowerField.text, "object", L10n.I18n.tr("Уровни типов событий"))
        validatePowerMap(usersPower, L10n.I18n.tr("Уровни пользователей"))
        validatePowerMap(eventsPower, L10n.I18n.tr("Уровни типов событий"))
        if (Object.keys(usersPower).length > 0) powerLevels.users = usersPower
        if (Object.keys(eventsPower).length > 0) powerLevels.events = eventsPower
        if (Object.keys(powerLevels).length > 0)
            options.power_level_content_override = powerLevels

        return options
    }

    function submit() {
        if (creating)
            return
        errorText = ""
        try {
            var options = buildOptions()
            creating = true
            createRequested(options)
        } catch (error) {
            errorText = String(error)
        }
    }

    onOpened: Qt.callLater(function() { nameField.forceActiveFocus() })

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(100) }
            NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: L10n.UiPreferences.duration(140); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(80) }
            NumberAnimation { property: "scale"; from: 1; to: 0.985; duration: L10n.UiPreferences.duration(80) }
        }
    }

    Timer {
        id: helpHideTimer
        interval: 5200
        repeat: false
        onTriggered: root.hideHelp()
    }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.56) }

    background: Rectangle {
        radius: 17
        color: root.backgroundColor
        border.width: 1
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                              root.textSecondary.b, 0.22)
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(createRoomMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }
    }

    contentItem: Item {
        transform: Matrix4x4 {
            matrix: PlanarTransform.fromShear(
                        Math.tan(createRoomMoveArea.visualShearAngle * Math.PI / 180),
                        0, width / 2, 0)
        }

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 116
            radius: 17
            color: root.surfaceColor

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 17
                color: parent.color
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.top: parent.top
                anchors.topMargin: 17
                text: root.creatingSpace
                    ? L10n.I18n.tr("Создать пространство")
                    : L10n.I18n.tr("Создать комнату")
                color: root.textPrimary
                font.bold: true
                font.pointSize: 14
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.top: parent.top
                anchors.topMargin: 43
                text: root.creatingSpace
                    ? L10n.I18n.tr("Пространство создаётся как отдельный тип Matrix m.space.")
                    : L10n.I18n.tr("Параметры стандартного Matrix createRoom")
                color: root.textSecondary
                font.pointSize: 8
            }

            PopupMoveArea {
                id: createRoomMoveArea
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: closeButton.left
                height: 64
                moveTarget: root
                movementBoundary: root.parent
            }

            PopupCloseButton {
                id: closeButton
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.rightMargin: 11
                enabled: !root.creating
                accentColor: root.accentColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                onClicked: root.close()
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                spacing: 8

                Repeater {
                    model: [L10n.I18n.tr("Основное"), L10n.I18n.tr("Расширенное")]
                    delegate: Basic.Button {
                        required property string modelData
                        required property int index
                        width: 150
                        height: 36
                        text: modelData
                        hoverEnabled: true
                        scale: down ? 0.95 : 1
                        onClicked: root.pageIndex = index
                        Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
                        contentItem: Text {
                            text: parent.text
                            color: root.pageIndex === parent.index ? root.accentTextColor : root.textSecondary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: root.pageIndex === parent.index
                            font.pointSize: 9
                        }
                        background: Rectangle {
                            radius: 9
                            color: root.pageIndex === parent.index
                                ? root.accentColor
                                : parent.hovered ? root.elevatedColor : "transparent"
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                        }
                    }
                }
            }
        }

        Flickable {
            id: formFlick
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.margins: 0
            clip: true
            contentWidth: width
            contentHeight: formColumn.implicitHeight + 28
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: root.hideHelpOutsideViewport()

            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
                trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                    root.textSecondary.b, 0.12)
            }

            Column {
                id: formColumn
                x: 22
                y: 18
                width: formFlick.width - 44
                spacing: 14

                Column {
                    width: parent.width
                    spacing: 13
                    visible: root.pageIndex === 0

                    CheckBox {
                        visible: !root.creatingSpace
                        text: L10n.I18n.tr("Голосовой канал (MatrixRTC)")
                        checked: root.creatingVoice
                        onToggled: root.creatingVoice = checked
                    }
                    Text { text: L10n.I18n.tr("Название и описание"); color: root.textPrimary; font.bold: true; font.pointSize: 11 }

                    HelpLabel {
                        width: parent.width
                        labelText: root.creatingSpace
                            ? L10n.I18n.tr("Название пространства")
                            : L10n.I18n.tr("Название комнаты")
                    }
                    Basic.TextField {
                        id: nameField
                        width: parent.width
                        height: 42
                        leftPadding: 13
                        rightPadding: 13
                        color: root.textPrimary
                        placeholderText: root.creatingSpace
                            ? L10n.I18n.tr("Например, Сообщество проекта")
                            : L10n.I18n.tr("Например, Команда проекта")
                        placeholderTextColor: root.textSecondary
                        selectionColor: root.accentColor
                        selectedTextColor: root.accentTextColor
                        background: Rectangle {
                            radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor
                        }
                    }

                    HelpLabel {
                        width: parent.width
                        labelText: root.creatingSpace
                            ? L10n.I18n.tr("Тема пространства")
                            : L10n.I18n.tr("Тема комнаты")
                    }
                    Basic.TextArea {
                        id: topicField
                        width: parent.width
                        height: 74
                        leftPadding: 12
                        rightPadding: 12
                        topPadding: 10
                        bottomPadding: 10
                        color: root.textPrimary
                        placeholderText: root.creatingSpace
                            ? L10n.I18n.tr("Краткое описание назначения пространства")
                            : L10n.I18n.tr("Краткое описание назначения комнаты")
                        placeholderTextColor: root.textSecondary
                        wrapMode: TextEdit.Wrap
                        background: Rectangle {
                            radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor
                        }
                    }

                    GridLayout {
                        width: parent.width
                        columns: 2
                        columnSpacing: 14
                        rowSpacing: 7

                        HelpLabel {
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Локальная часть алиаса")
                            helpText: L10n.I18n.tr("Необязательный читаемый адрес. Укажите только часть после # и до имени сервера.")
                        }
                        HelpLabel {
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Версия комнаты")
                            helpText: L10n.I18n.tr("Версия протокола Matrix. Обычно это поле лучше оставить пустым и использовать значение сервера.")
                        }
                        Basic.TextField {
                            id: aliasField
                            Layout.fillWidth: true; Layout.preferredHeight: 40
                            leftPadding: 12; rightPadding: 12; color: root.textPrimary
                            placeholderText: "project-room"; placeholderTextColor: root.textSecondary
                            background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                        }
                        Basic.TextField {
                            id: roomVersionField
                            Layout.fillWidth: true; Layout.preferredHeight: 40
                            leftPadding: 12; rightPadding: 12; color: root.textPrimary
                            placeholderText: L10n.I18n.tr("По умолчанию сервера"); placeholderTextColor: root.textSecondary
                            background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                        }
                    }

                    GridLayout {
                        width: parent.width
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 7

                        HelpLabel {
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Видимость")
                            helpText: L10n.I18n.tr("Публичные комнаты можно находить через каталог сервера. Приватные доступны только приглашённым.")
                        }
                        HelpLabel {
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Пресет")
                            helpText: L10n.I18n.tr("Набор начальных правил Matrix для доступа, истории и уровней полномочий.")
                        }

                        StyledComboBox {
                            id: visibilityCombo
                            Layout.fillWidth: true
                            model: [L10n.I18n.tr("Приватная"), L10n.I18n.tr("Публичная")]
                            accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                            surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                        }
                        StyledComboBox {
                            id: presetCombo
                            Layout.fillWidth: true
                            model: [L10n.I18n.tr("Приватный чат"), L10n.I18n.tr("Публичный чат"), L10n.I18n.tr("Доверенный приватный чат")]
                            accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                            surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                        }
                    }

                    HelpLabel {
                        width: parent.width
                        labelText: L10n.I18n.tr("Пользователи для приглашения")
                    }

                    Basic.Button {
                        id: chooseUsersButton
                        width: parent.width
                        height: 62
                        hoverEnabled: true
                        onClicked: root.userPickerRequested(root.selectedInviteUsers)
                        contentItem: Item {
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.right: selectedCount.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    width: parent.width
                                    text: L10n.I18n.tr("Выбрать пользователей")
                                    color: root.textPrimary
                                    font.bold: true
                                    font.pointSize: 9
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: root.selectedInviteSummary()
                                    color: root.textSecondary
                                    font.pointSize: 7
                                    elide: Text.ElideRight
                                }
                            }
                            Rectangle {
                                id: selectedCount
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(28, countText.implicitWidth + 14)
                                height: 28
                                radius: 14
                                color: root.selectedInviteUsers.length > 0
                                    ? root.accentColor : root.surfaceColor
                                border.width: root.selectedInviteUsers.length > 0 ? 0 : 1
                                border.color: root.dividerColor
                                Text {
                                    id: countText
                                    anchors.centerIn: parent
                                    text: String(root.selectedInviteUsers.length)
                                    color: root.selectedInviteUsers.length > 0
                                        ? root.accentTextColor : root.textSecondary
                                    font.bold: true
                                    font.pointSize: 8
                                }
                            }
                        }
                        background: Rectangle {
                            radius: 9
                            color: chooseUsersButton.hovered
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.09)
                                : root.elevatedColor
                            border.width: 1
                            border.color: chooseUsersButton.hovered ? root.accentColor : root.dividerColor
                        }
                    }

                    HelpLabel {
                        width: parent.width
                        labelText: L10n.I18n.tr("Matrix ID вручную (необязательно)")
                        helpText: L10n.I18n.tr("Используйте полный идентификатор вида @user:server. Можно указать несколько ID через пробел, запятую или с новой строки.")
                    }
                    Basic.TextArea {
                        id: inviteField
                        width: parent.width
                        height: 62
                        leftPadding: 12; rightPadding: 12; topPadding: 9; bottomPadding: 9
                        color: root.textPrimary
                        placeholderText: "@alice:example.org\n@bob:example.org"
                        placeholderTextColor: root.textSecondary
                        wrapMode: TextEdit.WrapAnywhere
                        background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                    }

                    Rectangle { width: parent.width; height: 1; color: root.dividerColor; opacity: 0.65 }
                    Text {
                        text: root.creatingSpace
                            ? L10n.I18n.tr("Поведение пространства")
                            : L10n.I18n.tr("Поведение комнаты")
                        color: root.textPrimary
                        font.bold: true
                        font.pointSize: 11
                    }

                    Repeater {
                        model: [
                            { label: L10n.I18n.tr("Пометить как личный чат"), note: L10n.I18n.tr("Устанавливает is_direct для приглашений"), target: directSwitch, available: !root.creatingSpace },
                            { label: L10n.I18n.tr("Разрешить федерацию"), note: L10n.I18n.tr("Пользователи с других серверов смогут участвовать"), target: federationSwitch, available: true },
                            { label: L10n.I18n.tr("Включить сквозное шифрование"), note: L10n.I18n.tr("Добавляет m.room.encryption при создании"), target: encryptionSwitch, available: !root.creatingSpace }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            visible: !!modelData.available
                            width: formColumn.width
                            height: visible ? 58 : 0
                            radius: 10
                            color: rowHover.hovered
                                ? Qt.darker(root.surfaceColor, 1.16)
                                : root.surfaceColor
                            Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(120) } }

                            HoverHandler {
                                id: rowHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            Text { anchors.left: parent.left; anchors.leftMargin: 13; anchors.top: parent.top; anchors.topMargin: 10; text: modelData.label; color: root.textPrimary; font.pointSize: 9 }
                            Text { anchors.left: parent.left; anchors.leftMargin: 13; anchors.top: parent.top; anchors.topMargin: 31; text: modelData.note; color: root.textSecondary; font.pointSize: 7 }
                            StyledSwitch {
                                id: rowSwitch
                                anchors.right: parent.right; anchors.rightMargin: 13; anchors.verticalCenter: parent.verticalCenter
                                checked: modelData.target.checked
                                accentColor: root.accentColor; inactiveColor: root.textSecondary
                                onToggled: modelData.target.checked = checked
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                anchors.rightMargin: 60
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.target.checked = !modelData.target.checked
                            }
                        }
                    }
                    StyledSwitch { id: directSwitch; visible: false }
                    StyledSwitch { id: federationSwitch; visible: false; checked: true }
                    StyledSwitch { id: encryptionSwitch; visible: false; checked: true }
                }

                Column {
                    width: parent.width
                    spacing: 13
                    visible: root.pageIndex === 1

                    Text { text: L10n.I18n.tr("События состояния"); color: root.textPrimary; font.bold: true; font.pointSize: 11 }
                    GridLayout {
                        width: parent.width
                        columns: 3
                        columnSpacing: 12
                        rowSpacing: 7
                        HelpLabel {
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Правило входа")
                            helpText: L10n.I18n.tr("Определяет, кто и каким способом может вступить: по приглашению, свободно, по запросу или через другое пространство.")
                        }
                        HelpLabel {
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Видимость истории")
                            helpText: L10n.I18n.tr("Определяет, какую часть истории смогут читать пользователи до и после вступления.")
                        }
                        HelpLabel {
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Доступ гостям")
                            helpText: L10n.I18n.tr("Разрешает или запрещает вход гостевым Matrix-аккаунтам.")
                        }
                        StyledComboBox {
                            id: joinRuleCombo; Layout.fillWidth: true
                            model: [L10n.I18n.tr("По умолчанию пресета"), "invite", "public", "knock", "restricted", "knock_restricted"]
                            accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                        }
                        StyledComboBox {
                            id: historyCombo; Layout.fillWidth: true
                            model: [L10n.I18n.tr("По умолчанию пресета"), "invited", "joined", "shared", "world_readable"]
                            accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                        }
                        StyledComboBox {
                            id: guestCombo; Layout.fillWidth: true
                            model: [L10n.I18n.tr("По умолчанию пресета"), "forbidden", "can_join"]
                            accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary; surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                        }
                    }

                    HelpLabel {
                        width: parent.width
                        labelText: root.creatingSpace
                            ? L10n.I18n.tr("Аватар пространства (mxc://)")
                            : L10n.I18n.tr("Аватар комнаты (mxc://)")
                        helpText: L10n.I18n.tr("MXC-ссылка на уже загруженное в Matrix изображение. Обычная ссылка https:// здесь не подходит.")
                    }
                    Basic.TextField {
                        id: avatarField; width: parent.width; height: 40
                        leftPadding: 12; rightPadding: 12; color: root.textPrimary
                        placeholderText: "mxc://example.org/mediaId"; placeholderTextColor: root.textSecondary
                        background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                    }

                    Rectangle { width: parent.width; height: 1; color: root.dividerColor; opacity: 0.65 }
                    Text { text: L10n.I18n.tr("Уровни доступа"); color: root.textPrimary; font.bold: true; font.pointSize: 11 }
                    Text { text: L10n.I18n.tr("Пустое поле оставляет значение сервера без переопределения."); color: root.textSecondary; font.pointSize: 7 }

                    GridLayout {
                        width: parent.width
                        columns: 4
                        columnSpacing: 10
                        rowSpacing: 12

                        PowerLevelField {
                            id: usersDefaultField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Участники")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "0"
                        }
                        PowerLevelField {
                            id: eventsDefaultField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Сообщения")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "0"
                        }
                        PowerLevelField {
                            id: stateDefaultField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Состояние")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "50"
                        }
                        PowerLevelField {
                            id: inviteLevelField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Приглашение")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "0"
                        }
                        PowerLevelField {
                            id: kickLevelField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Исключение")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "50"
                        }
                        PowerLevelField {
                            id: banLevelField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Блокировка")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "50"
                        }
                        PowerLevelField {
                            id: redactLevelField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("Удаление")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "50"
                        }
                        PowerLevelField {
                            id: notificationLevelField
                            Layout.fillWidth: true
                            labelText: L10n.I18n.tr("@room")
                            helpText: L10n.I18n.tr("Числовой уровень доступа Matrix: действие разрешено пользователям с таким же или более высоким уровнем.")
                            placeholderText: "50"
                        }
                    }

                    HelpLabel {
                        width: parent.width
                        labelText: L10n.I18n.tr("Уровни пользователей — JSON-объект")
                        helpText: L10n.I18n.tr("Сопоставляет полные Matrix ID пользователей с их числовыми уровнями доступа, например {\"@admin:server\":100}.")
                    }
                    Basic.TextArea {
                        id: usersPowerField; width: parent.width; height: 64
                        leftPadding: 11; rightPadding: 11; topPadding: 8; bottomPadding: 8; color: root.textPrimary; font.family: "monospace"; font.pointSize: 8
                        wrapMode: TextEdit.WrapAnywhere
                        background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                    }
                    HelpLabel {
                        width: parent.width
                        labelText: L10n.I18n.tr("Уровни типов событий — JSON-объект")
                        helpText: L10n.I18n.tr("Задаёт минимальный уровень доступа для отдельных типов событий Matrix, например m.room.name или m.room.power_levels.")
                    }
                    Basic.TextArea {
                        id: eventsPowerField; width: parent.width; height: 64
                        leftPadding: 11; rightPadding: 11; topPadding: 8; bottomPadding: 8; color: root.textPrimary; font.family: "monospace"; font.pointSize: 8
                        wrapMode: TextEdit.WrapAnywhere
                        background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                    }

                    Rectangle { width: parent.width; height: 1; color: root.dividerColor; opacity: 0.65 }
                    Text { text: L10n.I18n.tr("Полные параметры Matrix"); color: root.textPrimary; font.bold: true; font.pointSize: 11 }
                    Text { text: L10n.I18n.tr("Эти поля позволяют передать сложные параметры протокола без потери данных."); color: root.textSecondary; font.pointSize: 7; wrapMode: Text.Wrap; width: parent.width }

                    HelpLabel {
                        width: parent.width
                        labelText: L10n.I18n.tr("Приглашения по 3PID — JSON-массив")
                        helpText: L10n.I18n.tr("Расширенные приглашения по электронной почте или телефону через identity server. Обычно поле оставляют пустым.")
                    }
                    Basic.TextArea {
                        id: invite3pidField; width: parent.width; height: 78
                        leftPadding: 11; rightPadding: 11; topPadding: 8; bottomPadding: 8; color: root.textPrimary; font.family: "monospace"; font.pointSize: 8; wrapMode: TextEdit.WrapAnywhere
                        background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                    }
                    HelpLabel {
                        width: parent.width
                        labelText: L10n.I18n.tr("Дополнительный creation_content — JSON-объект")
                        helpText: L10n.I18n.tr("Дополнительные данные события m.room.create. Используйте только для параметров Matrix, которых нет в форме.")
                    }
                    Basic.TextArea {
                        id: creationContentField; width: parent.width; height: 78
                        leftPadding: 11; rightPadding: 11; topPadding: 8; bottomPadding: 8; color: root.textPrimary; font.family: "monospace"; font.pointSize: 8; wrapMode: TextEdit.WrapAnywhere
                        background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                    }
                    HelpLabel {
                        width: parent.width
                        labelText: L10n.I18n.tr("Дополнительный initial_state — JSON-массив")
                        helpText: L10n.I18n.tr("Список state-событий, которые сервер отправит сразу при создании. Каждый элемент должен содержать type, state_key и content.")
                    }
                    Basic.TextArea {
                        id: initialStateField; width: parent.width; height: 110
                        leftPadding: 11; rightPadding: 11; topPadding: 8; bottomPadding: 8; color: root.textPrimary; font.family: "monospace"; font.pointSize: 8; wrapMode: TextEdit.WrapAnywhere
                        background: Rectangle { radius: 9; color: root.elevatedColor; border.width: parent.activeFocus ? 1 : 0; border.color: root.accentColor }
                    }
                }
            }

            Rectangle {
                id: helpBubble
                property bool shown: false
                width: Math.min(340, Math.max(220, formFlick.width - 64))
                height: helpBubbleText.implicitHeight + 24
                radius: 10
                z: 1000
                visible: shown || opacity > 0.001
                opacity: shown ? 1 : 0
                color: root.elevatedColor
                border.width: 1
                border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                      root.textSecondary.b, 0.45)

                Behavior on opacity {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(helpBubble.shown ? 150 : 240)
                        easing.type: helpBubble.shown ? Easing.OutCubic : Easing.InOutCubic
                    }
                }

                Text {
                    id: helpBubbleText
                    anchors.fill: parent
                    anchors.margins: 12
                    text: root.helpText
                    color: root.textPrimary
                    font.pointSize: 8
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.errorText === "" ? 74 : 100
            color: root.surfaceColor
            radius: 17

            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 17; color: parent.color }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: root.dividerColor; opacity: 0.6 }

            Text {
                visible: root.errorText !== ""
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                anchors.top: parent.top
                anchors.topMargin: 10
                text: root.errorText
                color: "#ff7373"
                font.pointSize: 8
                elide: Text.ElideRight
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                spacing: 10

                Basic.Button {
                    id: cancelButton
                    width: 116; height: 40
                    enabled: !root.creating
                    hoverEnabled: true
                    scale: down ? 0.95 : 1
                    text: L10n.I18n.tr("Отмена")
                    onClicked: root.close()
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
                    contentItem: Text { text: parent.text; color: root.textPrimary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pointSize: 9 }
                    background: Rectangle {
                        radius: 9
                        color: cancelButton.down
                            ? Qt.darker(root.elevatedColor, 1.12)
                            : cancelButton.hovered ? root.elevatedColor : "transparent"
                        border.width: 1; border.color: root.dividerColor
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }
                }

                Basic.Button {
                    id: createButton
                    width: 160; height: 40
                    enabled: !root.creating
                    hoverEnabled: true
                    scale: down ? 0.95 : 1
                    text: root.creating ? L10n.I18n.tr("Создание…")
                        : root.creatingSpace
                            ? L10n.I18n.tr("Создать пространство")
                            : L10n.I18n.tr("Создать комнату")
                    onClicked: root.submit()
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90); easing.type: Easing.OutCubic } }
                    contentItem: Item {
                        PrismBusyIndicator {
                            visible: root.creating
                            running: root.creating
                            anchors.centerIn: parent
                            width: 20; height: 20; strokeWidth: 2
                            accentColor: root.accentTextColor
                        }
                        Text {
                            visible: !root.creating
                            anchors.fill: parent
                            text: createButton.text
                            color: root.accentTextColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: true; font.pointSize: 9
                        }
                    }
                    background: Rectangle {
                        radius: 9
                        color: createButton.down
                            ? Qt.darker(root.accentColor, 1.18)
                            : createButton.hovered ? Qt.lighter(root.accentColor, 1.08) : root.accentColor
                        Behavior on color { ColorAnimation { duration: L10n.UiPreferences.duration(100) } }
                    }
                }
            }
        }
    }
}

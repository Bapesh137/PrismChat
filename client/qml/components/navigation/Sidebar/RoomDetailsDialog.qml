import ".." as Navigation
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils/PrismUtils.js" as Utils

Basic.Dialog {
    required property var sidebar
    readonly property var root: sidebar
    id: roomDetailsDialog

    property var details: null
    property string mode: "info"
    property bool saving: false
    property string errorText: ""
    property string originalName: ""
    property string originalTopic: ""
    property string originalAvatarUrl: ""
    property string originalJoinRule: "invite"
    property string originalHistoryVisibility: "shared"
    property string originalGuestAccess: "forbidden"
    property string originalReadReceiptPreference: "inherit"
    property string originalTypingPreference: "inherit"
    property bool memberModerationBusy: false
    readonly property bool editing: mode === "edit"

    function roomKind() {
        if (!details)
            return L10n.I18n.tr("Комната")
        if (details.is_space)
            return L10n.I18n.tr("Пространство")
        if (details.is_dm)
            return L10n.I18n.tr("Личный чат")
        return L10n.I18n.tr("Комната")
    }

    function timestampText(value) {
        var timestamp = Number(value || 0)
        if (!isFinite(timestamp) || timestamp <= 0)
            return L10n.I18n.tr("Нет данных")
        return new Date(timestamp).toLocaleString(Qt.locale())
    }

    function openFor(roomDetails, requestedMode) {
        details = roomDetails
        mode = requestedMode === "edit" ? "edit" : "info"
        saving = false
        memberModerationBusy = false
        errorText = ""
        syncEditor()
        open()
        if (editing)
            Qt.callLater(function() { roomNameEditor.forceActiveFocus() })
    }

    function valueIndex(values, value, fallbackValue) {
        var normalized = String(value || fallbackValue)
        var index = values.indexOf(normalized)
        if (index < 0)
            index = values.indexOf(String(fallbackValue || ""))
        return Math.max(0, index)
    }

    function optionsWithCurrent(values, currentValue) {
        var result = values.slice(0)
        var current = String(currentValue || "")
        if (current !== "" && result.indexOf(current) < 0)
            result.unshift(current)
        return result
    }

    function canModerateTarget(userId, targetLevel) {
        if (!details || userId === root.currentUserId)
            return false
        return Number(details.current_user_power_level || -1)
            > Number(targetLevel || 0)
    }

    function moderateMember(userId, action) {
        if (!details || memberModerationBusy || userId === "")
            return
        memberModerationBusy = true
        errorText = ""
        root.roomMemberModerationRequested(
            details.room_id || "", userId, action)
    }

    function syncEditor() {
        var current = details || ({})
        originalName = String(current.name || "")
        originalTopic = String(current.topic || "")
        originalAvatarUrl = String(current.avatar_url || "")
        originalJoinRule = String(current.join_rule || "invite")
        originalHistoryVisibility = String(current.history_visibility || "shared")
        originalGuestAccess = String(current.guest_access || "forbidden")
        originalReadReceiptPreference = String(root.roomReadReceiptOverrides[current.room_id] || "inherit")
        originalTypingPreference = String(
            root.roomTypingNotificationOverrides[current.room_id] || "inherit")
        roomNameEditor.text = originalName
        roomTopicEditor.text = originalTopic
        roomAvatarEditor.text = originalAvatarUrl

        joinRuleEditor.model = optionsWithCurrent(
            ["invite", "public", "knock", "restricted", "knock_restricted"],
            originalJoinRule)
        historyEditor.model = optionsWithCurrent(
            ["invited", "joined", "shared", "world_readable"],
            originalHistoryVisibility)
        guestEditor.model = optionsWithCurrent(
            ["forbidden", "can_join"], originalGuestAccess)

        joinRuleEditor.currentIndex = valueIndex(
            joinRuleEditor.model, originalJoinRule, "invite")
        historyEditor.currentIndex = valueIndex(
            historyEditor.model, originalHistoryVisibility, "shared")
        guestEditor.currentIndex = valueIndex(
            guestEditor.model, originalGuestAccess, "forbidden")
        readReceiptEditor.currentIndex = valueIndex(
            readReceiptEditor.model, originalReadReceiptPreference, "inherit")
        typingEditor.currentIndex = valueIndex(
            typingEditor.model, originalTypingPreference, "inherit")
    }

    function submitChanges() {
        if (!details || saving)
            return
        var avatar = roomAvatarEditor.text.trim()
        if (avatar !== "" && avatar.indexOf("mxc://") !== 0) {
            errorText = L10n.I18n.tr("Аватар должен быть ссылкой mxc://")
            return
        }

        var changes = ({})
        var name = roomNameEditor.text.trim()
        var topic = roomTopicEditor.text.trim()
        if (name !== originalName)
            changes.name = name
        if (topic !== originalTopic)
            changes.topic = topic
        if (avatar !== originalAvatarUrl)
            changes.avatar_url = avatar

        var selectedJoinRule = String(
            joinRuleEditor.model[joinRuleEditor.currentIndex] || originalJoinRule)
        var selectedHistoryVisibility = String(
            historyEditor.model[historyEditor.currentIndex] || originalHistoryVisibility)
        var selectedGuestAccess = String(
            guestEditor.model[guestEditor.currentIndex] || originalGuestAccess)
        if (selectedJoinRule !== originalJoinRule)
            changes.join_rule = selectedJoinRule
        if (selectedHistoryVisibility !== originalHistoryVisibility)
            changes.history_visibility = selectedHistoryVisibility
        if (selectedGuestAccess !== originalGuestAccess)
            changes.guest_access = selectedGuestAccess

        var selectedReadReceiptPreference = String(
            readReceiptEditor.model[readReceiptEditor.currentIndex] || "inherit")
        var readReceiptPreferenceChanged = selectedReadReceiptPreference
            !== originalReadReceiptPreference
        var selectedTypingPreference = String(
            typingEditor.model[typingEditor.currentIndex] || "inherit")
        var typingPreferenceChanged = selectedTypingPreference
            !== originalTypingPreference

        var userPowerChanges = ({})
        for (var index = 0; index < powerLevelEditorRepeater.count; ++index) {
            var editor = powerLevelEditorRepeater.itemAt(index)
            if (!editor)
                continue
            var level = editor.currentLevel()
            if (!isFinite(level) || Math.floor(level) !== level) {
                errorText = L10n.I18n.tr("Уровень доступа должен быть целым числом")
                return
            }
            if (level > 100) {
                errorText = L10n.I18n.tr("Уровень доступа не может быть больше 100")
                return
            }
            if (level < -100) {
                errorText = L10n.I18n.tr("Уровень доступа не может быть меньше -100")
                return
            }
            if (level !== editor.originalLevel)
                userPowerChanges[editor.userId] = level
        }
        if (Object.keys(userPowerChanges).length > 0)
            changes.user_power_levels = userPowerChanges

        if (readReceiptPreferenceChanged)
            root.roomReadReceiptPreferenceChanged(details.room_id,
                                                   selectedReadReceiptPreference)
        if (typingPreferenceChanged)
            root.roomTypingPreferenceChanged(details.room_id,
                                             selectedTypingPreference)

        if (Object.keys(changes).length === 0) {
            if (readReceiptPreferenceChanged || typingPreferenceChanged) {
                close()
                return
            }
            errorText = L10n.I18n.tr("Нет изменений для сохранения")
            return
        }

        saving = true
        errorText = ""
        root.roomUpdateRequested(String(details.room_id || ""), changes)
    }

    parent: Overlay.overlay
    modal: true
    dim: true
    padding: 0
    width: Math.min(640, parent ? parent.width - 32 : 640)
    height: Math.min(700, parent ? parent.height - 32 : 700)
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    closePolicy: saving ? Popup.NoAutoClose
                        : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: {
        saving = false
        errorText = ""
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: L10n.UiPreferences.duration(45) }
            NumberAnimation { property: "scale"; from: 0.985; to: 1; duration: L10n.UiPreferences.duration(55); easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: L10n.UiPreferences.duration(35) }
    }

    background: Rectangle {
        radius: 12
        color: root.surfaceColor
        border.color: Qt.rgba(root.textSecondary.r, root.textSecondary.g, root.textSecondary.b, 0.18)
        border.width: 1
    }

    contentItem: Item {
        Item {
            id: roomDetailsActionBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 66

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: root.dividerColor
                opacity: 0.72
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10

                Basic.Button {
                    id: roomDetailsCancelButton
                    visible: roomDetailsDialog.editing
                    width: visible ? (parent.width - 10) / 2 : 0
                    height: 38
                    enabled: !roomDetailsDialog.saving
                    text: L10n.I18n.tr("Отмена")
                    hoverEnabled: true
                    scale: down ? 0.96 : 1
                    onClicked: roomDetailsDialog.close()
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic } }
                    background: Rectangle {
                        radius: 7
                        color: roomDetailsCancelButton.down
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                            : roomDetailsCancelButton.hovered
                                ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                                : root.elevatedColor
                    }
                    contentItem: Text {
                        text: parent.text
                        color: root.textPrimary
                        font.pointSize: 9
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Basic.Button {
                    id: roomDetailsPrimaryButton
                    width: roomDetailsDialog.editing ? (parent.width - 10) / 2 : parent.width
                    height: 38
                    enabled: !roomDetailsDialog.saving
                    text: roomDetailsDialog.editing
                        ? (roomDetailsDialog.saving ? L10n.I18n.tr("Сохранение…") : L10n.I18n.tr("Сохранить"))
                        : L10n.I18n.tr("Закрыть")
                    hoverEnabled: true
                    scale: down ? 0.96 : 1
                    onClicked: roomDetailsDialog.editing
                        ? roomDetailsDialog.submitChanges() : roomDetailsDialog.close()
                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(100); easing.type: Easing.OutCubic } }
                    background: Rectangle {
                        radius: 7
                        color: roomDetailsPrimaryButton.down
                            ? Qt.darker(root.accentColor, 1.18)
                            : roomDetailsPrimaryButton.hovered
                                ? Qt.lighter(root.accentColor, 1.08) : root.accentColor
                    }
                    contentItem: Text {
                        text: parent.text
                        color: root.accentTextColor
                        font.bold: true
                        font.pointSize: 9
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        Flickable {
            id: roomDetailsFlickable
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: roomDetailsActionBar.top
            clip: true
            contentWidth: width
            contentHeight: roomDetailsContent.implicitHeight + 40
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: PrismScrollBar {
                policy: ScrollBar.AsNeeded
                autoHide: true
                handleColor: root.textSecondary
                handleHoverColor: root.accentColor
                trackColor: Qt.rgba(root.textSecondary.r, root.textSecondary.g,
                                    root.textSecondary.b, 0.14)
            }

            Column {
                id: roomDetailsContent
                x: 20
                y: 20
                width: roomDetailsFlickable.width - 40
                spacing: 14

                Row {
                    width: parent.width
                    spacing: 12

                    AvatarItem {
                        mxcUrl: roomDetailsDialog.details ? roomDetailsDialog.details.avatar_url || "" : ""
                        fallbackId: roomDetailsDialog.details ? roomDetailsDialog.details.room_id || "" : ""
                        mediaProxy: root.mediaProxy
                        roundAvatars: root.roundAvatars
                        size: 52
                    }

                    Column {
                        width: parent.width - 64
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            width: parent.width
                            text: roomDetailsDialog.details
                                ? roomDetailsDialog.details.display_name || roomDetailsDialog.details.name || L10n.I18n.tr("Комната")
                                : L10n.I18n.tr("Комната")
                            color: root.textPrimary
                            font.bold: true
                            font.pointSize: 14
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: roomDetailsDialog.editing
                                ? (roomDetailsDialog.details && roomDetailsDialog.details.is_space
                                    ? L10n.I18n.tr("Редактирование пространства")
                                    : L10n.I18n.tr("Редактирование комнаты"))
                                : roomDetailsDialog.roomKind()
                            color: root.textSecondary
                            font.pointSize: 9
                        }
                    }
                }

                Text {
                    visible: !roomDetailsDialog.editing
                        && roomDetailsDialog.details && roomDetailsDialog.details.topic
                    width: parent.width
                    text: roomDetailsDialog.details ? roomDetailsDialog.details.topic : ""
                    wrapMode: Text.Wrap
                    color: root.textPrimary
                    font.pointSize: 9
                }

                Rectangle { width: parent.width; height: 1; color: root.dividerColor; opacity: 0.7 }

                Grid {
                    visible: !roomDetailsDialog.editing
                    width: parent.width
                    columns: 2
                    rowSpacing: 12
                    columnSpacing: 16

                    Repeater {
                        model: roomDetailsDialog.details ? [
                            { icon: "members", label: L10n.I18n.tr("Участники"), value: String(roomDetailsDialog.details.joined_members_count || 0) },
                            { icon: "members", label: L10n.I18n.tr("Приглашены"), value: String(roomDetailsDialog.details.invited_members_count || 0) },
                            { icon: "members", label: L10n.I18n.tr("Активные участники"), value: String(roomDetailsDialog.details.active_members_count || 0) },
                            { icon: "hash", label: L10n.I18n.tr("Прямые связи"), value: String(roomDetailsDialog.details.direct_targets_count || 0) },
                            { icon: "shield", label: L10n.I18n.tr("Шифрование"), value: roomDetailsDialog.details.is_encrypted ? L10n.I18n.tr("Включено") : L10n.I18n.tr("Нет") },
                            { icon: "bell", label: L10n.I18n.tr("Непрочитанные"), value: String(roomDetailsDialog.details.unread_notification_count || 0) },
                            { icon: "bell", label: L10n.I18n.tr("Важные упоминания"), value: String(roomDetailsDialog.details.unread_highlight_count || 0) },
                            { icon: "hash", label: L10n.I18n.tr("Состояние"), value: String(roomDetailsDialog.details.room_state || L10n.I18n.tr("Неизвестно")) },
                            { icon: "hash", label: L10n.I18n.tr("Тип комнаты"), value: String(roomDetailsDialog.details.room_type || roomDetailsDialog.roomKind()) },
                            { icon: "hash", label: L10n.I18n.tr("Последнее событие"), value: roomDetailsDialog.timestampText(roomDetailsDialog.details.last_event_timestamp) }
                        ] : []

                        delegate: Row {
                            required property var modelData
                            width: (parent.width - 16) / 2
                            spacing: 8
                            Canvas {
                                width: 20; height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                property color iconColor: root.iconColor
                                onIconColorChanged: requestPaint()
                                onPaint: root.drawIcon(getContext("2d"), modelData.icon, iconColor, width, height)
                            }
                            Column {
                                width: parent.width - 28
                                spacing: 1
                                Text { width: parent.width; text: modelData.label; color: root.textSecondary; font.pointSize: 8; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.value; color: root.textPrimary; font.pointSize: 9; font.bold: true; elide: Text.ElideRight }
                            }
                        }
                    }
                }

                Column {
                    visible: !roomDetailsDialog.editing
                    width: parent.width
                    spacing: 8

                    Text { text: L10n.I18n.tr("РАСШИРЕННАЯ ИНФОРМАЦИЯ"); color: root.textSecondary; font.pointSize: 7; font.bold: true }

                    Repeater {
                        model: roomDetailsDialog.details ? [
                            { label: L10n.I18n.tr("Matrix ID"), value: String(roomDetailsDialog.details.room_id || "") },
                            { label: L10n.I18n.tr("Канонический алиас"), value: String(roomDetailsDialog.details.canonical_alias || L10n.I18n.tr("Не задан")) },
                            { label: L10n.I18n.tr("MXC-адрес аватара"), value: String(roomDetailsDialog.details.avatar_url || L10n.I18n.tr("Не задан")) }
                        ] : []

                        delegate: Column {
                            required property var modelData
                            width: parent.width
                            spacing: 2
                            Text { text: modelData.label; color: root.textSecondary; font.pointSize: 7; font.bold: true }
                            Text {
                                width: parent.width
                                text: modelData.value
                                color: root.textPrimary
                                font.pointSize: 8
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }

                Column {
                    visible: !roomDetailsDialog.editing
                        && roomDetailsDialog.details
                        && (roomDetailsDialog.details.user_power_levels || []).length > 0
                    width: parent.width
                    spacing: 8

                    Text {
                        text: L10n.I18n.tr("ПРАВА ПОЛЬЗОВАТЕЛЕЙ")
                        color: root.textSecondary
                        font.pointSize: 7
                        font.bold: true
                    }

                    Repeater {
                        model: roomDetailsDialog.details
                            ? roomDetailsDialog.details.user_power_levels || [] : []
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 42
                            radius: 7
                            color: root.elevatedColor

                            Column {
                                anchors.left: parent.left
                                anchors.right: powerLevelValue.left
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: modelData.display_name || modelData.user_id
                                    color: root.textPrimary
                                    font.pointSize: 8
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.user_id || ""
                                    color: root.textSecondary
                                    font.pointSize: 7
                                    elide: Text.ElideMiddle
                                }
                            }
                            Text {
                                id: powerLevelValue
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.power_level || 0)
                                color: root.accentColor
                                font.pointSize: 10
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        visible: roomDetailsDialog.details
                            && !!roomDetailsDialog.details.power_levels_truncated
                        width: parent.width
                        text: L10n.I18n.tr("Показаны первые 200 участников")
                        color: root.textSecondary
                        font.pointSize: 7
                        wrapMode: Text.WordWrap
                    }
                }

                Column {
                    visible: roomDetailsDialog.editing
                    width: parent.width
                    spacing: 10

                    Text { text: L10n.I18n.tr("Название"); color: root.textSecondary; font.pointSize: 8; font.bold: true }
                    Basic.TextField {
                        id: roomNameEditor
                        width: parent.width
                        height: 38
                        color: root.textPrimary
                        placeholderText: L10n.I18n.tr("Название комнаты или пространства")
                        placeholderTextColor: root.textSecondary
                        background: Rectangle {
                            radius: 8
                            color: root.elevatedColor
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: root.accentColor
                        }
                    }

                    Text { text: L10n.I18n.tr("Описание / тема"); color: root.textSecondary; font.pointSize: 8; font.bold: true }
                    Basic.TextArea {
                        id: roomTopicEditor
                        width: parent.width
                        height: 72
                        color: root.textPrimary
                        wrapMode: TextEdit.Wrap
                        placeholderText: L10n.I18n.tr("Описание комнаты или пространства")
                        placeholderTextColor: root.textSecondary
                        background: Rectangle {
                            radius: 8
                            color: root.elevatedColor
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: root.accentColor
                        }
                    }

                    Text { text: L10n.I18n.tr("Аватар (mxc://)"); color: root.textSecondary; font.pointSize: 8; font.bold: true }
                    Basic.TextField {
                        id: roomAvatarEditor
                        width: parent.width
                        height: 38
                        color: root.textPrimary
                        placeholderText: "mxc://server/media-id"
                        placeholderTextColor: root.textSecondary
                        background: Rectangle {
                            radius: 8
                            color: root.elevatedColor
                            border.width: parent.activeFocus ? 1 : 0
                            border.color: root.accentColor
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 10

                        Column {
                            width: (parent.width - 12) / 2
                            spacing: 5
                            Text { text: L10n.I18n.tr("Правило входа"); color: root.textSecondary; font.pointSize: 8 }
                            StyledComboBox {
                                id: joinRuleEditor
                                width: parent.width
                                model: ["invite", "public", "knock", "restricted", "knock_restricted"]
                                accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                                surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                            }
                        }

                        Column {
                            width: (parent.width - 12) / 2
                            spacing: 5
                            Text { text: L10n.I18n.tr("История сообщений"); color: root.textSecondary; font.pointSize: 8 }
                            StyledComboBox {
                                id: historyEditor
                                width: parent.width
                                model: ["invited", "joined", "shared", "world_readable"]
                                accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                                surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                            }
                        }

                        Column {
                            width: (parent.width - 12) / 2
                            spacing: 5
                            Text { text: L10n.I18n.tr("Гостевой доступ"); color: root.textSecondary; font.pointSize: 8 }
                            StyledComboBox {
                                id: guestEditor
                                width: parent.width
                                model: ["forbidden", "can_join"]
                                accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                                surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                            }
                        }

                        Column {
                            width: (parent.width - 12) / 2
                            spacing: 5
                            Text { text: L10n.I18n.tr("Отметки о прочтении"); color: root.textSecondary; font.pointSize: 8 }
                            StyledComboBox {
                                id: readReceiptEditor
                                width: parent.width
                                model: ["inherit", "on", "off"]
                                accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                                surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                            }
                        }

                        Column {
                            width: (parent.width - 12) / 2
                            spacing: 5
                            Text { text: L10n.I18n.tr("Индикатор набора текста"); color: root.textSecondary; font.pointSize: 8 }
                            StyledComboBox {
                                id: typingEditor
                                width: parent.width
                                model: ["inherit", "on", "off"]
                                accentColor: root.accentColor; textPrimary: root.textPrimary; textSecondary: root.textSecondary
                                surfaceColor: root.elevatedColor; elevatedColor: root.surfaceColor
                            }
                        }
                    }
                }

                Column {
                    visible: roomDetailsDialog.editing
                        && roomDetailsDialog.details
                        && (roomDetailsDialog.details.can_kick_members
                            || roomDetailsDialog.details.can_ban_members
                            || roomDetailsDialog.details.can_manage_power_levels)
                        && (roomDetailsDialog.details.user_power_levels || []).length > 0
                    width: parent.width
                    spacing: 8

                    Text {
                        text: L10n.I18n.tr("Управление участниками")
                        color: root.textPrimary
                        font.pointSize: 9
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: L10n.I18n.tr("Роли задаются уровнем доступа; также можно исключить или заблокировать участника.")
                        color: root.textSecondary
                        font.pointSize: 7
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        id: powerLevelEditorRepeater
                        model: roomDetailsDialog.details
                            ? roomDetailsDialog.details.user_power_levels || [] : []

                        delegate: Rectangle {
                            id: powerLevelEditorDelegate
                            required property var modelData
                            property string userId: String(modelData.user_id || "")
                            property int originalLevel: Number(modelData.power_level || 0)
                            function currentLevel() { return Number(powerEditor.text) }

                            width: parent.width
                            height: 48
                            radius: 7
                            color: root.elevatedColor

                            Column {
                                anchors.left: parent.left
                                anchors.right: moderationButtons.visible
                                    ? moderationButtons.left : powerEditor.left
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: modelData.display_name || modelData.user_id
                                    color: root.textPrimary
                                    font.pointSize: 8
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.user_id || ""
                                    color: root.textSecondary
                                    font.pointSize: 7
                                    elide: Text.ElideMiddle
                                }
                            }

                            Row {
                                id: moderationButtons
                                visible: roomDetailsDialog.canModerateTarget(
                                    powerLevelEditorDelegate.userId,
                                    powerLevelEditorDelegate.originalLevel)
                                    && (roomDetailsDialog.details.can_kick_members
                                        || roomDetailsDialog.details.can_ban_members)
                                anchors.right: powerEditor.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Basic.Button {
                                    id: kickMemberButton
                                    visible: roomDetailsDialog.details.can_kick_members
                                    width: visible ? 66 : 0
                                    height: 30
                                    enabled: !roomDetailsDialog.memberModerationBusy
                                    hoverEnabled: true
                                    scale: down ? 0.91 : 1
                                    text: L10n.I18n.tr("Исключить")
                                    onClicked: roomDetailsDialog.moderateMember(
                                        powerLevelEditorDelegate.userId, "kick")
                                    contentItem: Text {
                                        text: kickMemberButton.text
                                        color: "#ffb36b"; font.pointSize: 7
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        radius: 7
                                        color: kickMemberButton.hovered
                                            ? Qt.rgba(1, 0.55, 0.2, 0.14) : root.surfaceColor
                                        border.width: 1
                                        border.color: Qt.rgba(1, 0.55, 0.2, 0.4)
                                    }
                                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90) } }
                                }

                                Basic.Button {
                                    id: banMemberButton
                                    visible: roomDetailsDialog.details.can_ban_members
                                    width: visible ? 54 : 0
                                    height: 30
                                    enabled: !roomDetailsDialog.memberModerationBusy
                                    hoverEnabled: true
                                    scale: down ? 0.91 : 1
                                    text: L10n.I18n.tr("Бан")
                                    onClicked: roomDetailsDialog.moderateMember(
                                        powerLevelEditorDelegate.userId, "ban")
                                    contentItem: Text {
                                        text: banMemberButton.text
                                        color: "#ff7777"; font.pointSize: 7
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        radius: 7
                                        color: banMemberButton.hovered
                                            ? Qt.rgba(1, 0.3, 0.3, 0.14) : root.surfaceColor
                                        border.width: 1
                                        border.color: Qt.rgba(1, 0.3, 0.3, 0.4)
                                    }
                                    Behavior on scale { NumberAnimation { duration: L10n.UiPreferences.duration(90) } }
                                }
                            }

                            Basic.TextField {
                                id: powerEditor
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 58
                                height: 34
                                enabled: roomDetailsDialog.details.can_manage_power_levels
                                text: String(powerLevelEditorDelegate.originalLevel)
                                color: root.textPrimary
                                horizontalAlignment: TextInput.AlignHCenter
                                validator: IntValidator { bottom: -100; top: 100 }
                                background: Rectangle {
                                    radius: 7
                                    color: root.surfaceColor
                                    border.width: parent.activeFocus ? 1 : 0
                                    border.color: root.accentColor
                                }
                            }
                        }
                    }

                    Text {
                        visible: roomDetailsDialog.details
                            && !!roomDetailsDialog.details.power_levels_truncated
                        width: parent.width
                        text: L10n.I18n.tr("Для редактирования показаны первые 200 участников")
                        color: root.textSecondary
                        font.pointSize: 7
                        wrapMode: Text.WordWrap
                    }
                }

                Text {
                    visible: roomDetailsDialog.errorText !== ""
                    width: parent.width
                    text: roomDetailsDialog.errorText
                    color: "#ff6b6b"
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}

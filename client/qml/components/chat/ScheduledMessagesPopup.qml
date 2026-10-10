import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../common"
import "../../utils" as L10n
import "../../assets/icons" as Icons

Basic.Popup {
    id: root

    property var scheduledItems: []
    property color accentColor: "#20D500"
    property color accentTextColor: "#071007"
    property color elevatedColor: "#102016"
    property color surfaceColor: "#0B1710"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"

    property string editingItemId: ""
    property var stagedAttachments: []
    property string stagedReplyEventId: ""
    property var stagedMentionedUserIds: []
    property string validationError: ""

    signal saveRequested(string itemId, string body, double scheduledAt,
                         var attachments, string replyEventId,
                         var mentionedUserIds)
    signal cancelRequested(string itemId)

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(500, parent ? parent.width - 32 : 500)
    height: Math.min(650, parent ? parent.height - 32 : 650)
    modal: true
    focus: true
    padding: 0
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.48) }

    background: Rectangle {
        radius: 14
        color: root.elevatedColor
        border.width: 1
        border.color: root.dividerColor
    }

    function pad2(value) {
        return Number(value) < 10 ? "0" + Number(value) : String(Number(value))
    }

    function dateText(timestamp) {
        var value = new Date(Number(timestamp || Date.now()))
        return pad2(value.getDate()) + "." + pad2(value.getMonth() + 1)
            + "." + value.getFullYear()
    }

    function timeText(timestamp) {
        var value = new Date(Number(timestamp || Date.now()))
        return pad2(value.getHours()) + ":" + pad2(value.getMinutes())
    }

    function displayTimestamp(timestamp) {
        return dateText(timestamp) + "  " + timeText(timestamp)
    }

    function defaultTimestamp() {
        var value = new Date(Date.now() + 60 * 60 * 1000)
        value.setSeconds(0, 0)
        return value.getTime()
    }

    function applyTimestamp(timestamp) {
        scheduleDate.text = dateText(timestamp)
        scheduleTime.text = timeText(timestamp)
    }

    function openForDraft(body, attachments, replyEventId, mentionedUserIds) {
        editingItemId = ""
        stagedAttachments = attachments ? attachments.slice(0) : []
        stagedReplyEventId = replyEventId || ""
        stagedMentionedUserIds = mentionedUserIds ? mentionedUserIds.slice(0) : []
        messageEditor.text = body || ""
        validationError = ""
        applyTimestamp(defaultTimestamp())
        open()
        messageEditor.forceActiveFocus()
    }

    function editItem(item) {
        editingItemId = String((item && item.id) || "")
        stagedAttachments = item && item.attachments
            ? item.attachments.slice(0) : []
        stagedReplyEventId = String((item && item.reply_event_id) || "")
        stagedMentionedUserIds = item && item.mentioned_user_ids
            ? item.mentioned_user_ids.slice(0) : []
        messageEditor.text = String((item && item.body) || "")
        validationError = ""
        applyTimestamp(Number((item && item.scheduled_at) || defaultTimestamp()))
        messageEditor.forceActiveFocus()
    }

    function setPreset(offsetDays, hour, minute) {
        var value = new Date()
        value.setDate(value.getDate() + Number(offsetDays || 0))
        value.setHours(hour, minute, 0, 0)
        if (value.getTime() <= Date.now() + 5000)
            value.setDate(value.getDate() + 1)
        applyTimestamp(value.getTime())
        validationError = ""
    }

    function parsedTimestamp() {
        var dateMatch = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec(
            scheduleDate.text.trim())
        var timeMatch = /^(\d{1,2}):(\d{2})$/.exec(scheduleTime.text.trim())
        if (!dateMatch || !timeMatch)
            return NaN
        var day = Number(dateMatch[1])
        var month = Number(dateMatch[2])
        var year = Number(dateMatch[3])
        var hour = Number(timeMatch[1])
        var minute = Number(timeMatch[2])
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59)
            return NaN
        var value = new Date(year, month - 1, day, hour, minute, 0, 0)
        if (value.getFullYear() !== year || value.getMonth() !== month - 1
                || value.getDate() !== day)
            return NaN
        return value.getTime()
    }

    function submit() {
        var body = messageEditor.text.trim()
        if (body === "" && stagedAttachments.length === 0) {
            validationError = L10n.I18n.tr("Введите сообщение или добавьте вложение")
            return
        }
        var timestamp = parsedTimestamp()
        if (!isFinite(timestamp)) {
            validationError = L10n.I18n.tr("Проверьте дату и время")
            return
        }
        if (timestamp <= Date.now() + 5000) {
            validationError = L10n.I18n.tr("Выберите время в будущем")
            return
        }
        validationError = ""
        saveRequested(editingItemId, body, timestamp, stagedAttachments,
                      stagedReplyEventId, stagedMentionedUserIds)
        editingItemId = ""
        stagedAttachments = []
        stagedReplyEventId = ""
        stagedMentionedUserIds = []
        messageEditor.text = ""
        close()
    }

    contentItem: ColumnLayout {
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: root.editingItemId !== ""
                    ? L10n.I18n.tr("Изменить отложенное сообщение")
                    : L10n.I18n.tr("Отложенная отправка")
                color: root.textPrimary
                font.pointSize: 12
                font.bold: true
            }

            Basic.Button {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                onClicked: root.close()
                contentItem: Icons.CloseIcon {
                    color: root.textSecondary
                    width: 18
                    height: 18
                }
                background: Rectangle {
                    radius: 8
                    color: parent.hovered
                        ? Qt.rgba(root.textPrimary.r, root.textPrimary.g,
                                  root.textPrimary.b, 0.08) : "transparent"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.dividerColor
            opacity: 0.7
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: editorColumn.implicitHeight + 32
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: editorColumn
                x: 16
                y: 16
                width: parent.width - 32
                spacing: 12

                TextArea {
                    id: messageEditor
                    width: parent.width
                    height: Math.max(86, Math.min(150, implicitHeight + 20))
                    placeholderText: L10n.I18n.tr("Сообщение")
                    color: root.textPrimary
                    placeholderTextColor: root.textSecondary
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    background: Rectangle {
                        radius: 10
                        color: root.surfaceColor
                        border.width: 1
                        border.color: messageEditor.activeFocus
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                      root.accentColor.b, 0.55)
                            : root.dividerColor
                    }
                }

                Text {
                    visible: root.stagedAttachments.length > 0
                    width: parent.width
                    text: L10n.I18n.tr("Вложения") + ": "
                        + root.stagedAttachments.length
                    color: root.textSecondary
                    font.pointSize: 8
                }

                RowLayout {
                    width: parent.width
                    spacing: 8

                    TextField {
                        id: scheduleDate
                        Layout.fillWidth: true
                        placeholderText: L10n.I18n.tr("ДД.ММ.ГГГГ")
                        color: root.textPrimary
                        selectByMouse: true
                        background: Rectangle {
                            radius: 9
                            color: root.surfaceColor
                            border.width: 1
                            border.color: parent.activeFocus
                                ? root.accentColor : root.dividerColor
                        }
                    }
                    TextField {
                        id: scheduleTime
                        Layout.preferredWidth: 104
                        placeholderText: L10n.I18n.tr("ЧЧ:ММ")
                        color: root.textPrimary
                        selectByMouse: true
                        background: Rectangle {
                            radius: 9
                            color: root.surfaceColor
                            border.width: 1
                            border.color: parent.activeFocus
                                ? root.accentColor : root.dividerColor
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 7

                    Repeater {
                        model: [
                            { text: L10n.I18n.tr("Через час"), days: 0, hour: -1 },
                            { text: L10n.I18n.tr("Сегодня вечером"), days: 0, hour: 21 },
                            { text: L10n.I18n.tr("Завтра утром"), days: 1, hour: 9 }
                        ]

                        delegate: Basic.Button {
                            required property var modelData
                            height: 30
                            width: Math.min(132, implicitWidth + 20)
                            text: modelData.text
                            onClicked: {
                                if (modelData.hour < 0)
                                    root.applyTimestamp(root.defaultTimestamp())
                                else
                                    root.setPreset(modelData.days, modelData.hour, 0)
                            }
                            contentItem: Text {
                                text: parent.text
                                color: root.textSecondary
                                font.pointSize: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.12)
                                    : root.surfaceColor
                                border.width: 1
                                border.color: root.dividerColor
                            }
                        }
                    }
                }

                Text {
                    visible: root.validationError !== ""
                    width: parent.width
                    text: root.validationError
                    color: "#ff7777"
                    font.pointSize: 8
                    wrapMode: Text.Wrap
                }

                Basic.Button {
                    width: parent.width
                    height: 38
                    text: root.editingItemId !== ""
                        ? L10n.I18n.tr("Сохранить изменения")
                        : L10n.I18n.tr("Запланировать")
                    onClicked: root.submit()
                    contentItem: Text {
                        text: parent.text
                        color: root.accentTextColor
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: parent.down
                            ? Qt.darker(root.accentColor, 1.12) : root.accentColor
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.dividerColor
                    visible: root.scheduledItems.length > 0
                }

                Text {
                    visible: root.scheduledItems.length > 0
                    width: parent.width
                    text: L10n.I18n.tr("Запланированные сообщения")
                    color: root.textPrimary
                    font.pointSize: 10
                    font.bold: true
                }

                Repeater {
                    model: root.scheduledItems

                    delegate: Rectangle {
                        required property var modelData
                        width: editorColumn.width
                        height: 78
                        radius: 10
                        color: root.surfaceColor
                        border.width: 1
                        border.color: root.dividerColor

                        Column {
                            anchors.left: parent.left
                            anchors.right: actions.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 10
                            anchors.rightMargin: 8
                            spacing: 4

                            Text {
                                width: parent.width
                                text: modelData.body || L10n.I18n.tr("Вложение")
                                color: root.textPrimary
                                font.pointSize: 9
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: root.displayTimestamp(modelData.scheduled_at)
                                    + (modelData.attachments
                                       && modelData.attachments.length > 0
                                        ? " · " + L10n.I18n.tr("вложений") + ": "
                                          + modelData.attachments.length : "")
                                color: root.textSecondary
                                font.pointSize: 8
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: actions
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Basic.Button {
                                width: 34
                                height: 32
                                onClicked: root.editItem(modelData)
                                contentItem: Icons.PencilIcon {
                                    color: root.accentColor
                                    width: 16
                                    height: 16
                                }
                                background: Rectangle {
                                    radius: 8
                                    color: parent.hovered
                                        ? Qt.rgba(root.accentColor.r,
                                                  root.accentColor.g,
                                                  root.accentColor.b, 0.12)
                                        : "transparent"
                                }
                            }
                            Basic.Button {
                                width: 34
                                height: 32
                                onClicked: root.cancelRequested(modelData.id || "")
                                contentItem: Icons.CloseIcon {
                                    color: "#ff7777"
                                    width: 17
                                    height: 17
                                }
                                background: Rectangle {
                                    radius: 8
                                    color: parent.hovered
                                        ? Qt.rgba(1, 0.3, 0.3, 0.12)
                                        : "transparent"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

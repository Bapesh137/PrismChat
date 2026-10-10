import QtQuick
import "../../utils" as L10n
import "../../utils/PrismUtils.js" as Utils
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../common"

Item {
    id: root

    readonly property string emojiFontFamily: L10n.UiPreferences.emojiFontFamily

    property int selectedCount: 0
    property bool canDeleteSelected: false
    property string currentUserId: ""
    property bool canRedactOther: false
    property bool threadsEnabled: true
    property string mediaProxy: ""
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A8B7AB"
    property color dividerColor: "#29402E"
    property bool roundAvatars: true
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"
    property int singleIndex: -1
    property var singleData: null
    property var stickerPackResolver: null
    property var authorNameResolver: null
    property var authorAvatarResolver: null
    property var singleStickerPack: null

    signal copySelectedRequested()
    signal deleteSelectedRequested()
    signal copySingleRequested(string text)
    signal copyLinkRequested(var messageData)
    signal markUnreadRequested(int messageIndex, var messageData)
    signal sourceRequested(var messageData)
    signal editRequested(var messageData)
    signal replyRequested(var messageData)
    signal threadRequested(var messageData)
    signal deleteSingleRequested(int messageIndex, var messageData)
    signal pinRequested(var messageData)
    signal reactionRequested(var messageData, string key)
    signal downloadRequested(var messageData)
    signal stickerSaveRequested(var messageData)
    signal stickerPackViewRequested(var pack)

    function openMulti() {
        multiMenu.popup()
    }

    function openSingle(messageIndex, messageData) {
        singleIndex = messageIndex
        singleData = messageData
        singleStickerPack = stickerPackResolver && messageData
            ? stickerPackResolver(messageData) : null
        singleMenu.reactionsExpanded = false
        singleMenu.readersExpanded = false
        singleMenu.popup()
    }

    function openQuickReactionEditor() {
        singleMenu.close()
        if (reactionEditorLoader.item)
            reactionEditorLoader.item.open()
        else
            reactionEditorLoader.active = true
    }

    Loader {
        id: reactionEditorLoader
        active: false
        onLoaded: item.open()
        sourceComponent: Component {
            EmojiPicker {
                objectName: "quickReactionEditor"
                parent: root.Overlay.overlay
                anchors.centerIn: parent
                width: Math.min(380, parent ? parent.width - 16 : 380)
                height: Math.min(460, parent ? parent.height - 16 : 460)
                quickReactionsMode: true
                accentColor: root.accentColor
                surfaceColor: root.elevatedColor
                elevatedColor: root.elevatedColor
                textPrimary: root.textPrimary
                textSecondary: root.textSecondary
                dividerColor: root.dividerColor
                onClosed: Qt.callLater(function() {
                    if (!reactionEditorLoader.item
                            || !reactionEditorLoader.item.opened)
                        reactionEditorLoader.active = false
                })
            }
        }
    }

    function reactionActive(key) {
        if (!singleData || !singleData.reactions)
            return false
        var reactions = singleData.reactions
        var count = typeof reactions.length === "number"
            ? reactions.length : Number(reactions.count || 0)
        for (var index = 0; index < count; index++) {
            var reaction = typeof reactions.get === "function"
                ? reactions.get(index) : reactions[index]
            if (reaction && reaction.key === key)
                return !!reaction.reacted
        }
        return false
    }

    function receiptCount() {
        if (!singleData || !singleData.read_receipts)
            return 0
        var receipts = singleData.read_receipts
        return typeof receipts.length === "number"
            ? receipts.length : Number(receipts.count || 0)
    }

    function receiptAt(index) {
        if (!singleData || !singleData.read_receipts)
            return ({})
        var receipts = singleData.read_receipts
        if (typeof receipts.get === "function")
            return receipts.get(index) || ({})
        return receipts[index] || ({})
    }

    function receiptDisplayName(receipt) {
        var userId = String((receipt && receipt.user_id) || "")
        var cachedName = String((receipt && receipt.display_name) || "")
        if (authorNameResolver)
            return authorNameResolver(userId, cachedName)
        return cachedName || Utils.displayName(userId)
    }

    function receiptAvatarUrl(receipt) {
        var userId = String((receipt && receipt.user_id) || "")
        var cachedAvatar = String((receipt && receipt.avatar_url) || "")
        if (authorAvatarResolver)
            return authorAvatarResolver(userId, cachedAvatar)
        return cachedAvatar
    }

    function receiptTime(receipt) {
        var timestamp = Number((receipt && receipt.timestamp) || 0)
        if (timestamp <= 0)
            return L10n.I18n.tr("Время прочтения неизвестно")
        var formatted = Qt.formatDateTime(new Date(timestamp),
                                          messageDateFormat + " " + messageTimeFormat)
        return L10n.I18n.tr("Прочитано") + ": " + formatted
    }

    Basic.Menu {
        id: multiMenu
        width: 244
        height: multiColumn.implicitHeight + topPadding + bottomPadding
        padding: 6

        background: Rectangle {
            color: root.elevatedColor
            radius: 10
            border.width: 1
            border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                  root.dividerColor.b, 0.9)
        }

        contentItem: Column {
            id: multiColumn
            width: multiMenu.availableWidth

            ContextMenuAction {
                text: root.selectedCount > 1
                    ? L10n.I18n.tr("Копировать (") + root.selectedCount + ")"
                    : L10n.I18n.tr("Копировать")
                iconKind: "copy"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.selectedCount > 0
                onClicked: {
                    multiMenu.close()
                    root.copySelectedRequested()
                }
            }

            Item {
                width: parent.width
                height: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    height: 1
                    color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                   root.dividerColor.b, 0.72)
                }
            }

            ContextMenuAction {
                text: root.selectedCount > 1
                    ? L10n.I18n.tr("Удалить (") + root.selectedCount + ")"
                    : L10n.I18n.tr("Удалить")
                iconKind: "delete"
                destructive: true
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.canDeleteSelected
                onClicked: {
                    multiMenu.close()
                    root.deleteSelectedRequested()
                }
            }
        }
    }

    Basic.Menu {
        id: singleMenu
        objectName: "messageSingleMenu"
        property bool reactionsExpanded: false
        property bool readersExpanded: false

        width: readersExpanded ? 310 : 244
        height: singleColumn.implicitHeight + topPadding + bottomPadding
        padding: 6

        background: Rectangle {
            color: root.elevatedColor
            radius: 10
            border.width: 1
            border.color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                  root.dividerColor.b, 0.9)
        }

        contentItem: Column {
            id: singleColumn
            width: singleMenu.availableWidth

            ContextMenuAction {
                text: L10n.I18n.tr("Реакция")
                iconKind: "reaction"
                showArrow: true
                expanded: singleMenu.reactionsExpanded
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData
                    && !root.singleData.is_system
                    && !root.singleData.is_redacted
                    && !root.singleData.is_encrypted
                onClicked: singleMenu.reactionsExpanded = !singleMenu.reactionsExpanded
            }

            Item {
                width: parent.width
                height: singleMenu.reactionsExpanded ? 40 : 0
                opacity: singleMenu.reactionsExpanded ? 1 : 0
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(120)
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: L10n.UiPreferences.duration(90) }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    LayoutMirroring.enabled: false

                    Repeater {
                        model: L10n.QuickReactionStore.orderedKeys

                        delegate: Basic.Button {
                            required property string modelData
                            objectName: "quickReaction_" + modelData
                            readonly property bool active: root.reactionActive(modelData)
                            width: 34
                            height: 34
                            padding: 0
                            hoverEnabled: true
                            scale: down ? 0.84 : hovered ? 1.08 : 1

                            Behavior on scale {
                                NumberAnimation {
                                    duration: L10n.UiPreferences.duration(90)
                                    easing.type: Easing.OutCubic
                                }
                            }

                            contentItem: Text {
                                text: modelData
                                elide: Text.ElideRight
                                clip: true
                                font.family: root.emojiFontFamily
                                font.pointSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 8
                                color: parent.down
                                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                              root.accentColor.b, 0.26)
                                    : parent.active
                                        ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                                  root.accentColor.b, 0.19)
                                        : parent.hovered
                                            ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                                                      root.accentColor.b, 0.11)
                                            : "transparent"
                                border.width: parent.active ? 1 : 0
                                border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                                                      root.accentColor.b, 0.62)
                                Behavior on color {
                                    ColorAnimation { duration: L10n.UiPreferences.duration(90) }
                                }
                            }

                            onClicked: {
                                singleMenu.close()
                                if (root.singleData)
                                    root.reactionRequested(root.singleData, modelData)
                            }
                        }
                    }
                }
            }

            ContextMenuAction {
                objectName: "editQuickReactions"
                visible: singleMenu.reactionsExpanded
                text: L10n.I18n.tr("Изменить набор")
                iconKind: "edit"
                accentColor: root.accentColor
                textColor: root.textPrimary
                onClicked: root.openQuickReactionEditor()
            }

            ContextMenuAction {
                visible: root.singleData && root.singleData.msg_type === "m.sticker"
                text: L10n.I18n.tr("Добавить в мои стикеры")
                iconKind: "reaction"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData && (root.singleData.media_url || "") !== ""
                onClicked: {
                    singleMenu.close()
                    if (root.singleData) root.stickerSaveRequested(root.singleData)
                }
            }

            ContextMenuAction {
                visible: root.singleData && root.singleData.msg_type === "m.sticker"
                    && !!root.singleStickerPack
                text: L10n.I18n.tr("Посмотреть набор")
                iconKind: "source"
                accentColor: root.accentColor
                textColor: root.textPrimary
                onClicked: {
                    var pack = root.singleStickerPack
                    singleMenu.close()
                    if (pack) root.stickerPackViewRequested(pack)
                }
            }

            Item {
                visible: root.singleData && root.singleData.msg_type === "m.sticker"
                width: parent.width
                height: visible ? 7 : 0
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    height: 1
                    color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                   root.dividerColor.b, 0.72)
                }
            }

            ContextMenuAction {
                text: L10n.I18n.tr("Ответить")
                iconKind: "reply"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData
                    && !root.singleData.is_system
                    && !root.singleData.is_redacted
                    && !root.singleData.is_encrypted
                    && (root.singleData.event_id || "") !== ""
                    && (root.singleData.event_id || "").indexOf("local:") !== 0
                onClicked: {
                    singleMenu.close()
                    if (root.singleData) root.replyRequested(root.singleData)
                }
            }
            ContextMenuAction {
                visible: root.threadsEnabled
                text: L10n.I18n.tr("Ответить в треде")
                iconKind: "reply"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData
                    && !root.singleData.is_system
                    && !root.singleData.is_redacted
                    && !root.singleData.is_encrypted
                    && (root.singleData.event_id || "") !== ""
                    && (root.singleData.event_id || "").indexOf("local:") !== 0
                    && (root.singleData.thread_root_id || "") === ""
                onClicked: {
                    singleMenu.close()
                    if (root.singleData) root.threadRequested(root.singleData)
                }
            }
            ContextMenuAction {
                text: L10n.I18n.tr("Отметить как непрочитанное")
                iconKind: "unread"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData
                    && (root.singleData.event_id || "") !== ""
                    && (root.singleData.event_id || "").indexOf("local:") !== 0
                onClicked: {
                    var message = root.singleData
                    singleMenu.close()
                    if (message && root.singleIndex >= 0)
                        root.markUnreadRequested(root.singleIndex, message)
                }
            }

            ContextMenuAction {
                visible: root.singleData
                    && !root.singleData.is_system
                text: L10n.I18n.tr("Прочитали") + " · " + root.receiptCount()
                iconKind: "readers"
                showArrow: root.receiptCount() > 0
                expanded: singleMenu.readersExpanded
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.receiptCount() > 0
                onClicked: singleMenu.readersExpanded = !singleMenu.readersExpanded
            }

            Item {
                visible: root.singleData
                    && !root.singleData.is_system
                width: parent.width
                height: visible && singleMenu.readersExpanded
                    ? Math.min(192, root.receiptCount() * 48) : 0
                opacity: singleMenu.readersExpanded ? 1 : 0
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: L10n.UiPreferences.duration(120)
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: L10n.UiPreferences.duration(90) }
                }

                ListView {
                    id: receiptReadersList
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.receiptCount()

                    delegate: Item {
                        id: readerRow
                        required property int index
                        readonly property var receipt: root.receiptAt(index)
                        width: receiptReadersList.width
                        height: 48

                        AvatarItem {
                            id: readerAvatar
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            size: 30
                            mxcUrl: root.receiptAvatarUrl(readerRow.receipt)
                            fallbackId: (readerRow.receipt.user_id || "")
                            mediaProxy: root.mediaProxy
                            roundAvatars: root.roundAvatars
                        }

                        Column {
                            anchors.left: readerAvatar.right
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: root.receiptDisplayName(readerRow.receipt)
                                color: root.textPrimary
                                font.pointSize: 9
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: root.receiptTime(readerRow.receipt)
                                color: root.textSecondary
                                font.pointSize: 8
                                elide: Text.ElideRight
                            }
                        }
                    }

                    ScrollBar.vertical: PrismScrollBar {
                        policy: ScrollBar.AsNeeded
                        autoHide: true
                        handleColor: root.textSecondary
                        handleHoverColor: root.accentColor
                        trackColor: Qt.rgba(root.textSecondary.r,
                                            root.textSecondary.g,
                                            root.textSecondary.b, 0.14)
                    }
                }
            }


            ContextMenuAction {
                text: L10n.I18n.tr("Копировать")
                iconKind: "copy"
                accentColor: root.accentColor
                textColor: root.textPrimary
                onClicked: {
                    singleMenu.close()
                    if (root.singleData)
                        root.copySingleRequested(root.singleData.body || "")
                }
            }

            ContextMenuAction {
                text: L10n.I18n.tr("Копировать ссылку на сообщение")
                iconKind: "link"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData
                    && (root.singleData.event_id || "") !== ""
                    && (root.singleData.event_id || "").indexOf("local:") !== 0
                onClicked: {
                    var message = root.singleData
                    singleMenu.close()
                    if (message)
                        root.copyLinkRequested(message)
                }
            }

            ContextMenuAction {
                text: L10n.I18n.tr("Показать исходник")
                iconKind: "source"
                accentColor: root.accentColor
                textColor: root.textPrimary
                onClicked: {
                    singleMenu.close()
                    if (root.singleData) root.sourceRequested(root.singleData)
                }
            }

            ContextMenuAction {
                text: root.singleData && root.singleData.pinned
                    ? L10n.I18n.tr("Открепить сообщение")
                    : L10n.I18n.tr("Закрепить сообщение")
                iconKind: "pin"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData && !root.singleData.is_redacted
                    && !root.singleData.is_encrypted
                onClicked: {
                    singleMenu.close()
                    if (root.singleData) root.pinRequested(root.singleData)
                }
            }

            ContextMenuAction {
                text: L10n.I18n.tr("Редактировать")
                iconKind: "edit"
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData
                    && root.singleData.sender === root.currentUserId
                    && root.singleData.msg_type === "m.text"
                    && !root.singleData.is_redacted
                    && !root.singleData.is_encrypted
                    && (root.singleData.event_id || "") !== ""
                    && (root.singleData.event_id || "").indexOf("local:") !== 0
                    && (root.singleData.send_state || "sent") === "sent"
                onClicked: {
                    singleMenu.close()
                    if (root.singleData) root.editRequested(root.singleData)
                }
            }

            ContextMenuAction {
                text: L10n.I18n.tr("Удалить")
                iconKind: "delete"
                destructive: true
                accentColor: root.accentColor
                textColor: root.textPrimary
                enabled: root.singleData
                    && !root.singleData.is_system
                    && !root.singleData.is_redacted
                    && (root.singleData.event_id || "") !== ""
                    && (root.singleData.event_id || "").indexOf("local:") !== 0
                    && (root.singleData.sender === root.currentUserId || root.canRedactOther)
                onClicked: {
                    singleMenu.close()
                    if (root.singleData)
                        root.deleteSingleRequested(root.singleIndex, root.singleData)
                }
            }

            Item {
                visible: root.singleData && (root.singleData.media_url || "") !== ""
                width: parent.width
                height: visible ? 7 : 0
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    height: 1
                    color: Qt.rgba(root.dividerColor.r, root.dividerColor.g,
                                   root.dividerColor.b, 0.72)
                }
            }

            ContextMenuAction {
                visible: root.singleData && (root.singleData.media_url || "") !== ""
                text: L10n.I18n.tr("Скачать файл")
                iconKind: "download"
                accentColor: root.accentColor
                textColor: root.textPrimary
                onClicked: {
                    singleMenu.close()
                    if (root.singleData && root.singleData.media_url)
                        root.downloadRequested(root.singleData)
                }
            }
        }
    }
}

import ".." as Chat
import QtQuick
import Prism.Ipc 1.0 as Native
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "../../common"
import "../../../assets/icons" as Icons
import "../../../utils" as L10n
import "../../../utils/PrismUtils.js" as Utils

Item {
    id: root

    readonly property alias attachmentContextMenuObject: attachmentContextMenu
    readonly property alias attachmentsVideoPlayerObject: attachmentsVideoPlayer
    readonly property alias panelObject: panel

    property bool opened: false
    property string roomId: ""
    readonly property var activeRoom: roomCache[roomId] || newRoom()
    readonly property var activeCategory: activeRoom.states[currentCategory] || newCategory()
    readonly property var attachments: activeRoom.items
    readonly property string nextFrom: activeCategory.nextFrom
    readonly property string errorText: activeCategory.error
    readonly property bool loading: (pageRequests[roomId] && pageRequests[roomId].category === currentCategory) || (opened && needsMore())
    readonly property bool canLoadMore: hasLoadedPage && !loading && errorText === "" && nextFrom !== ""
    property int currentCategory: 0
    property string mediaProxy: ""
    property var authorNameResolver: null
    property int authorNameRevision: 0
    property string messageDateFormat: "dd.MM.yyyy"
    property string messageTimeFormat: "HH:mm"
    property bool autoLoadImages: true
    property bool autoLoadVideos: true
    property color accentColor: "#20D500"
    property color iconColor: accentColor
    property color accentTextColor: "#071007"
    property color backgroundColor: "#07100A"
    property color surfaceColor: "#0B1710"
    property color elevatedColor: "#102016"
    property color textPrimary: "#F2FFF4"
    property color textSecondary: "#A7B8AA"
    property color dividerColor: "#29402E"
    property string activeVoiceEventId: ""
    property bool activeVoicePlaying: false
    readonly property bool hasLoadedPage: activeCategory.loaded
    property var roomCache: ({})
    property var pageRequests: ({})
    property var ignoredSenders: ({})
    property int requestSequence: 0
    // Keep quick reopen useful without retaining thousands of JS objects after
    // browsing attachment-heavy rooms.
    readonly property int maxCachedRooms: 4
    readonly property int maxCachedAttachmentsPerRoom: 120

    function authorName(sender, fallback) {
        var revision = root.authorNameRevision
        if (authorNameResolver)
            return authorNameResolver(sender || "", fallback || "")
        return fallback || Utils.displayName(sender || "")
    }

    signal loadMoreRequested(string targetRoomId, string nextFrom, string requestId, int category, int count)
    signal imageRequested(string source, string caption)
    signal urlRequested(string url)
    signal downloadRequested(var item)
    signal messageRequested(string eventId)
    signal closed()
    signal voicePlaybackRequested(var details)

    visible: opened || opacity > 0.01
    enabled: opened
    opacity: opened ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: L10n.UiPreferences.duration(170); easing.type: Easing.OutCubic } }

    function newCategory() { return {loaded: false, nextFrom: "", goal: 30, error: ""} }
    function newRoom() {
        return Native.FrontendLogic.invoke("attachments.newRoom", root, [])
    }

    function saveRoom(targetRoomId, value) {
        return Native.FrontendLogic.invoke("attachments.saveRoom", root, [targetRoomId, value])
    }

    function saveCategory(targetRoomId, category, state, items) {
        return Native.FrontendLogic.invoke("attachments.saveCategory", root,
                                           [targetRoomId, category, state, items])
    }

    function cacheCurrentRoom() {
        return Native.FrontendLogic.invoke("attachments.cacheCurrentRoom", root, [])
    }

    function openForRoom(targetRoomId) {
        return Native.FrontendLogic.invoke("attachments.openForRoom", root, [targetRoomId])
    }

    onCurrentCategoryChanged: {
        if (opened) {
            cacheCurrentRoom()
            Qt.callLater(continueLoading)
        }
    }

    function needsMore() {
        return Native.FrontendLogic.invoke("attachments.needsMore", root, [])
    }

    function continueLoading() {
        return Native.FrontendLogic.invoke("attachments.continueLoading", root, [])
    }

    function close() {
        return Native.FrontendLogic.invoke("attachments.close", root, [])
    }

    function reset() {
        return Native.FrontendLogic.invoke("attachments.reset", root, [])
    }

    function requestPage(from) {
        return Native.FrontendLogic.invoke("attachments.requestPage", root, [from])
    }

    function receivePage(targetRoomId, items, continuation, error, requestId) {
        return Native.FrontendLogic.invoke("attachments.receivePage", root,
                                           [targetRoomId, items, continuation,
                                            error, requestId])
    }

    function reconcileTimeline(targetRoomId, model) {
        return Native.FrontendLogic.invoke("attachments.reconcileTimeline", root,
                                           [targetRoomId, model])
    }

    function setSenderIgnored(userId, ignored) {
        return Native.FrontendLogic.invoke("attachments.setSenderIgnored", root, [userId, ignored])
    }

    function openAttachmentContext(item, sourceItem, localX, localY) {
        var eventId = item ? (item.event_id || "") : ""
        if (eventId === "" || !sourceItem) return
        var point = sourceItem.mapToItem(root, localX, localY)
        attachmentContextMenu.eventId = eventId
        attachmentContextMenu.x = Math.max(8, Math.min(
            root.width - attachmentContextMenu.width - 8, point.x))
        attachmentContextMenu.y = Math.max(8, Math.min(
            root.height - attachmentContextMenu.height - 8, point.y))
        attachmentContextMenu.open()
    }

    function requestNextPage() {
        if (!opened || !canLoadMore) return
        saveCategory(roomId, currentCategory, Object.assign({}, activeCategory,
            {goal: categoryCount(currentCategory) + 30}))
        continueLoading()
    }

    function mergePage(existing, items) {
        return Native.FrontendLogic.invoke("attachments.mergePage", root, [existing, items])
    }

    function firstLink(body) {
        return Native.FrontendLogic.invoke("attachments.firstLink", root, [body])
    }

    function isVideoItem(item) {
        return Native.FrontendLogic.invoke("attachments.isVideoItem", root, [item])
    }

    function matchesCategory(item, category) {
        return Native.FrontendLogic.invoke("attachments.matchesCategory", root, [item, category])
    }

    readonly property var categoryItems: {
        var groups = [[],[],[],[]]
        var source = attachments || []
        for (var i = 0; i < source.length; i++)
            for (var c = 0; c < 4; c++)
                if (matchesCategory(source[i],c)) { groups[c].push(source[i]); break }
        return groups
    }

    function filtered(category) { return categoryItems[category] || [] }
    function categoryCount(category) { return filtered(category).length }

    function timestampText(timestamp) {
        return Utils.formatMessageTimestamp(timestamp || 0, messageDateFormat,
                                            messageTimeFormat, L10n.I18n.tr("вчера"))
    }

    function blendedColor(base, overlay, amount) {
        var ratio = Math.max(0, Math.min(1, Number(amount || 0)))
        return Qt.rgba(base.r + (overlay.r - base.r) * ratio,
                       base.g + (overlay.g - base.g) * ratio,
                       base.b + (overlay.b - base.b) * ratio,
                       base.a)
    }

    function openMedia(item) {
        if (!item || !item.media_url) return
        var source = Utils.proxyUrl(item.media_url, mediaProxy,
                                    item.media_file, item.media_mime_type)
        if ((item.msg_type || "") === "m.image") {
            imageRequested(source, item.body || L10n.I18n.tr("Изображение"))
        } else if (root.isVideoItem(item)) {
            attachmentsVideoPlayer.eventId = item.event_id || ""
            attachmentsVideoPlayer.mediaUrl = item.media_url || ""
            attachmentsVideoPlayer.mediaFile = item.media_file || null
            attachmentsVideoPlayer.mediaMimeType = item.media_mime_type || ""
            attachmentsVideoPlayer.title = item.body || L10n.I18n.tr("Видео")
            attachmentsVideoPlayer.open()
        } else {
            urlRequested(source)
        }
    }

    function openFile(item) {
        if (item && item.media_url)
            downloadRequested(item)
    }

    function toggleVoice(item) {
        if (!item || !item.media_url) return
        root.voicePlaybackRequested({
            event_id: item.event_id || item.media_url,
            room_id: root.roomId,
            title: root.authorName(item.sender || "", item.sender_display_name || ""),
            source: Utils.proxyUrl(item.media_url, mediaProxy,
                                   item.media_file, item.media_mime_type)
        })
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.close()
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }

    AttachmentBrowser {
        id: panel
        attachments: root
    }
    Chat.VideoPlayerPopup {
        id: attachmentsVideoPlayer
        mediaProxy: root.mediaProxy
        accentColor: root.accentColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        elevatedColor: root.elevatedColor
        dividerColor: root.dividerColor
    }

    Basic.Menu {
        id: attachmentContextMenu
        parent: root
        z: 12000
        width: 220
        padding: 6
        property string eventId: ""

        onClosed: eventId = ""

        background: Rectangle {
            radius: 10
            color: root.elevatedColor
            border.width: 1
            border.color: root.dividerColor
        }

        Basic.MenuItem {
            id: jumpToMessageAction
            implicitWidth: 208
            implicitHeight: 38
            text: L10n.I18n.tr("Перейти к сообщению")

            onTriggered: {
                var targetEventId = attachmentContextMenu.eventId
                attachmentContextMenu.close()
                root.close()
                if (targetEventId !== "")
                    root.messageRequested(targetEventId)
            }

            contentItem: Text {
                text: jumpToMessageAction.text
                color: root.textPrimary
                font.pointSize: 9
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
                rightPadding: 10
            }

            background: Rectangle {
                radius: 7
                color: jumpToMessageAction.highlighted
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.13)
                    : "transparent"
            }
        }
    }
}

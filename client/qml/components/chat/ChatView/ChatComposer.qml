import ".." as Chat
import QtQuick
import "../../../utils" as L10n
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import "../../../utils/PrismUtils.js" as Utils

Chat.MessageComposer {
    required property var chat
    readonly property var root: chat
    id: composer
    anchors.bottom: parent.bottom
    width: parent.width - root.rightPanelWidth
    currentRoomId: root.currentRoomId
    currentUserId: root.currentUserId
    dispatchEnabled: root.backendConnected
    mediaProxy: root.mediaProxy
    authorNameResolver: root.authorDisplayName
    authorNameRevision: root.authorNameRevision
    requestIdFactory: root.requestIdFactory
    clearDraftsGeneration: root.draftClearGeneration
    typingNotificationsEnabled: root.typingNotificationsEnabled
    onDraftRoomIdsChanged: root.draftRoomIds = draftRoomIds
    accentColor: root.accentColor
    iconColor: root.iconColor
    accentTextColor: root.accentTextColor
    backgroundColor: root.backgroundColor
    surfaceColor: root.surfaceColor
    elevatedColor: root.elevatedColor
    textPrimary: root.textPrimary
    textSecondary: root.textSecondary
    dividerColor: root.dividerColor
    stickerProvider: root.collectStickerLibrary
    stickerPackProvider: root.collectSharedStickerPacks

    onMessageSubmitted: function(text, editEventId, replyEventId,
                                 mentionedUserIds) {
        if (editEventId !== "") {
            var editRequestId = root.nextRequestId("edit")
            var edits = Object.assign({}, root.pendingEdits)
            edits[editRequestId] = {
                room_id: root.currentRoomId,
                event_id: editEventId,
                body: text
            }
            root.pendingEdits = edits
            root.commandRequested({
                type: "edit_message",
                request_id: editRequestId,
                room_id: root.currentRoomId,
                event_id: editEventId,
                new_body: text
            })
        } else {
            var requestId = root.nextRequestId("send")
            root.commandRequested({
                type: "send_message",
                request_id: requestId,
                room_id: root.currentRoomId,
                body: text,
                reply_to: replyEventId || undefined,
                mentioned_user_ids: mentionedUserIds || []
            })
        }
    }

    onScheduledMessageDue: function(message) {
        if (!message || !message.room_id)
            return
        var roomId = String(message.room_id)
        var body = String(message.body || "").trim()
        if (body !== "") {
            root.commandRequested({
                type: "send_message",
                request_id: root.nextRequestId("scheduled-send"),
                room_id: roomId,
                body: body,
                reply_to: message.reply_event_id || undefined,
                mentioned_user_ids: message.mentioned_user_ids || []
            })
        }
        var attachments = message.attachments || []
        for (var index = 0; index < attachments.length; index++) {
            var attachment = attachments[index] || ({})
            var uploadRequestId = root.nextRequestId("scheduled-upload")
            composer.beginUpload(uploadRequestId, roomId,
                                 attachment.name || L10n.I18n.tr("Вложение"))
            root.commandRequested({
                type: "upload_media",
                request_id: uploadRequestId,
                room_id: roomId,
                path: attachment.path || "",
                mime_type: attachment.mime
                    || Utils.guessMime(attachment.name || ""),
                filename: attachment.name || L10n.I18n.tr("Вложение"),
                duration_ms: Math.max(0, Math.round(
                    Number(attachment.duration_ms || 0))),
                as_sticker: false
            })
        }
        root.feedbackRequested(
            L10n.I18n.tr("Отложенное сообщение отправляется"), false)
    }

    onUploadRequested: function(path, filename, mimeType, durationMs) {
        var uploadRequestId = root.nextRequestId("upload")
        composer.beginUpload(uploadRequestId, root.currentRoomId, filename)
        root.commandRequested({
            type: "upload_media",
            request_id: uploadRequestId,
            room_id: root.currentRoomId,
            path: path,
            mime_type: mimeType || Utils.guessMime(filename),
            filename: filename,
            duration_ms: Math.max(0, Math.round(Number(durationMs || 0))),
            as_sticker: false
        })
    }

    onUploadCancelRequested: function(uploadRequestId) {
        var cancelled = Object.assign({}, root.cancelledUploadIds)
        cancelled[uploadRequestId] = true
        root.cancelledUploadIds = cancelled
        root.commandRequested({
            type: "cancel_upload",
            request_id: root.nextRequestId("cancel-upload"),
            upload_request_id: uploadRequestId
        })
    }

    onStickerMediaRequested: function(sticker) { root.sendSticker(sticker) }

    onStickerAssetCreateRequested: function(draft) {
        if (!draft || root.currentRoomId === "" || !draft.path)
            return
        var requestId = root.nextRequestId("sticker-asset")
        var pending = Object.assign({}, root.pendingStickerCreations)
        pending[requestId] = Object.assign({}, draft, { account_id: root.currentUserId })
        root.pendingStickerCreations = pending
        root.commandRequested({
            type: "upload_sticker_asset",
            request_id: requestId,
            path: draft.path,
            mime_type: draft.mime_type || Utils.guessMime(draft.filename || ""),
            filename: draft.filename || "sticker"
        })
    }

    onStickerPackShareRequested: function(pack) { root.shareStickerPack(pack) }
    onStickerSaveRequested: function(sticker) { root.saveStickerToOwn(sticker) }
    onStickerPackViewRequested: function(pack) { root.openStickerPack(pack) }

    onClipboardPasteRequested: function(requestId) {
        root.commandRequested({
            type: "paste_clipboard",
            request_id: requestId,
            room_id: root.currentRoomId
        })
    }

    onFeedbackRequested: function(text, isError) {
        root.feedbackRequested(text, isError)
    }

    onTypingStateChanged: function(roomId, typing) {
        root.typingStateChanged(roomId, typing)
    }
}

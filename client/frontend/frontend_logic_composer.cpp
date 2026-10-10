#include "frontend_logic.h"

#include "frontend_logic_support.h"

#include <QJsonDocument>
#include <QRegularExpression>
#include <QUrl>

using namespace FrontendLogicSupport;

namespace {

QString json(const QJSValue &value)
{
    return QString::fromUtf8(
        QJsonDocument::fromVariant(value.toVariant()).toJson(QJsonDocument::Compact));
}

QString guessMime(const QString &filename)
{
    static const QHash<QString, QString> mimeTypes = {
        {QStringLiteral("png"), QStringLiteral("image/png")},
        {QStringLiteral("jpg"), QStringLiteral("image/jpeg")},
        {QStringLiteral("jpeg"), QStringLiteral("image/jpeg")},
        {QStringLiteral("gif"), QStringLiteral("image/gif")},
        {QStringLiteral("apng"), QStringLiteral("image/apng")},
        {QStringLiteral("webp"), QStringLiteral("image/webp")},
        {QStringLiteral("mp4"), QStringLiteral("video/mp4")},
        {QStringLiteral("m4v"), QStringLiteral("video/mp4")},
        {QStringLiteral("mov"), QStringLiteral("video/quicktime")},
        {QStringLiteral("mkv"), QStringLiteral("video/x-matroska")},
        {QStringLiteral("webm"), QStringLiteral("video/webm")},
        {QStringLiteral("avi"), QStringLiteral("video/x-msvideo")},
        {QStringLiteral("mpeg"), QStringLiteral("video/mpeg")},
        {QStringLiteral("mpg"), QStringLiteral("video/mpeg")},
        {QStringLiteral("ogv"), QStringLiteral("video/ogg")},
        {QStringLiteral("ts"), QStringLiteral("video/mp2t")},
        {QStringLiteral("mts"), QStringLiteral("video/mp2t")},
        {QStringLiteral("m2ts"), QStringLiteral("video/mp2t")},
        {QStringLiteral("3gp"), QStringLiteral("video/3gpp")},
        {QStringLiteral("3g2"), QStringLiteral("video/3gpp2")},
        {QStringLiteral("flv"), QStringLiteral("video/x-flv")},
        {QStringLiteral("mp3"), QStringLiteral("audio/mpeg")},
        {QStringLiteral("m4a"), QStringLiteral("audio/mp4")},
        {QStringLiteral("aac"), QStringLiteral("audio/aac")},
        {QStringLiteral("ogg"), QStringLiteral("audio/ogg")},
        {QStringLiteral("opus"), QStringLiteral("audio/ogg")},
        {QStringLiteral("wav"), QStringLiteral("audio/wav")},
        {QStringLiteral("flac"), QStringLiteral("audio/flac")},
        {QStringLiteral("pdf"), QStringLiteral("application/pdf")}
    };
    return mimeTypes.value(filename.section(QLatin1Char('.'), -1).toLower(),
                           QStringLiteral("application/octet-stream"));
}

QString localFileUrl(const QString &path)
{
    QString normalized = path;
    normalized.replace(QLatin1Char('\\'), QLatin1Char('/'));
    static const QRegularExpression drive(QStringLiteral("^[A-Za-z]:/"));
    if (drive.match(normalized).hasMatch())
        return QStringLiteral("file:///") + normalized;
    return normalized.startsWith(QLatin1Char('/'))
        ? QStringLiteral("file://") + normalized : normalized;
}

QString localPath(const QString &fileUrl)
{
    if (fileUrl.isEmpty())
        return {};
    const QUrl url(fileUrl);
    if (url.isLocalFile())
        return url.toLocalFile();
    QString path = fileUrl;
    if (path.startsWith(QStringLiteral("file://")))
        path.remove(0, 7);
    else if (path.startsWith(QStringLiteral("file:")))
        path.remove(0, 5);
    path = QUrl::fromPercentEncoding(path.toUtf8());
    static const QRegularExpression windowsPath(QStringLiteral("^/[A-Za-z]:[/\\\\]"));
    if (windowsPath.match(path).hasMatch())
        path.remove(0, 1);
    return path;
}

QJSValue messageArea(const QJSValue &root)
{
    return root.property(QStringLiteral("inputBarObject"))
        .property(QStringLiteral("messageAreaObject"));
}

void feedback(const QJSValue &root, const QString &message, bool isError)
{
    callRoot(root, QStringLiteral("feedbackRequested"),
             {QJSValue(message), QJSValue(isError)});
}

QJSValue clipboardProvider(const QJSValue &root)
{
    const QJSValue platform = root.property(QStringLiteral("platformClipboard"));
    return platform.isObject()
        ? platform : root.property(QStringLiteral("nativeClipboardHelper"));
}

} // namespace

QJSValue FrontendLogic::invokeComposer(const QString &operation,
                                       const QJSValue &root,
                                       const QJSValue &arguments)
{
    QJSEngine *engine = engineFor(root);
    const QJSValue first = argument(arguments, 0);
    const QJSValue second = argument(arguments, 1);
    const QJSValue third = argument(arguments, 2);
    const QJSValue fourth = argument(arguments, 3);
    const QJSValue fifth = argument(arguments, 4);
    const QJSValue sixth = argument(arguments, 5);
    const QJSValue seventh = argument(arguments, 6);

    if (operation == QStringLiteral("uploadsForRoom")) {
        Values result;
        const QString roomId = string(first);
        for (const QJSValue &upload : values(root.property(QStringLiteral("activeUploads")))) {
            if (string(upload.property(QStringLiteral("room_id"))) == roomId)
                result.append(upload);
        }
        return arrayFromValues(engine, result);
    }

    if (operation == QStringLiteral("beginUpload")) {
        Values uploads = values(root.property(QStringLiteral("activeUploads")));
        QString filename = string(third);
        if (filename.isEmpty())
            filename = translated(root, QStringLiteral("Вложение"));
        uploads.append(objectFromProperties(engine, {
            {QStringLiteral("request_id"), first},
            {QStringLiteral("room_id"), second},
            {QStringLiteral("filename"), QJSValue(filename)},
            {QStringLiteral("current"), QJSValue(0)},
            {QStringLiteral("total"), QJSValue(0)}
        }));
        set(root, QStringLiteral("activeUploads"), arrayFromValues(engine, uploads));
        return undefined();
    }

    if (operation == QStringLiteral("updateUpload")) {
        Values uploads = values(root.property(QStringLiteral("activeUploads")));
        for (int index = 0; index < uploads.size(); ++index) {
            if (string(uploads.at(index).property(QStringLiteral("request_id")))
                != string(first))
                continue;
            uploads[index] = mergeObjects(engine, uploads.at(index), {
                {QStringLiteral("current"), QJSValue(number(second))},
                {QStringLiteral("total"), QJSValue(number(third))}
            });
            set(root, QStringLiteral("activeUploads"), arrayFromValues(engine, uploads));
            break;
        }
        return undefined();
    }

    if (operation == QStringLiteral("finishUpload")) {
        Values retained;
        for (const QJSValue &upload : values(root.property(QStringLiteral("activeUploads")))) {
            if (string(upload.property(QStringLiteral("request_id"))) != string(first))
                retained.append(upload);
        }
        set(root, QStringLiteral("activeUploads"), arrayFromValues(engine, retained));
        return undefined();
    }

    if (operation == QStringLiteral("formatBytes")) {
        const double bytes = qMax(0.0, number(first));
        if (bytes < 1024)
            return QJSValue(QString::number(qRound(bytes)) + QStringLiteral(" B"));
        if (bytes < 1024 * 1024)
            return QJSValue(QString::number(bytes / 1024, 'f', 1) + QStringLiteral(" KB"));
        return QJSValue(QString::number(bytes / (1024 * 1024), 'f', 1)
                        + QStringLiteral(" MB"));
    }

    if (operation == QStringLiteral("attachmentCountText")) {
        const int count = qMax(0, qRound(number(first)));
        const int lastTwo = count % 100;
        const int last = count % 10;
        const QString word = last == 1 && lastTwo != 11
            ? translated(root, QStringLiteral("файл"))
            : last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)
                ? translated(root, QStringLiteral("файла"))
                : translated(root, QStringLiteral("файлов"));
        return QJSValue(QString::number(count) + QLatin1Char(' ') + word);
    }

    if (operation == QStringLiteral("attachmentSummary")) {
        QString summary = string(callRoot(root, QStringLiteral("attachmentCountText"),
            {QJSValue(length(root.property(QStringLiteral("pendingAttachments"))))}));
        if (boolean(root.property(QStringLiteral("pendingAttachmentSizesKnown")))) {
            summary += QStringLiteral(" · ")
                + string(callRoot(root, QStringLiteral("formatBytes"),
                                  {root.property(QStringLiteral("pendingAttachmentsTotalSize"))}));
        }
        return QJSValue(summary);
    }

    if (operation == QStringLiteral("largestPendingAttachment")) {
        QJSValue largest = nullValue();
        double largestSize = -1;
        const double threshold = number(root.property(QStringLiteral("largeFileWarningBytes")));
        for (const QJSValue &attachment : values(root.property(QStringLiteral("pendingAttachments")))) {
            const double size = attachment.property(QStringLiteral("size")).toNumber();
            if (std::isfinite(size) && size >= threshold && size > largestSize) {
                largest = attachment;
                largestSize = size;
            }
        }
        return largest;
    }

    if (operation == QStringLiteral("localFileUrl"))
        return QJSValue(localFileUrl(string(first)));

    if (operation == QStringLiteral("clipboardProvider"))
        return clipboardProvider(root);

    if (operation == QStringLiteral("stageAttachment")) {
        const QString path = string(second);
        if (path.isEmpty())
            return undefined();
        QString filename = string(third);
        if (filename.isEmpty())
            filename = translated(root, QStringLiteral("Вложение"));
        QString mime = string(fifth);
        if (mime.isEmpty())
            mime = guessMime(filename);
        const QJSValue provider = clipboardProvider(root);
        double size = seventh.toNumber();
        if (!std::isfinite(size) || size < 0) {
            const QJSValue method = provider.property(QStringLiteral("fileSizeForPath"));
            size = provider.isObject() && method.isCallable()
                ? call(provider, QStringLiteral("fileSizeForPath"), {QJSValue(path)}).toNumber()
                : -1;
        }
        if ((string(fifth).isEmpty() || mime == QStringLiteral("application/octet-stream"))
            && provider.isObject()
            && provider.property(QStringLiteral("mimeTypeForFile")).isCallable()) {
            const QString nativeMime = string(call(provider, QStringLiteral("mimeTypeForFile"),
                                                   {QJSValue(path)}));
            if (!nativeMime.isEmpty() && nativeMime != QStringLiteral("application/octet-stream"))
                mime = nativeMime;
        }
        QString source = string(first);
        if (source.isEmpty())
            source = localFileUrl(path);
        QJSValue attachment = objectFromProperties(engine, {
            {QStringLiteral("source"), QJSValue(source)},
            {QStringLiteral("path"), QJSValue(path)},
            {QStringLiteral("name"), QJSValue(filename)},
            {QStringLiteral("image"), fourth.isUndefined()
                ? QJSValue(mime.startsWith(QStringLiteral("image/")))
                : QJSValue(boolean(fourth))},
            {QStringLiteral("audio"), QJSValue(mime.startsWith(QStringLiteral("audio/")))},
            {QStringLiteral("mime"), QJSValue(mime)},
            {QStringLiteral("size"), QJSValue(std::isfinite(size) && size >= 0 ? size : -1)},
            {QStringLiteral("duration_ms"), QJSValue(qMax(0, qRound(number(sixth))))}
        });
        Values attachments = values(root.property(QStringLiteral("pendingAttachments")));
        attachments.append(attachment);
        set(root, QStringLiteral("pendingAttachments"), arrayFromValues(engine, attachments));
        callRoot(root, QStringLiteral("saveCurrentDraft"));
        set(root, QStringLiteral("microphoneMode"), QJSValue(false));
        call(messageArea(root), QStringLiteral("forceActiveFocus"));
        return undefined();
    }

    if (operation == QStringLiteral("removePendingAttachment")) {
        Values attachments = values(root.property(QStringLiteral("pendingAttachments")));
        const int index = first.toInt();
        if (index < 0 || index >= attachments.size())
            return undefined();
        attachments.removeAt(index);
        set(root, QStringLiteral("pendingAttachments"), arrayFromValues(engine, attachments));
        callRoot(root, QStringLiteral("saveCurrentDraft"));
        return undefined();
    }

    if (operation == QStringLiteral("clearPendingAttachment")) {
        set(root, QStringLiteral("pendingAttachments"), array(engine));
        callRoot(root, QStringLiteral("saveCurrentDraft"));
        return undefined();
    }

    if (operation == QStringLiteral("requestClipboardPaste")) {
        if (string(root.property(QStringLiteral("currentRoomId"))).isEmpty())
            return undefined();
        const QJSValue requestId = callRoot(root, QStringLiteral("nextRequestId"),
                                            {QJSValue(QStringLiteral("clipboard"))});
        set(root, QStringLiteral("pendingPasteRequestId"), requestId);
        const QJSValue area = messageArea(root);
        set(root, QStringLiteral("pendingPasteStart"), area.property(QStringLiteral("selectionStart")));
        set(root, QStringLiteral("pendingPasteEnd"), area.property(QStringLiteral("selectionEnd")));
        const QJSValue provider = clipboardProvider(root);
        if (provider.isObject()
            && provider.property(QStringLiteral("pasteContents")).isCallable()) {
            const QJSValue result = call(provider, QStringLiteral("pasteContents"));
            callRoot(root, QStringLiteral("finishClipboardPaste"), {
                requestId,
                QJSValue(boolean(result.property(QStringLiteral("success")))),
                QJSValue(string(result.property(QStringLiteral("text")))),
                result.property(QStringLiteral("attachments")).isObject()
                    ? result.property(QStringLiteral("attachments")) : array(engine),
                QJSValue(string(result.property(QStringLiteral("error"))))
            });
            return undefined();
        }
        set(root, QStringLiteral("pendingPasteRequestId"), QJSValue(QString()));
        call(area, QStringLiteral("paste"));
        return undefined();
    }

    if (operation == QStringLiteral("finishClipboardPaste")) {
        if (string(first) != string(root.property(QStringLiteral("pendingPasteRequestId"))))
            return undefined();
        set(root, QStringLiteral("pendingPasteRequestId"), QJSValue(QString()));
        if (!boolean(second)) {
            const QString reason = localizedError(
                root, string(fifth), QStringLiteral("неизвестная ошибка"));
            feedback(root, translated(root,
                QStringLiteral("Не удалось вставить содержимое буфера: ")) + reason, true);
            return undefined();
        }
        const QJSValue area = messageArea(root);
        const QString pastedText = string(third);
        if (!pastedText.isEmpty()) {
            const int textLength = area.property(QStringLiteral("length")).toInt();
            const int start = qMax(0, qMin(root.property(QStringLiteral("pendingPasteStart")).toInt(),
                                          textLength));
            const int end = qMax(start,
                qMin(root.property(QStringLiteral("pendingPasteEnd")).toInt(), textLength));
            if (end > start)
                call(area, QStringLiteral("remove"), {QJSValue(start), QJSValue(end)});
            call(area, QStringLiteral("insert"), {QJSValue(start), QJSValue(pastedText)});
            set(area, QStringLiteral("cursorPosition"),
                QJSValue(start + int(pastedText.size())));
        }
        for (const QJSValue &attachment : values(fourth)) {
            const QString path = string(attachment.property(QStringLiteral("path")));
            QString filename = string(attachment.property(QStringLiteral("filename")));
            if (filename.isEmpty())
                filename = translated(root, QStringLiteral("Вложение"));
            callRoot(root, QStringLiteral("stageAttachment"), {
                QJSValue(localFileUrl(path)), QJSValue(path), QJSValue(filename),
                attachment.property(QStringLiteral("is_image")),
                attachment.property(QStringLiteral("mime_type")), QJSValue(0),
                attachment.property(QStringLiteral("size"))
            });
        }
        call(area, QStringLiteral("forceActiveFocus"));
        return undefined();
    }

    if (operation == QStringLiteral("clearComposerForRoomChange")) {
        callRoot(root, QStringLiteral("cancelVoiceRecording"));
        set(root, QStringLiteral("microphoneMode"), QJSValue(false));
        const QJSValue loader = root.property(QStringLiteral("emojiPickerLoaderObject"));
        if (loader.property(QStringLiteral("item")).isObject())
            call(loader.property(QStringLiteral("item")), QStringLiteral("close"));
        set(root, QStringLiteral("pendingPasteRequestId"), QJSValue(QString()));
        set(root, QStringLiteral("pendingPasteStart"), QJSValue(0));
        set(root, QStringLiteral("pendingPasteEnd"), QJSValue(0));
        callRoot(root, QStringLiteral("clearPendingAttachment"));
        set(root, QStringLiteral("mentionedUserIds"), array(engine));
        set(root, QStringLiteral("editingEventId"), QJSValue(QString()));
        callRoot(root, QStringLiteral("cancelReply"));
        set(messageArea(root), QStringLiteral("text"), QJSValue(QString()));
        return undefined();
    }

    if (operation == QStringLiteral("resetForRoomChange")) {
        callRoot(root, QStringLiteral("switchDraftRoom"),
                 {root.property(QStringLiteral("currentRoomId"))});
        return undefined();
    }

    if (operation == QStringLiteral("draftSnapshot")) {
        return objectFromProperties(engine, {
            {QStringLiteral("text"), QJSValue(string(messageArea(root).property(QStringLiteral("text"))))},
            {QStringLiteral("attachments"), cloneArray(engine, root.property(QStringLiteral("pendingAttachments")))},
            {QStringLiteral("reply_event_id"), QJSValue(string(root.property(QStringLiteral("replyingEventId"))))},
            {QStringLiteral("reply_sender"), QJSValue(string(root.property(QStringLiteral("replyingSender"))))},
            {QStringLiteral("reply_body"), QJSValue(string(root.property(QStringLiteral("replyingBody"))))},
            {QStringLiteral("mentioned_user_ids"), cloneArray(engine, root.property(QStringLiteral("mentionedUserIds")))},
            {QStringLiteral("cursor_position"), QJSValue(qMax(0,
                qRound(number(messageArea(root).property(QStringLiteral("cursorPosition"))))))}
        });
    }

    if (operation == QStringLiteral("draftHasContent")) {
        return QJSValue(first.isObject()
            && (!string(first.property(QStringLiteral("text"))).isEmpty()
                || length(first.property(QStringLiteral("attachments"))) > 0
                || !string(first.property(QStringLiteral("reply_event_id"))).isEmpty()));
    }

    if (operation == QStringLiteral("saveCurrentDraft")) {
        const QString roomId = string(root.property(QStringLiteral("activeDraftRoomId")));
        if (boolean(root.property(QStringLiteral("restoringDraft"))) || roomId.isEmpty()
            || boolean(root.property(QStringLiteral("editing"))))
            return undefined();
        QJSValue drafts = cloneObject(engine, root.property(QStringLiteral("roomDrafts")));
        const QJSValue draft = callRoot(root, QStringLiteral("draftSnapshot"));
        if (boolean(callRoot(root, QStringLiteral("draftHasContent"), {draft})))
            drafts.setProperty(roomId, draft);
        else
            drafts.deleteProperty(roomId);
        set(root, QStringLiteral("roomDrafts"), drafts);
        call(root.property(QStringLiteral("draftSaveTimerObject")), QStringLiteral("restart"));
        return undefined();
    }

    if (operation == QStringLiteral("persistDrafts")) {
        set(root.property(QStringLiteral("draftSettingsObject")),
            QStringLiteral("roomDraftsJson"),
            QJSValue(json(root.property(QStringLiteral("roomDrafts")))));
        return undefined();
    }

    if (operation == QStringLiteral("clearAllDrafts")) {
        call(root.property(QStringLiteral("draftSaveTimerObject")), QStringLiteral("stop"));
        set(root, QStringLiteral("restoringDraft"), QJSValue(true));
        callRoot(root, QStringLiteral("cancelVoiceRecording"));
        set(root, QStringLiteral("roomDrafts"), object(engine));
        set(root.property(QStringLiteral("draftSettingsObject")),
            QStringLiteral("roomDraftsJson"), QJSValue(QStringLiteral("{}")));
        callRoot(root, QStringLiteral("clearPendingAttachment"));
        set(root, QStringLiteral("mentionedUserIds"), array(engine));
        set(root, QStringLiteral("editingEventId"), QJSValue(QString()));
        callRoot(root, QStringLiteral("cancelReply"));
        set(messageArea(root), QStringLiteral("text"), QJSValue(QString()));
        set(root, QStringLiteral("activeDraftRoomId"),
            QJSValue(string(root.property(QStringLiteral("currentRoomId")))));
        set(root, QStringLiteral("restoringDraft"), QJSValue(false));
        return undefined();
    }

    if (operation == QStringLiteral("removeDraft")) {
        const QString roomId = string(first);
        const QJSValue current = root.property(QStringLiteral("roomDrafts"));
        if (roomId.isEmpty() || current.property(roomId).isUndefined())
            return undefined();
        QJSValue drafts = cloneObject(engine, current);
        drafts.deleteProperty(roomId);
        set(root, QStringLiteral("roomDrafts"), drafts);
        call(root.property(QStringLiteral("draftSaveTimerObject")), QStringLiteral("restart"));
        return undefined();
    }

    if (operation == QStringLiteral("switchDraftRoom")) {
        const QString roomId = string(first);
        if (string(root.property(QStringLiteral("activeDraftRoomId"))) == roomId)
            return undefined();
        callRoot(root, QStringLiteral("saveCurrentDraft"));
        set(root, QStringLiteral("restoringDraft"), QJSValue(true));
        callRoot(root, QStringLiteral("clearComposerForRoomChange"));
        set(root, QStringLiteral("activeDraftRoomId"), QJSValue(roomId));
        const QJSValue draft = roomId.isEmpty()
            ? nullValue() : root.property(QStringLiteral("roomDrafts")).property(roomId);
        if (draft.isObject()) {
            const QJSValue area = messageArea(root);
            set(area, QStringLiteral("text"), QJSValue(string(draft.property(QStringLiteral("text")))));
            const QJSValue attachments = draft.property(QStringLiteral("attachments"));
            set(root, QStringLiteral("pendingAttachments"),
                attachments.isObject() ? attachments : array(engine));
            set(root, QStringLiteral("replyingEventId"),
                QJSValue(string(draft.property(QStringLiteral("reply_event_id")))));
            set(root, QStringLiteral("replyingSender"),
                QJSValue(string(draft.property(QStringLiteral("reply_sender")))));
            set(root, QStringLiteral("replyingBody"),
                QJSValue(string(draft.property(QStringLiteral("reply_body")))));
            const QJSValue mentions = draft.property(QStringLiteral("mentioned_user_ids"));
            set(root, QStringLiteral("mentionedUserIds"),
                mentions.isObject() ? mentions : array(engine));
            double cursor = draft.property(QStringLiteral("cursor_position")).toNumber();
            if (!std::isfinite(cursor))
                cursor = area.property(QStringLiteral("length")).toInt();
            set(area, QStringLiteral("cursorPosition"), QJSValue(qMax(0,
                qMin(area.property(QStringLiteral("length")).toInt(), qRound(cursor)))));
        }
        set(root, QStringLiteral("restoringDraft"), QJSValue(false));
        return undefined();
    }

    if (operation == QStringLiteral("persistScheduledMessages")) {
        set(root.property(QStringLiteral("draftSettingsObject")),
            QStringLiteral("scheduledMessagesJson"),
            QJSValue(json(root.property(QStringLiteral("scheduledMessages")))));
        return undefined();
    }

    if (operation == QStringLiteral("armScheduledDispatch")) {
        const QJSValue timer = root.property(QStringLiteral("scheduledDispatchTimerObject"));
        call(timer, QStringLiteral("stop"));
        const QString accountId = string(root.property(QStringLiteral("currentUserId")));
        if (!boolean(root.property(QStringLiteral("dispatchEnabled"))) || accountId.isEmpty())
            return undefined();
        double nextTimestamp = 0;
        for (const QJSValue &item : values(root.property(QStringLiteral("scheduledMessages")))) {
            if (string(item.property(QStringLiteral("account_id"))) != accountId)
                continue;
            const double timestamp = item.property(QStringLiteral("scheduled_at")).toNumber();
            if (!std::isfinite(timestamp) || timestamp <= 0)
                continue;
            if (nextTimestamp == 0 || timestamp < nextTimestamp)
                nextTimestamp = timestamp;
        }
        if (nextTimestamp == 0)
            return undefined();
        const double delay = nextTimestamp - double(nowMs());
        if (delay <= 0) {
            callLater(root, QStringLiteral("processScheduledMessages"));
            return undefined();
        }
        set(timer, QStringLiteral("interval"), QJSValue(qMax(100,
            qMin(2147480000, qRound(delay)))));
        call(timer, QStringLiteral("start"));
        return undefined();
    }

    if (operation == QStringLiteral("processScheduledMessages")) {
        call(root.property(QStringLiteral("scheduledDispatchTimerObject")), QStringLiteral("stop"));
        const QString accountId = string(root.property(QStringLiteral("currentUserId")));
        if (!boolean(root.property(QStringLiteral("dispatchEnabled"))) || accountId.isEmpty())
            return undefined();
        Values due;
        Values remaining;
        const qint64 currentTime = nowMs();
        for (const QJSValue &item : values(root.property(QStringLiteral("scheduledMessages")))) {
            const double timestamp = item.property(QStringLiteral("scheduled_at")).toNumber();
            if (string(item.property(QStringLiteral("account_id"))) == accountId
                && std::isfinite(timestamp) && timestamp <= currentTime)
                due.append(item);
            else
                remaining.append(item);
        }
        if (!due.isEmpty()) {
            set(root, QStringLiteral("scheduledMessages"), arrayFromValues(engine, remaining));
            std::sort(due.begin(), due.end(), [](const QJSValue &left, const QJSValue &right) {
                return number(left.property(QStringLiteral("scheduled_at")))
                    < number(right.property(QStringLiteral("scheduled_at")));
            });
            for (const QJSValue &item : std::as_const(due))
                callRoot(root, QStringLiteral("scheduledMessageDue"), {item});
        } else {
            callRoot(root, QStringLiteral("armScheduledDispatch"));
        }
        return undefined();
    }

    if (operation == QStringLiteral("saveScheduledMessage")) {
        const QString identifier = string(first);
        const QString body = string(second).trimmed();
        Values files = values(fourth);
        Values mentions;
        for (const QJSValue &userId : values(sixth)) {
            if (body.contains(string(userId)))
                mentions.append(userId);
        }
        Values scheduled = values(root.property(QStringLiteral("scheduledMessages")));
        if (!identifier.isEmpty()) {
            for (int index = 0; index < scheduled.size(); ++index) {
                if (string(scheduled.at(index).property(QStringLiteral("id"))) != identifier)
                    continue;
                scheduled[index] = mergeObjects(engine, scheduled.at(index), {
                    {QStringLiteral("body"), QJSValue(body)},
                    {QStringLiteral("scheduled_at"), QJSValue(number(third))},
                    {QStringLiteral("attachments"), arrayFromValues(engine, files)},
                    {QStringLiteral("reply_event_id"), QJSValue(string(fifth))},
                    {QStringLiteral("mentioned_user_ids"), arrayFromValues(engine, mentions)},
                    {QStringLiteral("updated_at"), QJSValue(double(nowMs()))}
                });
                set(root, QStringLiteral("scheduledMessages"), arrayFromValues(engine, scheduled));
                feedback(root, translated(root,
                    QStringLiteral("Отложенное сообщение обновлено")), false);
                return undefined();
            }
            return undefined();
        }
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        const QString accountId = string(root.property(QStringLiteral("currentUserId")));
        if (roomId.isEmpty() || accountId.isEmpty())
            return undefined();
        const qint64 timestamp = nowMs();
        scheduled.append(objectFromProperties(engine, {
            {QStringLiteral("id"), callRoot(root, QStringLiteral("nextRequestId"),
                {QJSValue(QStringLiteral("scheduled"))})},
            {QStringLiteral("account_id"), QJSValue(accountId)},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("body"), QJSValue(body)},
            {QStringLiteral("attachments"), arrayFromValues(engine, files)},
            {QStringLiteral("reply_event_id"), QJSValue(string(fifth))},
            {QStringLiteral("mentioned_user_ids"), arrayFromValues(engine, mentions)},
            {QStringLiteral("scheduled_at"), QJSValue(number(third))},
            {QStringLiteral("created_at"), QJSValue(double(timestamp))},
            {QStringLiteral("updated_at"), QJSValue(double(timestamp))}
        }));
        set(root, QStringLiteral("scheduledMessages"), arrayFromValues(engine, scheduled));
        callRoot(root, QStringLiteral("stopTyping"));
        set(messageArea(root), QStringLiteral("text"), QJSValue(QString()));
        set(root, QStringLiteral("editingEventId"), QJSValue(QString()));
        set(root, QStringLiteral("microphoneMode"), QJSValue(false));
        callRoot(root, QStringLiteral("clearPendingAttachment"));
        set(root, QStringLiteral("mentionedUserIds"), array(engine));
        callRoot(root, QStringLiteral("cancelReply"));
        callRoot(root, QStringLiteral("removeDraft"), {QJSValue(roomId)});
        feedback(root, translated(root, QStringLiteral("Сообщение запланировано")), false);
        return undefined();
    }

    if (operation == QStringLiteral("cancelScheduledMessage")) {
        const QString identifier = string(first);
        if (identifier.isEmpty())
            return undefined();
        Values retained;
        bool removed = false;
        for (const QJSValue &item : values(root.property(QStringLiteral("scheduledMessages")))) {
            if (string(item.property(QStringLiteral("id"))) == identifier)
                removed = true;
            else
                retained.append(item);
        }
        if (!removed)
            return undefined();
        set(root, QStringLiteral("scheduledMessages"), arrayFromValues(engine, retained));
        feedback(root, translated(root, QStringLiteral("Отложенная отправка отменена")), false);
        return undefined();
    }

    if (operation == QStringLiteral("openScheduledMessages")) {
        if (string(root.property(QStringLiteral("currentRoomId"))).isEmpty())
            return undefined();
        const bool editing = boolean(root.property(QStringLiteral("editing")));
        call(root.property(QStringLiteral("scheduledMessagesPopupObject")),
             QStringLiteral("openForDraft"), {
                 QJSValue(editing ? QString() : string(messageArea(root).property(QStringLiteral("text"))).trimmed()),
                 editing ? array(engine) : root.property(QStringLiteral("pendingAttachments")),
                 QJSValue(editing ? QString() : string(root.property(QStringLiteral("replyingEventId")))),
                 editing ? array(engine) : root.property(QStringLiteral("mentionedUserIds"))
             });
        return undefined();
    }

    if (operation == QStringLiteral("formatVoiceDuration")) {
        const int totalSeconds = qMax(0, int(std::floor(number(first) / 1000.0)));
        const int minutes = totalSeconds / 60;
        const int seconds = totalSeconds % 60;
        return QJSValue(QString::number(minutes) + QLatin1Char(':')
                        + (seconds < 10 ? QStringLiteral("0") : QString())
                        + QString::number(seconds));
    }

    if (operation == QStringLiteral("startVoiceRecording")) {
        if (!boolean(root.property(QStringLiteral("microphoneVisible")))
            || boolean(root.property(QStringLiteral("voicePressActive")))
            || string(root.property(QStringLiteral("currentRoomId"))).isEmpty())
            return undefined();
        const QString tempRoot = string(root.property(QStringLiteral("temporaryDirectory")));
        if (tempRoot.isEmpty()) {
            feedback(root, translated(root,
                QStringLiteral("Не удалось найти папку для временной записи")), true);
            return undefined();
        }
        callRoot(root, QStringLiteral("closeEmojiPicker"));
        set(root, QStringLiteral("voiceDurationMs"), QJSValue(0));
        set(root, QStringLiteral("voiceStopPending"), QJSValue(false));
        set(root, QStringLiteral("voicePressActive"), QJSValue(true));
        const QString separator = tempRoot.endsWith(QLatin1Char('/')) ? QString() : QStringLiteral("/");
        const QJSValue loader = root.property(QStringLiteral("voiceRecorderLoaderObject"));
        set(loader, QStringLiteral("outputLocation"), QJSValue(tempRoot + separator
            + QStringLiteral("prismchat-voice-") + QString::number(nowMs())));
        set(loader, QStringLiteral("active"), QJSValue(true));
        return undefined();
    }

    if (operation == QStringLiteral("stopVoiceRecording")) {
        if (!boolean(root.property(QStringLiteral("voicePressActive"))))
            return undefined();
        set(root, QStringLiteral("voicePressActive"), QJSValue(false));
        const QJSValue item = root.property(QStringLiteral("voiceRecorderLoaderObject"))
            .property(QStringLiteral("item"));
        if (item.isObject() && boolean(item.property(QStringLiteral("recording")))) {
            set(root, QStringLiteral("voiceStopPending"), QJSValue(true));
            call(item, QStringLiteral("stop"));
        }
        return undefined();
    }

    if (operation == QStringLiteral("finishVoiceRecording")) {
        if (!boolean(root.property(QStringLiteral("voiceStopPending"))))
            return undefined();
        set(root, QStringLiteral("voiceStopPending"), QJSValue(false));
        const QJSValue loader = root.property(QStringLiteral("voiceRecorderLoaderObject"));
        const QJSValue item = loader.property(QStringLiteral("item"));
        const QString fileUrl = item.isObject()
            ? string(item.property(QStringLiteral("actualLocation"))) : QString();
        const int duration = root.property(QStringLiteral("voiceDurationMs")).toInt();
        if (fileUrl.isEmpty() || duration < 500) {
            set(root, QStringLiteral("microphoneMode"), QJSValue(false));
            set(loader, QStringLiteral("active"), QJSValue(false));
            return undefined();
        }
        callRoot(root, QStringLiteral("stageAttachment"), {
            QJSValue(fileUrl), QJSValue(localPath(fileUrl)),
            QJSValue(translated(root, QStringLiteral("Голосовое сообщение.wav"))),
            QJSValue(false), QJSValue(QStringLiteral("audio/wav")), QJSValue(duration)
        });
        set(root, QStringLiteral("microphoneMode"), QJSValue(false));
        set(loader, QStringLiteral("active"), QJSValue(false));
        return undefined();
    }

    if (operation == QStringLiteral("cancelVoiceRecording")) {
        set(root, QStringLiteral("voicePressActive"), QJSValue(false));
        set(root, QStringLiteral("voiceStopPending"), QJSValue(false));
        const QJSValue loader = root.property(QStringLiteral("voiceRecorderLoaderObject"));
        const QJSValue item = loader.property(QStringLiteral("item"));
        if (item.isObject())
            call(item, QStringLiteral("stop"));
        if (QObject *context = root.toQObject()) {
            QTimer::singleShot(0, context, [loader] {
                set(loader, QStringLiteral("active"), QJSValue(false));
            });
        }
        return undefined();
    }

    return error(engine, QStringLiteral("composer.") + operation);
}

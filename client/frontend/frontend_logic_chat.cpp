#include "frontend_logic.h"

#include "frontend_logic_support.h"

#include <QRegularExpression>
#include <QUrl>

using namespace FrontendLogicSupport;

namespace {

QString proxyUrl(const QString &mxc,
                 const QString &mediaProxy,
                 const QJSValue &mediaFile,
                 const QString &mimeType)
{
    if (mediaProxy.isEmpty() || !mxc.startsWith(QStringLiteral("mxc://")))
        return {};
    QString normalized = mxc;
    const qsizetype fragment = normalized.indexOf(QLatin1Char('#'));
    if (fragment >= 0)
        normalized.truncate(fragment);
    QString result = mediaProxy + QString::fromUtf8(QUrl::toPercentEncoding(normalized));
    const QString fileId = string(mediaFile.property(QStringLiteral("_prism_media_id")));
    if (!fileId.isEmpty())
        result += QStringLiteral("&file_id=") + QString::fromUtf8(QUrl::toPercentEncoding(fileId));
    if (!mimeType.isEmpty())
        result += QStringLiteral("&mime=") + QString::fromUtf8(QUrl::toPercentEncoding(mimeType));
    return result;
}

QJSValue nextRequestId(const QJSValue &root, const QString &suffix)
{
    return callRoot(root, QStringLiteral("nextRequestId"), {QJSValue(suffix)});
}

void emitCommand(const QJSValue &root, const QJSValue &command)
{
    callRoot(root, QStringLiteral("commandRequested"), {command});
}

QJSValue threadMessageKey(const QJSValue &message)
{
    if (!message.isObject())
        return QJSValue(QString());
    QString key = string(message.property(QStringLiteral("timeline_item_id")));
    if (key.isEmpty())
        key = string(message.property(QStringLiteral("event_id")));
    return QJSValue(key);
}

QJSValue stickerPackKey(const QJSValue &pack)
{
    QString key = string(pack.property(QStringLiteral("id")));
    if (key.isEmpty())
        key = string(pack.property(QStringLiteral("display_name")));
    if (key.isEmpty())
        key = string(pack.property(QStringLiteral("display_name_source")));
    return QJSValue(key);
}

void feedback(const QJSValue &root, const QString &message, bool isError)
{
    callRoot(root, QStringLiteral("feedbackRequested"),
             {QJSValue(message), QJSValue(isError)});
}

} // namespace

QJSValue FrontendLogic::invokeChat(const QString &operation,
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

    if (operation == QStringLiteral("threadMessageKey"))
        return threadMessageKey(first);

    if (operation == QStringLiteral("mergeThreadMessages")) {
        Values candidates = values(first);
        candidates.append(values(root.property(QStringLiteral("threadMessages"))));
        const QJSValue threadRoot = root.property(QStringLiteral("threadRootMessage"));
        if (threadRoot.isObject())
            candidates.append(threadRoot);
        const QString rootId = string(root.property(QStringLiteral("threadRootEventId")));
        QSet<QString> seen;
        Values merged;
        for (const QJSValue &message : std::as_const(candidates)) {
            if (!message.isObject())
                continue;
            const bool belongs = string(message.property(QStringLiteral("event_id"))) == rootId
                || string(message.property(QStringLiteral("thread_root_id"))) == rootId;
            if (!belongs)
                continue;
            const QString key = string(threadMessageKey(message));
            if (key.isEmpty() || seen.contains(key))
                continue;
            seen.insert(key);
            merged.append(message);
        }
        std::sort(merged.begin(), merged.end(), [](const QJSValue &left,
                                                   const QJSValue &right) {
            return number(left.property(QStringLiteral("timestamp")))
                > number(right.property(QStringLiteral("timestamp")));
        });
        set(root, QStringLiteral("threadMessages"), arrayFromValues(engine, merged));
        return undefined();
    }

    if (operation == QStringLiteral("requestThreadMessages")) {
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (!boolean(root.property(QStringLiteral("threadsAvailable")))
            || !boolean(root.property(QStringLiteral("threadDetailOpen")))
            || roomId.isEmpty())
            return undefined();
        set(root, QStringLiteral("threadLoading"), QJSValue(true));
        set(root, QStringLiteral("threadError"), QJSValue(QString()));
        const QJSValue requestId = nextRequestId(root, QStringLiteral("thread"));
        set(root, QStringLiteral("threadRequestId"), requestId);
        emitCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_thread_messages"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("root_event_id"), root.property(QStringLiteral("threadRootEventId"))},
            {QStringLiteral("limit"), root.property(QStringLiteral("threadMessageLimit"))}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("openThread")) {
        if (!boolean(root.property(QStringLiteral("threadsAvailable"))) || !first.isObject())
            return undefined();
        QString rootId = string(first.property(QStringLiteral("thread_root_id")));
        if (rootId.isEmpty())
            rootId = string(first.property(QStringLiteral("event_id")));
        if (rootId.isEmpty() || rootId.startsWith(QStringLiteral("local:")))
            return undefined();
        set(root, QStringLiteral("threadsPanelVisible"), QJSValue(true));
        set(root, QStringLiteral("threadRootEventId"), QJSValue(rootId));
        QJSValue rootMessage = cloneObject(engine, first);
        rootMessage.setProperty(QStringLiteral("thread_root_id"), QJSValue(QString()));
        set(root, QStringLiteral("threadRootMessage"), rootMessage);
        set(root, QStringLiteral("threadMessages"), array(engine));
        set(root, QStringLiteral("threadMessageLimit"), QJSValue(50));
        set(root, QStringLiteral("threadHasMore"), QJSValue(false));
        set(root, QStringLiteral("threadError"), QJSValue(QString()));
        set(root, QStringLiteral("membersPanelCollapsed"), QJSValue(true));
        callRoot(root, QStringLiteral("mergeThreadMessages"), {array(engine)});
        callRoot(root, QStringLiteral("requestThreadMessages"));
        return undefined();
    }

    if (operation == QStringLiteral("openThreadsPanel")) {
        if (!boolean(root.property(QStringLiteral("threadsAvailable"))))
            return undefined();
        set(root, QStringLiteral("threadsPanelVisible"), QJSValue(true));
        set(root, QStringLiteral("threadRootEventId"), QJSValue(QString()));
        set(root, QStringLiteral("threadRootMessage"), nullValue());
        set(root, QStringLiteral("threadMessages"), array(engine));
        set(root, QStringLiteral("membersPanelCollapsed"), QJSValue(true));
        callRoot(root, QStringLiteral("requestRoomThreads"), {QJSValue(false)});
        return undefined();
    }

    if (operation == QStringLiteral("backToThreadList")) {
        if (!boolean(root.property(QStringLiteral("threadsAvailable"))))
            return undefined();
        set(root, QStringLiteral("threadRootEventId"), QJSValue(QString()));
        set(root, QStringLiteral("threadRootMessage"), nullValue());
        set(root, QStringLiteral("threadMessages"), array(engine));
        set(root, QStringLiteral("threadLoading"), QJSValue(false));
        set(root, QStringLiteral("threadError"), QJSValue(QString()));
        callRoot(root, QStringLiteral("requestRoomThreads"), {QJSValue(false)});
        return undefined();
    }

    if (operation == QStringLiteral("closeThread")) {
        set(root, QStringLiteral("threadsPanelVisible"), QJSValue(false));
        set(root, QStringLiteral("threadRootEventId"), QJSValue(QString()));
        set(root, QStringLiteral("threadRootMessage"), nullValue());
        set(root, QStringLiteral("threadMessages"), array(engine));
        set(root, QStringLiteral("threadLoading"), QJSValue(false));
        set(root, QStringLiteral("threadHasMore"), QJSValue(false));
        set(root, QStringLiteral("threadError"), QJSValue(QString()));
        set(root, QStringLiteral("threadRequestId"), QJSValue(QString()));
        return undefined();
    }

    if (operation == QStringLiteral("requestRoomThreads")) {
        const bool append = boolean(first);
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (!boolean(root.property(QStringLiteral("threadsAvailable"))) || roomId.isEmpty()
            || boolean(root.property(QStringLiteral("roomThreadsLoading")))
            || boolean(root.property(QStringLiteral("markingThreadsRead"))))
            return undefined();
        set(root, QStringLiteral("roomThreadsLoading"), QJSValue(true));
        set(root, QStringLiteral("roomThreadsAppendPending"), QJSValue(append));
        set(root, QStringLiteral("roomThreadsError"), QJSValue(QString()));
        const QJSValue requestId = nextRequestId(root, QStringLiteral("room-threads"));
        set(root, QStringLiteral("roomThreadsRequestId"), requestId);
        emitCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_room_threads"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("from"), append
                ? root.property(QStringLiteral("roomThreadsNextFrom")) : QJSValue(QString())},
            {QStringLiteral("limit"), QJSValue(20)}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("receiveRoomThreads")) {
        const QString roomId = string(first);
        if (roomId != string(root.property(QStringLiteral("currentRoomId")))
            || boolean(root.property(QStringLiteral("markingThreadsRead")))
            || string(sixth) != string(root.property(QStringLiteral("roomThreadsRequestId"))))
            return undefined();
        const bool append = boolean(root.property(QStringLiteral("roomThreadsAppendPending")));
        set(root, QStringLiteral("roomThreadsLoading"), QJSValue(false));
        set(root, QStringLiteral("roomThreadsAppendPending"), QJSValue(false));
        const QString roomThreadsError = string(fifth).isEmpty()
            ? QString()
            : localizedError(root, string(fifth), QStringLiteral("Не удалось выполнить действие"));
        set(root, QStringLiteral("roomThreadsError"), QJSValue(roomThreadsError));
        if (!roomThreadsError.isEmpty())
            return undefined();
        Values threads = append ? values(root.property(QStringLiteral("roomThreads"))) : Values();
        threads.append(values(second));
        set(root, QStringLiteral("roomThreads"), arrayFromValues(engine, threads));
        set(root, QStringLiteral("roomThreadsNextFrom"), QJSValue(string(third)));
        const int unread = qRound(number(fourth));
        set(root, QStringLiteral("threadUnreadCount"), QJSValue(append
            ? root.property(QStringLiteral("threadUnreadCount")).toInt() + unread : unread));
        return undefined();
    }

    if (operation == QStringLiteral("markActiveThreadRead")) {
        const QJSValue messages = root.property(QStringLiteral("threadMessages"));
        if (!boolean(root.property(QStringLiteral("threadsAvailable")))
            || !boolean(root.property(QStringLiteral("threadDetailOpen")))
            || length(messages) == 0)
            return undefined();
        const QString eventId = string(messages.property(0).property(QStringLiteral("event_id")));
        if (eventId.isEmpty() || eventId.startsWith(QStringLiteral("local:")))
            return undefined();
        emitCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("mark_thread_read"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("thread-read"))},
            {QStringLiteral("room_id"), root.property(QStringLiteral("currentRoomId"))},
            {QStringLiteral("root_event_id"), root.property(QStringLiteral("threadRootEventId"))},
            {QStringLiteral("event_id"), QJSValue(eventId)},
            {QStringLiteral("public_receipt"), root.property(QStringLiteral("publicReadReceipts"))}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("receiveThreadRead")) {
        if (!boolean(third)
            || string(first) != string(root.property(QStringLiteral("currentRoomId")))
            || string(second) != string(root.property(QStringLiteral("threadRootEventId"))))
            return undefined();
        Values threads = values(root.property(QStringLiteral("roomThreads")));
        bool wasUnread = false;
        for (int index = 0; index < threads.size(); ++index) {
            const QJSValue summary = threads.at(index);
            if (string(summary.property(QStringLiteral("root")).property(QStringLiteral("event_id")))
                != string(second))
                continue;
            wasUnread = boolean(summary.property(QStringLiteral("unread")));
            threads[index] = mergeObjects(engine, summary,
                {{QStringLiteral("unread"), QJSValue(false)}});
        }
        set(root, QStringLiteral("roomThreads"), arrayFromValues(engine, threads));
        if (wasUnread)
            set(root, QStringLiteral("threadUnreadCount"),
                QJSValue(qMax(0, root.property(QStringLiteral("threadUnreadCount")).toInt() - 1)));
        return undefined();
    }

    if (operation == QStringLiteral("receiveThreadMessages")) {
        if (string(first) != string(root.property(QStringLiteral("currentRoomId")))
            || string(second) != string(root.property(QStringLiteral("threadRootEventId")))
            || (!string(root.property(QStringLiteral("threadRequestId"))).isEmpty()
                && string(sixth) != string(root.property(QStringLiteral("threadRequestId")))))
            return undefined();
        set(root, QStringLiteral("threadLoading"), QJSValue(false));
        set(root, QStringLiteral("threadHasMore"), QJSValue(boolean(fourth)));
        const QString threadError = string(fifth).isEmpty()
            ? QString()
            : localizedError(root, string(fifth), QStringLiteral("Не удалось выполнить действие"));
        set(root, QStringLiteral("threadError"), QJSValue(threadError));
        if (threadError.isEmpty()) {
            callRoot(root, QStringLiteral("mergeThreadMessages"), {third});
            callRoot(root, QStringLiteral("markActiveThreadRead"));
        }
        return undefined();
    }

    if (operation == QStringLiteral("receiveLiveTimelineMessages")) {
        if (!boolean(root.property(QStringLiteral("threadsAvailable")))
            || string(first) != string(root.property(QStringLiteral("currentRoomId"))))
            return undefined();
        bool hasThreadUpdate = false;
        for (const QJSValue &message : values(second)) {
            if (!string(message.property(QStringLiteral("thread_root_id"))).isEmpty()
                || number(message.property(QStringLiteral("thread_reply_count"))) > 0) {
                hasThreadUpdate = true;
                break;
            }
        }
        if (hasThreadUpdate)
            call(root.property(QStringLiteral("threadDirectoryRefreshTimerObject")),
                 QStringLiteral("restart"));
        if (boolean(root.property(QStringLiteral("threadDetailOpen"))))
            callRoot(root, QStringLiteral("mergeThreadMessages"), {second});
        return undefined();
    }

    if (operation == QStringLiteral("receiveThreadMutation")) {
        if (!boolean(root.property(QStringLiteral("threadsAvailable")))
            || !boolean(root.property(QStringLiteral("threadDetailOpen")))
            || string(first) != string(root.property(QStringLiteral("currentRoomId")))
            || string(second) != string(root.property(QStringLiteral("threadRootEventId"))))
            return undefined();
        callRoot(root, QStringLiteral("requestThreadMessages"));
        call(root.property(QStringLiteral("threadDirectoryRefreshTimerObject")),
             QStringLiteral("restart"));
        return undefined();
    }

    if (operation == QStringLiteral("markAllThreadsRead")) {
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (!boolean(root.property(QStringLiteral("threadsAvailable"))) || roomId.isEmpty()
            || boolean(root.property(QStringLiteral("markingThreadsRead"))))
            return undefined();
        const QJSValue requestId = nextRequestId(root, QStringLiteral("all-threads-read"));
        QJSValue pending = cloneObject(engine,
            root.property(QStringLiteral("threadReadAllRequests")));
        pending.setProperty(roomId, requestId);
        set(root, QStringLiteral("threadReadAllRequests"), pending);
        set(root, QStringLiteral("roomThreadsRequestId"), QJSValue(QString()));
        set(root, QStringLiteral("roomThreadsLoading"), QJSValue(false));
        call(root.property(QStringLiteral("threadDirectoryRefreshTimerObject")),
             QStringLiteral("stop"));
        emitCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("mark_room_threads_read"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("public_receipt"), root.property(QStringLiteral("publicReadReceipts"))}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("receiveAllThreadsRead")) {
        const QString roomId = string(first);
        const QString requestId = string(fifth);
        const QJSValue requests = root.property(QStringLiteral("threadReadAllRequests"));
        if (requestId.isEmpty() || string(requests.property(roomId)) != requestId)
            return undefined();
        QJSValue pending = cloneObject(engine, requests);
        pending.deleteProperty(roomId);
        set(root, QStringLiteral("threadReadAllRequests"), pending);
        if (!boolean(second))
            feedback(root, localizedError(root, string(fourth),
                QStringLiteral("Не удалось выполнить действие")), true);
        if (roomId != string(root.property(QStringLiteral("currentRoomId"))))
            return undefined();
        const QJSValue confirmed = third.isObject() ? third : object(engine);
        Values updated;
        int unreadCount = 0;
        for (const QJSValue &summary : values(root.property(QStringLiteral("roomThreads")))) {
            const QString eventId = string(summary.property(QStringLiteral("root"))
                                               .property(QStringLiteral("event_id")));
            QJSValue next = summary;
            if (boolean(confirmed.property(eventId)))
                next = mergeObjects(engine, summary,
                    {{QStringLiteral("unread"), QJSValue(false)}});
            unreadCount += boolean(next.property(QStringLiteral("unread"))) ? 1 : 0;
            updated.append(next);
        }
        set(root, QStringLiteral("roomThreads"), arrayFromValues(engine, updated));
        set(root, QStringLiteral("threadUnreadCount"), QJSValue(unreadCount));
        callRoot(root, QStringLiteral("requestRoomThreads"), {QJSValue(false)});
        return undefined();
    }

    if (operation == QStringLiteral("userDetailsCacheKey"))
        return QJSValue(string(second) + QLatin1Char('|') + string(first));

    if (operation == QStringLiteral("cachedOrPreviewUserDetails")) {
        const QString userId = string(first);
        const QString roomId = string(second);
        const QString key = string(callRoot(root, QStringLiteral("userDetailsCacheKey"),
                                            {QJSValue(userId), QJSValue(roomId)}));
        const QJSValue cache = root.property(QStringLiteral("userDetailsCache"));
        if (!cache.property(key).isUndefined())
            return cache.property(key);
        QString avatar = userId == string(root.property(QStringLiteral("currentUserId")))
            ? string(root.property(QStringLiteral("currentUserAvatar"))) : QString();
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (avatar.isEmpty() && model.isObject()) {
            for (int index = 0; index < modelCount(model); ++index) {
                const QJSValue message = modelGet(model, index);
                if (string(message.property(QStringLiteral("sender"))) == userId
                    && !string(message.property(QStringLiteral("sender_avatar_url"))).isEmpty()) {
                    avatar = string(message.property(QStringLiteral("sender_avatar_url")));
                    break;
                }
            }
        }
        return objectFromProperties(engine, {
            {QStringLiteral("user_id"), QJSValue(userId)},
            {QStringLiteral("display_name"), callRoot(root, QStringLiteral("authorDisplayName"),
                {QJSValue(userId), QJSValue(QString())})},
            {QStringLiteral("avatar_url"), QJSValue(avatar)},
            {QStringLiteral("can_send_dm"), QJSValue(userId
                != string(root.property(QStringLiteral("currentUserId"))))},
            {QStringLiteral("is_self"), QJSValue(userId
                == string(root.property(QStringLiteral("currentUserId"))))},
            {QStringLiteral("is_ignored"), QJSValue(false)},
            {QStringLiteral("is_admin"), QJSValue(false)},
            {QStringLiteral("is_moderator"), QJSValue(false)},
            {QStringLiteral("room_member"), nullValue()}
        });
    }

    if (operation == QStringLiteral("receiveUserDetails")) {
        if (string(second) != string(root.property(QStringLiteral("pendingMiniProfileRequestId"))))
            return undefined();
        set(root, QStringLiteral("pendingMiniProfileRequestId"), QJSValue(QString()));
        if (!string(third).isEmpty() || !first.isObject()) {
            feedback(root, localizedError(root, string(third),
                QStringLiteral("Не удалось загрузить профиль")), true);
            return undefined();
        }
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("userDetailsCache")));
        cache.setProperty(string(root.property(QStringLiteral("pendingMiniProfileCacheKey"))), first);
        QStringList keys = objectKeys(cache);
        while (keys.size() > root.property(QStringLiteral("maxUserDetailsCacheEntries")).toInt())
            cache.deleteProperty(keys.takeFirst());
        set(root, QStringLiteral("userDetailsCache"), cache);
        const QJSValue profile = root.property(QStringLiteral("miniProfile"));
        if (profile.isObject())
            set(profile, QStringLiteral("details"), first);
        return undefined();
    }

    if (operation == QStringLiteral("receiveUserIgnoreResult")) {
        const QString userId = string(first);
        const bool ignored = boolean(second);
        const bool success = boolean(third);
        if (string(fifth) == string(root.property(QStringLiteral("pendingMiniProfileIgnoreRequestId")))) {
            set(root, QStringLiteral("pendingMiniProfileIgnoreRequestId"), QJSValue(QString()));
            const QJSValue profile = root.property(QStringLiteral("miniProfile"));
            if (profile.isObject())
                set(profile, QStringLiteral("ignoreBusy"), QJSValue(false));
            if (!success)
                feedback(root, localizedError(root, string(fourth),
                    QStringLiteral("Не удалось выполнить действие")), true);
        }
        if (!success)
            return undefined();
        QJSValue updatedCache = object(engine);
        const QJSValue currentCache = root.property(QStringLiteral("userDetailsCache"));
        QJSValueIterator iterator(currentCache);
        while (iterator.hasNext()) {
            iterator.next();
            QJSValue details = iterator.value();
            if (details.isObject()
                && string(details.property(QStringLiteral("user_id"))) == userId) {
                QJSValue member = details.property(QStringLiteral("room_member"));
                if (member.isObject())
                    member = mergeObjects(engine, member,
                        {{QStringLiteral("is_ignored"), QJSValue(ignored)}});
                else
                    member = nullValue();
                details = mergeObjects(engine, details, {
                    {QStringLiteral("is_ignored"), QJSValue(ignored)},
                    {QStringLiteral("room_member"), member}
                });
            }
            updatedCache.setProperty(iterator.name(), details);
        }
        set(root, QStringLiteral("userDetailsCache"), updatedCache);
        Values pinned;
        for (const QJSValue &message : values(root.property(QStringLiteral("pinnedMessages")))) {
            pinned.append(string(message.property(QStringLiteral("sender"))) == userId
                ? mergeObjects(engine, message,
                    {{QStringLiteral("sender_is_ignored"), QJSValue(ignored)}})
                : message);
        }
        set(root, QStringLiteral("pinnedMessages"), arrayFromValues(engine, pinned));
        if (ignored) {
            Values searchResults;
            for (const QJSValue &message : values(root.property(QStringLiteral("searchResults")))) {
                if (string(message.property(QStringLiteral("sender"))) != userId)
                    searchResults.append(message);
            }
            set(root, QStringLiteral("searchResults"), arrayFromValues(engine, searchResults));
        }
        const QJSValue attachments = root.property(QStringLiteral("attachmentsPanel"));
        if (attachments.isObject())
            call(attachments, QStringLiteral("setSenderIgnored"),
                 {QJSValue(userId), QJSValue(ignored)});
        const QJSValue profile = root.property(QStringLiteral("miniProfile"));
        const QJSValue details = profile.property(QStringLiteral("details"));
        if (profile.isObject() && details.isObject()
            && string(details.property(QStringLiteral("user_id"))) == userId) {
            QJSValue member = details.property(QStringLiteral("room_member"));
            if (member.isObject())
                member = mergeObjects(engine, member,
                    {{QStringLiteral("is_ignored"), QJSValue(ignored)}});
            else
                member = nullValue();
            set(profile, QStringLiteral("details"), mergeObjects(engine, details, {
                {QStringLiteral("is_ignored"), QJSValue(ignored)},
                {QStringLiteral("room_member"), member}
            }));
        }
        return undefined();
    }

    if (operation == QStringLiteral("receiveModerationResult")) {
        if (string(sixth) != string(root.property(QStringLiteral("pendingMiniProfileModerationRequestId"))))
            return undefined();
        set(root, QStringLiteral("pendingMiniProfileModerationRequestId"), QJSValue(QString()));
        const QJSValue profile = root.property(QStringLiteral("miniProfile"));
        if (profile.isObject())
            set(profile, QStringLiteral("moderationBusy"), QJSValue(false));
        if (!boolean(fourth)) {
            feedback(root, localizedError(root, string(fifth),
                QStringLiteral("Не удалось выполнить действие модерации")), true);
            return undefined();
        }
        const QString userId = string(second);
        const QString roomId = string(first);
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("userDetailsCache")));
        const QString key = string(callRoot(root, QStringLiteral("userDetailsCacheKey"),
                                            {QJSValue(userId), QJSValue(roomId)}));
        cache.deleteProperty(key);
        set(root, QStringLiteral("userDetailsCache"), cache);
        feedback(root, translated(root, QStringLiteral("Действие модерации выполнено")), false);
        const QString action = string(third);
        if (action == QStringLiteral("kick") || action == QStringLiteral("ban")
            || action == QStringLiteral("unban")) {
            if (profile.isObject())
                call(profile, QStringLiteral("close"));
            return undefined();
        }
        QJSValue refreshId;
        const QJSValue factory = root.property(QStringLiteral("requestIdFactory"));
        if (factory.isCallable())
            refreshId = factory.call({QJSValue(QStringLiteral("miniprofile-moderation-refresh"))});
        else
            refreshId = QJSValue(QString::number(nowMs())
                + QStringLiteral("-miniprofile-moderation-refresh"));
        set(root, QStringLiteral("pendingMiniProfileRequestId"), refreshId);
        set(root, QStringLiteral("pendingMiniProfileCacheKey"), QJSValue(key));
        emitCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_user_details"))},
            {QStringLiteral("request_id"), refreshId},
            {QStringLiteral("user_id"), QJSValue(userId)},
            {QStringLiteral("room_id"), QJSValue(roomId)}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("receiveSearchResults")) {
        if (string(fourth) != string(root.property(QStringLiteral("activeSearchRequestId"))))
            return undefined();
        set(root, QStringLiteral("activeSearchRequestId"), QJSValue(QString()));
        set(root, QStringLiteral("searchLoading"), QJSValue(false));
        Values results = boolean(root.property(QStringLiteral("searchAppendPending")))
            ? values(root.property(QStringLiteral("searchResults"))) : Values();
        results.append(values(first));
        set(root, QStringLiteral("searchResults"), arrayFromValues(engine, results));
        set(root, QStringLiteral("searchAppendPending"), QJSValue(false));
        set(root, QStringLiteral("searchNextBatch"), QJSValue(string(second)));
        set(root, QStringLiteral("searchError"), QJSValue(string(third).isEmpty()
            ? QString()
            : localizedError(root, string(third), QStringLiteral("Не удалось выполнить действие"))));
        return undefined();
    }

    if (operation == QStringLiteral("requestAttachments")) {
        QJSValue command = objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_room_attachments"))},
            {QStringLiteral("request_id"), third},
            {QStringLiteral("room_id"), first},
            {QStringLiteral("limit"), fifth},
            {QStringLiteral("category"), fourth}
        });
        if (!string(second).isEmpty())
            command.setProperty(QStringLiteral("from"), second);
        emitCommand(root, command);
        return undefined();
    }

    if (operation == QStringLiteral("receiveAttachments")) {
        const QJSValue panel = root.property(QStringLiteral("attachmentsPanel"));
        if (panel.isObject())
            call(panel, QStringLiteral("receivePage"),
                 {first, second.isObject() ? second : array(engine), QJSValue(string(third)),
                  QJSValue(string(fourth).isEmpty() ? QString()
                      : localizedError(root, string(fourth), QStringLiteral("Не удалось загрузить вложения"))),
                  fifth});
        return undefined();
    }

    if (operation == QStringLiteral("openAttachmentsPanel")) {
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (roomId.isEmpty())
            return undefined();
        const QJSValue loader = root.property(QStringLiteral("attachmentsPanelLoaderObject"));
        set(loader, QStringLiteral("targetRoomId"), QJSValue(roomId));
        const QJSValue item = loader.property(QStringLiteral("item"));
        if (item.isObject()) {
            call(item, QStringLiteral("openForRoom"), {QJSValue(roomId)});
            call(root.property(QStringLiteral("attachmentCacheTimerObject")),
                 QStringLiteral("restart"));
        } else {
            set(loader, QStringLiteral("active"), QJSValue(true));
        }
        return undefined();
    }

    if (operation == QStringLiteral("openSearchResult")) {
        const QString eventId = first.isObject()
            ? string(first.property(QStringLiteral("event_id"))) : QString();
        if (eventId.isEmpty())
            return undefined();
        call(root.property(QStringLiteral("headerObject")), QStringLiteral("closeSearch"));
        if (boolean(call(root.property(QStringLiteral("messageListObject")),
                         QStringLiteral("scrollToEvent"), {QJSValue(eventId)})))
            return undefined();
        set(root, QStringLiteral("pendingSearchEventId"), QJSValue(eventId));
        callRoot(root, QStringLiteral("messageContextRequested"),
                 {root.property(QStringLiteral("currentRoomId")), QJSValue(eventId)});
        return undefined();
    }

    if (operation == QStringLiteral("openMessageEvent")) {
        const QString eventId = string(first);
        if (eventId.isEmpty())
            return undefined();
        if (boolean(call(root.property(QStringLiteral("messageListObject")),
                         QStringLiteral("scrollToEvent"), {QJSValue(eventId)})))
            return undefined();
        set(root, QStringLiteral("pendingSearchEventId"), QJSValue(eventId));
        callRoot(root, QStringLiteral("messageContextRequested"),
                 {root.property(QStringLiteral("currentRoomId")), QJSValue(eventId)});
        return undefined();
    }

    if (operation == QStringLiteral("requestExternalSearchContext")) {
        const QString roomId = string(first);
        const QString eventId = string(second);
        if (roomId.isEmpty() || eventId.isEmpty()
            || string(root.property(QStringLiteral("currentRoomId"))) != roomId)
            return undefined();
        set(root, QStringLiteral("pendingSearchEventId"), QJSValue(eventId));
        callRoot(root, QStringLiteral("messageContextRequested"),
                 {QJSValue(roomId), QJSValue(eventId)});
        return undefined();
    }

    if (operation == QStringLiteral("openExternalSearchResult")) {
        const QString roomId = string(first);
        const QString eventId = string(second);
        if (roomId.isEmpty() || eventId.isEmpty())
            return undefined();
        set(root, QStringLiteral("pendingExternalSearchRoomId"), QJSValue(roomId));
        set(root, QStringLiteral("pendingExternalSearchEventId"), QJSValue(eventId));
        if (string(root.property(QStringLiteral("currentRoomId"))) == roomId) {
            set(root, QStringLiteral("pendingExternalSearchRoomId"), QJSValue(QString()));
            set(root, QStringLiteral("pendingExternalSearchEventId"), QJSValue(QString()));
            callLater(root, QStringLiteral("requestExternalSearchContext"),
                      {QJSValue(roomId), QJSValue(eventId)});
        }
        return undefined();
    }

    if (operation == QStringLiteral("receiveMessageContext")) {
        const QString roomId = string(first);
        const QString eventId = string(second);
        if (roomId != string(root.property(QStringLiteral("currentRoomId")))
            || eventId != string(root.property(QStringLiteral("pendingSearchEventId"))))
            return undefined();
        set(root, QStringLiteral("pendingSearchEventId"), QJSValue(QString()));
        if (!boolean(third)) {
            feedback(root, translated(root,
                QStringLiteral("Сообщение не найдено или не удалось расшифровать")), true);
            return undefined();
        }
        if (QObject *context = root.toQObject()) {
            QTimer::singleShot(0, context, [root, eventId] {
                if (!boolean(call(root.property(QStringLiteral("messageListObject")),
                                  QStringLiteral("scrollToEvent"), {QJSValue(eventId)}))) {
                    feedback(root, translated(root,
                        QStringLiteral("Не удалось перейти к сообщению")), true);
                }
            });
        }
        return undefined();
    }

    if (operation == QStringLiteral("performSearch")) {
        const QString query = string(first).trimmed();
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (query.isEmpty() || roomId.isEmpty())
            return undefined();
        set(root, QStringLiteral("activeSearchQuery"), QJSValue(query));
        set(root, QStringLiteral("searchLoading"), QJSValue(true));
        set(root, QStringLiteral("searchAppendPending"), QJSValue(false));
        set(root, QStringLiteral("searchError"), QJSValue(QString()));
        const QJSValue requestId = nextRequestId(root, QStringLiteral("search"));
        set(root, QStringLiteral("activeSearchRequestId"), requestId);
        callRoot(root, QStringLiteral("searchRequested"),
                 {QJSValue(roomId), QJSValue(query), QJSValue(QString()), requestId});
        return undefined();
    }

    if (operation == QStringLiteral("focusMessageSearch")) {
        if (!string(root.property(QStringLiteral("currentRoomId"))).isEmpty())
            call(root.property(QStringLiteral("headerObject")),
                 QStringLiteral("focusMessageSearch"));
        return undefined();
    }

    if (operation == QStringLiteral("harvestTemporaryStickerData")) {
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (!model.isObject())
            return undefined();
        Values stickers;
        QSet<QString> stickerSeen;
        Values packs;
        QSet<QString> packSeen;
        for (int index = modelCount(model) - 1; index >= 0; --index) {
            const QJSValue message = modelGet(model, index);
            if (!message.isObject())
                continue;
            if (string(message.property(QStringLiteral("msg_type"))) == QStringLiteral("m.sticker")) {
                const QString mediaUrl = string(message.property(QStringLiteral("media_url")));
                if (!mediaUrl.isEmpty() && !stickerSeen.contains(mediaUrl)) {
                    stickerSeen.insert(mediaUrl);
                    QString body = string(message.property(QStringLiteral("body")));
                    if (body.isEmpty())
                        body = translated(root, QStringLiteral("Стикер"));
                    QString mime = string(message.property(QStringLiteral("media_mime_type")));
                    if (mime.isEmpty())
                        mime = QStringLiteral("image/webp");
                    const QJSValue mediaFile = message.property(QStringLiteral("media_file"));
                    QJSValue sticker = objectFromProperties(engine, {
                        {QStringLiteral("body"), QJSValue(body)},
                        {QStringLiteral("media_url"), QJSValue(mediaUrl)},
                        {QStringLiteral("media_mime_type"), QJSValue(mime)},
                        {QStringLiteral("preview_url"), QJSValue(proxyUrl(mediaUrl,
                            string(root.property(QStringLiteral("mediaProxy"))), mediaFile, mime))}
                    });
                    if (!mediaFile.isUndefined())
                        sticker.setProperty(QStringLiteral("media_file"), mediaFile);
                    stickers.append(sticker);
                }
            }
            const QJSValue pack = message.property(QStringLiteral("sticker_pack"));
            const QString key = string(stickerPackKey(pack));
            if (pack.isObject() && length(pack.property(QStringLiteral("images"))) > 0
                && !key.isEmpty() && !packSeen.contains(key)) {
                packSeen.insert(key);
                packs.append(pack);
            }
        }
        for (const QJSValue &sticker : values(root.property(QStringLiteral("temporaryStickerLibrary")))) {
            const QString url = string(sticker.property(QStringLiteral("media_url")));
            if (!url.isEmpty() && !stickerSeen.contains(url)) {
                stickerSeen.insert(url);
                stickers.append(sticker);
            }
        }
        for (const QJSValue &pack : values(root.property(QStringLiteral("temporarySharedStickerPacks")))) {
            const QString key = string(stickerPackKey(pack));
            if (!key.isEmpty() && !packSeen.contains(key)) {
                packSeen.insert(key);
                packs.append(pack);
            }
        }
        stickers = stickers.mid(0, 160);
        packs = packs.mid(0, 60);
        set(root, QStringLiteral("temporaryStickerLibrary"), arrayFromValues(engine, stickers));
        set(root, QStringLiteral("temporarySharedStickerPacks"), arrayFromValues(engine, packs));
        return undefined();
    }

    if (operation == QStringLiteral("collectStickerLibrary")
        || operation == QStringLiteral("collectSharedStickerPacks")) {
        callRoot(root, QStringLiteral("harvestTemporaryStickerData"));
        const QString property = operation == QStringLiteral("collectStickerLibrary")
            ? QStringLiteral("temporaryStickerLibrary")
            : QStringLiteral("temporarySharedStickerPacks");
        return cloneArray(engine, root.property(property));
    }

    if (operation == QStringLiteral("collectKnownStickerPacks")) {
        Values sources;
        const QJSValue catalog = root.property(QStringLiteral("stickerCatalogService"));
        const QJSValue store = root.property(QStringLiteral("stickerPackStoreService"));
        sources.append(catalog.property(QStringLiteral("builtinPacks")));
        sources.append(call(store, QStringLiteral("packsFor"),
                            {root.property(QStringLiteral("currentUserId"))}));
        sources.append(callRoot(root, QStringLiteral("collectSharedStickerPacks")));
        QSet<QString> seen;
        Values result;
        for (const QJSValue &source : std::as_const(sources)) {
            for (const QJSValue &pack : values(source)) {
                const QString key = string(stickerPackKey(pack));
                if (!key.isEmpty() && !seen.contains(key)) {
                    seen.insert(key);
                    result.append(pack);
                }
            }
        }
        return arrayFromValues(engine, result);
    }

    if (operation == QStringLiteral("resolveStickerPack")) {
        if (!first.isObject())
            return nullValue();
        const QJSValue builtin = call(root.property(QStringLiteral("stickerCatalogService")),
                                      QStringLiteral("packForBody"),
                                      {first.property(QStringLiteral("body"))});
        if (builtin.isObject())
            return builtin;
        const QString mediaUrl = string(first.property(QStringLiteral("media_url")));
        if (mediaUrl.isEmpty())
            return nullValue();
        for (const QJSValue &pack : values(callRoot(root,
                 QStringLiteral("collectKnownStickerPacks")))) {
            for (const QJSValue &image : values(pack.property(QStringLiteral("images")))) {
                if (string(image.property(QStringLiteral("media_url"))) == mediaUrl)
                    return pack;
            }
        }
        return nullValue();
    }

    if (operation == QStringLiteral("saveStickerToOwn")) {
        if (!first.isObject()
            || string(first.property(QStringLiteral("media_url"))).isEmpty()) {
            feedback(root, translated(root, QStringLiteral("Не удалось добавить стикер")), true);
            return undefined();
        }
        QString body = string(first.property(QStringLiteral("body")));
        if (body.isEmpty())
            body = translated(root, QStringLiteral("Стикер"));
        QString shortcode = string(first.property(QStringLiteral("shortcode")));
        if (shortcode.isEmpty())
            shortcode = QStringLiteral("saved_sticker");
        QString mime = string(first.property(QStringLiteral("media_mime_type")));
        if (mime.isEmpty())
            mime = QStringLiteral("image/webp");
        static const QRegularExpression animatedPattern(
            QStringLiteral("(?:gif|webp|apng)"), QRegularExpression::CaseInsensitiveOption);
        QJSValue item = objectFromProperties(engine, {
            {QStringLiteral("body"), QJSValue(body)},
            {QStringLiteral("shortcode"), QJSValue(shortcode)},
            {QStringLiteral("media_url"), first.property(QStringLiteral("media_url"))},
            {QStringLiteral("media_mime_type"), QJSValue(mime)},
            {QStringLiteral("animated"), QJSValue(
                boolean(first.property(QStringLiteral("animated")))
                || animatedPattern.match(mime).hasMatch())}
        });
        if (!first.property(QStringLiteral("media_file")).isUndefined())
            item.setProperty(QStringLiteral("media_file"),
                             first.property(QStringLiteral("media_file")));
        const QJSValue store = root.property(QStringLiteral("stickerPackStoreService"));
        if (boolean(call(store, QStringLiteral("saveSticker"), {
                root.property(QStringLiteral("currentUserId")), item,
                QJSValue(translated(root, QStringLiteral("Сохранённые стикеры")))}))) {
            call(store, QStringLiteral("flush"));
            call(root.property(QStringLiteral("composerObject")),
                 QStringLiteral("refreshStickerPicker"));
            feedback(root, translated(root, QStringLiteral("Стикер добавлен в мои стикеры")), false);
        } else {
            feedback(root, translated(root, QStringLiteral("Не удалось добавить стикер")), true);
        }
        return undefined();
    }

    if (operation == QStringLiteral("installStickerPack")) {
        if (!first.isObject())
            return undefined();
        const QJSValue store = root.property(QStringLiteral("stickerPackStoreService"));
        if (boolean(call(store, QStringLiteral("installPack"),
                         {root.property(QStringLiteral("currentUserId")), first}))) {
            call(store, QStringLiteral("flush"));
            call(root.property(QStringLiteral("composerObject")),
                 QStringLiteral("refreshStickerPicker"));
            feedback(root, translated(root, QStringLiteral("Набор стикеров установлен")), false);
        } else {
            feedback(root, translated(root, QStringLiteral("Не удалось установить набор стикеров")), true);
        }
        return undefined();
    }

    if (operation == QStringLiteral("shareStickerPack")) {
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (!first.isObject() || roomId.isEmpty())
            return undefined();
        emitCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("share_sticker_pack"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("share-sticker-pack"))},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("pack"), first}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("sendSticker")) {
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (!first.isObject() || roomId.isEmpty())
            return undefined();
        const QString builtinId = string(first.property(QStringLiteral("builtin_id")));
        if (!builtinId.isEmpty()) {
            emitCommand(root, objectFromProperties(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("send_builtin_sticker"))},
                {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("sticker"))},
                {QStringLiteral("room_id"), QJSValue(roomId)},
                {QStringLiteral("sticker_id"), QJSValue(builtinId)}
            }));
            return undefined();
        }
        const QString mediaUrl = string(first.property(QStringLiteral("media_url")));
        if (mediaUrl.isEmpty())
            return undefined();
        QString body = string(first.property(QStringLiteral("body")));
        if (body.isEmpty())
            body = translated(root, QStringLiteral("Стикер"));
        QString mime = string(first.property(QStringLiteral("media_mime_type")));
        if (mime.isEmpty())
            mime = QStringLiteral("image/webp");
        QJSValue command = objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("send_sticker"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("sticker"))},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("body"), QJSValue(body)},
            {QStringLiteral("media_url"), QJSValue(mediaUrl)},
            {QStringLiteral("mime_type"), QJSValue(mime)}
        });
        if (!first.property(QStringLiteral("media_file")).isUndefined())
            command.setProperty(QStringLiteral("media_file"),
                                first.property(QStringLiteral("media_file")));
        emitCommand(root, command);
        return undefined();
    }

    if (operation == QStringLiteral("receiveClipboardPasteResult")) {
        call(root.property(QStringLiteral("composerObject")),
             QStringLiteral("finishClipboardPaste"),
             {first, second, third, fourth, fifth});
        return undefined();
    }

    if (operation == QStringLiteral("receiveEditResult")) {
        const QString requestId = string(first);
        const QJSValue pending = root.property(QStringLiteral("pendingEdits"));
        if (pending.property(requestId).isUndefined())
            return undefined();
        const QJSValue edit = pending.property(requestId);
        QJSValue remaining = cloneObject(engine, pending);
        remaining.deleteProperty(requestId);
        set(root, QStringLiteral("pendingEdits"), remaining);
        if (!boolean(second)) {
            if (string(edit.property(QStringLiteral("room_id")))
                == string(root.property(QStringLiteral("currentRoomId")))) {
                call(root.property(QStringLiteral("composerObject")),
                     QStringLiteral("restoreEditing"),
                     {edit.property(QStringLiteral("event_id")),
                      edit.property(QStringLiteral("body"))});
            }
            const QString reason = localizedError(root, string(third),
                QStringLiteral("неизвестная ошибка"));
            feedback(root, translated(root, QStringLiteral("Не удалось изменить сообщение: "))
                + reason, true);
            return undefined();
        }
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (string(edit.property(QStringLiteral("room_id")))
                != string(root.property(QStringLiteral("currentRoomId")))
            || !model.isObject())
            return undefined();
        for (int index = 0; index < modelCount(model); ++index) {
            if (string(modelGet(model, index).property(QStringLiteral("event_id")))
                == string(edit.property(QStringLiteral("event_id")))) {
                modelSetProperty(model, index, QStringLiteral("body"),
                                 edit.property(QStringLiteral("body")));
                modelSetProperty(model, index, QStringLiteral("is_edited"), QJSValue(true));
                break;
            }
        }
        return undefined();
    }

    if (operation == QStringLiteral("receiveUploadProgress")) {
        call(root.property(QStringLiteral("composerObject")),
             QStringLiteral("updateUpload"), {first, second, third});
        return undefined();
    }

    if (operation == QStringLiteral("receiveUploadResult")) {
        const QString requestId = string(first);
        call(root.property(QStringLiteral("composerObject")),
             QStringLiteral("finishUpload"), {first});
        const QJSValue cancelled = root.property(QStringLiteral("cancelledUploadIds"));
        if (boolean(cancelled.property(requestId))) {
            QJSValue remaining = cloneObject(engine, cancelled);
            remaining.deleteProperty(requestId);
            set(root, QStringLiteral("cancelledUploadIds"), remaining);
            return undefined();
        }
        if (!boolean(second)) {
            const QString reason = localizedError(root, string(third),
                QStringLiteral("неизвестная ошибка"));
            feedback(root, translated(root, QStringLiteral("Не удалось отправить файл: "))
                + reason, true);
        }
        return undefined();
    }

    if (operation == QStringLiteral("receiveStickerAssetUpload")) {
        const QString requestId = string(first);
        const QJSValue pending = root.property(QStringLiteral("pendingStickerCreations"));
        if (pending.property(requestId).isUndefined())
            return undefined();
        const QJSValue draft = pending.property(requestId);
        QJSValue remaining = cloneObject(engine, pending);
        remaining.deleteProperty(requestId);
        set(root, QStringLiteral("pendingStickerCreations"), remaining);
        const QString mediaUrl = string(third);
        if (!boolean(second) || mediaUrl.isEmpty()) {
            const QString reason = localizedError(root, string(fifth),
                QStringLiteral("неизвестная ошибка"));
            feedback(root, translated(root, QStringLiteral("Не удалось создать стикер: "))
                + reason, true);
            return undefined();
        }
        const QJSValue store = root.property(QStringLiteral("stickerPackStoreService"));
        QString accountId = string(draft.property(QStringLiteral("account_id")));
        if (accountId.isEmpty())
            accountId = string(root.property(QStringLiteral("currentUserId")));
        QString packId = string(draft.property(QStringLiteral("pack_id")));
        if (packId.isEmpty()) {
            QString packName = string(draft.property(QStringLiteral("pack_name")));
            if (packName.isEmpty())
                packName = translated(root, QStringLiteral("Мои стикеры"));
            const QJSValue created = call(store, QStringLiteral("createPack"),
                                          {QJSValue(accountId), QJSValue(packName)});
            packId = string(created.property(QStringLiteral("id")));
        }
        QString shortcode = string(draft.property(QStringLiteral("shortcode")));
        if (shortcode.isEmpty())
            shortcode = QStringLiteral("sticker");
        QString body = string(draft.property(QStringLiteral("body")));
        if (body.isEmpty())
            body = translated(root, QStringLiteral("Стикер"));
        QString mime = string(fourth);
        if (mime.isEmpty())
            mime = string(draft.property(QStringLiteral("mime_type")));
        if (mime.isEmpty())
            mime = QStringLiteral("image/webp");
        static const QRegularExpression animatedPattern(
            QStringLiteral("(?:gif|webp|apng)"), QRegularExpression::CaseInsensitiveOption);
        const QJSValue sticker = objectFromProperties(engine, {
            {QStringLiteral("shortcode"), QJSValue(shortcode)},
            {QStringLiteral("body"), QJSValue(body)},
            {QStringLiteral("media_url"), QJSValue(mediaUrl)},
            {QStringLiteral("media_mime_type"), QJSValue(mime)},
            {QStringLiteral("animated"), QJSValue(animatedPattern.match(mime).hasMatch())}
        });
        if (packId.isEmpty()
            || !boolean(call(store, QStringLiteral("addSticker"),
                             {QJSValue(accountId), QJSValue(packId), sticker}))) {
            feedback(root, translated(root,
                QStringLiteral("Стикер загружен, но не удалось сохранить его в набор")), true);
            return undefined();
        }
        call(store, QStringLiteral("flush"));
        call(root.property(QStringLiteral("composerObject")),
             QStringLiteral("refreshStickerPicker"));
        feedback(root, translated(root, QStringLiteral("Стикер добавлен в набор")), false);
        return undefined();
    }

    return error(engine, QStringLiteral("chat.") + operation);
}

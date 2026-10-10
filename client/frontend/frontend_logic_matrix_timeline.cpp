#include "frontend_logic_matrix_internal.h"

#include <QJsonDocument>

#include <limits>

using namespace FrontendLogicSupport;

namespace FrontendMatrixLogic {
namespace {

QByteArray json(const QJSValue &value)
{
    return QJsonDocument::fromVariant(value.toVariant()).toJson(QJsonDocument::Compact);
}

int indexOfString(const QJSValue &arrayValue, const QString &needle)
{
    for (int index = 0; index < length(arrayValue); ++index) {
        if (string(arrayValue.property(index)) == needle)
            return index;
    }
    return -1;
}

void setMapValue(QJSEngine *engine,
                 const QJSValue &root,
                 const QString &property,
                 const QString &key,
                 const QJSValue &value,
                 bool remove = false)
{
    QJSValue map = cloneObject(engine, root.property(property));
    if (remove)
        map.deleteProperty(key);
    else
        map.setProperty(key, value);
    set(root, property, map);
}

QJSValue normalizedMessage(const QJSValue &root, const QJSValue &value)
{
    return callRoot(root, QStringLiteral("normalizeMessage"), {value});
}

QJSValue timelineItemMessage(const QJSValue &root,
                             QJSEngine *engine,
                             const QJSValue &item)
{
    if (!item.isObject()
        || string(item.property(QStringLiteral("kind"))) != QStringLiteral("event")
        || !item.property(QStringLiteral("message")).isObject())
        return nullValue();
    QJSValue source = cloneObject(engine, item.property(QStringLiteral("message")));
    QString timelineId = string(item.property(QStringLiteral("timeline_item_id")));
    if (timelineId.isEmpty())
        timelineId = string(source.property(QStringLiteral("timeline_item_id")));
    source.setProperty(QStringLiteral("timeline_item_id"), QJSValue(timelineId));
    QString sendState = string(item.property(QStringLiteral("send_state")));
    if (sendState.isEmpty())
        sendState = string(source.property(QStringLiteral("send_state")));
    if (sendState.isEmpty())
        sendState = boolean(item.property(QStringLiteral("is_local_echo")))
            ? QStringLiteral("sending") : QStringLiteral("sent");
    source.setProperty(QStringLiteral("send_state"), QJSValue(sendState));
    source.setProperty(QStringLiteral("is_optimistic"),
                       QJSValue(boolean(item.property(QStringLiteral("is_local_echo")))
                                && sendState != QStringLiteral("sent")));
    QString sendError = string(item.property(QStringLiteral("send_error")));
    if (sendError.isEmpty())
        sendError = string(source.property(QStringLiteral("send_error")));
    source.setProperty(QStringLiteral("send_error"), QJSValue(sendError));
    source.setProperty(QStringLiteral("send_recoverable"),
                       QJSValue(boolean(item.property(QStringLiteral("send_recoverable")))));
    const QString type = string(source.property(QStringLiteral("msg_type")));
    const bool encrypted = boolean(source.property(QStringLiteral("is_encrypted")))
        || type == QStringLiteral("m.encrypted");
    if (string(source.property(QStringLiteral("body"))).isEmpty()
        && string(source.property(QStringLiteral("media_url"))).isEmpty()
        && !source.property(QStringLiteral("media_file")).isObject()
        && type != QStringLiteral("m.audio") && type != QStringLiteral("m.image")
        && type != QStringLiteral("m.video") && type != QStringLiteral("m.file")
        && !encrypted)
        return nullValue();
    return normalizedMessage(root, source);
}

QJSValue rebuildVisibleTimeline(const QJSValue &root,
                                QJSEngine *engine,
                                bool includeThreadReplies)
{
    const QJSValue items = root.property(QStringLiteral("timelineItems"));
    QHash<QString, QJSValue> readers;
    QStringList readerOrder;
    Values visible;
    for (int index = length(items) - 1; index >= 0; --index) {
        QJSValue message = timelineItemMessage(root, engine, items.property(index));
        if (!message.isObject())
            continue;
        if (!includeThreadReplies
            && !string(message.property(QStringLiteral("thread_root_id"))).isEmpty())
            continue;
        for (const QJSValue &receipt : values(message.property(QStringLiteral("read_receipts")))) {
            const QString userId = string(receipt.property(QStringLiteral("user_id")));
            if (!userId.isEmpty()) {
                if (!readers.contains(userId))
                    readerOrder.append(userId);
                readers.insert(userId, receipt);
            }
        }
        Values cumulative;
        for (const QString &userId : std::as_const(readerOrder))
            cumulative.append(readers.value(userId));
        message.setProperty(QStringLiteral("read_receipts"),
                            arrayFromValues(engine, cumulative));
        visible.append(message);
    }
    return arrayFromValues(engine, visible);
}

bool isIncomingUnread(const QJSValue &root, const QJSValue &message)
{
    const QString eventId = string(message.property(QStringLiteral("event_id")));
    return message.isObject()
        && string(message.property(QStringLiteral("sender")))
            != string(root.property(QStringLiteral("authenticatedUserId")))
        && !boolean(message.property(QStringLiteral("is_system")))
        && !boolean(message.property(QStringLiteral("is_redacted")))
        && !boolean(message.property(QStringLiteral("sender_is_ignored")))
        && !eventId.isEmpty() && !eventId.startsWith(QStringLiteral("local:"));
}

QJSValue preparedModelForRoom(const QJSValue &root,
                              QJSEngine *engine,
                              const QString &roomId)
{
    QJSValue prepared = root.property(QStringLiteral("preparedRoomModels"));
    QJSValue model = prepared.property(roomId);
    if (!model.isObject()) {
        model = call(root.property(QStringLiteral("cachedMessageModelObject")),
                     QStringLiteral("createObject"), {root});
        QJSValue rows = root.property(QStringLiteral("roomMessageCache")).property(roomId);
        if (!rows.isObject())
            rows = root.property(QStringLiteral("roomPreviewCache")).property(roomId);
        if (length(rows) > 0)
            call(model, QStringLiteral("append"), {rows});
        prepared.setProperty(roomId, model);
    }
    return model;
}

} // namespace

Result invokeCacheAndTimeline(const QString &operation,
                              const QJSValue &root,
                              const QJSValue &arguments)
{
    QJSEngine *engine = engineFor(root);
    const QJSValue first = argument(arguments, 0);
    const QJSValue second = argument(arguments, 1);
    const QJSValue third = argument(arguments, 2);

    if (operation == QStringLiteral("hasCachedRoom")) {
        const QString roomId = string(first);
        return QJSValue(!roomId.isEmpty()
            && !root.property(QStringLiteral("roomMessageCache")).property(roomId).isUndefined());
    }

    if (operation == QStringLiteral("touchMessageCacheRoom")) {
        const QString roomId = string(first);
        if (!roomId.isEmpty())
            setMapValue(engine, root, QStringLiteral("roomMessageCacheLastAccess"),
                        roomId, QJSValue(double(nowMs())));
        return undefined();
    }

    if (operation == QStringLiteral("discardPreparedRoom")) {
        const QString roomId = string(first);
        QJSValue prepared = root.property(QStringLiteral("preparedRoomModels"));
        const QJSValue model = prepared.property(roomId);
        if (model.isObject() && !model.strictlyEquals(root.property(QStringLiteral("messageModel")))) {
            prepared.deleteProperty(roomId);
            call(model, QStringLiteral("destroy"));
        }
        return undefined();
    }

    if (operation == QStringLiteral("clearPreparedRooms")) {
        set(root, QStringLiteral("messageModel"),
            root.property(QStringLiteral("emptyMessageModelObject")));
        const QJSValue prepared = root.property(QStringLiteral("preparedRoomModels"));
        for (const QString &roomId : objectKeys(prepared))
            call(prepared.property(roomId), QStringLiteral("destroy"));
        set(root, QStringLiteral("preparedRoomModels"), object(engine));
        modelClear(root.property(QStringLiteral("emptyMessageModelObject")));
        return undefined();
    }

    if (operation == QStringLiteral("preparedModelForRoom"))
        return preparedModelForRoom(root, engine, string(first));

    if (operation == QStringLiteral("trimMessageCache")) {
        const QString preferredRoomId = string(first);
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("roomMessageCache")));
        QStringList roomIds = objectKeys(cache);
        for (const QString &preparedId : objectKeys(root.property(QStringLiteral("preparedRoomModels")))) {
            if (!roomIds.contains(preparedId))
                roomIds.append(preparedId);
        }
        const int maximum = root.property(QStringLiteral("maxCachedMessageRooms")).toInt();
        while (roomIds.size() > maximum) {
            QString victim;
            double victimAccess = std::numeric_limits<double>::max();
            for (const QString &candidate : std::as_const(roomIds)) {
                if (candidate == string(root.property(QStringLiteral("currentRoomId")))
                    || candidate == string(root.property(QStringLiteral("displayedRoomId")))
                    || indexOfString(root.property(QStringLiteral("roomPreviewPrefetchTargets")),
                                     candidate) >= 0)
                    continue;
                const double accessed = number(root.property(
                    QStringLiteral("roomMessageCacheLastAccess")).property(candidate));
                if (accessed < victimAccess) {
                    victim = candidate;
                    victimAccess = accessed;
                }
            }
            if (victim.isEmpty())
                break;
            callRoot(root, QStringLiteral("discardPreparedRoom"), {QJSValue(victim)});
            cache.deleteProperty(victim);
            root.property(QStringLiteral("roomMessageCacheUpdatedAt")).deleteProperty(victim);
            root.property(QStringLiteral("roomMessageCacheLastAccess")).deleteProperty(victim);
            roomIds.removeAll(victim);
        }
        set(root, QStringLiteral("roomMessageCache"), cache);
        Q_UNUSED(preferredRoomId)
        return undefined();
    }

    if (operation == QStringLiteral("compactInactiveRoom")) {
        const QString roomId = string(first);
        const QJSValue model = second;
        if (roomId == string(root.property(QStringLiteral("displayedRoomId")))
            || !root.property(QStringLiteral("preparedRoomModels")).property(roomId)
                    .strictlyEquals(model))
            return undefined();
        QJSValue position = nullValue();
        const QJSValue resolver = root.property(QStringLiteral("readingPositionResolver"));
        if (resolver.isCallable())
            position = resolver.call({QJSValue(roomId)});
        int firstIndex = 0;
        const int maximum = root.property(QStringLiteral("maxCachedMessagesPerRoom")).toInt();
        if (position.isObject() && modelCount(model) > maximum) {
            for (int index = 0; index < modelCount(model); ++index) {
                if (string(modelGet(model, index).property(QStringLiteral("event_id")))
                    != string(position.property(QStringLiteral("event_id"))))
                    continue;
                firstIndex = qMax(0, qMin(modelCount(model) - maximum,
                                         index - maximum / 2));
                break;
            }
        }
        if (modelCount(model) > firstIndex + maximum)
            call(model, QStringLiteral("remove"),
                 {QJSValue(firstIndex + maximum),
                  QJSValue(modelCount(model) - firstIndex - maximum)});
        if (firstIndex > 0)
            call(model, QStringLiteral("remove"), {QJSValue(0), QJSValue(firstIndex)});
        Values rows;
        for (int index = 0; index < modelCount(model); ++index)
            rows.append(normalizedMessage(root, modelGet(model, index)));
        root.property(QStringLiteral("roomMessageCache"))
            .setProperty(roomId, arrayFromValues(engine, rows));
        callRoot(root, QStringLiteral("trimMessageCache"), {QJSValue(roomId)});
        return undefined();
    }

    if (operation == QStringLiteral("replaceMessageModel")) {
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (!model.isObject())
            return undefined();
        modelClear(model);
        for (const QJSValue &message : values(first))
            modelAppend(model, normalizedMessage(root, message));
        return undefined();
    }

    if (operation == QStringLiteral("sameMessageValue")) {
        if (first.strictlyEquals(second))
            return QJSValue(true);
        if (first.isNull() || first.isUndefined() || second.isNull() || second.isUndefined())
            return QJSValue(false);
        const bool nextList = second.isArray()
            || (second.property(QStringLiteral("count")).isNumber()
                && second.property(QStringLiteral("get")).isCallable());
        if (nextList) {
            if (length(first) != length(second))
                return QJSValue(false);
            for (int index = 0; index < length(second); ++index) {
                QJSValue left = first.property(index);
                if (left.isUndefined() && first.property(QStringLiteral("get")).isCallable())
                    left = modelGet(first, index);
                QJSValue right = second.property(index);
                if (right.isUndefined() && second.property(QStringLiteral("get")).isCallable())
                    right = modelGet(second, index);
                if (!boolean(callRoot(root, QStringLiteral("sameMessageValue"), {left, right})))
                    return QJSValue(false);
            }
            return QJSValue(true);
        }
        return QJSValue(second.isObject() && json(first) == json(second));
    }

    if (operation == QStringLiteral("updateMessageRow")) {
        const int index = first.toInt();
        const QJSValue message = second;
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        const QJSValue current = modelGet(model, index);
        QJSValueIterator iterator(message);
        while (iterator.hasNext()) {
            iterator.next();
            if (!boolean(callRoot(root, QStringLiteral("sameMessageValue"),
                                  {current.property(iterator.name()), iterator.value()}))) {
                modelSetProperty(model, index, iterator.name(), iterator.value());
            }
        }
        return undefined();
    }

    if (operation == QStringLiteral("mergeTimelineHistory")) {
        set(root, QStringLiteral("timelineCacheGapPending"), QJSValue(false));
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (!boolean(root.property(QStringLiteral("timelineHasMoreBackwards")))
            || !model.isObject() || modelCount(model) == 0)
            return first;
        QHash<QString, int> cachedIndexes;
        for (int index = 0; index < modelCount(model); ++index)
            cachedIndexes.insert(string(modelGet(model, index).property(QStringLiteral("event_id"))), index);
        Values messages = values(first);
        int firstOlder = -1;
        for (int index = messages.size() - 1; index >= 0; --index) {
            const QString id = string(messages.at(index).property(QStringLiteral("event_id")));
            if (!id.isEmpty() && cachedIndexes.contains(id)) {
                firstOlder = cachedIndexes.value(id) + 1;
                break;
            }
        }
        if (firstOlder < 0) {
            set(root, QStringLiteral("timelineCacheGapPending"), QJSValue(true));
            firstOlder = 0;
            messages.clear();
        }
        QSet<QString> seen;
        for (const QJSValue &message : std::as_const(messages))
            seen.insert(string(message.property(QStringLiteral("event_id"))));
        for (int index = firstOlder; index < modelCount(model); ++index) {
            const QJSValue cached = modelGet(model, index);
            if (!string(cached.property(QStringLiteral("thread_root_id"))).isEmpty())
                continue;
            const QString id = string(cached.property(QStringLiteral("event_id")));
            if (!seen.contains(id))
                messages.append(normalizedMessage(root, cached));
        }
        return arrayFromValues(engine, messages);
    }

    if (operation == QStringLiteral("reconcileMessageModel")) {
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (!model.isObject())
            return array(engine);
        const Values target = values(first);
        for (int targetIndex = 0; targetIndex < target.size(); ++targetIndex) {
            const QJSValue targetMessage = target.at(targetIndex);
            QString targetId = string(targetMessage.property(QStringLiteral("timeline_item_id")));
            if (targetId.isEmpty())
                targetId = string(targetMessage.property(QStringLiteral("event_id")));
            const QJSValue current = targetIndex < modelCount(model)
                ? modelGet(model, targetIndex) : nullValue();
            QString currentId = string(current.property(QStringLiteral("timeline_item_id")));
            if (currentId.isEmpty())
                currentId = string(current.property(QStringLiteral("event_id")));
            const QString targetEvent = string(targetMessage.property(QStringLiteral("event_id")));
            if (targetIndex < modelCount(model)
                && (currentId == targetId
                    || (!targetEvent.isEmpty()
                        && string(current.property(QStringLiteral("event_id"))) == targetEvent))) {
                callRoot(root, QStringLiteral("updateMessageRow"),
                         {QJSValue(targetIndex), targetMessage});
                continue;
            }
            int found = -1;
            for (int lookup = targetIndex + 1; lookup < modelCount(model); ++lookup) {
                const QJSValue candidate = modelGet(model, lookup);
                QString candidateId = string(candidate.property(QStringLiteral("timeline_item_id")));
                if (candidateId.isEmpty())
                    candidateId = string(candidate.property(QStringLiteral("event_id")));
                if (candidateId == targetId
                    || (!targetEvent.isEmpty()
                        && string(candidate.property(QStringLiteral("event_id"))) == targetEvent)) {
                    found = lookup;
                    break;
                }
            }
            if (found >= 0) {
                call(model, QStringLiteral("move"),
                     {QJSValue(found), QJSValue(targetIndex), QJSValue(1)});
                callRoot(root, QStringLiteral("updateMessageRow"),
                         {QJSValue(targetIndex), targetMessage});
            } else {
                call(model, QStringLiteral("insert"),
                     {QJSValue(targetIndex), targetMessage});
            }
        }
        if (modelCount(model) > target.size())
            call(model, QStringLiteral("remove"),
                 {QJSValue(int(target.size())),
                  QJSValue(modelCount(model) - int(target.size()))});
        return arrayFromValues(engine, target);
    }

    if (operation == QStringLiteral("snapshotDisplayedRoom")) {
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        const QString roomId = string(root.property(QStringLiteral("displayedRoomId")));
        if (!model.isObject() || roomId.isEmpty())
            return undefined();
        callRoot(root, QStringLiteral("touchMessageCacheRoom"), {QJSValue(roomId)});
        if (QObject *context = root.toQObject()) {
            QTimer::singleShot(0, context, [root, roomId, model] {
                callRoot(root, QStringLiteral("compactInactiveRoom"),
                         {QJSValue(roomId), model});
            });
        }
        return undefined();
    }

    if (operation == QStringLiteral("showRoomFromCache")) {
        const QString roomId = string(first);
        const QJSValue model = preparedModelForRoom(root, engine, roomId);
        set(root, QStringLiteral("messageModel"), model);
        set(root, QStringLiteral("displayedRoomId"), QJSValue(roomId));
        set(root, QStringLiteral("showEmptyState"), QJSValue(modelCount(model) == 0));
        return undefined();
    }

    if (operation == QStringLiteral("cachedRoomPreview")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return array(engine);
        const double requestedLimit = number(second);
        const int maximum = qMax(1, qRound(requestedLimit == 0 ? 30 : requestedLimit));
        Values cached;
        const QJSValue local = root.property(QStringLiteral("roomMessageCache")).property(roomId);
        for (int index = 0; index < length(local) && cached.size() < maximum; ++index)
            cached.append(local.property(index));
        if (length(local) > 0)
            callRoot(root, QStringLiteral("touchMessageCacheRoom"), {QJSValue(roomId)});
        const QJSValue previewCache = root.property(QStringLiteral("roomPreviewCache"));
        if (!previewCache.property(roomId).isUndefined()) {
            callRoot(root, QStringLiteral("touchRoomPreviewCache"), {QJSValue(roomId)});
            for (const QJSValue &candidate : values(previewCache.property(roomId))) {
                if (cached.size() >= maximum)
                    break;
                const QString eventId = string(candidate.property(QStringLiteral("event_id")));
                bool duplicate = false;
                for (const QJSValue &existing : std::as_const(cached)) {
                    if (string(existing.property(QStringLiteral("event_id"))) == eventId) {
                        duplicate = true;
                        break;
                    }
                }
                if (!duplicate)
                    cached.append(candidate);
            }
        }
        return arrayFromValues(engine, cached);
    }

    if (operation == QStringLiteral("cacheRoomPreview")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return undefined();
        Values rows = values(second).mid(0, 30);
        setMapValue(engine, root, QStringLiteral("roomPreviewCache"), roomId,
                    arrayFromValues(engine, rows));
        callRoot(root, QStringLiteral("touchRoomPreviewCache"), {QJSValue(roomId)});
        return undefined();
    }

    if (operation == QStringLiteral("touchRoomPreviewCache")) {
        const QString roomId = string(first);
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("roomPreviewCache")));
        if (roomId.isEmpty() || cache.property(roomId).isUndefined())
            return undefined();
        Values order = values(root.property(QStringLiteral("roomPreviewCacheOrder")));
        for (int index = order.size() - 1; index >= 0; --index) {
            if (string(order.at(index)) == roomId)
                order.removeAt(index);
        }
        order.prepend(QJSValue(roomId));
        while (order.size() > root.property(QStringLiteral("maxCachedRoomPreviews")).toInt())
            cache.deleteProperty(string(order.takeLast()));
        set(root, QStringLiteral("roomPreviewCache"), cache);
        set(root, QStringLiteral("roomPreviewCacheOrder"), arrayFromValues(engine, order));
        return undefined();
    }

    if (operation == QStringLiteral("roomPrefetchStamp")) {
        const QString roomId = string(first);
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        for (int index = 0; model.isObject() && index < modelCount(model); ++index) {
            const QJSValue room = modelGet(model, index);
            if (string(room.property(QStringLiteral("room_id"))) == roomId) {
                return QJSValue(string(room.property(QStringLiteral("last_event_id")))
                    + QLatin1Char(':')
                    + string(room.property(QStringLiteral("last_timestamp")), QStringLiteral("0")));
            }
        }
        return QJSValue(QString());
    }

    if (operation == QStringLiteral("scheduleRoomPreviewPrefetch")) {
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        if (!model.isObject()
            || string(root.property(QStringLiteral("authenticatedUserId"))).isEmpty())
            return undefined();
        Values targets;
        Values roomIds;
        Values queue;
        QSet<QString> stamps;
        const qint64 currentTime = nowMs();
        for (int index = 0; index < modelCount(model); ++index) {
            const QJSValue room = modelGet(model, index);
            const QString roomId = string(room.property(QStringLiteral("room_id")));
            if (roomId.isEmpty() || boolean(room.property(QStringLiteral("is_invited")))
                || boolean(room.property(QStringLiteral("is_space")))
                || boolean(root.property(QStringLiteral("pendingLeaveRoomIds")).property(roomId)))
                continue;
            roomIds.append(QJSValue(roomId));
            if (targets.size() < root.property(QStringLiteral("maxPreparedPrefetchRooms")).toInt())
                targets.append(QJSValue(roomId));
            const QString stamp = string(room.property(QStringLiteral("last_event_id")))
                + QLatin1Char(':')
                + string(room.property(QStringLiteral("last_timestamp")), QStringLiteral("0"));
            stamps.insert(roomId);
            if (roomId == string(root.property(QStringLiteral("currentRoomId")))
                || boolean(root.property(QStringLiteral("roomPreviewPrefetchQueued")).property(roomId)))
                continue;
            const QJSValue state = root.property(QStringLiteral("roomPreviewPrefetchState")).property(roomId);
            if (state.isObject()
                && number(state.property(QStringLiteral("retryAfter"))) > currentTime)
                continue;
            if (state.isObject() && boolean(state.property(QStringLiteral("complete")))
                && string(state.property(QStringLiteral("stamp"))) == stamp
                && currentTime - qint64(number(state.property(QStringLiteral("updatedAt")))) < 300000)
                continue;
            queue.append(QJSValue(roomId));
        }
        set(root, QStringLiteral("roomPreviewPrefetchTargets"), arrayFromValues(engine, targets));
        set(root, QStringLiteral("roomPreviewPrefetchRoomIds"), arrayFromValues(engine, roomIds));
        QJSValue progress = cloneObject(engine, root.property(QStringLiteral("roomPreviewPrefetchProgress")));
        for (const QString &roomId : objectKeys(progress)) {
            if (!stamps.contains(roomId)
                && !boolean(root.property(QStringLiteral("roomPreviewPrefetchQueued")).property(roomId)))
                progress.deleteProperty(roomId);
        }
        set(root, QStringLiteral("roomPreviewPrefetchProgress"), progress);
        QJSValue states = cloneObject(engine, root.property(QStringLiteral("roomPreviewPrefetchState")));
        for (const QString &roomId : objectKeys(states)) {
            if (!stamps.contains(roomId))
                states.deleteProperty(roomId);
        }
        set(root, QStringLiteral("roomPreviewPrefetchState"), states);
        set(root, QStringLiteral("roomPreviewPrefetchQueue"), arrayFromValues(engine, queue));
        callRoot(root, QStringLiteral("trimMessageCache"),
                 {root.property(QStringLiteral("currentRoomId"))});
        const bool canStart = !queue.isEmpty()
            && root.property(QStringLiteral("roomPreviewPrefetchInFlight")).toInt()
                < root.property(QStringLiteral("maxConcurrentRoomPreviewPrefetches")).toInt();
        const QJSValue timer = root.property(QStringLiteral("roomPreviewPrefetchTimerObject"));
        if (!boolean(root.property(QStringLiteral("foregroundTimelineBusy")))
            && (canStart
                || length(root.property(QStringLiteral("roomPreviewPrefetchResults"))) > 0
                || !string(callRoot(root, QStringLiteral("nextCachedRoomToPrepare"))).isEmpty())
            && !boolean(timer.property(QStringLiteral("running"))))
            call(timer, QStringLiteral("start"));
        return undefined();
    }

    if (operation == QStringLiteral("nextCachedRoomToPrepare")) {
        for (const QJSValue &value : values(root.property(QStringLiteral("roomPreviewPrefetchTargets")))) {
            const QString roomId = string(value);
            if (roomId != string(root.property(QStringLiteral("currentRoomId")))
                && !root.property(QStringLiteral("preparedRoomModels")).property(roomId).isObject()
                && (boolean(callRoot(root, QStringLiteral("hasCachedRoom"), {QJSValue(roomId)}))
                    || !root.property(QStringLiteral("roomPreviewCache")).property(roomId).isUndefined()))
                return QJSValue(roomId);
        }
        return QJSValue(QString());
    }

    if (operation == QStringLiteral("prefetchQueuedRoomPreviews")) {
        if (!boolean(root.property(QStringLiteral("connected")))
            || string(root.property(QStringLiteral("authenticatedUserId"))).isEmpty()
            || boolean(root.property(QStringLiteral("foregroundTimelineBusy"))))
            return undefined();
        const QString cachedRoom = string(callRoot(root, QStringLiteral("nextCachedRoomToPrepare")));
        if (!cachedRoom.isEmpty())
            preparedModelForRoom(root, engine, cachedRoom);
        Values results = values(root.property(QStringLiteral("roomPreviewPrefetchResults")));
        if (!results.isEmpty()) {
            const QJSValue result = results.takeFirst();
            set(root, QStringLiteral("roomPreviewPrefetchResults"),
                arrayFromValues(engine, results));
            callRoot(root, QStringLiteral("consumeRoomPrefetchResult"),
                     {result.property(QStringLiteral("request")),
                      result.property(QStringLiteral("response"))});
        }
        callRoot(root, QStringLiteral("scheduleRoomPreviewPrefetch"));
        while (root.property(QStringLiteral("roomPreviewPrefetchInFlight")).toInt()
                   < root.property(QStringLiteral("maxConcurrentRoomPreviewPrefetches")).toInt()) {
            Values queue = values(root.property(QStringLiteral("roomPreviewPrefetchQueue")));
            if (queue.isEmpty())
                break;
            const QString roomId = string(queue.takeFirst());
            set(root, QStringLiteral("roomPreviewPrefetchQueue"), arrayFromValues(engine, queue));
            const QString stamp = string(callRoot(root, QStringLiteral("roomPrefetchStamp"),
                                                  {QJSValue(roomId)}));
            QJSValue progressMap = root.property(QStringLiteral("roomPreviewPrefetchProgress"));
            QJSValue progress = progressMap.property(roomId);
            if (!progress.isObject()
                || string(progress.property(QStringLiteral("stamp"))) != stamp) {
                progress = objectFromProperties(engine, {
                    {QStringLiteral("stamp"), QJSValue(stamp)},
                    {QStringLiteral("messages"), array(engine)},
                    {QStringLiteral("nextFrom"), QJSValue(QString())},
                    {QStringLiteral("pages"), QJSValue(0)},
                    {QStringLiteral("stalled"), QJSValue(0)}
                });
                progressMap.setProperty(roomId, progress);
            }
            const QJSValue requestId = nextRequestId(root, QStringLiteral("room-prefetch"));
            root.property(QStringLiteral("roomPreviewRequests")).setProperty(requestId.toString(),
                objectFromProperties(engine, {
                    {QStringLiteral("room_id"), QJSValue(roomId)},
                    {QStringLiteral("prefetch"), QJSValue(true)},
                    {QStringLiteral("stamp"), QJSValue(stamp)},
                    {QStringLiteral("from"), progress.property(QStringLiteral("nextFrom"))}
                }));
            root.property(QStringLiteral("roomPreviewPrefetchQueued"))
                .setProperty(roomId, QJSValue(true));
            set(root, QStringLiteral("roomPreviewPrefetchInFlight"),
                QJSValue(root.property(QStringLiteral("roomPreviewPrefetchInFlight")).toInt() + 1));
            QJSValue value = objectFromProperties(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("get_timeline_preview"))},
                {QStringLiteral("request_id"), requestId},
                {QStringLiteral("room_id"), QJSValue(roomId)},
                {QStringLiteral("limit"), QJSValue(
                    root.property(QStringLiteral("initialRoomMessageCount")).toInt()
                    - length(progress.property(QStringLiteral("messages"))))}
            });
            if (!string(progress.property(QStringLiteral("nextFrom"))).isEmpty())
                value.setProperty(QStringLiteral("from"),
                                  progress.property(QStringLiteral("nextFrom")));
            sendCommand(root, value);
        }
        return undefined();
    }

    if (operation == QStringLiteral("finishRoomPreviewPrefetch")) {
        set(root, QStringLiteral("roomPreviewPrefetchInFlight"), QJSValue(qMax(0,
            root.property(QStringLiteral("roomPreviewPrefetchInFlight")).toInt() - 1)));
        Values results = values(root.property(QStringLiteral("roomPreviewPrefetchResults")));
        results.append(objectFromProperties(engine, {
            {QStringLiteral("request"), first}, {QStringLiteral("response"), second}
        }));
        set(root, QStringLiteral("roomPreviewPrefetchResults"), arrayFromValues(engine, results));
        call(root.property(QStringLiteral("roomPreviewPrefetchTimerObject")),
             QStringLiteral("restart"));
        return undefined();
    }

    if (operation == QStringLiteral("consumeRoomPrefetchResult")) {
        const QJSValue request = first;
        const QJSValue response = second;
        const bool openingRoom = boolean(third);
        const QString roomId = string(request.property(QStringLiteral("room_id")));
        root.property(QStringLiteral("roomPreviewPrefetchQueued")).deleteProperty(roomId);
        if ((roomId == string(root.property(QStringLiteral("currentRoomId"))) && !openingRoom)
            || indexOfString(root.property(QStringLiteral("roomPreviewPrefetchRoomIds")), roomId) < 0
            || string(request.property(QStringLiteral("stamp")))
                != string(callRoot(root, QStringLiteral("roomPrefetchStamp"), {QJSValue(roomId)}))) {
            root.property(QStringLiteral("roomPreviewPrefetchProgress")).deleteProperty(roomId);
            return undefined();
        }
        if (response.property(QStringLiteral("success")).isBool()
            && !boolean(response.property(QStringLiteral("success")))) {
            root.property(QStringLiteral("roomPreviewPrefetchState")).setProperty(roomId,
                objectFromProperties(engine, {
                    {QStringLiteral("retryAfter"), QJSValue(double(nowMs() + 30000))}
                }));
            root.property(QStringLiteral("roomPreviewPrefetchProgress")).deleteProperty(roomId);
            return undefined();
        }
        QJSValue progress = root.property(QStringLiteral("roomPreviewPrefetchProgress"))
            .property(roomId);
        if (!progress.isObject()
            || string(progress.property(QStringLiteral("stamp")))
                != string(request.property(QStringLiteral("stamp"))))
            return undefined();
        QJSValue messages = progress.property(QStringLiteral("messages"));
        const int before = length(messages);
        QSet<QString> seen;
        for (const QJSValue &message : values(messages))
            seen.insert(string(message.property(QStringLiteral("event_id"))));
        for (const QJSValue &message : values(response.property(QStringLiteral("messages")))) {
            if (length(messages) >= root.property(QStringLiteral("initialRoomMessageCount")).toInt())
                break;
            const QString eventId = string(message.property(QStringLiteral("event_id")));
            if (seen.contains(eventId))
                continue;
            seen.insert(eventId);
            messages.setProperty(length(messages), normalizedMessage(root, message));
        }
        progress.setProperty(QStringLiteral("pages"),
                             QJSValue(progress.property(QStringLiteral("pages")).toInt() + 1));
        progress.setProperty(QStringLiteral("stalled"), QJSValue(before == length(messages)
            ? progress.property(QStringLiteral("stalled")).toInt() + 1 : 0));
        progress.setProperty(QStringLiteral("nextFrom"),
                             QJSValue(string(response.property(QStringLiteral("next_from")))));
        const bool complete = length(messages)
                >= root.property(QStringLiteral("initialRoomMessageCount")).toInt()
            || string(progress.property(QStringLiteral("nextFrom"))).isEmpty();
        if (length(messages) > before || complete) {
            callRoot(root, QStringLiteral("cacheRoomPreview"), {QJSValue(roomId), messages});
            if (openingRoom
                || indexOfString(root.property(QStringLiteral("roomPreviewPrefetchTargets")), roomId) >= 0
                || root.property(QStringLiteral("preparedRoomModels")).property(roomId).isObject()) {
                callRoot(root, QStringLiteral("preparePrefetchedRoom"),
                         {QJSValue(roomId), messages});
            }
        }
        if (!complete && progress.property(QStringLiteral("pages")).toInt() < 8
            && progress.property(QStringLiteral("stalled")).toInt() < 2)
            return undefined();
        root.property(QStringLiteral("roomPreviewPrefetchState")).setProperty(roomId,
            objectFromProperties(engine, {
                {QStringLiteral("stamp"), request.property(QStringLiteral("stamp"))},
                {QStringLiteral("updatedAt"), QJSValue(double(nowMs()))},
                {QStringLiteral("complete"), QJSValue(complete)},
                {QStringLiteral("retryAfter"), QJSValue(double(complete ? 0 : nowMs() + 30000))}
            }));
        root.property(QStringLiteral("roomPreviewPrefetchProgress")).deleteProperty(roomId);
        return undefined();
    }

    if (operation == QStringLiteral("preparePrefetchedRoom")) {
        const QString roomId = string(first);
        const QJSValue messagesValue = second;
        Values previous = values(root.property(QStringLiteral("roomMessageCache")).property(roomId));
        Values messages = values(messagesValue);
        Values merged = messages;
        if (!previous.isEmpty() && messages.isEmpty()) {
            preparedModelForRoom(root, engine, roomId);
            return undefined();
        }
        if (!previous.isEmpty() && !messages.isEmpty()) {
            QHash<QString, int> indexes;
            for (int index = 0; index < previous.size(); ++index)
                indexes.insert(string(previous.at(index).property(QStringLiteral("event_id"))), index);
            int overlap = -1;
            for (int index = messages.size() - 1; index >= 0; --index) {
                const QString id = string(messages.at(index).property(QStringLiteral("event_id")));
                if (indexes.contains(id)) {
                    overlap = indexes.value(id);
                    break;
                }
            }
            if (overlap < 0) {
                preparedModelForRoom(root, engine, roomId);
                return undefined();
            }
            QSet<QString> seen;
            for (const QJSValue &message : std::as_const(messages))
                seen.insert(string(message.property(QStringLiteral("event_id"))));
            for (int index = overlap + 1; index < previous.size(); ++index) {
                if (!seen.contains(string(previous.at(index).property(QStringLiteral("event_id")))))
                    merged.append(previous.at(index));
            }
        }
        const QJSValue mergedArray = arrayFromValues(engine, merged);
        root.property(QStringLiteral("roomMessageCache")).setProperty(roomId, mergedArray);
        QJSValue model = root.property(QStringLiteral("preparedRoomModels")).property(roomId);
        if (model.isObject()) {
            modelClear(model);
            if (!merged.isEmpty())
                modelAppend(model, mergedArray);
        } else {
            model = preparedModelForRoom(root, engine, roomId);
        }
        callRoot(root, QStringLiteral("compactInactiveRoom"), {QJSValue(roomId), model});
        return undefined();
    }

    if (operation == QStringLiteral("adoptPendingRoomPrefetch")) {
        const QString roomId = string(first);
        if (string(root.property(QStringLiteral("displayedRoomId"))) == roomId)
            return undefined();
        Values waiting;
        const Values results = values(root.property(QStringLiteral("roomPreviewPrefetchResults")));
        set(root, QStringLiteral("roomPreviewPrefetchResults"), array(engine));
        for (const QJSValue &result : results) {
            if (string(result.property(QStringLiteral("request")).property(QStringLiteral("room_id")))
                == roomId) {
                callRoot(root, QStringLiteral("consumeRoomPrefetchResult"), {
                    result.property(QStringLiteral("request")),
                    result.property(QStringLiteral("response")), QJSValue(true)
                });
            } else {
                waiting.append(result);
            }
        }
        set(root, QStringLiteral("roomPreviewPrefetchResults"),
            arrayFromValues(engine, waiting));
        return undefined();
    }

    if (operation == QStringLiteral("clearRoomPreviewCache")) {
        call(root.property(QStringLiteral("roomPreviewPrefetchTimerObject")), QStringLiteral("stop"));
        set(root, QStringLiteral("roomPreviewCache"), object(engine));
        set(root, QStringLiteral("roomPreviewCacheOrder"), array(engine));
        set(root, QStringLiteral("roomPreviewPrefetchQueue"), array(engine));
        set(root, QStringLiteral("roomPreviewPrefetchQueued"), object(engine));
        set(root, QStringLiteral("roomPreviewPrefetchTargets"), array(engine));
        set(root, QStringLiteral("roomPreviewPrefetchRoomIds"), array(engine));
        set(root, QStringLiteral("roomPreviewPrefetchState"), object(engine));
        set(root, QStringLiteral("roomPreviewPrefetchProgress"), object(engine));
        set(root, QStringLiteral("roomPreviewPrefetchResults"), array(engine));
        set(root, QStringLiteral("roomPreviewPrefetchInFlight"), QJSValue(0));
        return undefined();
    }

    if (operation == QStringLiteral("requestRoomPreview")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return QJSValue(QString());
        QJSValue requestId = third;
        if (string(requestId).isEmpty())
            requestId = nextRequestId(root, QStringLiteral("room-preview"));
        setMapValue(engine, root, QStringLiteral("roomPreviewRequests"), requestId.toString(),
            objectFromProperties(engine, {
                {QStringLiteral("room_id"), QJSValue(roomId)},
                {QStringLiteral("append"), QJSValue(!string(second).isEmpty())}
            }));
        QJSValue value = objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_timeline_preview"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("limit"), QJSValue(30)}
        });
        if (!string(second).isEmpty())
            value.setProperty(QStringLiteral("from"), second);
        sendCommand(root, value);
        return requestId;
    }

    if (operation == QStringLiteral("requestMessageContext")) {
        const QString roomId = string(first);
        const QString eventId = string(second);
        if (roomId.isEmpty() || eventId.isEmpty())
            return undefined();
        const QJSValue requestId = nextRequestId(root, QStringLiteral("message-context"));
        root.property(QStringLiteral("messageRequestRooms"))
            .setProperty(requestId.toString(), QJSValue(roomId));
        root.property(QStringLiteral("messageRequestTargets"))
            .setProperty(requestId.toString(), QJSValue(eventId));
        call(root.property(QStringLiteral("encryptedRefreshTimerObject")), QStringLiteral("stop"));
        set(root, QStringLiteral("encryptedRefreshRoomId"), QJSValue(QString()));
        set(root, QStringLiteral("encryptedRefreshAttempts"), QJSValue(0));
        sendCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_message_context"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("limit"), QJSValue(25)},
            {QStringLiteral("event_id"), QJSValue(eventId)}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("requestOlderMessages")) {
        if (!string(first).isEmpty()
            && string(first) == string(root.property(QStringLiteral("currentRoomId"))))
            callRoot(root, QStringLiteral("paginateTimelineBackwards"), {QJSValue(false)});
        return undefined();
    }

    if (operation == QStringLiteral("timelineItemMessage"))
        return timelineItemMessage(root, engine, first);

    if (operation == QStringLiteral("rebuildVisibleTimeline"))
        return rebuildVisibleTimeline(root, engine, boolean(first));

    if (operation == QStringLiteral("propagateReadReceipts")) {
        QHash<QString, QJSValue> readers;
        QStringList readerOrder;
        Values result;
        for (const QJSValue &source : values(first)) {
            QJSValue message = cloneObject(engine, source);
            for (const QJSValue &receipt : values(message.property(QStringLiteral("read_receipts")))) {
                const QString userId = string(receipt.property(QStringLiteral("user_id")));
                if (!userId.isEmpty()) {
                    if (!readers.contains(userId))
                        readerOrder.append(userId);
                    readers.insert(userId, receipt);
                }
            }
            Values cumulative;
            for (const QString &userId : std::as_const(readerOrder))
                cumulative.append(readers.value(userId));
            message.setProperty(QStringLiteral("read_receipts"),
                                arrayFromValues(engine, cumulative));
            result.append(message);
        }
        return arrayFromValues(engine, result);
    }

    if (operation == QStringLiteral("firstEventAfterReadMarker")) {
        const Values items = values(first);
        int marker = -1;
        for (int index = 0; index < items.size(); ++index) {
            if (string(items.at(index).property(QStringLiteral("kind"))) == QStringLiteral("read_marker")) {
                marker = index;
                break;
            }
        }
        if (marker >= 0) {
            for (int index = marker + 1; index < items.size(); ++index) {
                const QJSValue message = timelineItemMessage(root, engine, items.at(index));
                const QString eventId = string(message.property(QStringLiteral("event_id")));
                if (!eventId.isEmpty())
                    return QJSValue(eventId);
            }
        }
        return QJSValue(QString());
    }

    if (operation == QStringLiteral("needsReadingPosition")) {
        const QString eventId = string(root.property(QStringLiteral("restoreEventId")));
        if (eventId.isEmpty())
            return QJSValue(false);
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        for (int index = 0; model.isObject() && index < modelCount(model); ++index) {
            if (string(modelGet(model, index).property(QStringLiteral("event_id"))) == eventId)
                return QJSValue(false);
        }
        return QJSValue(true);
    }

    if (operation == QStringLiteral("updateReadingPositionReady")) {
        set(root, QStringLiteral("timelineInitialPositionReady"), QJSValue(
            boolean(root.property(QStringLiteral("timelineInitialPositionReady")))
            || !boolean(callRoot(root, QStringLiteral("needsReadingPosition")))
            || !boolean(root.property(QStringLiteral("timelineHasMoreBackwards")))));
        return undefined();
    }

    if (operation == QStringLiteral("updateTimelineLoadingState")) {
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        const bool empty = !model.isObject() || modelCount(model) == 0;
        const bool loading = empty
            && (string(root.property(QStringLiteral("timelineFreshness"))) == QStringLiteral("catching_up")
                || boolean(root.property(QStringLiteral("timelineHasMoreBackwards"))));
        set(root, QStringLiteral("isLoadingMessages"), QJSValue(loading));
        set(root, QStringLiteral("showEmptyState"), QJSValue(empty && !loading));
        return undefined();
    }

    if (operation == QStringLiteral("responseTimelineFreshness")) {
        if (root.property(QStringLiteral("syncFreshnessEpoch")).toInt()
                == qRound(number(first.property(QStringLiteral("session_epoch"))))
            && !string(root.property(QStringLiteral("syncFreshness"))).isEmpty())
            return root.property(QStringLiteral("syncFreshness"));
        QString freshness = string(first.property(QStringLiteral("freshness")));
        return QJSValue(freshness.isEmpty() ? QStringLiteral("offline") : freshness);
    }

    if (operation == QStringLiteral("refreshTimelineReadState")) {
        if (root.property(QStringLiteral("timelineGeneration")).toInt() <= 0
            || string(root.property(QStringLiteral("displayedRoomId")))
                != string(root.property(QStringLiteral("currentRoomId"))))
            return undefined();
        const bool waiting = boolean(root.property(QStringLiteral("showingCachedTimeline")))
            && string(root.property(QStringLiteral("timelineFreshness"))) != QStringLiteral("live");
        if (!boolean(root.property(QStringLiteral("timelineCacheGapPending"))) && !waiting
            && boolean(root.property(QStringLiteral("unreadBoundaryPending")))) {
            QJSValue messages = first;
            if (!messages.isObject()) {
                Values rows;
                const QJSValue model = root.property(QStringLiteral("messageModel"));
                for (int index = 0; model.isObject() && index < modelCount(model); ++index)
                    rows.append(modelGet(model, index));
                messages = arrayFromValues(engine, rows);
            }
            callRoot(root, QStringLiteral("resolveUnreadBoundary"),
                     {root.property(QStringLiteral("timelineItems")), messages});
        }
        set(root, QStringLiteral("showingCachedTimeline"),
            QJSValue(boolean(root.property(QStringLiteral("timelineCacheGapPending"))) || waiting));
        return undefined();
    }

    if (operation == QStringLiteral("isIncomingUnreadMessage"))
        return QJSValue(isIncomingUnread(root, first));

    if (operation == QStringLiteral("firstUnreadEventFromCount")) {
        int remaining = qMax(0, qRound(number(second)));
        if (remaining <= 0 || length(first) < remaining)
            return QJSValue(QString());
        for (const QJSValue &message : values(first)) {
            if (!isIncomingUnread(root, message))
                continue;
            if (--remaining == 0)
                return QJSValue(string(message.property(QStringLiteral("event_id"))));
        }
        return QJSValue(QString());
    }

    if (operation == QStringLiteral("resolveUnreadBoundary")) {
        if (!boolean(root.property(QStringLiteral("unreadBoundaryPending"))))
            return undefined();
        const QJSValue messages = second;
        QString boundary;
        const QJSValue restore = root.property(QStringLiteral("readingRestorePosition"));
        const QString readEvent = restore.isObject()
            ? string(restore.property(QStringLiteral("read_event_id"))) : QString();
        for (int index = 1; !readEvent.isEmpty() && index < length(messages); ++index) {
            if (string(messages.property(index).property(QStringLiteral("event_id"))) == readEvent) {
                boundary = string(messages.property(index - 1).property(QStringLiteral("event_id")));
                break;
            }
        }
        if (boundary.isEmpty())
            boundary = string(callRoot(root, QStringLiteral("firstEventAfterReadMarker"), {first}));
        if (boundary.isEmpty())
            boundary = string(callRoot(root, QStringLiteral("firstUnreadEventFromCount"),
                                       {messages, root.property(QStringLiteral("openingUnreadCount"))}));
        if (boundary.isEmpty()
            && !boolean(root.property(QStringLiteral("timelineHasMoreBackwards")))) {
            for (int index = length(messages) - 1; index >= 0; --index) {
                if (isIncomingUnread(root, messages.property(index))) {
                    boundary = string(messages.property(index).property(QStringLiteral("event_id")));
                    break;
                }
            }
        }
        if (!boundary.isEmpty()) {
            set(root, QStringLiteral("unreadBoundaryEventId"), QJSValue(boundary));
            set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
        } else if (!boolean(root.property(QStringLiteral("timelineHasMoreBackwards")))) {
            set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
            set(root, QStringLiteral("openingUnreadCount"), QJSValue(0));
        }
        return undefined();
    }

    if (operation == QStringLiteral("applyTimelineSnapshot")) {
        const QJSValue message = first;
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        if (!message.isObject()
            || roomId != string(root.property(QStringLiteral("currentRoomId"))))
            return undefined();
        const QString expected = string(root.property(QStringLiteral("timelineRequestByRoom"))
                                            .property(roomId));
        const QString requestId = string(message.property(QStringLiteral("request_id")));
        if (!expected.isEmpty() && !requestId.isEmpty() && requestId != expected)
            return undefined();
        set(root, QStringLiteral("timelineSessionEpoch"),
            QJSValue(number(message.property(QStringLiteral("session_epoch")))));
        set(root, QStringLiteral("timelineGeneration"),
            QJSValue(number(message.property(QStringLiteral("generation")))));
        set(root, QStringLiteral("timelineFreshness"),
            callRoot(root, QStringLiteral("responseTimelineFreshness"), {message}));
        set(root, QStringLiteral("timelineHasMoreBackwards"),
            QJSValue(boolean(message.property(QStringLiteral("has_more_backwards")))));
        QJSValue items = message.property(QStringLiteral("items"));
        if (!items.isObject())
            items = array(engine);
        set(root, QStringLiteral("timelineItems"), cloneArray(engine, items));
        const QJSValue all = rebuildVisibleTimeline(root, engine, true);
        signal(root, QStringLiteral("timelineMessagesUpdated"), {QJSValue(roomId), all});
        QJSValue visible = callRoot(root, QStringLiteral("mergeTimelineHistory"),
            {rebuildVisibleTimeline(root, engine, false)});
        Values ids;
        for (int index = 0; index < length(items); ++index) {
            QString id = string(items.property(index).property(QStringLiteral("timeline_item_id")));
            if (id.isEmpty())
                id = QStringLiteral("virtual:") + QString::number(index);
            ids.append(QJSValue(id));
        }
        set(root, QStringLiteral("timelineItemIds"), arrayFromValues(engine, ids));
        visible = callRoot(root, QStringLiteral("reconcileMessageModel"), {visible});
        setMapValue(engine, root, QStringLiteral("roomMessageCache"), roomId,
                    cloneArray(engine, visible));
        set(root, QStringLiteral("displayedRoomId"), QJSValue(roomId));
        callRoot(root, QStringLiteral("refreshManualUnreadCount"), {QJSValue(roomId), visible});
        callRoot(root, QStringLiteral("refreshTimelineReadState"), {visible});
        callRoot(root, QStringLiteral("updateReadingPositionReady"));
        callRoot(root, QStringLiteral("updateTimelineLoadingState"));
        const bool initialFill = (length(visible)
                    < root.property(QStringLiteral("timelineInitialMessageTarget")).toInt()
                || boolean(root.property(QStringLiteral("unreadBoundaryPending")))
                || boolean(callRoot(root, QStringLiteral("needsReadingPosition")))
                || boolean(root.property(QStringLiteral("timelineCacheGapPending"))))
            && boolean(root.property(QStringLiteral("timelineHasMoreBackwards")));
        set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(initialFill));
        set(root, QStringLiteral("timelineInitialFillStalledPages"), QJSValue(0));
        set(root, QStringLiteral("timelinePaginationStartItemCount"), QJSValue(length(items)));
        if (string(root.property(QStringLiteral("timelineFreshness"))) == QStringLiteral("live")
            && !boolean(root.property(QStringLiteral("timelineCacheGapPending")))
            && !initialFill) {
            root.property(QStringLiteral("roomPreviewPrefetchState")).setProperty(roomId,
                objectFromProperties(engine, {
                    {QStringLiteral("stamp"), callRoot(root, QStringLiteral("roomPrefetchStamp"), {QJSValue(roomId)})},
                    {QStringLiteral("updatedAt"), QJSValue(double(nowMs()))},
                    {QStringLiteral("complete"), QJSValue(true)}
                }));
        }
        if (initialFill)
            callLater(root, QStringLiteral("continueInitialTimelineFill"));
        return undefined();
    }

    if (operation == QStringLiteral("continueInitialTimelineFill")) {
        if (!boolean(root.property(QStringLiteral("timelineInitialFillActive"))))
            return undefined();
        if (!boolean(root.property(QStringLiteral("timelineDiffsSupported")))
            || string(root.property(QStringLiteral("currentRoomId"))).isEmpty()) {
            set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
            return undefined();
        }
        if (boolean(root.property(QStringLiteral("timelinePaginationInFlight"))))
            return undefined();
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        const int loaded = model.isObject() ? modelCount(model) : 0;
        if ((loaded >= root.property(QStringLiteral("timelineInitialMessageTarget")).toInt()
                && !boolean(root.property(QStringLiteral("unreadBoundaryPending")))
                && !boolean(callRoot(root, QStringLiteral("needsReadingPosition")))
                && !boolean(root.property(QStringLiteral("timelineCacheGapPending"))))
            || !boolean(root.property(QStringLiteral("timelineHasMoreBackwards")))) {
            set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
            set(root, QStringLiteral("timelineInitialFillStalledPages"), QJSValue(0));
            return undefined();
        }
        callRoot(root, QStringLiteral("paginateTimelineBackwards"), {QJSValue(true)});
        return undefined();
    }

    if (operation == QStringLiteral("paginateTimelineBackwards")) {
        const bool initial = boolean(first);
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        const int sessionEpoch = root.property(QStringLiteral("timelineSessionEpoch")).toInt();
        const int activeEpoch = root.property(QStringLiteral("activeSessionEpoch")).toInt();
        if (!boolean(root.property(QStringLiteral("timelineDiffsSupported")))
            || boolean(root.property(QStringLiteral("timelinePaginationInFlight")))
            || roomId.isEmpty()
            || string(root.property(QStringLiteral("displayedRoomId"))) != roomId
            || sessionEpoch <= 0
            || root.property(QStringLiteral("timelineGeneration")).toInt() <= 0
            || (activeEpoch > 0 && sessionEpoch != activeEpoch))
            return QJSValue(false);
        const QJSValue requestId = nextRequestId(root,
            initial ? QStringLiteral("timeline-initial-page") : QStringLiteral("timeline-page"));
        set(root, QStringLiteral("timelinePaginationInFlight"), QJSValue(true));
        set(root, QStringLiteral("timelinePaginationRoomId"), QJSValue(roomId));
        set(root, QStringLiteral("timelinePaginationRequestId"), requestId);
        set(root, QStringLiteral("timelinePaginationWasInitialFill"), QJSValue(initial));
        set(root, QStringLiteral("timelinePaginationStartItemCount"),
            QJSValue(length(root.property(QStringLiteral("timelineItems")))));
        const int count = initial
                && (boolean(callRoot(root, QStringLiteral("needsReadingPosition")))
                    || boolean(root.property(QStringLiteral("timelineCacheGapPending"))))
            ? 100 : 25;
        return sendCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("paginate_timeline_backwards"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("count"), QJSValue(count)},
            {QStringLiteral("session_epoch"), QJSValue(sessionEpoch)},
            {QStringLiteral("generation"), root.property(QStringLiteral("timelineGeneration"))}
        }));
    }

    if (operation == QStringLiteral("applyTimelineDiffs")) {
        const QJSValue message = first;
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (!message.isObject() || roomId != string(root.property(QStringLiteral("currentRoomId")))
            || !model.isObject()
            || qRound(number(message.property(QStringLiteral("session_epoch"))))
                != root.property(QStringLiteral("timelineSessionEpoch")).toInt()
            || qRound(number(message.property(QStringLiteral("generation"))))
                != root.property(QStringLiteral("timelineGeneration")).toInt())
            return undefined();
        const QString previousLatest = modelCount(model) > 0
            ? string(modelGet(model, 0).property(QStringLiteral("event_id"))) : QString();
        Values full = values(root.property(QStringLiteral("timelineItems")));
        for (const QJSValue &diff : values(message.property(QStringLiteral("diffs")))) {
            const QString op = string(diff.property(QStringLiteral("op")));
            const int at = qRound(number(diff.property(QStringLiteral("index"))));
            if (op == QStringLiteral("clear"))
                full.clear();
            else if (op == QStringLiteral("reset"))
                full = values(diff.property(QStringLiteral("items")));
            else if (op == QStringLiteral("append"))
                full.append(values(diff.property(QStringLiteral("items"))));
            else if (op == QStringLiteral("push_front"))
                full.prepend(diff.property(QStringLiteral("item")));
            else if (op == QStringLiteral("push_back"))
                full.append(diff.property(QStringLiteral("item")));
            else if (op == QStringLiteral("insert") && at >= 0 && at <= full.size())
                full.insert(at, diff.property(QStringLiteral("item")));
            else if (op == QStringLiteral("set") && at >= 0 && at < full.size())
                full[at] = diff.property(QStringLiteral("item"));
            else if (op == QStringLiteral("remove") && at >= 0 && at < full.size())
                full.removeAt(at);
            else if (op == QStringLiteral("pop_front") && !full.isEmpty())
                full.removeFirst();
            else if (op == QStringLiteral("pop_back") && !full.isEmpty())
                full.removeLast();
            else if (op == QStringLiteral("truncate"))
                full = full.mid(0, qMax(0, qRound(number(diff.property(QStringLiteral("length"))))));
        }
        const QJSValue fullArray = arrayFromValues(engine, full);
        set(root, QStringLiteral("timelineItems"), fullArray);
        const QJSValue all = rebuildVisibleTimeline(root, engine, true);
        signal(root, QStringLiteral("timelineMessagesUpdated"), {QJSValue(roomId), all});
        QJSValue visible = callRoot(root, QStringLiteral("reconcileMessageModel"), {
            callRoot(root, QStringLiteral("mergeTimelineHistory"),
                     {rebuildVisibleTimeline(root, engine, false)})
        });
        Values ids;
        for (int index = 0; index < full.size(); ++index) {
            QString id = string(full.at(index).property(QStringLiteral("timeline_item_id")));
            if (id.isEmpty())
                id = QStringLiteral("virtual:") + QString::number(index);
            ids.append(QJSValue(id));
        }
        set(root, QStringLiteral("timelineItemIds"), arrayFromValues(engine, ids));
        setMapValue(engine, root, QStringLiteral("roomMessageCache"), roomId,
                    cloneArray(engine, visible));
        setMapValue(engine, root, QStringLiteral("roomMessageCacheUpdatedAt"), roomId,
                    QJSValue(double(nowMs())));
        callRoot(root, QStringLiteral("touchMessageCacheRoom"), {QJSValue(roomId)});
        callRoot(root, QStringLiteral("trimMessageCache"), {QJSValue(roomId)});
        callRoot(root, QStringLiteral("refreshManualUnreadCount"), {QJSValue(roomId), visible});
        if (string(root.property(QStringLiteral("unreadBoundaryEventId"))).isEmpty()
            && !boolean(root.property(QStringLiteral("unreadBoundaryPending")))
            && !previousLatest.isEmpty()) {
            const Values messages = values(visible);
            for (int addedIndex = 1; addedIndex < messages.size(); ++addedIndex) {
                if (string(messages.at(addedIndex).property(QStringLiteral("event_id")))
                    != previousLatest)
                    continue;
                int unread = 0;
                QString boundary;
                for (int index = 0; index < addedIndex; ++index) {
                    if (isIncomingUnread(root, messages.at(index))) {
                        ++unread;
                        boundary = string(messages.at(index).property(QStringLiteral("event_id")));
                    }
                }
                if (unread > 0) {
                    set(root, QStringLiteral("unreadBoundaryEventId"), QJSValue(boundary));
                    set(root, QStringLiteral("openingUnreadCount"), QJSValue(unread));
                }
                break;
            }
        }
        callRoot(root, QStringLiteral("refreshTimelineReadState"), {visible});
        callRoot(root, QStringLiteral("updateReadingPositionReady"));
        callRoot(root, QStringLiteral("updateTimelineLoadingState"));
        if (boolean(root.property(QStringLiteral("timelineCacheGapPending")))
            && boolean(root.property(QStringLiteral("timelineHasMoreBackwards"))))
            set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(true));
        if (full.size() > root.property(QStringLiteral("timelinePaginationStartItemCount")).toInt())
            set(root, QStringLiteral("timelineInitialFillStalledPages"), QJSValue(0));
        if (boolean(root.property(QStringLiteral("timelineInitialFillActive")))
            && !boolean(root.property(QStringLiteral("timelinePaginationInFlight"))))
            call(root.property(QStringLiteral("timelineInitialFillTimerObject")),
                 QStringLiteral("restart"));
        return undefined();
    }

    if (operation == QStringLiteral("requestMessages")) {
        const QString roomId = string(first);
        const bool force = boolean(second);
        if (roomId.isEmpty())
            return undefined();
        if (!force && boolean(root.property(QStringLiteral("timelineDiffsSupported")))
            && string(root.property(QStringLiteral("displayedRoomId"))) == roomId
            && ((root.property(QStringLiteral("timelineGeneration")).toInt() > 0
                 && root.property(QStringLiteral("timelineSessionEpoch")).toInt()
                    == root.property(QStringLiteral("activeSessionEpoch")).toInt())
                || (root.property(QStringLiteral("timelineGeneration")).toInt() == 0
                    && !root.property(QStringLiteral("timelineRequestByRoom"))
                            .property(roomId).isUndefined())))
            return undefined();
        callRoot(root, QStringLiteral("adoptPendingRoomPrefetch"), {QJSValue(roomId)});
        const int initialUnread = callRoot(root, QStringLiteral("roomUnreadCount"),
                                           {QJSValue(roomId)}).toInt();
        const QJSValue resolver = root.property(QStringLiteral("readingPositionResolver"));
        const QJSValue restore = resolver.isCallable()
            ? resolver.call({QJSValue(roomId)}) : nullValue();
        set(root, QStringLiteral("readingRestorePosition"), restore);
        set(root, QStringLiteral("restoreEventId"), QJSValue(restore.isObject()
            ? string(restore.property(QStringLiteral("event_id"))) : QString()));
        const QString manual = string(callRoot(root, QStringLiteral("manualUnreadEventId"),
                                               {QJSValue(roomId)}));
        if (!manual.isEmpty()) {
            set(root, QStringLiteral("openingUnreadCount"),
                callRoot(root, QStringLiteral("manualUnreadCount"), {QJSValue(roomId)}));
            set(root, QStringLiteral("unreadBoundaryEventId"), QJSValue(manual));
            set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
        } else {
            set(root, QStringLiteral("openingUnreadCount"), QJSValue(initialUnread));
            set(root, QStringLiteral("unreadBoundaryEventId"), QJSValue(QString()));
            set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(initialUnread > 0));
        }
        set(root, QStringLiteral("timelineInitialMessageTarget"), QJSValue(qMax(
            root.property(QStringLiteral("initialRoomMessageCount")).toInt(),
            qMin(500, root.property(QStringLiteral("openingUnreadCount")).toInt() + 5))));
        if (boolean(callRoot(root, QStringLiteral("hasManualUnreadHold"), {QJSValue(roomId)}))
            && string(root.property(QStringLiteral("displayedRoomId"))) != roomId)
            callRoot(root, QStringLiteral("setManualUnreadHold"), {QJSValue(roomId), QJSValue(false)});
        if (boolean(callRoot(root, QStringLiteral("roomIsMarkedUnread"), {QJSValue(roomId)}))
            && !boolean(callRoot(root, QStringLiteral("hasManualUnreadHold"), {QJSValue(roomId)}))) {
            callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                     {QJSValue(roomId), QJSValue(false)});
            const QJSValue requestId = nextRequestId(root, QStringLiteral("marked-unread-open"));
            callRoot(root, QStringLiteral("trackReadStateRequest"), {QJSValue(roomId), requestId});
            sendCommand(root, objectFromProperties(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("set_room_marked_unread"))},
                {QStringLiteral("request_id"), requestId},
                {QStringLiteral("room_id"), QJSValue(roomId)},
                {QStringLiteral("unread"), QJSValue(false)}
            }));
        }
        const double sequence = number(root.property(QStringLiteral("timelineOpenSequence"))) + 1;
        set(root, QStringLiteral("timelineOpenSequence"), QJSValue(sequence));
        const QString previousRoom = string(root.property(QStringLiteral("displayedRoomId")));
        if (!previousRoom.isEmpty() && previousRoom != roomId) {
            callRoot(root, QStringLiteral("snapshotDisplayedRoom"));
            sendCommand(root, objectFromProperties(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("close_timeline"))},
                {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("timeline-close"))},
                {QStringLiteral("room_id"), QJSValue(previousRoom)},
                {QStringLiteral("request_generation"), QJSValue(sequence)}
            }));
            callRoot(root, QStringLiteral("takePendingCommand"), {
                root.property(QStringLiteral("timelineRequestByRoom")).property(previousRoom)
            });
            setMapValue(engine, root, QStringLiteral("timelineRequestByRoom"), previousRoom,
                        undefined(), true);
        }
        set(root, QStringLiteral("displayedContextEventId"), QJSValue(QString()));
        set(root, QStringLiteral("timelineInitialPositionReady"), QJSValue(false));
        set(root, QStringLiteral("displayedRoomId"), QJSValue(roomId));
        set(root, QStringLiteral("showingCachedTimeline"), QJSValue(false));
        set(root, QStringLiteral("timelineCacheGapPending"), QJSValue(false));
        call(root.property(QStringLiteral("timelineInitialFillTimerObject")), QStringLiteral("stop"));
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {root.property(QStringLiteral("timelinePaginationRequestId"))});
        set(root, QStringLiteral("timelinePaginationInFlight"), QJSValue(false));
        set(root, QStringLiteral("timelinePaginationRoomId"), QJSValue(QString()));
        set(root, QStringLiteral("timelinePaginationRequestId"), QJSValue(QString()));
        set(root, QStringLiteral("timelinePaginationWasInitialFill"), QJSValue(false));
        set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
        set(root, QStringLiteral("timelineInitialFillStalledPages"), QJSValue(0));
        set(root, QStringLiteral("timelineHasMoreBackwards"), QJSValue(false));
        set(root, QStringLiteral("timelineSessionEpoch"), QJSValue(0));
        set(root, QStringLiteral("timelineGeneration"), QJSValue(0));
        set(root, QStringLiteral("timelineItems"), array(engine));
        set(root, QStringLiteral("timelineItemIds"), array(engine));
        const QJSValue model = preparedModelForRoom(root, engine, roomId);
        set(root, QStringLiteral("messageModel"), model);
        const bool hasCache = modelCount(model) > 0;
        set(root, QStringLiteral("isLoadingMessages"), QJSValue(!hasCache));
        set(root, QStringLiteral("showEmptyState"), QJSValue(false));
        set(root, QStringLiteral("showingCachedTimeline"), QJSValue(hasCache));
        set(root, QStringLiteral("timelineInitialPositionReady"),
            QJSValue(hasCache && !boolean(callRoot(root, QStringLiteral("needsReadingPosition")))));
        if (hasCache)
            callRoot(root, QStringLiteral("touchMessageCacheRoom"), {QJSValue(roomId)});
        const QJSValue timelineRequest = nextRequestId(root, QStringLiteral("timeline"));
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {root.property(QStringLiteral("timelineRequestByRoom")).property(roomId)});
        setMapValue(engine, root, QStringLiteral("timelineRequestByRoom"), roomId,
                    timelineRequest);
        sendCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("open_timeline"))},
            {QStringLiteral("request_id"), timelineRequest},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("request_generation"), QJSValue(sequence)}
        }));
        return undefined();
    }

    return std::nullopt;
}

} // namespace FrontendMatrixLogic

#include "frontend_logic_matrix_internal.h"
#include <QJsonDocument>

using namespace FrontendLogicSupport;

namespace FrontendMatrixLogic {
namespace {

QJSValue collectionItem(const QJSValue &collection, int index)
{
    QJSValue item = collection.property(index);
    if (item.isUndefined() && collection.property(QStringLiteral("get")).isCallable())
        item = modelGet(collection, index);
    return item;
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

QJSValue roomReadSnapshot(const QJSValue &root,
                          QJSEngine *engine,
                          const QString &roomId)
{
    const QJSValue model = root.property(QStringLiteral("roomModel"));
    for (int index = 0; model.isObject() && index < modelCount(model); ++index) {
        const QJSValue room = modelGet(model, index);
        if (string(room.property(QStringLiteral("room_id"))) != roomId)
            continue;
        return objectFromProperties(engine, {
            {QStringLiteral("last_event_id"), QJSValue(string(room.property(QStringLiteral("last_event_id"))))},
            {QStringLiteral("last_timestamp"), QJSValue(number(room.property(QStringLiteral("last_timestamp"))))},
            {QStringLiteral("unread_count"), QJSValue(number(room.property(QStringLiteral("unread_count"))))},
            {QStringLiteral("is_marked_unread"), QJSValue(boolean(room.property(QStringLiteral("is_marked_unread"))))},
            {QStringLiteral("manual_event_id"), callRoot(root, QStringLiteral("manualUnreadEventId"), {QJSValue(roomId)})},
            {QStringLiteral("manual_count"), callRoot(root, QStringLiteral("manualUnreadCount"), {QJSValue(roomId)})}
        });
    }
    return objectFromProperties(engine, {
        {QStringLiteral("last_event_id"), QJSValue(QString())},
        {QStringLiteral("last_timestamp"), QJSValue(0)},
        {QStringLiteral("unread_count"), QJSValue(0)},
        {QStringLiteral("is_marked_unread"), QJSValue(false)},
        {QStringLiteral("manual_event_id"), QJSValue(QString())},
        {QStringLiteral("manual_count"), QJSValue(1)}
    });
}

void setRoomModelProperty(const QJSValue &root,
                          const QString &roomId,
                          const QString &property,
                          const QJSValue &value)
{
    const QJSValue model = root.property(QStringLiteral("roomModel"));
    if (!model.isObject() || roomId.isEmpty())
        return;
    for (int index = 0; index < modelCount(model); ++index) {
        if (string(modelGet(model, index).property(QStringLiteral("room_id"))) == roomId) {
            modelSetProperty(model, index, property, value);
            return;
        }
    }
}

} // namespace

Result invokeModelsAndState(const QString &operation,
                            const QJSValue &root,
                            const QJSValue &arguments)
{
    QJSEngine *engine = engineFor(root);
    const QJSValue first = argument(arguments, 0);
    const QJSValue second = argument(arguments, 1);
    const QJSValue third = argument(arguments, 2);
    const QJSValue fourth = argument(arguments, 3);
    const QJSValue fifth = argument(arguments, 4);

    if (operation == QStringLiteral("normalizeReactions")) {
        Values normalized;
        for (int index = 0; index < length(first); ++index) {
            const QJSValue source = collectionItem(first, index);
            const QString key = string(source.property(QStringLiteral("key")));
            if (!source.isObject() || key.isEmpty())
                continue;
            normalized.append(objectFromProperties(engine, {
                {QStringLiteral("key"), QJSValue(key)},
                {QStringLiteral("count"), QJSValue(qMax(0, qRound(number(source.property(QStringLiteral("count"))))))},
                {QStringLiteral("reacted"), QJSValue(boolean(source.property(QStringLiteral("reacted"))))},
                {QStringLiteral("own_event_id"), QJSValue(string(source.property(QStringLiteral("own_event_id"))))}
            }));
        }
        return arrayFromValues(engine, normalized);
    }

    if (operation == QStringLiteral("normalizeReadReceipts")) {
        Values normalized;
        for (int index = 0; index < length(first); ++index) {
            const QJSValue source = collectionItem(first, index);
            const QString userId = string(source.property(QStringLiteral("user_id")));
            if (!source.isObject() || userId.isEmpty())
                continue;
            normalized.append(objectFromProperties(engine, {
                {QStringLiteral("user_id"), QJSValue(userId)},
                {QStringLiteral("timestamp"), source.property(QStringLiteral("timestamp")).isUndefined()
                    || source.property(QStringLiteral("timestamp")).isNull()
                        ? QJSValue(0) : QJSValue(source.property(QStringLiteral("timestamp")).toNumber())}
            }));
        }
        return arrayFromValues(engine, normalized);
    }

    if (operation == QStringLiteral("normalizeMessage")) {
        const QJSValue item = first;
        const bool redacted = boolean(item.property(QStringLiteral("is_redacted")));
        const QString sender = string(item.property(QStringLiteral("sender")));
        const QJSValue localIgnore = root.property(QStringLiteral("ignoredUserIds")).property(sender);
        const bool senderIgnored = localIgnore.isUndefined()
            ? boolean(item.property(QStringLiteral("sender_is_ignored"))) : boolean(localIgnore);
        QString messageType = string(item.property(QStringLiteral("msg_type")));
        if (messageType.isEmpty())
            messageType = QStringLiteral("m.text");
        QString sendState = string(item.property(QStringLiteral("send_state")));
        if (sendState.isEmpty())
            sendState = boolean(item.property(QStringLiteral("is_optimistic")))
                ? QStringLiteral("sending") : QStringLiteral("sent");
        QJSValue mentioned = item.property(QStringLiteral("mentioned_user_ids"));
        if (!mentioned.isObject())
            mentioned = array(engine);
        return objectFromProperties(engine, {
            {QStringLiteral("event_id"), QJSValue(string(item.property(QStringLiteral("event_id"))))},
            {QStringLiteral("replaces_event_id"), QJSValue(string(item.property(QStringLiteral("replaces_event_id"))))},
            {QStringLiteral("sender"), QJSValue(sender)},
            {QStringLiteral("sender_avatar_url"), QJSValue(string(item.property(QStringLiteral("sender_avatar_url"))))},
            {QStringLiteral("sender_display_name"), QJSValue(string(item.property(QStringLiteral("sender_display_name"))))},
            {QStringLiteral("sender_is_ignored"), QJSValue(senderIgnored)},
            {QStringLiteral("body"), QJSValue(string(item.property(QStringLiteral("body"))))},
            {QStringLiteral("msg_type"), QJSValue(messageType)},
            {QStringLiteral("mentioned_user_ids"), mentioned},
            {QStringLiteral("mentions_room"), QJSValue(boolean(item.property(QStringLiteral("mentions_room"))))},
            {QStringLiteral("timestamp"), QJSValue(number(item.property(QStringLiteral("timestamp"))))},
            {QStringLiteral("reply_to"), QJSValue(string(item.property(QStringLiteral("reply_to"))))},
            {QStringLiteral("reply_sender"), QJSValue(string(item.property(QStringLiteral("reply_sender"))))},
            {QStringLiteral("reply_body"), QJSValue(string(item.property(QStringLiteral("reply_body"))))},
            {QStringLiteral("thread_root_id"), QJSValue(string(item.property(QStringLiteral("thread_root_id"))))},
            {QStringLiteral("thread_reply_count"), QJSValue(number(item.property(QStringLiteral("thread_reply_count"))))},
            {QStringLiteral("hidden_reply_body"), QJSValue(string(item.property(QStringLiteral("hidden_reply_body"))))},
            {QStringLiteral("media_url"), QJSValue(string(item.property(QStringLiteral("media_url"))))},
            {QStringLiteral("media_file"), item.property(QStringLiteral("media_file")).isObject()
                ? item.property(QStringLiteral("media_file")) : nullValue()},
            {QStringLiteral("media_mime_type"), QJSValue(string(item.property(QStringLiteral("media_mime_type"))))},
            {QStringLiteral("sticker_pack"), item.property(QStringLiteral("sticker_pack")).isObject()
                ? item.property(QStringLiteral("sticker_pack")) : nullValue()},
            {QStringLiteral("is_system"), QJSValue(boolean(item.property(QStringLiteral("is_system"))))},
            {QStringLiteral("system_kind"), QJSValue(string(item.property(QStringLiteral("system_kind"))))},
            {QStringLiteral("is_edited"), QJSValue(boolean(item.property(QStringLiteral("is_edited"))))},
            {QStringLiteral("is_redacted"), QJSValue(redacted)},
            {QStringLiteral("is_encrypted"), QJSValue(!redacted
                && boolean(item.property(QStringLiteral("is_encrypted"))))},
            {QStringLiteral("timeline_item_id"), QJSValue(string(item.property(QStringLiteral("timeline_item_id"))))},
            {QStringLiteral("send_state"), QJSValue(sendState)},
            {QStringLiteral("send_error"), QJSValue(string(item.property(QStringLiteral("send_error"))))},
            {QStringLiteral("send_recoverable"), QJSValue(boolean(item.property(QStringLiteral("send_recoverable"))))},
            {QStringLiteral("is_optimistic"), QJSValue(boolean(item.property(QStringLiteral("is_optimistic"))))},
            {QStringLiteral("reactions"), callRoot(root, QStringLiteral("normalizeReactions"),
                {item.property(QStringLiteral("reactions"))})},
            {QStringLiteral("read_receipts"), callRoot(root, QStringLiteral("normalizeReadReceipts"),
                {item.property(QStringLiteral("read_receipts"))})}
        });
    }

    if (operation == QStringLiteral("applyUserProfileChanged")) {
        const QString roomId = string(first);
        const QString userId = string(second);
        const QString displayName = string(third);
        const QString avatarUrl = string(fourth);
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("roomMessageCache")));
        for (const QString &cachedRoomId : objectKeys(cache)) {
            if (!roomId.isEmpty() && cachedRoomId != roomId)
                continue;
            QJSValue messages = cache.property(cachedRoomId);
            for (int index = 0; index < length(messages); ++index) {
                QJSValue message = messages.property(index);
                if (string(message.property(QStringLiteral("sender"))) == userId) {
                    message.setProperty(QStringLiteral("sender_display_name"), QJSValue(displayName));
                    message.setProperty(QStringLiteral("sender_avatar_url"), QJSValue(avatarUrl));
                }
            }
        }
        set(root, QStringLiteral("roomMessageCache"), cache);
        const QJSValue prepared = root.property(QStringLiteral("preparedRoomModels"));
        for (const QString &preparedId : objectKeys(prepared))
            callRoot(root, QStringLiteral("discardPreparedRoom"), {QJSValue(preparedId)});
        callLater(root, QStringLiteral("scheduleRoomPreviewPrefetch"));
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (model.isObject()
            && (roomId.isEmpty()
                || roomId == string(root.property(QStringLiteral("currentRoomId"))))) {
            for (int index = 0; index < modelCount(model); ++index) {
                if (string(modelGet(model, index).property(QStringLiteral("sender"))) == userId) {
                    modelSetProperty(model, index, QStringLiteral("sender_display_name"),
                                     QJSValue(displayName));
                    modelSetProperty(model, index, QStringLiteral("sender_avatar_url"),
                                     QJSValue(avatarUrl));
                }
            }
        }
        signal(root, QStringLiteral("userProfileChanged"),
               {QJSValue(roomId), QJSValue(userId), QJSValue(displayName), QJSValue(avatarUrl)});
        return undefined();
    }

    if (operation == QStringLiteral("applyUserIgnored")) {
        const QString userId = string(first);
        const bool ignored = boolean(second);
        if (userId.isEmpty())
            return undefined();
        setMapValue(engine, root, QStringLiteral("ignoredUserIds"), userId,
                    QJSValue(ignored));
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("roomMessageCache")));
        for (const QString &roomId : objectKeys(cache)) {
            QJSValue messages = cache.property(roomId);
            for (int index = 0; index < length(messages); ++index) {
                QJSValue message = messages.property(index);
                if (string(message.property(QStringLiteral("sender"))) == userId)
                    message.setProperty(QStringLiteral("sender_is_ignored"), QJSValue(ignored));
                if (string(message.property(QStringLiteral("reply_sender"))) != userId)
                    continue;
                const QString hidden = string(message.property(QStringLiteral("hidden_reply_body")));
                if (ignored) {
                    if (hidden.isEmpty())
                        message.setProperty(QStringLiteral("hidden_reply_body"),
                                            message.property(QStringLiteral("reply_body")));
                    message.setProperty(QStringLiteral("reply_body"), QJSValue(QString()));
                } else if (!hidden.isEmpty()) {
                    message.setProperty(QStringLiteral("reply_body"), QJSValue(hidden));
                    message.setProperty(QStringLiteral("hidden_reply_body"), QJSValue(QString()));
                }
            }
        }
        set(root, QStringLiteral("roomMessageCache"), cache);
        for (const QString &preparedId : objectKeys(root.property(QStringLiteral("preparedRoomModels"))))
            callRoot(root, QStringLiteral("discardPreparedRoom"), {QJSValue(preparedId)});
        callLater(root, QStringLiteral("scheduleRoomPreviewPrefetch"));
        const QJSValue model = root.property(QStringLiteral("messageModel"));
        if (!model.isObject())
            return undefined();
        for (int index = 0; index < modelCount(model); ++index) {
            const QJSValue message = modelGet(model, index);
            if (string(message.property(QStringLiteral("sender"))) == userId)
                modelSetProperty(model, index, QStringLiteral("sender_is_ignored"), QJSValue(ignored));
            if (string(message.property(QStringLiteral("reply_sender"))) != userId)
                continue;
            const QString hidden = string(message.property(QStringLiteral("hidden_reply_body")));
            if (ignored) {
                if (hidden.isEmpty())
                    modelSetProperty(model, index, QStringLiteral("hidden_reply_body"),
                                     message.property(QStringLiteral("reply_body")));
                modelSetProperty(model, index, QStringLiteral("reply_body"), QJSValue(QString()));
            } else if (!hidden.isEmpty()) {
                modelSetProperty(model, index, QStringLiteral("reply_body"), QJSValue(hidden));
                modelSetProperty(model, index, QStringLiteral("hidden_reply_body"), QJSValue(QString()));
            }
        }
        return undefined();
    }

    if (operation == QStringLiteral("applyCanonicalIdentity")) {
        const QJSValue details = first;
        if (!details.isObject()
            || !boolean(details.property(QStringLiteral("is_self")))
            || boolean(details.property(QStringLiteral("room_member"))))
            return undefined();
        const QString authenticated = string(root.property(QStringLiteral("authenticatedUserId")));
        if (authenticated.isEmpty()
            || string(details.property(QStringLiteral("user_id"))) != authenticated)
            return undefined();
        QString displayName = string(details.property(QStringLiteral("global_display_name")));
        if (displayName.isEmpty())
            displayName = string(details.property(QStringLiteral("display_name")));
        if (displayName.isEmpty())
            displayName = authenticated;
        QString avatar = string(details.property(QStringLiteral("global_avatar_url")));
        if (avatar.isEmpty())
            avatar = string(details.property(QStringLiteral("avatar_url")));
        Values profiles = values(root.property(QStringLiteral("profiles")));
        const QString active = string(root.property(QStringLiteral("activeProfileId")));
        for (int index = 0; index < profiles.size(); ++index) {
            if (string(profiles.at(index).property(QStringLiteral("profile_id"))) != active)
                continue;
            profiles[index] = mergeObjects(engine, profiles.at(index), {
                {QStringLiteral("display_name"), QJSValue(displayName)},
                {QStringLiteral("avatar_url"), QJSValue(avatar)}
            });
            break;
        }
        const QJSValue updated = arrayFromValues(engine, profiles);
        set(root, QStringLiteral("profiles"), updated);
        signal(root, QStringLiteral("profilesUpdated"), {updated, QJSValue(active)});
        callRoot(root, QStringLiteral("applyUserProfileChanged"), {
            QJSValue(QString()), QJSValue(authenticated), QJSValue(displayName), QJSValue(avatar)
        });
        return undefined();
    }

    if (operation == QStringLiteral("roomIsPinned"))
        return QJSValue(indexOfString(root.property(QStringLiteral("pinnedRoomIds")), string(first)) >= 0);
    if (operation == QStringLiteral("pinnedRoomPosition"))
        return QJSValue(indexOfString(root.property(QStringLiteral("pinnedRoomIds")), string(first)));

    if (operation == QStringLiteral("applyRoomOrder")) {
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        if (!model.isObject())
            return undefined();
        int destination = 0;
        for (const QJSValue &pinned : values(root.property(QStringLiteral("pinnedRoomIds")))) {
            const QString roomId = string(pinned);
            for (int index = destination; index < modelCount(model); ++index) {
                if (string(modelGet(model, index).property(QStringLiteral("room_id"))) != roomId)
                    continue;
                if (index != destination)
                    call(model, QStringLiteral("move"),
                         {QJSValue(index), QJSValue(destination), QJSValue(1)});
                ++destination;
                break;
            }
        }
        return undefined();
    }

    if (operation == QStringLiteral("normalizeRoom")) {
        const QJSValue item = first;
        QStringList parentIds;
        for (const QJSValue &parent : values(item.property(QStringLiteral("parent_space_ids"))))
            parentIds.append(string(parent));
        const bool ignored = boolean(item.property(QStringLiteral("is_ignored")));
        QString roomState = string(item.property(QStringLiteral("room_state")));
        if (roomState.isEmpty())
            roomState = QStringLiteral("joined");
        return objectFromProperties(engine, {
            {QStringLiteral("room_id"), QJSValue(string(item.property(QStringLiteral("room_id"))))},
            {QStringLiteral("name"), QJSValue(string(item.property(QStringLiteral("name"))))},
            {QStringLiteral("avatar_url"), QJSValue(string(item.property(QStringLiteral("avatar_url"))))},
            {QStringLiteral("topic"), QJSValue(string(item.property(QStringLiteral("topic"))))},
            {QStringLiteral("last_message"), QJSValue(string(item.property(QStringLiteral("last_message"))))},
            {QStringLiteral("last_timestamp"), QJSValue(number(item.property(QStringLiteral("last_timestamp"))))},
            {QStringLiteral("last_event_id"), QJSValue(string(item.property(QStringLiteral("last_event_id"))))},
            {QStringLiteral("unread_count"), QJSValue(ignored ? 0
                : qRound(number(item.property(QStringLiteral("unread_count")))))},
            {QStringLiteral("is_marked_unread"), QJSValue(!ignored
                && boolean(item.property(QStringLiteral("is_marked_unread"))))},
            {QStringLiteral("member_count"), QJSValue(number(item.property(QStringLiteral("member_count"))))},
            {QStringLiteral("is_dm"), QJSValue(boolean(item.property(QStringLiteral("is_dm"))))},
            {QStringLiteral("direct_user_id"), QJSValue(string(item.property(QStringLiteral("direct_user_id"))))},
            {QStringLiteral("is_ignored"), QJSValue(ignored)},
            {QStringLiteral("is_space"), QJSValue(boolean(item.property(QStringLiteral("is_space"))))},
            {QStringLiteral("is_voice"), QJSValue(boolean(item.property(QStringLiteral("is_voice"))))},
            {QStringLiteral("voice_members_json"), QJSValue(QString::fromUtf8(QJsonDocument::fromVariant(
                item.property(QStringLiteral("voice_members")).toVariant()).toJson(QJsonDocument::Compact)))},
            {QStringLiteral("parent_space_key"), QJSValue(parentIds.join(QChar(0x1f)))},
            {QStringLiteral("is_encrypted"), QJSValue(boolean(item.property(QStringLiteral("is_encrypted"))))},
            {QStringLiteral("room_state"), QJSValue(roomState)},
            {QStringLiteral("can_edit"), QJSValue(boolean(item.property(QStringLiteral("can_edit"))))},
            {QStringLiteral("is_invited"), QJSValue(roomState == QStringLiteral("invited"))}
        });
    }

    if (operation == QStringLiteral("setRoomUnreadCount")) {
        setRoomModelProperty(root, string(first), QStringLiteral("unread_count"), second);
        return undefined();
    }
    if (operation == QStringLiteral("roomUnreadCount")) {
        const QString roomId = string(first);
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        for (int index = 0; model.isObject() && index < modelCount(model); ++index) {
            const QJSValue room = modelGet(model, index);
            if (string(room.property(QStringLiteral("room_id"))) == roomId)
                return QJSValue(qMax(0, qRound(number(room.property(QStringLiteral("unread_count"))))));
        }
        return QJSValue(0);
    }
    if (operation == QStringLiteral("manualUnreadCount"))
        return QJSValue(qMax(1, qRound(number(root.property(QStringLiteral("manualUnreadCounts"))
                                              .property(string(first)), 1))));

    if (operation == QStringLiteral("setManualUnreadDetails")) {
        const QString roomId = string(first);
        const QString eventId = string(second);
        if (roomId.isEmpty())
            return undefined();
        setMapValue(engine, root, QStringLiteral("manualUnreadEventIds"), roomId,
                    QJSValue(eventId), eventId.isEmpty());
        setMapValue(engine, root, QStringLiteral("manualUnreadCounts"), roomId,
                    QJSValue(qMax(1, qRound(number(third, 1)))), eventId.isEmpty());
        return undefined();
    }
    if (operation == QStringLiteral("manualUnreadEventId"))
        return QJSValue(string(first).isEmpty() ? QString()
            : string(root.property(QStringLiteral("manualUnreadEventIds")).property(string(first))));

    if (operation == QStringLiteral("refreshManualUnreadCount")) {
        const QString roomId = string(first);
        if (!boolean(callRoot(root, QStringLiteral("hasManualUnreadHold"), {QJSValue(roomId)})))
            return undefined();
        const QString boundary = string(callRoot(root, QStringLiteral("manualUnreadEventId"),
                                                 {QJSValue(roomId)}));
        if (boundary.isEmpty() || !second.isObject())
            return undefined();
        for (int index = 0; index < length(second); ++index) {
            if (string(second.property(index).property(QStringLiteral("event_id"))) == boundary) {
                const int count = index + 1;
                callRoot(root, QStringLiteral("setManualUnreadDetails"),
                         {QJSValue(roomId), QJSValue(boundary), QJSValue(count)});
                callRoot(root, QStringLiteral("setRoomUnreadCount"),
                         {QJSValue(roomId), QJSValue(count)});
                break;
            }
        }
        return undefined();
    }

    if (operation == QStringLiteral("roomIsMarkedUnread")) {
        const QString roomId = string(first);
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        for (int index = 0; model.isObject() && index < modelCount(model); ++index) {
            const QJSValue room = modelGet(model, index);
            if (string(room.property(QStringLiteral("room_id"))) == roomId)
                return QJSValue(boolean(room.property(QStringLiteral("is_marked_unread"))));
        }
        return QJSValue(false);
    }
    if (operation == QStringLiteral("setRoomMarkedUnreadLocal")) {
        setRoomModelProperty(root, string(first), QStringLiteral("is_marked_unread"),
                             QJSValue(boolean(second)));
        return undefined();
    }
    if (operation == QStringLiteral("newestReadableEventId")) {
        for (const QJSValue &message : values(first)) {
            const QString eventId = string(message.property(QStringLiteral("event_id")));
            if (!eventId.isEmpty() && !eventId.startsWith(QStringLiteral("local:")))
                return QJSValue(eventId);
        }
        return QJSValue(QString());
    }
    if (operation == QStringLiteral("hasManualUnreadHold")) {
        const QString roomId = string(first);
        return QJSValue(!roomId.isEmpty()
            && boolean(root.property(QStringLiteral("manualUnreadHolds")).property(roomId)));
    }
    if (operation == QStringLiteral("setManualUnreadHold")) {
        const QString roomId = string(first);
        if (!roomId.isEmpty())
            setMapValue(engine, root, QStringLiteral("manualUnreadHolds"), roomId,
                        QJSValue(true), !boolean(second));
        return undefined();
    }
    if (operation == QStringLiteral("roomReadSnapshot"))
        return roomReadSnapshot(root, engine, string(first));
    if (operation == QStringLiteral("clearPendingRoomRead")) {
        setMapValue(engine, root, QStringLiteral("pendingReadByRoom"), string(first),
                    undefined(), true);
        return undefined();
    }
    if (operation == QStringLiteral("trackReadStateRequest")) {
        setMapValue(engine, root, QStringLiteral("readStateRequestByRoom"), string(first),
                    second, false);
        return undefined();
    }

    if (operation == QStringLiteral("reconcilePendingRoomRead")) {
        QJSValue room = first;
        const QString roomId = string(room.property(QStringLiteral("room_id")));
        const QJSValue pending = root.property(QStringLiteral("pendingReadByRoom")).property(roomId);
        if (!pending.isObject())
            return undefined();
        const QJSValue before = pending.property(QStringLiteral("before"));
        const QString roomEvent = string(room.property(QStringLiteral("last_event_id")));
        const QString previousEvent = string(before.property(QStringLiteral("last_event_id")));
        const bool changedEvent = !roomEvent.isEmpty() && !previousEvent.isEmpty()
            ? roomEvent != previousEvent
            : number(room.property(QStringLiteral("last_timestamp")))
                > number(before.property(QStringLiteral("last_timestamp")));
        const bool acknowledged = boolean(pending.property(QStringLiteral("acknowledged")));
        const bool settled = acknowledged
            && ((number(room.property(QStringLiteral("unread_count")))
                    <= number(pending.property(QStringLiteral("remaining")))
                 && !boolean(room.property(QStringLiteral("is_marked_unread"))))
                || nowMs() >= qint64(number(pending.property(QStringLiteral("deadline")))));
        if (changedEvent || settled) {
            callRoot(root, QStringLiteral("clearPendingRoomRead"), {QJSValue(roomId)});
            return undefined();
        }
        room.setProperty(QStringLiteral("unread_count"), QJSValue(qMin(
            number(room.property(QStringLiteral("unread_count"))),
            number(pending.property(QStringLiteral("remaining"))))));
        room.setProperty(QStringLiteral("is_marked_unread"), QJSValue(false));
        return undefined();
    }

    if (operation == QStringLiteral("finishRoomRead")) {
        const QString roomId = string(first);
        const QString requestId = string(second);
        const QJSValue current = root.property(QStringLiteral("pendingReadByRoom"));
        const QJSValue pending = current.property(roomId);
        if (!pending.isObject()
            || string(pending.property(QStringLiteral("request_id"))) != requestId)
            return undefined();
        if (boolean(third)) {
            QJSValue before = cloneObject(engine, pending.property(QStringLiteral("before")));
            before.setProperty(QStringLiteral("unread_count"), QJSValue(qMin(
                number(before.property(QStringLiteral("unread_count"))),
                number(pending.property(QStringLiteral("sentRemaining"))))));
            before.setProperty(QStringLiteral("is_marked_unread"), QJSValue(false));
            before.setProperty(QStringLiteral("manual_event_id"), QJSValue(QString()));
            before.setProperty(QStringLiteral("manual_count"), QJSValue(1));
            QJSValue updated = mergeObjects(engine, pending, {
                {QStringLiteral("before"), before},
                {QStringLiteral("acknowledged"), QJSValue(true)},
                {QStringLiteral("deadline"), QJSValue(double(nowMs()
                    + root.property(QStringLiteral("defaultCommandTimeoutMs")).toInt()))}
            });
            setMapValue(engine, root, QStringLiteral("pendingReadByRoom"), roomId,
                        updated, false);
        } else {
            callRoot(root, QStringLiteral("clearPendingRoomRead"), {QJSValue(roomId)});
            const QJSValue before = pending.property(QStringLiteral("before"));
            callRoot(root, QStringLiteral("setRoomUnreadCount"),
                     {QJSValue(roomId), before.property(QStringLiteral("unread_count"))});
            callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                     {QJSValue(roomId), before.property(QStringLiteral("is_marked_unread"))});
            callRoot(root, QStringLiteral("setManualUnreadHold"),
                     {QJSValue(roomId), before.property(QStringLiteral("is_marked_unread"))});
            callRoot(root, QStringLiteral("setManualUnreadDetails"), {
                QJSValue(roomId), before.property(QStringLiteral("manual_event_id")),
                before.property(QStringLiteral("manual_count"))
            });
        }
        return undefined();
    }

    if (operation == QStringLiteral("markVisibleMessagesRead")) {
        const QString roomId = string(first);
        if (roomId == string(root.property(QStringLiteral("currentRoomId")))
            && roomId == string(root.property(QStringLiteral("displayedRoomId")))
            && boolean(root.property(QStringLiteral("timelineInitialPositionReady")))
            && !boolean(root.property(QStringLiteral("showingCachedTimeline")))
            && !boolean(root.property(QStringLiteral("unreadBoundaryPending")))) {
            callRoot(root, QStringLiteral("markRoomRead"),
                     {QJSValue(roomId), second, QJSValue(false), third});
        }
        return undefined();
    }

    if (operation == QStringLiteral("flushQueuedRoomRead")) {
        const QString roomId = string(first);
        const QJSValue queued = root.property(QStringLiteral("queuedRoomReads")).property(roomId);
        if (!queued.isObject())
            return undefined();
        setMapValue(engine, root, QStringLiteral("queuedRoomReads"), roomId,
                    undefined(), true);
        callRoot(root, QStringLiteral("markRoomRead"), {
            QJSValue(roomId), queued.property(QStringLiteral("event_id")),
            queued.property(QStringLiteral("explicitAction")),
            queued.property(QStringLiteral("remaining"))
        });
        return undefined();
    }

    if (operation == QStringLiteral("markRoomRead")) {
        const QString roomId = string(first);
        const QString eventId = string(second);
        const bool explicitAction = boolean(third);
        if (roomId.isEmpty())
            return undefined();
        if (boolean(callRoot(root, QStringLiteral("hasManualUnreadHold"), {QJSValue(roomId)}))
            && string(root.property(QStringLiteral("displayedRoomId"))) == roomId) {
            if (explicitAction)
                callRoot(root, QStringLiteral("setManualUnreadHold"),
                         {QJSValue(roomId), QJSValue(false)});
            else {
                callRoot(root, QStringLiteral("setRoomUnreadCount"),
                         {QJSValue(roomId), callRoot(root, QStringLiteral("manualUnreadCount"),
                                                    {QJSValue(roomId)})});
                return undefined();
            }
        }
        if (!explicitAction
            && (eventId.isEmpty() || eventId.startsWith(QStringLiteral("local:"))))
            return undefined();
        const QString previousRead = string(root.property(QStringLiteral("lastReadEventByRoom"))
                                                .property(roomId));
        if (!explicitAction
            && roomId == string(root.property(QStringLiteral("displayedRoomId")))
            && !previousRead.isEmpty()) {
            int previousIndex = -1;
            int nextIndex = -1;
            const QJSValue model = root.property(QStringLiteral("messageModel"));
            for (int index = 0; model.isObject() && index < modelCount(model); ++index) {
                const QString id = string(modelGet(model, index).property(QStringLiteral("event_id")));
                if (id == previousRead)
                    previousIndex = index;
                if (id == eventId)
                    nextIndex = index;
                if (previousIndex >= 0 && nextIndex >= 0)
                    break;
            }
            if (previousIndex >= 0 && nextIndex >= previousIndex)
                return undefined();
        }
        const QString stateRequest = string(root.property(QStringLiteral("readStateRequestByRoom"))
                                                .property(roomId));
        const QJSValue inFlight = root.property(QStringLiteral("pendingCommands"))
            .property(stateRequest);
        if (inFlight.isObject()
            && string(inFlight.property(QStringLiteral("type"))) == QStringLiteral("mark_room_read")) {
            const QString inFlightEvent = string(inFlight.property(QStringLiteral("event_id")));
            if (inFlightEvent.isEmpty() || (!explicitAction && inFlightEvent == eventId))
                return undefined();
            QJSValue queuedMap = cloneObject(engine, root.property(QStringLiteral("queuedRoomReads")));
            const QJSValue queuedCurrent = queuedMap.property(roomId);
            if (!queuedCurrent.isObject()
                || !boolean(queuedCurrent.property(QStringLiteral("explicitAction")))) {
                queuedMap.setProperty(roomId, objectFromProperties(engine, {
                    {QStringLiteral("event_id"), QJSValue(eventId)},
                    {QStringLiteral("explicitAction"), QJSValue(explicitAction)},
                    {QStringLiteral("remaining"), QJSValue(explicitAction ? 0
                        : qMax(0, qRound(number(fourth))))}
                }));
            }
            set(root, QStringLiteral("queuedRoomReads"), queuedMap);
            const QJSValue queued = queuedMap.property(roomId);
            QJSValue optimistic = cloneObject(engine, root.property(QStringLiteral("pendingReadByRoom")));
            if (optimistic.property(roomId).isObject())
                optimistic.setProperty(roomId, mergeObjects(engine, optimistic.property(roomId),
                    {{QStringLiteral("remaining"), queued.property(QStringLiteral("remaining"))}}));
            set(root, QStringLiteral("pendingReadByRoom"), optimistic);
            callRoot(root, QStringLiteral("setRoomUnreadCount"),
                     {QJSValue(roomId), queued.property(QStringLiteral("remaining"))});
            return undefined();
        }
        QString preference = string(root.property(QStringLiteral("roomReadReceiptOverrides"))
                                        .property(roomId));
        if (preference.isEmpty())
            preference = QStringLiteral("inherit");
        const bool publicReceipt = preference != QStringLiteral("off")
            && (preference != QStringLiteral("inherit")
                || boolean(root.property(QStringLiteral("readReceiptsEnabled"))));
        if (!explicitAction && previousRead == eventId)
            return undefined();
        const QJSValue currentPending = root.property(QStringLiteral("pendingReadByRoom"))
            .property(roomId);
        const QJSValue before = currentPending.isObject()
            ? currentPending.property(QStringLiteral("before"))
            : roomReadSnapshot(root, engine, roomId);
        const QJSValue requestId = nextRequestId(root, QStringLiteral("read"));
        const int remaining = explicitAction ? 0 : qMax(0, qRound(number(fourth)));
        const QJSValue pending = objectFromProperties(engine, {
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("before"), before},
            {QStringLiteral("acknowledged"), QJSValue(false)},
            {QStringLiteral("remaining"), QJSValue(remaining)},
            {QStringLiteral("sentRemaining"), QJSValue(remaining)}
        });
        setMapValue(engine, root, QStringLiteral("pendingReadByRoom"), roomId, pending);
        callRoot(root, QStringLiteral("trackReadStateRequest"), {QJSValue(roomId), requestId});
        callRoot(root, QStringLiteral("setManualUnreadHold"), {QJSValue(roomId), QJSValue(false)});
        callRoot(root, QStringLiteral("setManualUnreadDetails"),
                 {QJSValue(roomId), QJSValue(QString()), QJSValue(0)});
        callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                 {QJSValue(roomId), QJSValue(false)});
        callRoot(root, QStringLiteral("setRoomUnreadCount"),
                 {QJSValue(roomId), QJSValue(remaining)});
        setMapValue(engine, root, QStringLiteral("lastReadEventByRoom"), roomId,
                    QJSValue(eventId));
        QJSValue value = objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("mark_room_read"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("public_receipt"), QJSValue(publicReceipt)}
        });
        if (!explicitAction)
            value.setProperty(QStringLiteral("event_id"), QJSValue(eventId));
        sendCommand(root, value);
        return undefined();
    }

    if (operation == QStringLiteral("setRoomReadState")) {
        const QString roomId = string(first);
        const bool unread = boolean(second);
        if (roomId.isEmpty())
            return undefined();
        if (unread) {
            setMapValue(engine, root, QStringLiteral("queuedRoomReads"), roomId,
                        undefined(), true);
            callRoot(root, QStringLiteral("clearPendingRoomRead"), {QJSValue(roomId)});
            callRoot(root, QStringLiteral("setManualUnreadHold"),
                     {QJSValue(roomId), QJSValue(true)});
            callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                     {QJSValue(roomId), QJSValue(true)});
            const QString eventId = string(third);
            const int count = qMax(1, qRound(number(fourth, 1)));
            callRoot(root, QStringLiteral("setManualUnreadDetails"),
                     {QJSValue(roomId), QJSValue(eventId), QJSValue(count)});
            callRoot(root, QStringLiteral("setRoomUnreadCount"),
                     {QJSValue(roomId), QJSValue(count)});
            if (roomId == string(root.property(QStringLiteral("currentRoomId")))
                && !eventId.isEmpty()) {
                set(root, QStringLiteral("unreadBoundaryEventId"), QJSValue(eventId));
                set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
                set(root, QStringLiteral("openingUnreadCount"), QJSValue(count));
            }
        } else {
            if (roomId == string(root.property(QStringLiteral("currentRoomId")))) {
                set(root, QStringLiteral("unreadBoundaryEventId"), QJSValue(QString()));
                set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
                set(root, QStringLiteral("openingUnreadCount"), QJSValue(0));
            }
            QJSValue messages = array(engine);
            if (boolean(callRoot(root, QStringLiteral("hasCachedRoom"), {QJSValue(roomId)})))
                messages = root.property(QStringLiteral("roomMessageCache")).property(roomId);
            callRoot(root, QStringLiteral("markRoomRead"), {
                QJSValue(roomId),
                callRoot(root, QStringLiteral("newestReadableEventId"), {messages}),
                QJSValue(true)
            });
            return undefined();
        }
        const QJSValue requestId = nextRequestId(root, QStringLiteral("marked-unread"));
        callRoot(root, QStringLiteral("trackReadStateRequest"), {QJSValue(roomId), requestId});
        sendCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("set_room_marked_unread"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("unread"), QJSValue(unread)}
        }));
        return undefined();
    }

    return std::nullopt;
}

} // namespace FrontendMatrixLogic

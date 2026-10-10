#include "frontend_logic.h"

#include "frontend_logic_support.h"

#include <QJsonDocument>
#include <QRegularExpression>

#include <limits>

using namespace FrontendLogicSupport;

namespace {

QByteArray stableJson(const QJSValue &value)
{
    return QJsonDocument::fromVariant(value.toVariant()).toJson(QJsonDocument::Compact);
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
        {QStringLiteral("flv"), QStringLiteral("video/x-flv")}
    };
    return mimeTypes.value(filename.section(QLatin1Char('.'), -1).toLower(),
                           QStringLiteral("application/octet-stream"));
}

QJSValue newCategory(const QJSValue &root)
{
    return callRoot(root, QStringLiteral("newCategory"));
}

QJSValue newRoomValue(QJSEngine *engine, const QJSValue &root)
{
    QJSValue states = array(engine, 4);
    for (int index = 0; index < 4; ++index)
        states.setProperty(index, newCategory(root));
    QJSValue room = object(engine);
    room.setProperty(QStringLiteral("items"), array(engine));
    room.setProperty(QStringLiteral("states"), states);
    room.setProperty(QStringLiteral("category"), QJSValue(0));
    room.setProperty(QStringLiteral("touched"), QJSValue(double(nowMs())));
    return room;
}

bool matchesCategory(const QJSValue &root, const QJSValue &item, int category)
{
    const QString messageType = string(item.property(QStringLiteral("msg_type")));
    if (messageType == QStringLiteral("m.sticker"))
        return false;
    const bool video = boolean(callRoot(root, QStringLiteral("isVideoItem"), {item}));
    if (category == 0)
        return messageType == QStringLiteral("m.image") || video;
    if (category == 1)
        return messageType == QStringLiteral("m.text")
            && !string(callRoot(root, QStringLiteral("firstLink"),
                                {item.property(QStringLiteral("body"))})).isEmpty();
    if (category == 2)
        return messageType == QStringLiteral("m.file") && !video;
    return messageType == QStringLiteral("m.audio");
}

} // namespace

QJSValue FrontendLogic::invokeAttachments(const QString &operation,
                                          const QJSValue &root,
                                          const QJSValue &arguments)
{
    QJSEngine *engine = engineFor(root);
    const QJSValue first = argument(arguments, 0);
    const QJSValue second = argument(arguments, 1);
    const QJSValue third = argument(arguments, 2);
    const QJSValue fourth = argument(arguments, 3);
    const QJSValue fifth = argument(arguments, 4);

    if (operation == QStringLiteral("newRoom"))
        return newRoomValue(engine, root);

    if (operation == QStringLiteral("saveRoom")) {
        const QString roomId = string(first);
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("roomCache")));
        QJSValue value = cloneObject(engine, second);
        value.setProperty(QStringLiteral("touched"), QJSValue(double(nowMs())));
        cache.setProperty(roomId, value);

        QStringList removable;
        QJSValueIterator iterator(cache);
        while (iterator.hasNext()) {
            iterator.next();
            const QString id = iterator.name();
            const QJSValue room = iterator.value();
            if (id != string(root.property(QStringLiteral("roomId")))
                && root.property(QStringLiteral("pageRequests")).property(id).isUndefined()
                && length(room.property(QStringLiteral("items")))
                    > root.property(QStringLiteral("maxCachedAttachmentsPerRoom")).toInt()) {
                cache.deleteProperty(id);
                continue;
            }
            if (id != string(root.property(QStringLiteral("roomId")))
                && root.property(QStringLiteral("pageRequests")).property(id).isUndefined())
                removable.append(id);
        }
        std::sort(removable.begin(), removable.end(), [&cache](const QString &left,
                                                                const QString &right) {
            return number(cache.property(left).property(QStringLiteral("touched")))
                > number(cache.property(right).property(QStringLiteral("touched")));
        });
        while (objectKeys(cache).size() > root.property(QStringLiteral("maxCachedRooms")).toInt()
               && !removable.isEmpty()) {
            cache.deleteProperty(removable.takeLast());
        }
        set(root, QStringLiteral("roomCache"), cache);
        return undefined();
    }

    if (operation == QStringLiteral("saveCategory")) {
        const QString roomId = string(first);
        const int category = second.toInt();
        const QJSValue previous = root.property(QStringLiteral("roomCache")).property(roomId);
        if (!previous.isObject())
            return undefined();
        QJSValue states = cloneArray(engine, previous.property(QStringLiteral("states")));
        states.setProperty(category, third);
        QJSValue next = cloneObject(engine, previous);
        next.setProperty(QStringLiteral("states"), states);
        next.setProperty(QStringLiteral("items"),
                         fourth.isUndefined() ? previous.property(QStringLiteral("items")) : fourth);
        callRoot(root, QStringLiteral("saveRoom"), {QJSValue(roomId), next});
        return undefined();
    }

    if (operation == QStringLiteral("cacheCurrentRoom")) {
        const QString roomId = string(root.property(QStringLiteral("roomId")));
        const QJSValue cached = root.property(QStringLiteral("roomCache")).property(roomId);
        if (cached.isObject()) {
            QJSValue next = cloneObject(engine, cached);
            next.setProperty(QStringLiteral("category"),
                             root.property(QStringLiteral("currentCategory")));
            callRoot(root, QStringLiteral("saveRoom"), {QJSValue(roomId), next});
        }
        return undefined();
    }

    if (operation == QStringLiteral("openForRoom")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return undefined();
        const QJSValue panel = root.property(QStringLiteral("panelObject"));
        set(panel, QStringLiteral("dragOffsetX"), QJSValue(0));
        set(panel, QStringLiteral("dragOffsetY"), QJSValue(0));
        call(panel.property(QStringLiteral("attachmentsMoveAreaObject")),
             QStringLiteral("resetMotion"));
        callRoot(root, QStringLiteral("cacheCurrentRoom"));
        set(root, QStringLiteral("roomId"), QJSValue(roomId));
        if (!root.property(QStringLiteral("roomCache")).property(roomId).isObject())
            callRoot(root, QStringLiteral("saveRoom"), {QJSValue(roomId), newRoomValue(engine, root)});
        const QJSValue cached = root.property(QStringLiteral("roomCache")).property(roomId);
        set(root, QStringLiteral("currentCategory"),
            cached.property(QStringLiteral("category")));
        set(root, QStringLiteral("opened"), QJSValue(true));
        const QJSValue active = root.property(QStringLiteral("activeCategory"));
        if (!boolean(active.property(QStringLiteral("loaded")))
            && !string(active.property(QStringLiteral("error"))).isEmpty()) {
            QJSValue state = cloneObject(engine, active);
            state.setProperty(QStringLiteral("error"), QJSValue(QString()));
            callRoot(root, QStringLiteral("saveCategory"),
                     {QJSValue(roomId), root.property(QStringLiteral("currentCategory")), state});
        }
        callRoot(root, QStringLiteral("continueLoading"));
        return undefined();
    }

    if (operation == QStringLiteral("needsMore")) {
        const QString roomId = string(root.property(QStringLiteral("roomId")));
        const QJSValue active = root.property(QStringLiteral("activeCategory"));
        const int category = root.property(QStringLiteral("currentCategory")).toInt();
        const bool result = root.property(QStringLiteral("roomCache")).property(roomId).isObject()
            && string(active.property(QStringLiteral("error"))).isEmpty()
            && (!boolean(active.property(QStringLiteral("loaded")))
                || (callRoot(root, QStringLiteral("categoryCount"), {QJSValue(category)}).toInt()
                        < active.property(QStringLiteral("goal")).toInt()
                    && !string(root.property(QStringLiteral("nextFrom"))).isEmpty()));
        return QJSValue(result);
    }

    if (operation == QStringLiteral("continueLoading")) {
        const QString roomId = string(root.property(QStringLiteral("roomId")));
        if (boolean(root.property(QStringLiteral("opened")))
            && boolean(callRoot(root, QStringLiteral("needsMore")))
            && root.property(QStringLiteral("pageRequests")).property(roomId).isUndefined()) {
            callRoot(root, QStringLiteral("requestPage"),
                     {root.property(QStringLiteral("nextFrom"))});
        }
        return undefined();
    }

    if (operation == QStringLiteral("close")) {
        callRoot(root, QStringLiteral("cacheCurrentRoom"));
        set(root, QStringLiteral("opened"), QJSValue(false));
        call(root.property(QStringLiteral("attachmentContextMenuObject")), QStringLiteral("close"));
        call(root.property(QStringLiteral("attachmentsVideoPlayerObject")), QStringLiteral("close"));
        callRoot(root, QStringLiteral("closed"));
        return undefined();
    }

    if (operation == QStringLiteral("reset")) {
        callRoot(root, QStringLiteral("close"));
        set(root, QStringLiteral("pageRequests"), object(engine));
        set(root, QStringLiteral("roomCache"), object(engine));
        set(root, QStringLiteral("ignoredSenders"), object(engine));
        set(root, QStringLiteral("roomId"), QJSValue(QString()));
        set(root, QStringLiteral("currentCategory"), QJSValue(0));
        return undefined();
    }

    if (operation == QStringLiteral("requestPage")) {
        const QString from = string(first);
        const QString roomId = string(root.property(QStringLiteral("roomId")));
        if (roomId.isEmpty()
            || root.property(QStringLiteral("pageRequests")).property(roomId).isObject()
            || !root.property(QStringLiteral("roomCache")).property(roomId).isObject())
            return undefined();
        QJSValue active = cloneObject(engine, root.property(QStringLiteral("activeCategory")));
        active.setProperty(QStringLiteral("error"), QJSValue(QString()));
        const int category = root.property(QStringLiteral("currentCategory")).toInt();
        callRoot(root, QStringLiteral("saveCategory"),
                 {QJSValue(roomId), QJSValue(category), active});
        const int sequence = root.property(QStringLiteral("requestSequence")).toInt() + 1;
        set(root, QStringLiteral("requestSequence"), QJSValue(sequence));
        const QString requestId = QString::number(nowMs())
            + QStringLiteral("-attachment-cache-") + QString::number(sequence);
        QJSValue requests = cloneObject(engine, root.property(QStringLiteral("pageRequests")));
        QJSValue request = object(engine);
        request.setProperty(QStringLiteral("id"), QJSValue(requestId));
        request.setProperty(QStringLiteral("from"), QJSValue(from));
        request.setProperty(QStringLiteral("category"), QJSValue(category));
        requests.setProperty(roomId, request);
        set(root, QStringLiteral("pageRequests"), requests);
        const int remaining = qMax(1, qMin(30,
            active.property(QStringLiteral("goal")).toInt()
                - callRoot(root, QStringLiteral("categoryCount"), {QJSValue(category)}).toInt()));
        callRoot(root, QStringLiteral("loadMoreRequested"),
                 {QJSValue(roomId), QJSValue(from), QJSValue(requestId),
                  QJSValue(category), QJSValue(remaining)});
        return undefined();
    }

    if (operation == QStringLiteral("receivePage")) {
        const QString roomId = string(first);
        const QJSValue request = root.property(QStringLiteral("pageRequests")).property(roomId);
        const QString requestId = string(fifth);
        if (!request.isObject()
            || string(request.property(QStringLiteral("id"))) != requestId)
            return undefined();
        QJSValue requests = cloneObject(engine, root.property(QStringLiteral("pageRequests")));
        requests.deleteProperty(roomId);
        set(root, QStringLiteral("pageRequests"), requests);
        const QJSValue cached = root.property(QStringLiteral("roomCache")).property(roomId);
        if (cached.isObject()) {
            const int category = request.property(QStringLiteral("category")).toInt();
            QJSValue state = cloneObject(engine,
                cached.property(QStringLiteral("states")).property(category));
            QJSValue merged = cached.property(QStringLiteral("items"));
            const QString errorText = string(fourth).isEmpty()
                ? QString()
                : localizedError(root, string(fourth), QStringLiteral("Не удалось загрузить вложения"));
            if (!errorText.isEmpty()) {
                state.setProperty(QStringLiteral("error"), QJSValue(errorText));
            } else {
                state.setProperty(QStringLiteral("error"), QJSValue(QString()));
                state.setProperty(QStringLiteral("loaded"), QJSValue(true));
                QString continuation = string(third);
                if (continuation == string(request.property(QStringLiteral("from"))))
                    continuation.clear();
                state.setProperty(QStringLiteral("nextFrom"), QJSValue(continuation));
                merged = callRoot(root, QStringLiteral("mergePage"),
                                  {cached.property(QStringLiteral("items")), second});
            }
            callRoot(root, QStringLiteral("saveCategory"),
                     {QJSValue(roomId), QJSValue(category), state, merged});
        }
        callLater(root, QStringLiteral("continueLoading"));
        return undefined();
    }

    if (operation == QStringLiteral("reconcileTimeline")) {
        const QString roomId = string(first);
        const QJSValue model = second;
        const QJSValue cached = root.property(QStringLiteral("roomCache")).property(roomId);
        if (!cached.isObject())
            return undefined();
        bool anyLoaded = false;
        const QJSValue states = cached.property(QStringLiteral("states"));
        for (int category = 0; category < 4; ++category)
            anyLoaded = anyLoaded || boolean(states.property(category).property(QStringLiteral("loaded")));
        if (!anyLoaded)
            return undefined();

        QSet<QString> removed;
        QSet<QString> known;
        Values incoming;
        double oldest[4] = {
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN(),
            std::numeric_limits<double>::quiet_NaN()
        };
        const QJSValue cachedItems = cached.property(QStringLiteral("items"));
        for (const QJSValue &item : values(cachedItems)) {
            known.insert(string(item.property(QStringLiteral("event_id"))));
            for (int category = 0; category < 4; ++category) {
                if (!matchesCategory(root, item, category))
                    continue;
                const double timestamp = number(item.property(QStringLiteral("timestamp")));
                oldest[category] = std::isnan(oldest[category])
                    ? timestamp : qMin(oldest[category], timestamp);
            }
        }
        const QJSValue ignored = root.property(QStringLiteral("ignoredSenders"));
        for (int index = 0; index < modelCount(model); ++index) {
            const QJSValue message = modelGet(model, index);
            const QString eventId = string(message.property(QStringLiteral("event_id")));
            const QString sender = string(message.property(QStringLiteral("sender")));
            if (boolean(message.property(QStringLiteral("is_redacted")))
                || boolean(message.property(QStringLiteral("sender_is_ignored")))
                || boolean(ignored.property(sender))) {
                removed.insert(eventId);
                continue;
            }
            bool categorized = false;
            bool include = known.contains(eventId);
            for (int category = 0; category < 4; ++category) {
                if (!matchesCategory(root, message, category))
                    continue;
                categorized = true;
                const QJSValue state = states.property(category);
                include = include
                    || (boolean(state.property(QStringLiteral("loaded")))
                        && string(state.property(QStringLiteral("nextFrom"))).isEmpty())
                    || (!std::isnan(oldest[category])
                        && number(message.property(QStringLiteral("timestamp"))) >= oldest[category]);
            }
            if (categorized && include)
                incoming.append(fromVariant(engine, message.toVariant()));
            else if (!categorized && !boolean(message.property(QStringLiteral("is_encrypted"))))
                removed.insert(eventId);
        }
        Values retained;
        for (const QJSValue &item : values(cachedItems)) {
            if (!removed.contains(string(item.property(QStringLiteral("event_id")))))
                retained.append(item);
        }
        const QJSValue merged = callRoot(root, QStringLiteral("mergePage"),
            {arrayFromValues(engine, retained), arrayFromValues(engine, incoming)});
        if (stableJson(merged) != stableJson(cachedItems)) {
            QJSValue next = cloneObject(engine, cached);
            next.setProperty(QStringLiteral("items"), merged);
            callRoot(root, QStringLiteral("saveRoom"), {QJSValue(roomId), next});
        }
        callLater(root, QStringLiteral("continueLoading"));
        return undefined();
    }

    if (operation == QStringLiteral("setSenderIgnored")) {
        const QString userId = string(first);
        const bool ignored = boolean(second);
        if (!ignored) {
            QJSValue next = cloneObject(engine, root.property(QStringLiteral("ignoredSenders")));
            next.deleteProperty(userId);
            callRoot(root, QStringLiteral("reset"));
            set(root, QStringLiteral("ignoredSenders"), next);
            return undefined();
        }
        QJSValue ignoredSenders = cloneObject(engine,
            root.property(QStringLiteral("ignoredSenders")));
        ignoredSenders.setProperty(userId, QJSValue(true));
        set(root, QStringLiteral("ignoredSenders"), ignoredSenders);
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("roomCache")));
        QJSValueIterator iterator(cache);
        while (iterator.hasNext()) {
            iterator.next();
            Values retained;
            const QJSValue room = iterator.value();
            for (const QJSValue &item : values(room.property(QStringLiteral("items")))) {
                if (string(item.property(QStringLiteral("sender"))) != userId)
                    retained.append(item);
            }
            QJSValue next = cloneObject(engine, room);
            next.setProperty(QStringLiteral("items"), arrayFromValues(engine, retained));
            cache.setProperty(iterator.name(), next);
        }
        set(root, QStringLiteral("roomCache"), cache);
        callLater(root, QStringLiteral("continueLoading"));
        return undefined();
    }

    if (operation == QStringLiteral("mergePage")) {
        const QJSValue existing = first;
        Values combined = values(existing);
        QHash<QString, int> known;
        for (int index = 0; index < combined.size(); ++index) {
            QString key = string(combined.at(index).property(QStringLiteral("event_id")));
            if (key.isEmpty())
                key = QStringLiteral("existing-") + QString::number(index);
            known.insert(key, index);
        }
        bool changed = false;
        const QJSValue ignored = root.property(QStringLiteral("ignoredSenders"));
        const Values incoming = values(second);
        for (int index = 0; index < incoming.size(); ++index) {
            const QJSValue item = incoming.at(index);
            const QString sender = string(item.property(QStringLiteral("sender")));
            if (string(item.property(QStringLiteral("msg_type"))) == QStringLiteral("m.sticker")
                || boolean(item.property(QStringLiteral("is_redacted")))
                || boolean(item.property(QStringLiteral("is_encrypted")))
                || boolean(item.property(QStringLiteral("sender_is_ignored")))
                || boolean(ignored.property(sender)))
                continue;
            QString eventId = string(item.property(QStringLiteral("event_id")));
            if (eventId.isEmpty()) {
                eventId = QStringLiteral("incoming-") + QString::number(index)
                    + QLatin1Char('-')
                    + string(item.property(QStringLiteral("timestamp")));
            }
            if (!known.contains(eventId)) {
                known.insert(eventId, combined.size());
                combined.append(item);
                changed = true;
            } else {
                const int existingIndex = known.value(eventId);
                QJSValue updated = cloneObject(engine, combined.at(existingIndex));
                QJSValueIterator fields(item);
                while (fields.hasNext()) {
                    fields.next();
                    updated.setProperty(fields.name(), fields.value());
                }
                if (stableJson(updated) != stableJson(combined.at(existingIndex))) {
                    combined[existingIndex] = updated;
                    changed = true;
                }
            }
        }
        if (!changed)
            return existing;
        std::sort(combined.begin(), combined.end(), [](const QJSValue &left,
                                                       const QJSValue &right) {
            const double timestampDelta = number(right.property(QStringLiteral("timestamp")))
                - number(left.property(QStringLiteral("timestamp")));
            if (timestampDelta != 0)
                return timestampDelta < 0;
            return QString::localeAwareCompare(
                string(right.property(QStringLiteral("event_id"))),
                string(left.property(QStringLiteral("event_id")))) < 0;
        });
        return arrayFromValues(engine, combined);
    }

    if (operation == QStringLiteral("firstLink")) {
        static const QRegularExpression pattern(
            QStringLiteral(R"((?:https?://|www\.)[^\s<>"']+)"),
            QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch match = pattern.match(string(first));
        if (!match.hasMatch())
            return QJSValue(QString());
        QString link = match.captured(0);
        static const QRegularExpression trailing(QStringLiteral(R"([),.!?;:]+$)"));
        link.remove(trailing);
        return QJSValue(link.startsWith(QStringLiteral("www."))
                            ? QStringLiteral("https://") + link : link);
    }

    if (operation == QStringLiteral("isVideoItem")) {
        if (!first.isObject())
            return QJSValue(false);
        const QString type = string(first.property(QStringLiteral("msg_type")));
        if (type == QStringLiteral("m.video"))
            return QJSValue(true);
        if (type != QStringLiteral("m.file"))
            return QJSValue(false);
        const QString mime = string(first.property(QStringLiteral("media_mime_type"))).toLower();
        return QJSValue(mime.startsWith(QStringLiteral("video/"))
            || guessMime(string(first.property(QStringLiteral("body"))))
                   .startsWith(QStringLiteral("video/")));
    }

    if (operation == QStringLiteral("matchesCategory"))
        return QJSValue(matchesCategory(root, first, second.toInt()));

    return error(engine, QStringLiteral("attachments.") + operation);
}

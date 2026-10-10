#include "frontend_logic_matrix_internal.h"

#include <QSet>

using namespace FrontendLogicSupport;

namespace FrontendMatrixLogic {
namespace {

QJSValue command(QJSEngine *engine,
                 const QList<QPair<QString, QJSValue>> &properties)
{
    return objectFromProperties(engine, properties);
}

QString commandType(const QJSValue &command)
{
    return string(command.property(QStringLiteral("type")));
}

void setMapFlag(QJSEngine *engine,
                const QJSValue &root,
                const QString &property,
                const QString &key,
                const QJSValue &value,
                bool remove)
{
    QJSValue map = cloneObject(engine, root.property(property));
    if (remove)
        map.deleteProperty(key);
    else
        map.setProperty(key, value);
    set(root, property, map);
}

QJSValue emptyArray(QJSEngine *engine)
{
    return array(engine);
}

QString failureMessage(const QJSValue &root, const QJSValue &errorText)
{
    const QString value = string(errorText);
    return localizedError(root, value, QStringLiteral("Команда не была отправлена"));
}

void handleCommandFailure(const QJSValue &root,
                          QJSEngine *engine,
                          const QJSValue &failedCommand,
                          const QString &message)
{
    if (!failedCommand.isObject())
        return;
    const QString type = commandType(failedCommand);
    const QString requestId = string(failedCommand.property(QStringLiteral("request_id")));
    const QString roomId = string(failedCommand.property(QStringLiteral("room_id")));

    if (type == QStringLiteral("set_typing"))
        return;
    if (type == QStringLiteral("login")) {
        signal(root, QStringLiteral("loginFailed"), {QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("get_session_state")) {
        signal(root, QStringLiteral("sessionStateResolved"), {QJSValue(false)});
        if (string(root.property(QStringLiteral("authenticatedUserId"))).isEmpty())
            signal(root, QStringLiteral("loginFailed"), {QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("register")) {
        signal(root, QStringLiteral("registrationFailed"), {QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("export_room_keys") || type == QStringLiteral("import_room_keys")) {
        signal(root, QStringLiteral("roomKeysTransferFinished"), {
            QJSValue(requestId),
            QJSValue(type == QStringLiteral("export_room_keys")
                         ? QStringLiteral("export") : QStringLiteral("import")),
            QJSValue(false), QJSValue(0), QJSValue(0), QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("get_encryption_overview")) {
        signal(root, QStringLiteral("encryptionOverviewReceived"),
               {nullValue(), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("get_matrix_devices")) {
        signal(root, QStringLiteral("matrixDevicesReceived"),
               {emptyArray(engine), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("rename_matrix_device")
        || type == QStringLiteral("delete_matrix_devices")
        || type == QStringLiteral("submit_device_delete_uiaa")
        || type == QStringLiteral("copy_text")) {
        const QString operation = type == QStringLiteral("copy_text")
            ? QStringLiteral("copy")
            : type == QStringLiteral("rename_matrix_device")
                ? QStringLiteral("rename") : QStringLiteral("delete");
        QJSValue deviceIds = failedCommand.property(QStringLiteral("device_ids"));
        if (!deviceIds.isObject())
            deviceIds = emptyArray(engine);
        signal(root, QStringLiteral("deviceOperationFinished"),
               {QJSValue(requestId), QJSValue(operation), QJSValue(false),
                deviceIds, QJSValue(message)});
        return;
    }
    static const QSet<QString> e2eeActions = {
        QStringLiteral("bootstrap_cross_signing"),
        QStringLiteral("start_verification"),
        QStringLiteral("verification_action"),
        QStringLiteral("enable_recovery"),
        QStringLiteral("recover_encryption"),
        QStringLiteral("enable_key_backup"),
        QStringLiteral("change_recovery_key"),
        QStringLiteral("repair_key_backup"),
        QStringLiteral("recreate_key_backup"),
        QStringLiteral("reset_crypto_identity"),
        QStringLiteral("cancel_crypto_identity_reset")
    };
    if (e2eeActions.contains(type)) {
        signal(root, QStringLiteral("e2eeActionFinished"), {
            QJSValue(requestId), QJSValue(false), QJSValue(QString()),
            QJSValue(QString()), QJSValue(QString()), QJSValue(QString()),
            QJSValue(QString()), QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("get_storage_stats")) {
        signal(root, QStringLiteral("storageStatsReceived"),
               {nullValue(), QJSValue(message)});
        return;
    }
    static const QSet<QString> storageActions = {
        QStringLiteral("clear_cache"),
        QStringLiteral("set_storage_preferences"),
        QStringLiteral("download_media"),
        QStringLiteral("clear_temporary_data"),
        QStringLiteral("export_diagnostics")
    };
    if (storageActions.contains(type)) {
        signal(root, QStringLiteral("storageActionFinished"),
               {QJSValue(type), QJSValue(false), object(engine), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("get_profile_list")) {
        set(root, QStringLiteral("profileListInFlight"), QJSValue(false));
        feedback(root, tr(root, QStringLiteral("Не удалось выполнить действие")) + QStringLiteral(": ") + message, true);
        return;
    }
    if (type == QStringLiteral("get_room_list")) {
        set(root, QStringLiteral("roomsRequestInFlight"), QJSValue(false));
        signal(root, QStringLiteral("roomsLoadFinished"), {QJSValue(false)});
        feedback(root, tr(root, QStringLiteral("Не удалось выполнить действие")) + QStringLiteral(": ") + message, true);
        return;
    }
    if (type == QStringLiteral("moderate_room_member")) {
        signal(root, QStringLiteral("roomMemberModerationFinished"), {
            QJSValue(roomId),
            QJSValue(string(failedCommand.property(QStringLiteral("user_id")))),
            QJSValue(string(failedCommand.property(QStringLiteral("action")))),
            QJSValue(false), QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("open_timeline")) {
        const QJSValue requests = root.property(QStringLiteral("timelineRequestByRoom"));
        if (string(requests.property(roomId)) == requestId) {
            QJSValue remaining = cloneObject(engine, requests);
            remaining.deleteProperty(roomId);
            set(root, QStringLiteral("timelineRequestByRoom"), remaining);
            if (roomId == string(root.property(QStringLiteral("currentRoomId")))) {
                set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
                set(root, QStringLiteral("timelineInitialPositionReady"), QJSValue(true));
                set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
                set(root, QStringLiteral("restoreEventId"), QJSValue(QString()));
                call(root.property(QStringLiteral("timelineInitialFillTimerObject")),
                     QStringLiteral("stop"));
                set(root, QStringLiteral("isLoadingMessages"), QJSValue(false));
                const QJSValue model = root.property(QStringLiteral("messageModel"));
                set(root, QStringLiteral("showEmptyState"),
                    QJSValue(!model.isObject() || modelCount(model) == 0));
                feedback(root, message, true);
            }
        }
        return;
    }
    if (type == QStringLiteral("paginate_timeline_backwards")) {
        if (requestId == string(root.property(QStringLiteral("timelinePaginationRequestId")))) {
            set(root, QStringLiteral("timelinePaginationInFlight"), QJSValue(false));
            set(root, QStringLiteral("timelinePaginationRoomId"), QJSValue(QString()));
            set(root, QStringLiteral("timelinePaginationRequestId"), QJSValue(QString()));
            set(root, QStringLiteral("timelinePaginationWasInitialFill"), QJSValue(false));
            set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
            set(root, QStringLiteral("timelineInitialPositionReady"), QJSValue(true));
            set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
            set(root, QStringLiteral("restoreEventId"), QJSValue(QString()));
            call(root.property(QStringLiteral("timelineInitialFillTimerObject")),
                 QStringLiteral("stop"));
            signal(root, QStringLiteral("timelinePaginationFinished"));
            feedback(root, message, true);
        }
        return;
    }
    if (type == QStringLiteral("close_timeline"))
        return;
    if (type == QStringLiteral("get_pinned_messages")) {
        callRoot(root, QStringLiteral("finishPinnedMessagesRequest"),
                 {QJSValue(roomId), emptyArray(engine), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("get_room_members")) {
        QJSValue errors = cloneObject(engine, root.property(QStringLiteral("roomMembersErrors")));
        errors.setProperty(roomId, QJSValue(message));
        set(root, QStringLiteral("roomMembersErrors"), errors);
        callRoot(root, QStringLiteral("finishRoomMembersRequest"), {QJSValue(roomId)});
        signal(root, QStringLiteral("roomMembersReceived"), {
            QJSValue(roomId), emptyArray(engine), QJSValue(QString()),
            QJSValue(!string(failedCommand.property(QStringLiteral("from"))).isEmpty()),
            QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("get_space_hierarchy")) {
        signal(root, QStringLiteral("spaceHierarchyReceived"), {
            failedCommand.property(QStringLiteral("space_id")), emptyArray(engine),
            QJSValue(QString()),
            QJSValue(!string(failedCommand.property(QStringLiteral("from"))).isEmpty()),
            QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("switch_profile")) {
        set(root, QStringLiteral("profileSwitchInFlight"), QJSValue(false));
        signal(root, QStringLiteral("profileSwitchStateChanged"), {QJSValue(false)});
        signal(root, QStringLiteral("profileSwitchFailed"), {QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("get_timeline_preview")) {
        const QJSValue previews = root.property(QStringLiteral("roomPreviewRequests"));
        QJSValue request = previews.property(requestId);
        if (!request.isObject())
            request = object(engine);
        QJSValue remaining = cloneObject(engine, previews);
        remaining.deleteProperty(requestId);
        set(root, QStringLiteral("roomPreviewRequests"), remaining);
        if (boolean(request.property(QStringLiteral("prefetch")))) {
            callRoot(root, QStringLiteral("finishRoomPreviewPrefetch"),
                     {request, objectFromProperties(engine,
                         {{QStringLiteral("success"), QJSValue(false)}})});
            return;
        }
        QString targetRoom = string(request.property(QStringLiteral("room_id")));
        if (targetRoom.isEmpty())
            targetRoom = roomId;
        signal(root, QStringLiteral("roomPreviewReceived"), {
            QJSValue(targetRoom), emptyArray(engine), QJSValue(QString()),
            QJSValue(boolean(request.property(QStringLiteral("append")))),
            QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("get_message_context")) {
        QString eventId = string(root.property(QStringLiteral("messageRequestTargets"))
                                     .property(requestId));
        if (eventId.isEmpty())
            eventId = string(failedCommand.property(QStringLiteral("event_id")));
        callRoot(root, QStringLiteral("cleanupMessageRequest"),
                 {QJSValue(requestId), QJSValue(roomId)});
        signal(root, QStringLiteral("messageContextReceived"),
               {QJSValue(roomId), QJSValue(eventId), QJSValue(false)});
        feedback(root, tr(root, QStringLiteral("Не удалось открыть сообщение: ")) + message, true);
        return;
    }
    if (type == QStringLiteral("mark_room_read")
        || type == QStringLiteral("set_room_marked_unread")) {
        if (string(root.property(QStringLiteral("readStateRequestByRoom")).property(roomId))
            != requestId)
            return;
        if (type == QStringLiteral("mark_room_read"))
            callRoot(root, QStringLiteral("finishRoomRead"),
                     {QJSValue(roomId), QJSValue(requestId), QJSValue(false)});
        else {
            callRoot(root, QStringLiteral("setManualUnreadHold"),
                     {QJSValue(roomId), QJSValue(false)});
            callRoot(root, QStringLiteral("requestRooms"));
        }
        setMapFlag(engine, root, QStringLiteral("lastReadEventByRoom"), roomId,
                   undefined(), true);
        feedback(root, message, true);
        callRoot(root, QStringLiteral("flushQueuedRoomRead"), {QJSValue(roomId)});
        return;
    }
    if (type == QStringLiteral("send_message")) {
        feedback(root, tr(root, QStringLiteral("Сообщение не отправлено: ")) + message, true);
        return;
    }
    if (type == QStringLiteral("get_thread_messages")) {
        signal(root, QStringLiteral("threadMessagesReceived"), {
            QJSValue(roomId), failedCommand.property(QStringLiteral("root_event_id")),
            emptyArray(engine), QJSValue(false), QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("get_room_threads")) {
        signal(root, QStringLiteral("roomThreadsReceived"), {
            QJSValue(roomId), emptyArray(engine), QJSValue(QString()), QJSValue(0),
            QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("mark_room_threads_read")) {
        signal(root, QStringLiteral("allThreadsReadFinished"), {
            QJSValue(roomId), QJSValue(false), object(engine), QJSValue(message),
            QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("mark_thread_read")) {
        signal(root, QStringLiteral("threadReadFinished"), {
            QJSValue(roomId), failedCommand.property(QStringLiteral("root_event_id")),
            QJSValue(false), QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("retry_message")) {
        signal(root, QStringLiteral("retryMessageFinished"), {
            QJSValue(roomId), failedCommand.property(QStringLiteral("timeline_item_id")),
            QJSValue(false), QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("paste_clipboard")) {
        signal(root, QStringLiteral("clipboardPasteFinished"), {
            QJSValue(requestId), QJSValue(false), QJSValue(QString()),
            emptyArray(engine), QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("edit_message")) {
        signal(root, QStringLiteral("editMessageFinished"),
               {QJSValue(requestId), QJSValue(false), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("upload_media")) {
        signal(root, QStringLiteral("uploadFinished"),
               {QJSValue(requestId), QJSValue(false), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("search_room_messages")) {
        signal(root, QStringLiteral("roomSearchReceived"), {
            QJSValue(roomId), emptyArray(engine), QJSValue(QString()),
            QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("search_users")) {
        signal(root, QStringLiteral("userDirectorySearchReceived"), {
            emptyArray(engine), QJSValue(false), QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("search_public_rooms")) {
        signal(root, QStringLiteral("publicRoomSearchReceived"), {
            emptyArray(engine), QJSValue(QString()), QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("get_room_attachments")) {
        signal(root, QStringLiteral("roomAttachmentsReceived"), {
            QJSValue(roomId), emptyArray(engine), QJSValue(QString()),
            QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("get_room_details")) {
        signal(root, QStringLiteral("roomDetailsReceived"),
               {nullValue(), QJSValue(requestId), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("get_user_details")) {
        signal(root, QStringLiteral("userDetailsReceived"),
               {nullValue(), QJSValue(requestId), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("open_direct_message")) {
        signal(root, QStringLiteral("directMessageReady"), {
            QJSValue(QString()), QJSValue(QString()), QJSValue(QString()),
            QJSValue(false), QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("create_room")) {
        signal(root, QStringLiteral("roomCreated"), {
            QJSValue(QString()), QJSValue(QString()), QJSValue(false),
            QJSValue(message), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("join_space_room")) {
        signal(root, QStringLiteral("joinSpaceRoomFinished"), {
            QJSValue(roomId), QJSValue(false),
            QJSValue(boolean(failedCommand.property(QStringLiteral("knock")))),
            QJSValue(message)
        });
        return;
    }
    if (type == QStringLiteral("leave_room")) {
        callRoot(root, QStringLiteral("setRoomLeavePending"),
                 {QJSValue(roomId), QJSValue(false)});
        signal(root, QStringLiteral("roomLeaveFinished"),
               {QJSValue(roomId), QJSValue(false), QJSValue(message)});
        callRoot(root, QStringLiteral("requestRooms"));
        return;
    }
    if (type == QStringLiteral("accept_room_invite")) {
        signal(root, QStringLiteral("roomInviteFinished"),
               {QJSValue(roomId), QJSValue(false), QJSValue(message)});
        return;
    }
    if (type == QStringLiteral("set_avatar")) {
        signal(root, QStringLiteral("avatarUpdated"),
               {QJSValue(false), QJSValue(message), QJSValue(QString())});
        return;
    }
    if (type == QStringLiteral("update_own_profile")) {
        signal(root, QStringLiteral("ownProfileUpdated"),
               {QJSValue(false), nullValue(), QJSValue(message), QJSValue(requestId)});
        return;
    }

    QString action;
    if (type == QStringLiteral("redact_message"))
        action = tr(root, QStringLiteral("Не удалось удалить сообщение"));
    else if (type == QStringLiteral("upload_media"))
        action = tr(root, QStringLiteral("Не удалось отправить файл"));
    else if (type == QStringLiteral("open_direct_message"))
        action = tr(root, QStringLiteral("Не удалось открыть личный чат"));
    else if (type == QStringLiteral("create_room"))
        action = tr(root, QStringLiteral("Не удалось создать комнату"));
    else if (type == QStringLiteral("leave_room"))
        action = tr(root, QStringLiteral("Не удалось покинуть комнату"));
    else if (type == QStringLiteral("logout"))
        action = tr(root, QStringLiteral("Не удалось выйти из аккаунта"));
    else if (type == QStringLiteral("delete_profile"))
        action = tr(root, QStringLiteral("Не удалось удалить аккаунт"));
    else if (type == QStringLiteral("set_avatar"))
        action = tr(root, QStringLiteral("Не удалось обновить аватар"));
    else
        action = tr(root, QStringLiteral("Не удалось выполнить действие"));
    feedback(root, action + QStringLiteral(": ") + message, true);
}

} // namespace

Result invokeCommandsAndRequests(const QString &operation,
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

    if (operation == QStringLiteral("nextRequestId")) {
        const int sequence = root.property(QStringLiteral("commandRequestSequence")).toInt() + 1;
        set(root, QStringLiteral("commandRequestSequence"), QJSValue(sequence));
        const QString suffix = string(first);
        return QJSValue(QString::number(nowMs()) + QLatin1Char('-') + QString::number(sequence)
                        + (suffix.isEmpty() ? QString() : QLatin1Char('-') + suffix));
    }

    if (operation == QStringLiteral("commandTimeoutMs")) {
        const QString type = string(first);
        if (type == QStringLiteral("mark_room_threads_read")
            || type == QStringLiteral("get_room_members")) {
            return QJSValue(qMax(root.property(QStringLiteral("longCommandTimeoutMs")).toInt(),
                                 300000));
        }
        static const QSet<QString> longCommands = {
            QStringLiteral("get_session_state"), QStringLiteral("login"),
            QStringLiteral("register"), QStringLiteral("upload_media"),
            QStringLiteral("upload_sticker_asset"), QStringLiteral("paste_clipboard"),
            QStringLiteral("get_room_attachments"), QStringLiteral("get_timeline_preview"),
            QStringLiteral("get_pinned_messages"), QStringLiteral("export_room_keys"),
            QStringLiteral("import_room_keys"), QStringLiteral("enable_recovery"),
            QStringLiteral("recover_encryption"), QStringLiteral("change_recovery_key"),
            QStringLiteral("repair_key_backup"), QStringLiteral("reset_crypto_identity"),
            QStringLiteral("cancel_crypto_identity_reset"), QStringLiteral("clear_cache"),
            QStringLiteral("download_media"), QStringLiteral("clear_temporary_data"),
            QStringLiteral("export_diagnostics"), QStringLiteral("create_room")
        };
        return QJSValue(longCommands.contains(type)
            ? root.property(QStringLiteral("longCommandTimeoutMs")).toInt()
            : root.property(QStringLiteral("defaultCommandTimeoutMs")).toInt());
    }

    if (operation == QStringLiteral("registerPendingCommand")) {
        if (!first.isObject()
            || string(first.property(QStringLiteral("request_id"))).isEmpty())
            return undefined();
        const QString requestId = string(first.property(QStringLiteral("request_id")));
        QJSValue pending = cloneObject(engine, root.property(QStringLiteral("pendingCommands")));
        QJSValue record = object(engine);
        const QStringList stringFields = {
            QStringLiteral("type"), QStringLiteral("request_id"),
            QStringLiteral("room_id"), QStringLiteral("space_id"),
            QStringLiteral("event_id"), QStringLiteral("root_event_id"),
            QStringLiteral("thread_root"), QStringLiteral("timeline_item_id"),
            QStringLiteral("user_id"), QStringLiteral("action"), QStringLiteral("from")
        };
        for (const QString &field : stringFields)
            record.setProperty(field, QJSValue(string(first.property(field))));
        const QStringList numberFields = {
            QStringLiteral("session_epoch"), QStringLiteral("generation"),
            QStringLiteral("request_generation")
        };
        for (const QString &field : numberFields)
            record.setProperty(field, QJSValue(number(first.property(field))));
        const int timeout = callRoot(root, QStringLiteral("commandTimeoutMs"),
                                     {first.property(QStringLiteral("type"))}).toInt();
        record.setProperty(QStringLiteral("deadline"), QJSValue(double(nowMs() + timeout)));
        pending.setProperty(requestId, record);
        set(root, QStringLiteral("pendingCommands"), pending);
        return undefined();
    }

    if (operation == QStringLiteral("takePendingCommand")) {
        const QString requestId = string(first);
        const QJSValue pending = root.property(QStringLiteral("pendingCommands"));
        if (requestId.isEmpty() || pending.property(requestId).isUndefined())
            return nullValue();
        const QJSValue result = pending.property(requestId);
        QJSValue remaining = cloneObject(engine, pending);
        remaining.deleteProperty(requestId);
        set(root, QStringLiteral("pendingCommands"), remaining);
        return result;
    }

    if (operation == QStringLiteral("cleanupMessageRequest")) {
        QJSValue rooms = root.property(QStringLiteral("messageRequestRooms"));
        rooms.deleteProperty(string(first));
        QJSValue targets = root.property(QStringLiteral("messageRequestTargets"));
        targets.deleteProperty(string(first));
        return undefined();
    }

    if (operation == QStringLiteral("handleCommandFailure")) {
        handleCommandFailure(root, engine, first, failureMessage(root, second));
        return undefined();
    }

    if (operation == QStringLiteral("failAllPending")) {
        const QJSValue commands = root.property(QStringLiteral("pendingCommands"));
        set(root, QStringLiteral("pendingCommands"), object(engine));
        set(root, QStringLiteral("roomsRequestInFlight"), QJSValue(false));
        set(root, QStringLiteral("roomsRefreshQueued"), QJSValue(false));
        for (const QString &requestId : objectKeys(commands))
            handleCommandFailure(root, engine, commands.property(requestId), failureMessage(root, first));
        return undefined();
    }

    if (operation == QStringLiteral("sendTyping")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return QJSValue(false);
        const double generation = number(root.property(QStringLiteral("typingRequestGeneration"))) + 1;
        set(root, QStringLiteral("typingRequestGeneration"), QJSValue(generation));
        return sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("set_typing"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("typing"))},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("typing"), QJSValue(boolean(second))},
            {QStringLiteral("generation"), QJSValue(generation)}
        }));
    }

    if (operation == QStringLiteral("typingUsersForRoom")) {
        const QJSValue raw = root.property(QStringLiteral("typingUserIdsByRoom"))
            .property(string(first));
        QSet<QString> seen;
        Values result;
        for (const QJSValue &entry : values(raw)) {
            const QString userId = string(entry);
            if (userId.isEmpty()
                || userId == string(root.property(QStringLiteral("authenticatedUserId")))
                || boolean(root.property(QStringLiteral("ignoredUserIds")).property(userId))
                || seen.contains(userId))
                continue;
            seen.insert(userId);
            result.append(QJSValue(userId));
        }
        return arrayFromValues(engine, result);
    }

    if (operation == QStringLiteral("requestRooms")) {
        if (boolean(root.property(QStringLiteral("roomsRequestInFlight")))) {
            set(root, QStringLiteral("roomsRefreshQueued"), QJSValue(true));
            return undefined();
        }
        set(root, QStringLiteral("roomsRequestInFlight"), QJSValue(true));
        if (!boolean(sendCommand(root, command(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("get_room_list"))},
                {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("rooms"))}
            })))) {
            set(root, QStringLiteral("roomsRequestInFlight"), QJSValue(false));
        }
        return undefined();
    }

    if (operation == QStringLiteral("acceptRoomInvite")) {
        if (!string(first).isEmpty())
            sendCommand(root, command(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("accept_room_invite"))},
                {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("accept-invite"))},
                {QStringLiteral("room_id"), first}
            }));
        return undefined();
    }

    if (operation == QStringLiteral("requestRoomDetails")) {
        QJSValue requestId = second;
        if (string(requestId).isEmpty())
            requestId = nextRequestId(root, QStringLiteral("room-details"));
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_room_details"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), first}
        }));
        return requestId;
    }

    if (operation == QStringLiteral("setRoomLeavePending")) {
        setMapFlag(engine, root, QStringLiteral("pendingLeaveRoomIds"), string(first),
                   QJSValue(true), !boolean(second));
        return undefined();
    }

    if (operation == QStringLiteral("removeRoomFromVisibleModel")) {
        const QString roomId = string(first);
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        if (!model.isObject() || roomId.isEmpty())
            return undefined();
        for (int index = modelCount(model) - 1; index >= 0; --index) {
            if (string(modelGet(model, index).property(QStringLiteral("room_id"))) == roomId)
                call(model, QStringLiteral("remove"), {QJSValue(index)});
        }
        return undefined();
    }

    if (operation == QStringLiteral("leaveRoom")) {
        const QString roomId = string(first);
        if (roomId.isEmpty()
            || boolean(root.property(QStringLiteral("pendingLeaveRoomIds")).property(roomId)))
            return undefined();
        callRoot(root, QStringLiteral("setRoomLeavePending"),
                 {QJSValue(roomId), QJSValue(true)});
        callRoot(root, QStringLiteral("removeRoomFromVisibleModel"), {QJSValue(roomId)});
        signal(root, QStringLiteral("roomLeaveStarted"), {QJSValue(roomId)});
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("leave_room"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("leave-room"))},
            {QStringLiteral("room_id"), QJSValue(roomId)}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("requestProfiles")) {
        if (boolean(root.property(QStringLiteral("profileListInFlight"))))
            return undefined();
        set(root, QStringLiteral("profileListInFlight"), QJSValue(true));
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_profile_list"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("profiles"))}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("switchProfile")) {
        if (boolean(root.property(QStringLiteral("profileSwitchInFlight"))))
            return undefined();
        set(root, QStringLiteral("profileSwitchInFlight"), QJSValue(true));
        signal(root, QStringLiteral("profileSwitchStateChanged"), {QJSValue(true)});
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("switch_profile"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("switch-profile"))},
            {QStringLiteral("profile_id"), first}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("deleteProfile")) {
        if (!boolean(root.property(QStringLiteral("profileSwitchInFlight"))))
            sendCommand(root, command(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("delete_profile"))},
                {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("delete-profile"))},
                {QStringLiteral("profile_id"), first}
            }));
        return undefined();
    }

    if (operation == QStringLiteral("requestUserDetails")
        || operation == QStringLiteral("setUserIgnored")
        || operation == QStringLiteral("openDirectMessage")
        || operation == QStringLiteral("createRoom")) {
        QString suffix;
        QString type;
        if (operation == QStringLiteral("requestUserDetails")) {
            suffix = QStringLiteral("user"); type = QStringLiteral("get_user_details");
        } else if (operation == QStringLiteral("setUserIgnored")) {
            suffix = QStringLiteral("user-ignore"); type = QStringLiteral("set_user_ignored");
        } else if (operation == QStringLiteral("openDirectMessage")) {
            suffix = QStringLiteral("direct-message"); type = QStringLiteral("open_direct_message");
        } else {
            suffix = QStringLiteral("create-room"); type = QStringLiteral("create_room");
        }
        const QJSValue requestId = nextRequestId(root, suffix);
        QJSValue value = command(engine, {
            {QStringLiteral("type"), QJSValue(type)},
            {QStringLiteral("request_id"), requestId}
        });
        if (operation == QStringLiteral("requestUserDetails")) {
            value.setProperty(QStringLiteral("user_id"), first);
            value.setProperty(QStringLiteral("room_id"), QJSValue(string(second)));
        } else if (operation == QStringLiteral("setUserIgnored")) {
            value.setProperty(QStringLiteral("user_id"), first);
            value.setProperty(QStringLiteral("ignored"), QJSValue(boolean(second)));
        } else if (operation == QStringLiteral("openDirectMessage")) {
            value.setProperty(QStringLiteral("user_id"), first);
        } else {
            value.setProperty(QStringLiteral("options"),
                              first.isObject() ? first : object(engine));
        }
        sendCommand(root, value);
        return requestId;
    }

    if (operation == QStringLiteral("requestRoomMembers")) {
        const QString roomId = string(first);
        const QString from = string(second);
        if (roomId.isEmpty())
            return undefined();
        const bool append = !from.isEmpty();
        if (boolean(root.property(QStringLiteral("roomMembersPaginationInFlight")).property(roomId))) {
            if (!append)
                callRoot(root, QStringLiteral("queueRoomMembersRefresh"), {QJSValue(roomId)});
            return undefined();
        }
        const QJSValue requestId = nextRequestId(root,
            append ? QStringLiteral("members-page") : QStringLiteral("members"));
        setMapFlag(engine, root, QStringLiteral("roomMembersErrors"), roomId,
                   undefined(), true);
        setMapFlag(engine, root, QStringLiteral("roomMembersPaginationInFlight"), roomId,
                   QJSValue(true), false);
        if (!append)
            setMapFlag(engine, root, QStringLiteral("roomMembersNextTokens"), roomId,
                       QJSValue(QString()), false);
        const int loaded = qRound(number(root.property(QStringLiteral("roomMembersLoadedCounts"))
                                             .property(roomId)));
        const int pageSize = qBound(1,
            root.property(QStringLiteral("roomMembersPageSize")).toInt(), 1000);
        // Scrolling always adds exactly one page. A live refresh preserves the
        // number of rows already loaded instead of silently growing the list.
        const int limit = append ? pageSize
            : qMax(1, qMin(10000, loaded > 0 ? loaded : pageSize));
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_room_members"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("from"), QJSValue(from)},
            {QStringLiteral("limit"), QJSValue(limit)}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("queueRoomMembersRefresh")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return undefined();
        setMapFlag(engine, root, QStringLiteral("roomMembersRefreshQueued"), roomId,
                   QJSValue(true), false);
        set(root, QStringLiteral("roomMembersRefreshTarget"), QJSValue(roomId));
        call(root.property(QStringLiteral("roomMembersRefreshTimerObject")),
             QStringLiteral("restart"));
        return undefined();
    }

    if (operation == QStringLiteral("finishRoomMembersRequest")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return undefined();
        setMapFlag(engine, root, QStringLiteral("roomMembersPaginationInFlight"), roomId,
                   QJSValue(false), false);
        if (!boolean(root.property(QStringLiteral("roomMembersRefreshQueued")).property(roomId))
            || roomId != string(root.property(QStringLiteral("currentRoomId"))))
            return undefined();
        setMapFlag(engine, root, QStringLiteral("roomMembersRefreshQueued"), roomId,
                   undefined(), true);
        set(root, QStringLiteral("roomMembersRefreshTarget"), QJSValue(QString()));
        if (QObject *context = root.toQObject()) {
            QTimer::singleShot(0, context, [root, roomId] {
                if (roomId == string(root.property(QStringLiteral("currentRoomId"))))
                    callRoot(root, QStringLiteral("requestRoomMembers"), {QJSValue(roomId)});
            });
        }
        return undefined();
    }

    if (operation == QStringLiteral("requestOlderRoomMembers")) {
        const QString roomId = string(first);
        if (roomId.isEmpty()
            || boolean(root.property(QStringLiteral("roomMembersPaginationInFlight")).property(roomId)))
            return undefined();
        const QString token = string(root.property(QStringLiteral("roomMembersNextTokens")).property(roomId));
        if (!token.isEmpty())
            callRoot(root, QStringLiteral("requestRoomMembers"),
                     {QJSValue(roomId), QJSValue(token)});
        return undefined();
    }

    if (operation == QStringLiteral("requestPinnedMessages")) {
        const QString roomId = string(first);
        const bool force = boolean(second);
        if (roomId.isEmpty())
            return undefined();
        const QJSValue cached = root.property(QStringLiteral("pinnedMessagesCache")).property(roomId);
        if (cached.isObject() && cached.property(QStringLiteral("messages")).isObject())
            signal(root, QStringLiteral("pinnedMessagesReceived"),
                   {QJSValue(roomId), cached.property(QStringLiteral("messages")), QJSValue(QString())});
        const QJSValue pending = root.property(QStringLiteral("pendingCommands"));
        for (const QString &id : objectKeys(pending)) {
            const QJSValue pendingCommand = pending.property(id);
            if (commandType(pendingCommand) == QStringLiteral("get_pinned_messages")
                && string(pendingCommand.property(QStringLiteral("room_id"))) == roomId) {
                if (force)
                    setMapFlag(engine, root, QStringLiteral("pinnedMessagesRefreshQueued"),
                               roomId, QJSValue(true), false);
                return undefined();
            }
        }
        if (!force && cached.isObject()
            && nowMs() < qint64(number(cached.property(QStringLiteral("retryAfter")))))
            return undefined();
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_pinned_messages"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("pinned"))},
            {QStringLiteral("room_id"), QJSValue(roomId)}
        }));
        return undefined();
    }

    if (operation == QStringLiteral("finishPinnedMessagesRequest")) {
        const QString roomId = string(first);
        const QString errorText = string(third);
        if (roomId.isEmpty())
            return undefined();
        const QJSValue current = root.property(QStringLiteral("pinnedMessagesCache"));
        QJSValue cached = current.property(roomId);
        if (!cached.isObject())
            cached = object(engine);
        QJSValue next = cloneObject(engine, current);
        next.deleteProperty(roomId);
        QJSValue entry = object(engine);
        entry.setProperty(QStringLiteral("messages"), errorText.isEmpty()
            ? (second.isObject() ? second : emptyArray(engine))
            : cached.property(QStringLiteral("messages")));
        entry.setProperty(QStringLiteral("retryAfter"),
                          QJSValue(double(nowMs() + (errorText.isEmpty() ? 15000 : 30000))));
        next.setProperty(roomId, entry);
        QStringList rooms = objectKeys(next);
        while (rooms.size() > 32)
            next.deleteProperty(rooms.takeFirst());
        set(root, QStringLiteral("pinnedMessagesCache"), next);
        const bool refreshAgain = boolean(root.property(QStringLiteral("pinnedMessagesRefreshQueued"))
                                              .property(roomId));
        setMapFlag(engine, root, QStringLiteral("pinnedMessagesRefreshQueued"), roomId,
                   undefined(), true);
        QJSValue messages = next.property(roomId).property(QStringLiteral("messages"));
        if (!messages.isObject())
            messages = emptyArray(engine);
        signal(root, QStringLiteral("pinnedMessagesReceived"),
               {QJSValue(roomId), messages,
                QJSValue(errorText.isEmpty() ? QString()
                    : localizedError(root, errorText, QStringLiteral("Не удалось выполнить действие")))});
        if (refreshAgain && errorText.isEmpty())
            callRoot(root, QStringLiteral("requestPinnedMessages"),
                     {QJSValue(roomId), QJSValue(true)});
        return undefined();
    }

    if (operation == QStringLiteral("requestSpaceHierarchy")) {
        const QString spaceId = string(first);
        const QString from = string(second);
        if (!spaceId.isEmpty())
            sendCommand(root, command(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("get_space_hierarchy"))},
                {QStringLiteral("request_id"), nextRequestId(root, from.isEmpty()
                    ? QStringLiteral("space-hierarchy") : QStringLiteral("space-hierarchy-page"))},
                {QStringLiteral("space_id"), QJSValue(spaceId)},
                {QStringLiteral("from"), QJSValue(from)},
                {QStringLiteral("limit"), QJSValue(25)}
            }));
        return undefined();
    }

    if (operation == QStringLiteral("joinSpaceRoom")) {
        const QString roomId = string(first.property(QStringLiteral("room_id")));
        if (first.isObject() && !roomId.isEmpty()) {
            QJSValue via = first.property(QStringLiteral("via"));
            if (!via.isObject())
                via = emptyArray(engine);
            sendCommand(root, command(engine, {
                {QStringLiteral("type"), QJSValue(QStringLiteral("join_space_room"))},
                {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("space-join"))},
                {QStringLiteral("room_id"), QJSValue(roomId)},
                {QStringLiteral("knock"), QJSValue(boolean(second))},
                {QStringLiteral("via"), via}
            }));
        }
        return undefined();
    }

    if (operation == QStringLiteral("addRoomToSpace")
        || operation == QStringLiteral("removeRoomFromSpace")) {
        const QString roomId = string(first);
        const QString spaceId = string(second);
        if (roomId.isEmpty() || spaceId.isEmpty() || roomId == spaceId)
            return QJSValue(QString());
        const bool add = operation == QStringLiteral("addRoomToSpace");
        const QJSValue requestId = nextRequestId(root,
            add ? QStringLiteral("space-add-room") : QStringLiteral("space-remove-room"));
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(add
                ? QStringLiteral("add_room_to_space") : QStringLiteral("remove_room_from_space"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("space_id"), QJSValue(spaceId)}
        }));
        return requestId;
    }

    if (operation == QStringLiteral("updateRoom")) {
        const QString roomId = string(first);
        if (roomId.isEmpty() || !second.isObject())
            return QJSValue(QString());
        const QJSValue requestId = nextRequestId(root, QStringLiteral("update-room"));
        sendCommand(root, command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("update_room"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("changes"), second}
        }));
        return requestId;
    }

    if (operation == QStringLiteral("moderateRoomMember")) {
        if (string(first).isEmpty() || string(second).isEmpty() || string(third).isEmpty())
            return QJSValue(QString());
        const QJSValue requestId = nextRequestId(root, QStringLiteral("moderate-member"));
        QJSValue value = command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("moderate_room_member"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), first},
            {QStringLiteral("user_id"), second},
            {QStringLiteral("action"), third}
        });
        if (!fourth.isUndefined() && !fourth.isNull())
            value.setProperty(QStringLiteral("power_level"), QJSValue(fourth.toNumber()));
        if (!string(fifth).isEmpty())
            value.setProperty(QStringLiteral("reason"), QJSValue(string(fifth)));
        sendCommand(root, value);
        return requestId;
    }

    if (operation == QStringLiteral("searchRoomMessages")) {
        const QString roomId = string(first);
        const QString query = string(second).trimmed();
        if (roomId.isEmpty() || query.isEmpty())
            return QJSValue(QString());
        QJSValue requestId = fourth;
        if (string(requestId).isEmpty())
            requestId = nextRequestId(root, QStringLiteral("search"));
        QJSValue value = command(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("search_room_messages"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("query"), QJSValue(query)},
            {QStringLiteral("limit"), QJSValue(50)}
        });
        if (!string(third).isEmpty())
            value.setProperty(QStringLiteral("next_batch"), third);
        sendCommand(root, value);
        return requestId;
    }

    if (operation == QStringLiteral("searchUsers")
        || operation == QStringLiteral("searchPublicRooms")) {
        const QString query = string(first).trimmed();
        if (query.isEmpty())
            return QJSValue(QString());
        const bool users = operation == QStringLiteral("searchUsers");
        QJSValue requestId = second;
        if (string(requestId).isEmpty())
            requestId = nextRequestId(root, users
                ? QStringLiteral("user-directory") : QStringLiteral("room-directory"));
        QJSValue value = command(engine, {
            {QStringLiteral("type"), QJSValue(users
                ? QStringLiteral("search_users") : QStringLiteral("search_public_rooms"))},
            {QStringLiteral("request_id"), requestId},
            {QStringLiteral("query"), QJSValue(query)},
            {QStringLiteral("limit"), QJSValue(50)}
        });
        if (!users)
            value.setProperty(QStringLiteral("spaces_only"), QJSValue(boolean(third)));
        sendCommand(root, value);
        return requestId;
    }

    return std::nullopt;
}

} // namespace FrontendMatrixLogic

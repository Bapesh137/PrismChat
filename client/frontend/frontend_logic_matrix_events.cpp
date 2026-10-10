#include "frontend_logic_matrix_internal.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>

using namespace FrontendLogicSupport;

namespace FrontendMatrixLogic {
namespace {

QJSValue emptyArray(QJSEngine *engine)
{
    return array(engine);
}

QJSValue valueOrArray(QJSEngine *engine, const QJSValue &value)
{
    return value.isObject() ? value : emptyArray(engine);
}

QJSValue valueOrObject(QJSEngine *engine, const QJSValue &value)
{
    return value.isObject() ? value : object(engine);
}

QString errorOr(const QJSValue &root, const QJSValue &message, const QString &fallback)
{
    const QString error = string(message.property(QStringLiteral("error")));
    return localizedError(root, error, fallback);
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

void clearUiForSwitch(const QJSValue &root)
{
    callRoot(root, QStringLiteral("clearUiStateForProfileSwitch"));
}

QJSValue normalizeMessages(const QJSValue &root,
                           QJSEngine *engine,
                           const QJSValue &messages)
{
    Values result;
    for (const QJSValue &message : values(messages))
        result.append(callRoot(root, QStringLiteral("normalizeMessage"), {message}));
    return arrayFromValues(engine, result);
}

void accountEvent(const QJSValue &root,
                  QJSEngine *engine,
                  const QJSValue &message)
{
    const QString type = string(message.property(QStringLiteral("type")));
    if (type == QStringLiteral("session_restored")) {
        set(root, QStringLiteral("activeSessionEpoch"),
            QJSValue(number(message.property(QStringLiteral("session_epoch")))));
        const QString userId = string(message.property(QStringLiteral("user_id")));
        const QString profileId = string(message.property(QStringLiteral("profile_id")));
        const bool changed = string(root.property(QStringLiteral("authenticatedUserId"))).isEmpty()
            || string(root.property(QStringLiteral("authenticatedUserId"))) != userId
            || string(root.property(QStringLiteral("activeProfileId"))) != profileId;
        if (changed)
            clearUiForSwitch(root);
        set(root, QStringLiteral("authenticatedUserId"), QJSValue(userId));
        set(root, QStringLiteral("activeProfileId"), QJSValue(profileId));
        signal(root, QStringLiteral("authenticated"), {
            QJSValue(userId), QJSValue(string(message.property(QStringLiteral("server")))),
            QJSValue(string(message.property(QStringLiteral("avatar_url")))),
            QJSValue(profileId), QJSValue(changed)
        });
        signal(root, QStringLiteral("sessionStateResolved"), {QJSValue(true)});
        return;
    }
    if (type == QStringLiteral("session_state_result")) {
        set(root, QStringLiteral("activeSessionEpoch"),
            QJSValue(number(message.property(QStringLiteral("session_epoch")))));
        const bool authenticated = boolean(message.property(QStringLiteral("authenticated")));
        if (authenticated) {
            const QString userId = string(message.property(QStringLiteral("user_id")));
            const QString profileId = string(message.property(QStringLiteral("profile_id")));
            const bool changed = string(root.property(QStringLiteral("authenticatedUserId"))).isEmpty()
                || string(root.property(QStringLiteral("authenticatedUserId"))) != userId
                || string(root.property(QStringLiteral("activeProfileId"))) != profileId;
            if (changed) {
                clearUiForSwitch(root);
                set(root, QStringLiteral("authenticatedUserId"), QJSValue(userId));
                set(root, QStringLiteral("activeProfileId"), QJSValue(profileId));
                signal(root, QStringLiteral("authenticated"), {
                    QJSValue(userId), QJSValue(string(message.property(QStringLiteral("server")))),
                    QJSValue(string(message.property(QStringLiteral("avatar_url")))),
                    QJSValue(profileId), QJSValue(true)
                });
            }
        } else if (string(root.property(QStringLiteral("authenticatedUserId"))).isEmpty()
                   && !string(message.property(QStringLiteral("error"))).isEmpty()) {
            signal(root, QStringLiteral("loginFailed"),
                   {message.property(QStringLiteral("error"))});
        }
        signal(root, QStringLiteral("sessionStateResolved"), {QJSValue(authenticated)});
        return;
    }
    if (type == QStringLiteral("login_result") || type == QStringLiteral("register_result")) {
        set(root, QStringLiteral("activeSessionEpoch"),
            QJSValue(number(message.property(QStringLiteral("session_epoch")))));
        if (boolean(message.property(QStringLiteral("success")))) {
            clearUiForSwitch(root);
            const QString userId = string(message.property(QStringLiteral("user_id")));
            const QString profileId = string(message.property(QStringLiteral("profile_id")));
            set(root, QStringLiteral("authenticatedUserId"), QJSValue(userId));
            set(root, QStringLiteral("activeProfileId"), QJSValue(profileId));
            signal(root, QStringLiteral("authenticated"), {
                QJSValue(userId), QJSValue(string(message.property(QStringLiteral("server")))),
                QJSValue(string(message.property(QStringLiteral("avatar_url")))),
                QJSValue(profileId), QJSValue(true)
            });
        } else if (type == QStringLiteral("login_result")) {
            signal(root, QStringLiteral("sessionStateResolved"), {QJSValue(false)});
            signal(root, QStringLiteral("loginFailed"),
                   {QJSValue(errorOr(root, message, QStringLiteral("Ошибка входа")))});
        } else {
            signal(root, QStringLiteral("registrationFailed"),
                   {QJSValue(errorOr(root, message, QStringLiteral("Ошибка регистрации")))});
        }
        return;
    }
    if (type == QStringLiteral("logout_result")) {
        set(root, QStringLiteral("activeSessionEpoch"),
            QJSValue(number(message.property(QStringLiteral("session_epoch")))));
        if (!boolean(message.property(QStringLiteral("success")))) {
            feedback(root, tr(root, QStringLiteral("Не удалось выйти из аккаунта")), true);
            return;
        }
        clearUiForSwitch(root);
        set(root, QStringLiteral("authenticatedUserId"), QJSValue(QString()));
        set(root, QStringLiteral("activeProfileId"), QJSValue(QString()));
        set(root, QStringLiteral("profiles"), emptyArray(engine));
        signal(root, QStringLiteral("loggedOut"));
        return;
    }
    if (type == QStringLiteral("profiles_result")) {
        set(root, QStringLiteral("profileListInFlight"), QJSValue(false));
        const QJSValue profiles = valueOrArray(engine,
            message.property(QStringLiteral("profiles")));
        const QString active = string(message.property(QStringLiteral("active_profile_id")));
        set(root, QStringLiteral("profiles"), profiles);
        set(root, QStringLiteral("activeProfileId"), QJSValue(active));
        signal(root, QStringLiteral("profilesUpdated"), {profiles, QJSValue(active)});
        return;
    }
    if (type == QStringLiteral("switch_profile_result")) {
        set(root, QStringLiteral("activeSessionEpoch"),
            QJSValue(number(message.property(QStringLiteral("session_epoch")))));
        set(root, QStringLiteral("profileSwitchInFlight"), QJSValue(false));
        signal(root, QStringLiteral("profileSwitchStateChanged"), {QJSValue(false)});
        if (boolean(message.property(QStringLiteral("success")))) {
            clearUiForSwitch(root);
            const QString userId = string(message.property(QStringLiteral("user_id")));
            const QString profileId = string(message.property(QStringLiteral("profile_id")));
            set(root, QStringLiteral("authenticatedUserId"), QJSValue(userId));
            set(root, QStringLiteral("activeProfileId"), QJSValue(profileId));
            signal(root, QStringLiteral("authenticated"), {
                QJSValue(userId), QJSValue(string(message.property(QStringLiteral("server")))),
                QJSValue(string(message.property(QStringLiteral("avatar_url")))),
                QJSValue(profileId), QJSValue(true)
            });
        } else {
            signal(root, QStringLiteral("profileSwitchFailed"),
                   {QJSValue(errorOr(root, message,
                       QStringLiteral("Не удалось переключить аккаунт")))});
        }
        return;
    }
    if (type == QStringLiteral("current_profile_updated")) {
        const QString profileId = string(message.property(QStringLiteral("profile_id")));
        const QString avatar = string(message.property(QStringLiteral("avatar_url")));
        if (!profileId.isEmpty()) {
            Values profiles = values(root.property(QStringLiteral("profiles")));
            for (int index = 0; index < profiles.size(); ++index) {
                if (string(profiles.at(index).property(QStringLiteral("profile_id"))) == profileId) {
                    profiles[index] = mergeObjects(engine, profiles.at(index),
                        {{QStringLiteral("avatar_url"), QJSValue(avatar)}});
                    break;
                }
            }
            const QJSValue updated = arrayFromValues(engine, profiles);
            set(root, QStringLiteral("profiles"), updated);
            signal(root, QStringLiteral("profilesUpdated"),
                   {updated, root.property(QStringLiteral("activeProfileId"))});
        }
        signal(root, QStringLiteral("currentProfileUpdated"), {
            QJSValue(string(message.property(QStringLiteral("user_id")))),
            QJSValue(string(message.property(QStringLiteral("server")))),
            QJSValue(avatar), QJSValue(profileId)
        });
        return;
    }
    if (type == QStringLiteral("delete_profile_result")) {
        const QString profileId = string(message.property(QStringLiteral("profile_id")));
        const bool wasActive = !profileId.isEmpty()
            && profileId == string(root.property(QStringLiteral("activeProfileId")));
        if (boolean(message.property(QStringLiteral("success")))) {
            if (wasActive) {
                set(root, QStringLiteral("activeProfileId"), QJSValue(QString()));
                set(root, QStringLiteral("authenticatedUserId"), QJSValue(QString()));
                set(root, QStringLiteral("profiles"), emptyArray(engine));
                clearUiForSwitch(root);
                signal(root, QStringLiteral("loggedOut"));
            } else {
                callRoot(root, QStringLiteral("requestProfiles"));
            }
            signal(root, QStringLiteral("profileDeleted"),
                   {QJSValue(profileId), QJSValue(wasActive), QJSValue(QString())});
        } else {
            signal(root, QStringLiteral("profileDeleted"), {
                QJSValue(profileId), QJSValue(false),
                QJSValue(errorOr(root, message, QStringLiteral("Не удалось удалить аккаунт")))
            });
        }
        return;
    }
    if (type == QStringLiteral("set_avatar_result")) {
        const QString avatar = string(message.property(QStringLiteral("avatar_url")));
        const bool success = boolean(message.property(QStringLiteral("success")));
        const QString active = string(root.property(QStringLiteral("activeProfileId")));
        if (success && !active.isEmpty()) {
            Values profiles = values(root.property(QStringLiteral("profiles")));
            for (int index = 0; index < profiles.size(); ++index) {
                if (string(profiles.at(index).property(QStringLiteral("profile_id"))) == active) {
                    profiles[index] = mergeObjects(engine, profiles.at(index),
                        {{QStringLiteral("avatar_url"), QJSValue(avatar)}});
                    break;
                }
            }
            const QJSValue updated = arrayFromValues(engine, profiles);
            set(root, QStringLiteral("profiles"), updated);
            signal(root, QStringLiteral("profilesUpdated"), {updated, QJSValue(active)});
            signal(root, QStringLiteral("currentProfileUpdated"), {
                QJSValue(QString()), QJSValue(QString()), QJSValue(avatar), QJSValue(active)
            });
        }
        signal(root, QStringLiteral("avatarUpdated"), {
            QJSValue(success), QJSValue(string(message.property(QStringLiteral("error")))),
            QJSValue(avatar)
        });
        return;
    }
    if (type == QStringLiteral("user_details_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        const QJSValue details = message.property(QStringLiteral("details"));
        if (success && details.isObject())
            callRoot(root, QStringLiteral("applyCanonicalIdentity"), {details});
        signal(root, QStringLiteral("userDetailsReceived"), {
            success ? (details.isObject() ? details : nullValue()) : nullValue(),
            QJSValue(string(message.property(QStringLiteral("request_id")))),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось загрузить профиль")))
        });
        return;
    }
    if (type == QStringLiteral("user_ignored_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        const bool ignored = boolean(message.property(QStringLiteral("ignored")));
        const QString userId = string(message.property(QStringLiteral("user_id")));
        if (success)
            callRoot(root, QStringLiteral("applyUserIgnored"),
                     {QJSValue(userId), QJSValue(ignored)});
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        if (success && model.isObject()) {
            for (int index = 0; index < modelCount(model); ++index) {
                if (string(modelGet(model, index).property(QStringLiteral("direct_user_id")))
                    != userId)
                    continue;
                modelSetProperty(model, index, QStringLiteral("is_ignored"), QJSValue(ignored));
                if (ignored) {
                    modelSetProperty(model, index, QStringLiteral("unread_count"), QJSValue(0));
                    modelSetProperty(model, index, QStringLiteral("last_message"), QJSValue(QString()));
                }
            }
        }
        signal(root, QStringLiteral("userIgnoreFinished"), {
            QJSValue(userId), QJSValue(ignored), QJSValue(success),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось выполнить действие"))),
            QJSValue(string(message.property(QStringLiteral("request_id"))))
        });
        return;
    }
    if (type == QStringLiteral("update_own_profile_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        const QJSValue details = message.property(QStringLiteral("details"));
        if (success && details.isObject())
            callRoot(root, QStringLiteral("applyCanonicalIdentity"), {details});
        signal(root, QStringLiteral("ownProfileUpdated"), {
            QJSValue(success), success && details.isObject() ? details : nullValue(),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось обновить профиль"))),
            QJSValue(string(message.property(QStringLiteral("request_id"))))
        });
    }
}

void roomEvent(const QJSValue &root,
               QJSEngine *engine,
               const QJSValue &message,
               const QJSValue &responseCommand)
{
    const QString type = string(message.property(QStringLiteral("type")));
    if (type == QStringLiteral("rooms_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        set(root, QStringLiteral("roomsRequestInFlight"), QJSValue(false));
        const bool refreshAgain = boolean(root.property(QStringLiteral("roomsRefreshQueued")));
        set(root, QStringLiteral("roomsRefreshQueued"), QJSValue(false));
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        if (!model.isObject())
            return;
        if (message.property(QStringLiteral("success")).isBool()
            && !boolean(message.property(QStringLiteral("success")))) {
            signal(root, QStringLiteral("roomsLoadFinished"), {QJSValue(false)});
            feedback(root, errorOr(root, message,
                QStringLiteral("Не удалось обновить список комнат")), true);
            if (refreshAgain)
                callLater(root, QStringLiteral("requestRooms"));
            return;
        }
        modelClear(model);
        QJSValue invitedNow = object(engine);
        Values newInvitations;
        for (const QJSValue &raw : values(message.property(QStringLiteral("rooms")))) {
            QJSValue room = callRoot(root, QStringLiteral("normalizeRoom"), {raw});
            callRoot(root, QStringLiteral("reconcilePendingRoomRead"), {room});
            const QString roomId = string(room.property(QStringLiteral("room_id")));
            if (boolean(root.property(QStringLiteral("pendingLeaveRoomIds")).property(roomId)))
                continue;
            if (boolean(callRoot(root, QStringLiteral("hasManualUnreadHold"), {QJSValue(roomId)}))) {
                room.setProperty(QStringLiteral("is_marked_unread"), QJSValue(true));
                room.setProperty(QStringLiteral("unread_count"),
                                 callRoot(root, QStringLiteral("manualUnreadCount"), {QJSValue(roomId)}));
            }
            QString lastMessage = string(room.property(QStringLiteral("last_message")));
            if (!lastMessage.isEmpty()) {
                lastMessage.replace(QLatin1Char('\n'), QLatin1Char(' '));
                room.setProperty(QStringLiteral("last_message"), QJSValue(lastMessage));
            }
            modelAppend(model, room);
            if (boolean(room.property(QStringLiteral("is_invited"))) && !roomId.isEmpty()) {
                invitedNow.setProperty(roomId, QJSValue(true));
                if (!boolean(root.property(QStringLiteral("knownInvitedRoomIds")).property(roomId)))
                    newInvitations.append(room);
            }
        }
        set(root, QStringLiteral("knownInvitedRoomIds"), invitedNow);
        callRoot(root, QStringLiteral("applyRoomOrder"));
        callRoot(root, QStringLiteral("scheduleRoomPreviewPrefetch"));
        signal(root, QStringLiteral("roomsUpdated"));
        signal(root, QStringLiteral("roomsLoadFinished"), {QJSValue(true)});
        for (const QJSValue &room : std::as_const(newInvitations)) {
            const QString roomId = string(room.property(QStringLiteral("room_id")));
            QString name = string(room.property(QStringLiteral("name")));
            if (name.isEmpty())
                name = roomId;
            signal(root, QStringLiteral("roomInvitationReceived"),
                   {QJSValue(roomId), QJSValue(name), QJSValue(QString())});
        }
        if (refreshAgain)
            callLater(root, QStringLiteral("requestRooms"));
        return;
    }
    if (type == QStringLiteral("room_invite_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        signal(root, QStringLiteral("roomInviteFinished"), {
            QJSValue(string(message.property(QStringLiteral("room_id")))), QJSValue(success),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось принять приглашение")))
        });
        if (success)
            callRoot(root, QStringLiteral("requestRooms"));
        return;
    }
    if (type == QStringLiteral("room_details_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        signal(root, QStringLiteral("roomDetailsReceived"), {
            success && message.property(QStringLiteral("details")).isObject()
                ? message.property(QStringLiteral("details")) : nullValue(),
            message.property(QStringLiteral("request_id")),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось получить информацию о комнате")))
        });
        return;
    }
    if (type == QStringLiteral("leave_room_result")) {
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        const bool success = boolean(message.property(QStringLiteral("success")));
        callRoot(root, QStringLiteral("setRoomLeavePending"),
                 {QJSValue(roomId), QJSValue(false)});
        signal(root, QStringLiteral("roomLeaveFinished"),
               {QJSValue(roomId), QJSValue(success),
                QJSValue(string(message.property(QStringLiteral("error"))))});
        if (!success)
            callRoot(root, QStringLiteral("requestRooms"));
        return;
    }
    if (type == QStringLiteral("space_hierarchy_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        signal(root, QStringLiteral("spaceHierarchyReceived"), {
            QJSValue(string(message.property(QStringLiteral("space_id")))),
            valueOrArray(engine, message.property(QStringLiteral("rooms"))),
            QJSValue(string(message.property(QStringLiteral("next_batch")))),
            QJSValue(responseCommand.isObject()
                && !string(responseCommand.property(QStringLiteral("from"))).isEmpty()),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось загрузить комнаты пространства")))
        });
        return;
    }
    if (type == QStringLiteral("join_space_room_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        const bool knocked = boolean(message.property(QStringLiteral("knocked")));
        signal(root, QStringLiteral("joinSpaceRoomFinished"), {
            QJSValue(string(message.property(QStringLiteral("room_id")))),
            QJSValue(success), QJSValue(knocked),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось войти в комнату")))
        });
        if (success && !knocked)
            callRoot(root, QStringLiteral("requestRooms"));
        return;
    }
    if (type == QStringLiteral("add_room_to_space_result")
        || type == QStringLiteral("remove_room_from_space_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        const bool add = type == QStringLiteral("add_room_to_space_result");
        Values args = {
            QJSValue(string(message.property(QStringLiteral("room_id")))),
            QJSValue(string(message.property(QStringLiteral("space_id")))),
            QJSValue(success),
            QJSValue(success ? QString() : errorOr(root, message, add
                ? QStringLiteral("Не удалось добавить комнату в пространство")
                : QStringLiteral("Не удалось убрать комнату из пространства")))
        };
        if (!add)
            args.append(message.property(QStringLiteral("request_id")));
        signal(root, add ? QStringLiteral("roomAddedToSpace")
                         : QStringLiteral("roomRemovedFromSpace"), args);
        return;
    }
    if (type == QStringLiteral("update_room_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        signal(root, QStringLiteral("roomUpdateFinished"), {
            message.property(QStringLiteral("room_id")), QJSValue(success),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось изменить комнату")))
        });
        return;
    }
    if (type == QStringLiteral("room_member_moderation_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        signal(root, QStringLiteral("roomMemberModerationFinished"), {
            message.property(QStringLiteral("room_id")),
            message.property(QStringLiteral("user_id")),
            message.property(QStringLiteral("action")), QJSValue(success),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось выполнить действие модерации"))),
            message.property(QStringLiteral("request_id"))
        });
        if (success)
            callRoot(root, QStringLiteral("requestRooms"));
        return;
    }
    if (type == QStringLiteral("open_direct_message_result")
        || type == QStringLiteral("create_room_result")) {
        const bool direct = type == QStringLiteral("open_direct_message_result");
        const bool success = boolean(message.property(QStringLiteral("success")));
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        const QJSValue model = root.property(QStringLiteral("roomModel"));
        if (success && !roomId.isEmpty() && model.isObject()) {
            bool exists = false;
            for (int index = 0; index < modelCount(model); ++index) {
                if (string(modelGet(model, index).property(QStringLiteral("room_id"))) != roomId)
                    continue;
                exists = true;
                if (direct && !string(message.property(QStringLiteral("avatar_url"))).isEmpty())
                    modelSetProperty(model, index, QStringLiteral("avatar_url"),
                                     message.property(QStringLiteral("avatar_url")));
                if (!direct) {
                    QString name = string(message.property(QStringLiteral("room_name")));
                    modelSetProperty(model, index, QStringLiteral("name"),
                                     QJSValue(name.isEmpty() ? roomId : name));
                    modelSetProperty(model, index, QStringLiteral("is_space"),
                                     QJSValue(boolean(message.property(QStringLiteral("is_space")))));
                }
                break;
            }
            if (!exists) {
                QJSValue raw = objectFromProperties(engine, {
                    {QStringLiteral("room_id"), QJSValue(roomId)},
                    {QStringLiteral("name"), QJSValue(string(message.property(QStringLiteral("room_name"))).isEmpty()
                        ? (direct ? string(message.property(QStringLiteral("target_user_id"))) : roomId)
                        : string(message.property(QStringLiteral("room_name"))))},
                    {QStringLiteral("is_space"), QJSValue(!direct
                        && boolean(message.property(QStringLiteral("is_space"))))},
                    {QStringLiteral("room_state"), QJSValue(QStringLiteral("joined"))},
                    {QStringLiteral("last_timestamp"), QJSValue(double(nowMs()))}
                });
                if (direct) {
                    raw.setProperty(QStringLiteral("avatar_url"),
                                    message.property(QStringLiteral("avatar_url")));
                    raw.setProperty(QStringLiteral("is_dm"), QJSValue(true));
                    raw.setProperty(QStringLiteral("direct_user_id"),
                                    message.property(QStringLiteral("target_user_id")));
                    raw.setProperty(QStringLiteral("is_ignored"), QJSValue(false));
                }
                call(model, QStringLiteral("insert"),
                     {QJSValue(0), callRoot(root, QStringLiteral("normalizeRoom"), {raw})});
                callRoot(root, QStringLiteral("applyRoomOrder"));
            }
            if (!direct)
                callRoot(root, QStringLiteral("requestRooms"));
        }
        if (direct) {
            signal(root, QStringLiteral("directMessageReady"), {
                QJSValue(roomId), message.property(QStringLiteral("room_name")),
                message.property(QStringLiteral("avatar_url")),
                QJSValue(boolean(message.property(QStringLiteral("created")))),
                message.property(QStringLiteral("error")),
                message.property(QStringLiteral("request_id"))
            });
        } else {
            signal(root, QStringLiteral("roomCreated"), {
                QJSValue(roomId), message.property(QStringLiteral("room_name")),
                QJSValue(boolean(message.property(QStringLiteral("is_space")))),
                message.property(QStringLiteral("error")),
                message.property(QStringLiteral("request_id"))
            });
        }
        return;
    }
    if (type == QStringLiteral("room_members_result")) {
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        const QString errorText = string(message.property(QStringLiteral("error")));
        if (message.property(QStringLiteral("success")).isBool()
            && !boolean(message.property(QStringLiteral("success")))
            && errorText.startsWith(QStringLiteral("MEMBERS_SNAPSHOT_STALE"))) {
            setMapValue(engine, root, QStringLiteral("roomMembersRefreshQueued"), roomId,
                        undefined(), true);
            callRoot(root, QStringLiteral("finishRoomMembersRequest"), {QJSValue(roomId)});
            setMapValue(engine, root, QStringLiteral("roomMembersNextTokens"), roomId,
                        QJSValue(QString()));
            if (QObject *context = root.toQObject()) {
                QTimer::singleShot(0, context, [root, roomId] {
                    if (roomId == string(root.property(QStringLiteral("currentRoomId"))))
                        callRoot(root, QStringLiteral("requestRoomMembers"), {QJSValue(roomId)});
                });
            }
            return;
        }
        callRoot(root, QStringLiteral("finishRoomMembersRequest"), {QJSValue(roomId)});
        const bool success = boolean(message.property(QStringLiteral("success")));
        const QString membersError = success ? QString()
            : localizedError(root, errorText, QStringLiteral("Не удалось выполнить действие"));
        setMapValue(engine, root, QStringLiteral("roomMembersErrors"), roomId,
                    QJSValue(membersError), success);
        setMapValue(engine, root, QStringLiteral("roomMembersNextTokens"), roomId,
                    QJSValue(string(message.property(QStringLiteral("next_batch")))));
        const bool append = responseCommand.isObject()
            && !string(responseCommand.property(QStringLiteral("from"))).isEmpty();
        const QJSValue members = valueOrArray(engine,
            message.property(QStringLiteral("members")));
        if (success) {
            const int previous = root.property(QStringLiteral("roomMembersLoadedCounts"))
                                     .property(roomId).toInt();
            setMapValue(engine, root, QStringLiteral("roomMembersLoadedCounts"), roomId,
                        QJSValue(append ? previous + length(members) : length(members)));
        }
        signal(root, QStringLiteral("roomMembersReceived"), {
            QJSValue(roomId), members,
            QJSValue(string(message.property(QStringLiteral("next_batch")))),
            QJSValue(append), QJSValue(membersError)
        });
        return;
    }
    if (type == QStringLiteral("room_members_changed")) {
        if (qRound(number(message.property(QStringLiteral("session_epoch"))))
            == root.property(QStringLiteral("timelineSessionEpoch")).toInt()
            && string(message.property(QStringLiteral("room_id")))
                == string(root.property(QStringLiteral("currentRoomId")))) {
            callRoot(root, QStringLiteral("queueRoomMembersRefresh"),
                     {root.property(QStringLiteral("currentRoomId"))});
        }
        return;
    }
    if (type == QStringLiteral("sync_completed")) {
        const int epoch = qRound(number(message.property(QStringLiteral("session_epoch"))));
        if (root.property(QStringLiteral("activeSessionEpoch")).toInt() == 0 && epoch > 0)
            set(root, QStringLiteral("activeSessionEpoch"), QJSValue(epoch));
        if (epoch != root.property(QStringLiteral("activeSessionEpoch")).toInt())
            return;
        callRoot(root, QStringLiteral("requestRooms"));
        if ((boolean(message.property(QStringLiteral("initial")))
             || boolean(message.property(QStringLiteral("identity_changed"))))
            && !string(root.property(QStringLiteral("authenticatedUserId"))).isEmpty()) {
            callRoot(root, QStringLiteral("requestUserDetails"),
                     {root.property(QStringLiteral("authenticatedUserId"))});
        }
        return;
    }
    if (type == QStringLiteral("user_search_result")
        || type == QStringLiteral("public_rooms_search_result")) {
        const bool users = type == QStringLiteral("user_search_result");
        const bool success = boolean(message.property(QStringLiteral("success")));
        if (users) {
            signal(root, QStringLiteral("userDirectorySearchReceived"), {
                success ? valueOrArray(engine, message.property(QStringLiteral("users"))) : emptyArray(engine),
                QJSValue(boolean(message.property(QStringLiteral("limited")))),
                QJSValue(success ? QString() : errorOr(root, message,
                    QStringLiteral("Не удалось найти пользователей"))),
                message.property(QStringLiteral("request_id"))
            });
        } else {
            signal(root, QStringLiteral("publicRoomSearchReceived"), {
                success ? valueOrArray(engine, message.property(QStringLiteral("rooms"))) : emptyArray(engine),
                message.property(QStringLiteral("next_batch")),
                QJSValue(success ? QString() : errorOr(root, message,
                    QStringLiteral("Не удалось найти комнаты"))),
                message.property(QStringLiteral("request_id"))
            });
        }
    }
}

void messageEvent(const QJSValue &root,
                  QJSEngine *engine,
                  const QJSValue &message,
                  const QJSValue &responseCommand)
{
    const QString type = string(message.property(QStringLiteral("type")));
    if (type == QStringLiteral("timeline_preview_result")) {
        const QString requestId = string(message.property(QStringLiteral("request_id")));
        const QJSValue requests = root.property(QStringLiteral("roomPreviewRequests"));
        if (requestId.isEmpty() || requests.property(requestId).isUndefined())
            return;
        const QJSValue request = requests.property(requestId);
        setMapValue(engine, root, QStringLiteral("roomPreviewRequests"), requestId,
                    undefined(), true);
        if (boolean(request.property(QStringLiteral("prefetch")))) {
            callRoot(root, QStringLiteral("finishRoomPreviewPrefetch"), {request, message});
            return;
        }
        const bool success = !message.property(QStringLiteral("success")).isBool()
            || boolean(message.property(QStringLiteral("success")));
        const QString previewError = success ? QString()
            : errorOr(root, message, QStringLiteral("Не удалось загрузить предпросмотр"));
        const QJSValue preview = previewError.isEmpty()
            ? normalizeMessages(root, engine, message.property(QStringLiteral("messages")))
            : emptyArray(engine);
        QString roomId = string(request.property(QStringLiteral("room_id")));
        if (roomId.isEmpty())
            roomId = string(message.property(QStringLiteral("room_id")));
        if (previewError.isEmpty()
            && !boolean(request.property(QStringLiteral("append"))))
            callRoot(root, QStringLiteral("cacheRoomPreview"), {QJSValue(roomId), preview});
        signal(root, QStringLiteral("roomPreviewReceived"), {
            QJSValue(roomId), preview, message.property(QStringLiteral("next_from")),
            QJSValue(boolean(request.property(QStringLiteral("append")))),
            QJSValue(previewError), QJSValue(requestId)
        });
        return;
    }
    if (type == QStringLiteral("message_context_result")) {
        const QString requestId = string(message.property(QStringLiteral("request_id")));
        const QJSValue rooms = root.property(QStringLiteral("messageRequestRooms"));
        if (requestId.isEmpty() || rooms.property(requestId).isUndefined())
            return;
        const QString roomId = string(rooms.property(requestId));
        const QString eventId = string(root.property(QStringLiteral("messageRequestTargets"))
                                           .property(requestId));
        callRoot(root, QStringLiteral("cleanupMessageRequest"),
                 {QJSValue(requestId), QJSValue(roomId)});
        if (roomId.isEmpty())
            return;
        if (message.property(QStringLiteral("success")).isBool()
            && !boolean(message.property(QStringLiteral("success")))) {
            signal(root, QStringLiteral("messageContextReceived"),
                   {QJSValue(roomId), QJSValue(eventId), QJSValue(false)});
            feedback(root, errorOr(root, message, QStringLiteral("Не удалось открыть сообщение")), true);
            return;
        }
        const QJSValue normalized = normalizeMessages(root, engine,
            message.property(QStringLiteral("messages")));
        if (roomId != string(root.property(QStringLiteral("currentRoomId"))))
            return;
        set(root, QStringLiteral("isLoadingMessages"), QJSValue(false));
        callRoot(root, QStringLiteral("replaceMessageModel"), {normalized});
        set(root, QStringLiteral("displayedRoomId"), QJSValue(roomId));
        bool found = false;
        for (const QJSValue &item : values(normalized)) {
            if (string(item.property(QStringLiteral("event_id"))) == eventId) {
                found = true;
                break;
            }
        }
        set(root, QStringLiteral("displayedContextEventId"),
            QJSValue(found ? eventId : QString()));
        signal(root, QStringLiteral("messageContextReceived"),
               {QJSValue(roomId), QJSValue(eventId), QJSValue(found)});
        return;
    }
    if (type == QStringLiteral("mark_room_read_result")) {
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        const QString requestId = string(message.property(QStringLiteral("request_id")));
        if (!responseCommand.isObject()
            || string(root.property(QStringLiteral("readStateRequestByRoom")).property(roomId))
                != requestId)
            return;
        const bool success = boolean(message.property(QStringLiteral("success")));
        if (string(responseCommand.property(QStringLiteral("type")))
            == QStringLiteral("mark_room_read")) {
            callRoot(root, QStringLiteral("finishRoomRead"),
                     {QJSValue(roomId), QJSValue(requestId), QJSValue(success)});
            if (!success) {
                setMapValue(engine, root, QStringLiteral("lastReadEventByRoom"), roomId,
                            undefined(), true);
                feedback(root, errorOr(root, message,
                    QStringLiteral("Не удалось обновить статус прочтения:")), true);
            }
            callRoot(root, QStringLiteral("flushQueuedRoomRead"), {QJSValue(roomId)});
            return;
        }
        const QJSValue markedValue = message.property(QStringLiteral("marked_unread"));
        if (success) {
            if (markedValue.isBool() && markedValue.toBool()) {
                callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                         {QJSValue(roomId), QJSValue(true)});
                callRoot(root, QStringLiteral("setRoomUnreadCount"), {
                    QJSValue(roomId), callRoot(root, QStringLiteral("manualUnreadCount"), {QJSValue(roomId)})
                });
            } else if (markedValue.isBool() && !markedValue.toBool()) {
                callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                         {QJSValue(roomId), QJSValue(false)});
                callRoot(root, QStringLiteral("setRoomUnreadCount"), {QJSValue(roomId), QJSValue(0)});
                callRoot(root, QStringLiteral("setManualUnreadHold"), {QJSValue(roomId), QJSValue(false)});
                callRoot(root, QStringLiteral("setManualUnreadDetails"),
                         {QJSValue(roomId), QJSValue(QString()), QJSValue(0)});
            } else {
                callRoot(root, QStringLiteral("setRoomUnreadCount"), {QJSValue(roomId), QJSValue(0)});
            }
        } else {
            if (markedValue.isBool() && markedValue.toBool()) {
                callRoot(root, QStringLiteral("setManualUnreadHold"), {QJSValue(roomId), QJSValue(false)});
                callRoot(root, QStringLiteral("setManualUnreadDetails"),
                         {QJSValue(roomId), QJSValue(QString()), QJSValue(0)});
                callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                         {QJSValue(roomId), QJSValue(false)});
                callRoot(root, QStringLiteral("setRoomUnreadCount"), {QJSValue(roomId), QJSValue(0)});
                if (roomId == string(root.property(QStringLiteral("currentRoomId")))) {
                    set(root, QStringLiteral("unreadBoundaryEventId"), QJSValue(QString()));
                    set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
                }
            } else if (markedValue.isBool() && !markedValue.toBool()) {
                callRoot(root, QStringLiteral("setManualUnreadHold"), {QJSValue(roomId), QJSValue(true)});
                callRoot(root, QStringLiteral("setRoomMarkedUnreadLocal"),
                         {QJSValue(roomId), QJSValue(true)});
                callRoot(root, QStringLiteral("setRoomUnreadCount"), {
                    QJSValue(roomId), callRoot(root, QStringLiteral("manualUnreadCount"), {QJSValue(roomId)})
                });
            }
            setMapValue(engine, root, QStringLiteral("lastReadEventByRoom"), roomId,
                        undefined(), true);
        }
        return;
    }
    if (type == QStringLiteral("redact_result")) {
        if (!boolean(message.property(QStringLiteral("success"))))
            feedback(root, tr(root, QStringLiteral("Не удалось удалить сообщение: "))
                + errorOr(root, message, QStringLiteral("неизвестная ошибка")), true);
        return;
    }
    if (type == QStringLiteral("clipboard_paste_result")) {
        signal(root, QStringLiteral("clipboardPasteFinished"), {
            message.property(QStringLiteral("request_id")),
            QJSValue(boolean(message.property(QStringLiteral("success")))),
            message.property(QStringLiteral("text")),
            valueOrArray(engine, message.property(QStringLiteral("attachments"))),
            message.property(QStringLiteral("error"))
        });
        return;
    }
    if (type == QStringLiteral("upload_media_result")) {
        signal(root, QStringLiteral("uploadFinished"), {
            message.property(QStringLiteral("request_id")),
            QJSValue(boolean(message.property(QStringLiteral("success")))),
            message.property(QStringLiteral("error"))
        });
        return;
    }
    if (type == QStringLiteral("sticker_asset_upload_result")) {
        signal(root, QStringLiteral("stickerAssetUploaded"), {
            message.property(QStringLiteral("request_id")),
            QJSValue(boolean(message.property(QStringLiteral("success")))),
            message.property(QStringLiteral("media_url")),
            message.property(QStringLiteral("mime_type")),
            message.property(QStringLiteral("error"))
        });
        return;
    }
    if (type == QStringLiteral("send_message_result")) {
        const QJSValue sent = responseCommand;
        if (!boolean(message.property(QStringLiteral("success"))))
            feedback(root, tr(root, QStringLiteral("Сообщение не отправлено: "))
                + errorOr(root, message, QStringLiteral("неизвестная ошибка")), true);
        else if (sent.isObject()
                 && !string(sent.property(QStringLiteral("thread_root"))).isEmpty())
            signal(root, QStringLiteral("threadMutationFinished"), {
                sent.property(QStringLiteral("room_id")),
                sent.property(QStringLiteral("thread_root"))
            });
        return;
    }
    if (type == QStringLiteral("thread_messages_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        QJSValue messages = normalizeMessages(root, engine,
            message.property(QStringLiteral("messages")));
        messages = callRoot(root, QStringLiteral("propagateReadReceipts"), {messages});
        signal(root, QStringLiteral("threadMessagesReceived"), {
            message.property(QStringLiteral("room_id")),
            message.property(QStringLiteral("root_event_id")), messages,
            QJSValue(boolean(message.property(QStringLiteral("has_more")))),
            message.property(QStringLiteral("error")),
            message.property(QStringLiteral("request_id"))
        });
        return;
    }
    if (type == QStringLiteral("room_threads_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        Values threads;
        for (const QJSValue &summary : values(message.property(QStringLiteral("threads")))) {
            const QJSValue latest = summary.property(QStringLiteral("latest_reply"));
            threads.append(objectFromProperties(engine, {
                {QStringLiteral("root"), callRoot(root, QStringLiteral("normalizeMessage"),
                    {valueOrObject(engine, summary.property(QStringLiteral("root")))})},
                {QStringLiteral("latest_reply"), latest.isObject()
                    ? callRoot(root, QStringLiteral("normalizeMessage"), {latest}) : nullValue()},
                {QStringLiteral("reply_count"), QJSValue(number(summary.property(QStringLiteral("reply_count"))))},
                {QStringLiteral("unread"), QJSValue(boolean(summary.property(QStringLiteral("unread"))))}
            }));
        }
        signal(root, QStringLiteral("roomThreadsReceived"), {
            message.property(QStringLiteral("room_id")), arrayFromValues(engine, threads),
            message.property(QStringLiteral("next_from")),
            QJSValue(number(message.property(QStringLiteral("unread_count")))),
            message.property(QStringLiteral("error")),
            message.property(QStringLiteral("request_id"))
        });
        return;
    }
    if (type == QStringLiteral("mark_room_threads_read_result")
        || type == QStringLiteral("mark_thread_read_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        if (type == QStringLiteral("mark_room_threads_read_result")) {
            signal(root, QStringLiteral("allThreadsReadFinished"), {
                message.property(QStringLiteral("room_id")),
                QJSValue(boolean(message.property(QStringLiteral("success")))),
                valueOrObject(engine, message.property(QStringLiteral("read_events"))),
                message.property(QStringLiteral("error")),
                message.property(QStringLiteral("request_id"))
            });
        } else {
            signal(root, QStringLiteral("threadReadFinished"), {
                message.property(QStringLiteral("room_id")),
                message.property(QStringLiteral("root_event_id")),
                QJSValue(boolean(message.property(QStringLiteral("success")))),
                message.property(QStringLiteral("error"))
            });
        }
        return;
    }
    if (type == QStringLiteral("retry_message_result")) {
        const QJSValue retry = responseCommand;
        const bool success = boolean(message.property(QStringLiteral("success")));
        signal(root, QStringLiteral("retryMessageFinished"), {
            message.property(QStringLiteral("room_id")),
            message.property(QStringLiteral("timeline_item_id")),
            QJSValue(success), message.property(QStringLiteral("error"))
        });
        if (success && retry.isObject()
            && !string(retry.property(QStringLiteral("thread_root"))).isEmpty())
            signal(root, QStringLiteral("threadMutationFinished"), {
                retry.property(QStringLiteral("room_id")),
                retry.property(QStringLiteral("thread_root"))
            });
        if (!success)
            feedback(root, tr(root, QStringLiteral("Не удалось повторить отправку: "))
                + errorOr(root, message, QStringLiteral("неизвестная ошибка")), true);
        return;
    }
    if (type == QStringLiteral("edit_result")) {
        signal(root, QStringLiteral("editMessageFinished"), {
            message.property(QStringLiteral("request_id")),
            QJSValue(boolean(message.property(QStringLiteral("success")))),
            message.property(QStringLiteral("error"))
        });
        return;
    }
    if (type == QStringLiteral("pinned_messages_result")) {
        const bool success = boolean(message.property(QStringLiteral("success")));
        callRoot(root, QStringLiteral("finishPinnedMessagesRequest"), {
            message.property(QStringLiteral("room_id")),
            success ? valueOrArray(engine, message.property(QStringLiteral("messages")))
                    : emptyArray(engine),
            QJSValue(success ? QString() : errorOr(root, message,
                QStringLiteral("Не удалось загрузить закреплённые сообщения")))
        });
        return;
    }
    if (type == QStringLiteral("pin_message_result")
        || type == QStringLiteral("reaction_result")) {
        const bool pin = type == QStringLiteral("pin_message_result");
        const bool success = boolean(message.property(QStringLiteral("success")));
        const QString error = success ? QString() : errorOr(root, message, pin
            ? QStringLiteral("Не удалось закрепить сообщение")
            : QStringLiteral("Не удалось отправить реакцию"));
        signal(root, pin ? QStringLiteral("pinMessageFinished")
                         : QStringLiteral("reactionFinished"),
               {message.property(QStringLiteral("room_id")), QJSValue(success), QJSValue(error)});
        if (pin && success) {
            QString roomId = string(message.property(QStringLiteral("room_id")));
            if (roomId.isEmpty())
                roomId = string(root.property(QStringLiteral("currentRoomId")));
            callRoot(root, QStringLiteral("requestPinnedMessages"),
                     {QJSValue(roomId), QJSValue(true)});
        }
        if (!pin && !success)
            feedback(root, error, true);
        return;
    }
    if (type == QStringLiteral("room_attachments_result")
        || type == QStringLiteral("search_room_messages_result")) {
        const bool attachments = type == QStringLiteral("room_attachments_result");
        const bool success = boolean(message.property(QStringLiteral("success")));
        const QJSValue normalized = normalizeMessages(root, engine,
            message.property(QStringLiteral("messages")));
        if (attachments) {
            signal(root, QStringLiteral("roomAttachmentsReceived"), {
                message.property(QStringLiteral("room_id")), normalized,
                message.property(QStringLiteral("next_from")),
                QJSValue(success ? QString() : errorOr(root, message,
                    QStringLiteral("Не удалось загрузить вложения"))),
                message.property(QStringLiteral("request_id"))
            });
        } else {
            signal(root, QStringLiteral("roomSearchReceived"), {
                message.property(QStringLiteral("room_id")), normalized,
                message.property(QStringLiteral("next_batch")),
                QJSValue(success ? QString() : errorOr(root, message,
                    QStringLiteral("Ошибка поиска"))),
                message.property(QStringLiteral("request_id"))
            });
        }
    }
}

void securityEvent(const QJSValue &root,
                   QJSEngine *engine,
                   const QJSValue &message)
{
    const QString type = string(message.property(QStringLiteral("type")));
    if (type == QStringLiteral("export_room_keys_result")
        || type == QStringLiteral("import_room_keys_result")) {
        const bool exportKeys = type == QStringLiteral("export_room_keys_result");
        signal(root, QStringLiteral("roomKeysTransferFinished"), {
            message.property(QStringLiteral("request_id")),
            QJSValue(exportKeys ? QStringLiteral("export") : QStringLiteral("import")),
            QJSValue(boolean(message.property(QStringLiteral("success")))),
            QJSValue(exportKeys ? 0 : number(message.property(QStringLiteral("imported_count")))),
            QJSValue(exportKeys ? 0 : number(message.property(QStringLiteral("total_count")))),
            message.property(QStringLiteral("error"))
        });
        return;
    }
    if (type == QStringLiteral("encryption_overview_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        signal(root, QStringLiteral("encryptionOverviewReceived"), {
            message.property(QStringLiteral("overview")).isObject()
                ? message.property(QStringLiteral("overview")) : nullValue(),
            QJSValue(message.property(QStringLiteral("success")).isBool()
                     && !boolean(message.property(QStringLiteral("success")))
                ? errorOr(root, message, QStringLiteral("Не удалось получить состояние шифрования"))
                : QString())
        });
        return;
    }
    if (type == QStringLiteral("matrix_devices_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        signal(root, QStringLiteral("matrixDevicesReceived"), {
            valueOrArray(engine, message.property(QStringLiteral("devices"))),
            QJSValue(message.property(QStringLiteral("success")).isBool()
                     && !boolean(message.property(QStringLiteral("success")))
                ? errorOr(root, message, QStringLiteral("Не удалось получить устройства"))
                : QString())
        });
        return;
    }
    if (type == QStringLiteral("devices_changed")) {
        const int epoch = qRound(number(message.property(QStringLiteral("session_epoch"))));
        if (epoch == root.property(QStringLiteral("activeSessionEpoch")).toInt())
            signal(root, QStringLiteral("matrixDevicesChanged"),
                   {valueOrArray(engine, message.property(QStringLiteral("devices"))), QJSValue(epoch)});
        return;
    }
    if (type == QStringLiteral("device_operation_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        signal(root, QStringLiteral("deviceOperationFinished"), {
            message.property(QStringLiteral("request_id")),
            message.property(QStringLiteral("operation")),
            QJSValue(boolean(message.property(QStringLiteral("success")))),
            valueOrArray(engine, message.property(QStringLiteral("device_ids"))),
            message.property(QStringLiteral("error"))
        });
        return;
    }
    if (type == QStringLiteral("device_delete_uiaa_required")
        || type == QStringLiteral("device_delete_web_required")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        if (type == QStringLiteral("device_delete_uiaa_required")) {
            signal(root, QStringLiteral("deviceDeleteUiaaRequired"), {
                message.property(QStringLiteral("request_id")),
                message.property(QStringLiteral("operation_id")),
                valueOrArray(engine, message.property(QStringLiteral("flows"))),
                QJSValue(boolean(message.property(QStringLiteral("password_supported"))))
            });
        } else {
            signal(root, QStringLiteral("deviceDeleteWebRequired"), {
                message.property(QStringLiteral("request_id")),
                valueOrArray(engine, message.property(QStringLiteral("device_ids"))),
                message.property(QStringLiteral("url"))
            });
        }
        return;
    }
    if (type == QStringLiteral("e2ee_action_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        signal(root, QStringLiteral("e2eeActionFinished"), {
            message.property(QStringLiteral("request_id")),
            QJSValue(boolean(message.property(QStringLiteral("success")))),
            message.property(QStringLiteral("uiaa_session")),
            message.property(QStringLiteral("auth_type")),
            message.property(QStringLiteral("approval_url")),
            message.property(QStringLiteral("recovery_key")),
            message.property(QStringLiteral("flow_id")),
            message.property(QStringLiteral("error"))
        });
        return;
    }
    if (type == QStringLiteral("verification_update")) {
        if (qRound(number(message.property(QStringLiteral("session_epoch"))))
            == root.property(QStringLiteral("activeSessionEpoch")).toInt())
            signal(root, QStringLiteral("verificationUpdated"), {message});
        return;
    }
    if (type == QStringLiteral("encryption_state_changed")
        && qRound(number(message.property(QStringLiteral("session_epoch"))))
            == root.property(QStringLiteral("activeSessionEpoch")).toInt()) {
        signal(root, QStringLiteral("encryptionOverviewReceived"), {
            message.property(QStringLiteral("overview")).isObject()
                ? message.property(QStringLiteral("overview")) : nullValue(),
            QJSValue(QString())
        });
    }
}

void storageEvent(const QJSValue &root,
                  QJSEngine *engine,
                  const QJSValue &message)
{
    const QString type = string(message.property(QStringLiteral("type")));
    if (type == QStringLiteral("storage_stats_result")) {
        double cacheLimitMb = number(message.property(QStringLiteral("cache_limit_mb")));
        if (cacheLimitMb == 0)
            cacheLimitMb = 1024;
        signal(root, QStringLiteral("storageStatsReceived"), {
            objectFromProperties(engine, {
                {QStringLiteral("sqlite_bytes"), QJSValue(number(message.property(QStringLiteral("sqlite_bytes"))))},
                {QStringLiteral("event_cache_bytes"), QJSValue(number(message.property(QStringLiteral("event_cache_bytes"))))},
                {QStringLiteral("media_bytes"), QJSValue(number(message.property(QStringLiteral("media_bytes"))))},
                {QStringLiteral("total_cache_bytes"), QJSValue(number(message.property(QStringLiteral("total_cache_bytes"))))},
                {QStringLiteral("auto_cleanup_days"), QJSValue(number(message.property(QStringLiteral("auto_cleanup_days"))))},
                {QStringLiteral("cache_limit_mb"), QJSValue(cacheLimitMb)},
                {QStringLiteral("downloads_dir"), QJSValue(string(message.property(QStringLiteral("downloads_dir"))))},
                {QStringLiteral("auto_load_images"), QJSValue(!message.property(QStringLiteral("auto_load_images")).isBool()
                    || boolean(message.property(QStringLiteral("auto_load_images"))))},
                {QStringLiteral("auto_load_videos"), QJSValue(!message.property(QStringLiteral("auto_load_videos")).isBool()
                    || boolean(message.property(QStringLiteral("auto_load_videos"))))}
            }),
            QJSValue(boolean(message.property(QStringLiteral("success"))) ? QString()
                : errorOr(root, message, QStringLiteral("Не удалось получить сведения о хранилище")))
        });
        return;
    }
    QString action;
    QJSValue details = object(engine);
    if (type == QStringLiteral("clear_cache_result")) {
        action = QStringLiteral("clear_cache");
        details = objectFromProperties(engine, {
            {QStringLiteral("freed_bytes"), QJSValue(number(message.property(QStringLiteral("freed_bytes"))))},
            {QStringLiteral("restart_required"), QJSValue(boolean(message.property(QStringLiteral("restart_required"))))},
            {QStringLiteral("warnings"), valueOrArray(engine, message.property(QStringLiteral("warnings")))}
        });
    } else if (type == QStringLiteral("set_storage_preferences_result")) {
        action = QStringLiteral("set_storage_preferences");
    } else if (type == QStringLiteral("download_media_result")) {
        action = QStringLiteral("download_media");
        details = objectFromProperties(engine, {
            {QStringLiteral("path"), QJSValue(string(message.property(QStringLiteral("path"))))}
        });
    } else if (type == QStringLiteral("clear_temporary_data_result")) {
        action = QStringLiteral("clear_temporary_data");
        details = objectFromProperties(engine, {
            {QStringLiteral("removed_files"), QJSValue(number(message.property(QStringLiteral("removed_files"))))},
            {QStringLiteral("freed_bytes"), QJSValue(number(message.property(QStringLiteral("freed_bytes"))))},
            {QStringLiteral("warnings"), valueOrArray(engine, message.property(QStringLiteral("warnings")))}
        });
    } else if (type == QStringLiteral("export_diagnostics_result")) {
        action = QStringLiteral("export_diagnostics");
        details = objectFromProperties(engine, {
            {QStringLiteral("path"), QJSValue(string(message.property(QStringLiteral("path"))))}
        });
    }
    if (!action.isEmpty())
        signal(root, QStringLiteral("storageActionFinished"), {
            QJSValue(action), QJSValue(boolean(message.property(QStringLiteral("success")))),
            details, message.property(QStringLiteral("error"))
        });
}

QJSValue parseMessage(QJSEngine *engine, const QString &payload)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        return undefined();
    return fromVariant(engine, document.object().toVariantMap());
}

bool isAccountType(const QString &type)
{
    static const QSet<QString> types = {
        QStringLiteral("session_restored"), QStringLiteral("session_state_result"),
        QStringLiteral("login_result"), QStringLiteral("register_result"),
        QStringLiteral("logout_result"), QStringLiteral("profiles_result"),
        QStringLiteral("switch_profile_result"), QStringLiteral("current_profile_updated"),
        QStringLiteral("delete_profile_result"), QStringLiteral("set_avatar_result"),
        QStringLiteral("user_details_result"), QStringLiteral("user_ignored_result"),
        QStringLiteral("update_own_profile_result")
    };
    return types.contains(type);
}

bool isSecurityType(const QString &type)
{
    static const QSet<QString> types = {
        QStringLiteral("export_room_keys_result"), QStringLiteral("import_room_keys_result"),
        QStringLiteral("encryption_overview_result"), QStringLiteral("matrix_devices_result"),
        QStringLiteral("devices_changed"), QStringLiteral("device_operation_result"),
        QStringLiteral("device_delete_uiaa_required"), QStringLiteral("device_delete_web_required"),
        QStringLiteral("e2ee_action_result"), QStringLiteral("verification_update"),
        QStringLiteral("encryption_state_changed")
    };
    return types.contains(type);
}

bool isStorageType(const QString &type)
{
    static const QSet<QString> types = {
        QStringLiteral("storage_stats_result"), QStringLiteral("clear_cache_result"),
        QStringLiteral("set_storage_preferences_result"), QStringLiteral("download_media_result"),
        QStringLiteral("clear_temporary_data_result"), QStringLiteral("export_diagnostics_result")
    };
    return types.contains(type);
}

bool isRoomType(const QString &type)
{
    static const QSet<QString> types = {
        QStringLiteral("rooms_result"), QStringLiteral("room_invite_result"),
        QStringLiteral("room_details_result"), QStringLiteral("leave_room_result"),
        QStringLiteral("space_hierarchy_result"), QStringLiteral("join_space_room_result"),
        QStringLiteral("add_room_to_space_result"), QStringLiteral("remove_room_from_space_result"),
        QStringLiteral("update_room_result"), QStringLiteral("room_member_moderation_result"),
        QStringLiteral("open_direct_message_result"), QStringLiteral("create_room_result"),
        QStringLiteral("room_members_result"), QStringLiteral("room_members_changed"),
        QStringLiteral("sync_completed"), QStringLiteral("user_search_result"),
        QStringLiteral("public_rooms_search_result")
    };
    return types.contains(type);
}

bool isMessageType(const QString &type)
{
    static const QSet<QString> types = {
        QStringLiteral("timeline_preview_result"), QStringLiteral("message_context_result"),
        QStringLiteral("mark_room_read_result"), QStringLiteral("redact_result"),
        QStringLiteral("clipboard_paste_result"), QStringLiteral("upload_media_result"),
        QStringLiteral("sticker_asset_upload_result"), QStringLiteral("send_message_result"),
        QStringLiteral("thread_messages_result"), QStringLiteral("room_threads_result"),
        QStringLiteral("mark_room_threads_read_result"), QStringLiteral("mark_thread_read_result"),
        QStringLiteral("retry_message_result"), QStringLiteral("edit_result"),
        QStringLiteral("pinned_messages_result"), QStringLiteral("pin_message_result"),
        QStringLiteral("reaction_result"), QStringLiteral("room_attachments_result"),
        QStringLiteral("search_room_messages_result")
    };
    return types.contains(type);
}

} // namespace

Result invokeEvents(const QString &operation,
                    const QJSValue &root,
                    const QJSValue &arguments)
{
    if (operation != QStringLiteral("receiveBackend"))
        return std::nullopt;
    QJSEngine *engine = engineFor(root);
    const QJSValue message = parseMessage(engine, string(argument(arguments, 0)));
    if (!message.isObject())
        return undefined();

    const QJSValue proxy = message.property(QStringLiteral("media_proxy_url"));
    if (proxy.isString())
        set(root, QStringLiteral("mediaProxyBase"), proxy);
    const QString type = string(message.property(QStringLiteral("type")));

    if (type == QStringLiteral("system_notification_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        return undefined();
    }
    if (type == QStringLiteral("capabilities")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        set(root, QStringLiteral("timelineDiffsSupported"),
            QJSValue(boolean(message.property(QStringLiteral("timeline_diffs_v1")))));
        set(root, QStringLiteral("mediaProxyBase"),
            QJSValue(string(message.property(QStringLiteral("media_proxy_url")))));
        const QJSValue socket = root.property(QStringLiteral("socketObject"));
        const int nativeDelay = qRound(number(message.property(QStringLiteral("native_fallback_delay_ms"))));
        const int reconnectDelay = qRound(number(message.property(QStringLiteral("reconnect_delay_ms"))));
        const int normalTimeout = qRound(number(message.property(QStringLiteral("default_command_timeout_ms"))));
        const int longTimeout = qRound(number(message.property(QStringLiteral("long_command_timeout_ms"))));
        if (nativeDelay > 0)
            set(socket, QStringLiteral("nativeFallbackDelayMs"), QJSValue(nativeDelay));
        if (reconnectDelay > 0)
            set(socket, QStringLiteral("reconnectDelayMs"), QJSValue(reconnectDelay));
        if (normalTimeout > 0)
            set(root, QStringLiteral("defaultCommandTimeoutMs"), QJSValue(normalTimeout));
        if (longTimeout > 0)
            set(root, QStringLiteral("longCommandTimeoutMs"), QJSValue(longTimeout));
        sendCommand(root, objectFromProperties(engine, {
            {QStringLiteral("type"), QJSValue(QStringLiteral("get_session_state"))},
            {QStringLiteral("request_id"), nextRequestId(root, QStringLiteral("session-state"))}
        }));
        return undefined();
    }
    if (type == QStringLiteral("timeline_snapshot")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        callRoot(root, QStringLiteral("applyTimelineSnapshot"), {message});
        return undefined();
    }
    if (type == QStringLiteral("timeline_diffs")) {
        callRoot(root, QStringLiteral("applyTimelineDiffs"), {message});
        return undefined();
    }
    if (type == QStringLiteral("timeline_status")) {
        const QString requestId = string(message.property(QStringLiteral("request_id")));
        const QJSValue pending = root.property(QStringLiteral("pendingCommands")).property(requestId);
        const QString pendingType = string(pending.property(QStringLiteral("type")));
        if (pending.isObject() && pendingType == QStringLiteral("close_timeline")) {
            if (!boolean(message.property(QStringLiteral("paginating_backwards"))))
                callRoot(root, QStringLiteral("takePendingCommand"), {QJSValue(requestId)});
            return undefined();
        }
        if (pending.isObject() && pendingType == QStringLiteral("open_timeline")) {
            if (string(message.property(QStringLiteral("error"))).isEmpty())
                return undefined();
            callRoot(root, QStringLiteral("takePendingCommand"), {QJSValue(requestId)});
            const QString roomId = string(pending.property(QStringLiteral("room_id")));
            if (roomId != string(root.property(QStringLiteral("currentRoomId")))
                || string(root.property(QStringLiteral("timelineRequestByRoom")).property(roomId))
                    != requestId
                || (root.property(QStringLiteral("activeSessionEpoch")).toInt() > 0
                    && qRound(number(message.property(QStringLiteral("session_epoch"))))
                        != root.property(QStringLiteral("activeSessionEpoch")).toInt())
                || (!message.property(QStringLiteral("request_generation")).isUndefined()
                    && number(message.property(QStringLiteral("request_generation")))
                        != number(pending.property(QStringLiteral("request_generation")))))
                return undefined();
            setMapValue(engine, root, QStringLiteral("timelineRequestByRoom"), roomId,
                        undefined(), true);
            set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
            set(root, QStringLiteral("timelineInitialPositionReady"), QJSValue(true));
            set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
            set(root, QStringLiteral("restoreEventId"), QJSValue(QString()));
            call(root.property(QStringLiteral("timelineInitialFillTimerObject")), QStringLiteral("stop"));
            set(root, QStringLiteral("isLoadingMessages"), QJSValue(false));
            const QJSValue model = root.property(QStringLiteral("messageModel"));
            set(root, QStringLiteral("showEmptyState"),
                QJSValue(!model.isObject() || modelCount(model) == 0));
            feedback(root, localizedError(root, string(message.property(QStringLiteral("error"))),
                                      QStringLiteral("Не удалось выполнить действие")), true);
            return undefined();
        }
        if (string(message.property(QStringLiteral("room_id")))
                != string(root.property(QStringLiteral("currentRoomId")))
            || qRound(number(message.property(QStringLiteral("session_epoch"))))
                != root.property(QStringLiteral("timelineSessionEpoch")).toInt()
            || (!message.property(QStringLiteral("generation")).isUndefined()
                && qRound(number(message.property(QStringLiteral("generation"))))
                    != root.property(QStringLiteral("timelineGeneration")).toInt())
            || string(root.property(QStringLiteral("timelinePaginationRequestId"))).isEmpty()
            || requestId != string(root.property(QStringLiteral("timelinePaginationRequestId"))))
            return undefined();
        const bool paginating = boolean(message.property(QStringLiteral("paginating_backwards")));
        if (!paginating)
            callRoot(root, QStringLiteral("takePendingCommand"), {QJSValue(requestId)});
        set(root, QStringLiteral("timelinePaginationInFlight"), QJSValue(paginating));
        if (!message.property(QStringLiteral("has_more_backwards")).isUndefined())
            set(root, QStringLiteral("timelineHasMoreBackwards"),
                QJSValue(boolean(message.property(QStringLiteral("has_more_backwards")))));
        if (!string(message.property(QStringLiteral("freshness"))).isEmpty())
            set(root, QStringLiteral("timelineFreshness"),
                callRoot(root, QStringLiteral("responseTimelineFreshness"), {message}));
        if (!boolean(root.property(QStringLiteral("timelineHasMoreBackwards")))
            && boolean(root.property(QStringLiteral("timelineCacheGapPending")))) {
            callRoot(root, QStringLiteral("applyTimelineDiffs"), {
                objectFromProperties(engine, {
                    {QStringLiteral("room_id"), root.property(QStringLiteral("currentRoomId"))},
                    {QStringLiteral("session_epoch"), root.property(QStringLiteral("timelineSessionEpoch"))},
                    {QStringLiteral("generation"), root.property(QStringLiteral("timelineGeneration"))},
                    {QStringLiteral("diffs"), emptyArray(engine)}
                })
            });
        }
        callRoot(root, QStringLiteral("refreshTimelineReadState"));
        if (!boolean(root.property(QStringLiteral("timelineHasMoreBackwards"))))
            set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
        callRoot(root, QStringLiteral("updateReadingPositionReady"));
        const QString statusError = string(message.property(QStringLiteral("error")));
        if (!statusError.isEmpty()) {
            set(root, QStringLiteral("timelineInitialPositionReady"), QJSValue(true));
            set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
            set(root, QStringLiteral("restoreEventId"), QJSValue(QString()));
            set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
            call(root.property(QStringLiteral("timelineInitialFillTimerObject")), QStringLiteral("stop"));
            feedback(root, statusError, true);
        }
        if (!paginating) {
            const bool completedInitial = boolean(root.property(QStringLiteral("timelinePaginationWasInitialFill")));
            const bool progress = length(root.property(QStringLiteral("timelineItems")))
                > root.property(QStringLiteral("timelinePaginationStartItemCount")).toInt();
            set(root, QStringLiteral("timelinePaginationRoomId"), QJSValue(QString()));
            set(root, QStringLiteral("timelinePaginationRequestId"), QJSValue(QString()));
            set(root, QStringLiteral("timelinePaginationWasInitialFill"), QJSValue(false));
            if (completedInitial && statusError.isEmpty()) {
                int stalled = progress ? 0
                    : root.property(QStringLiteral("timelineInitialFillStalledPages")).toInt() + 1;
                set(root, QStringLiteral("timelineInitialFillStalledPages"), QJSValue(stalled));
                if (stalled >= 2) {
                    set(root, QStringLiteral("timelineInitialFillActive"), QJSValue(false));
                    set(root, QStringLiteral("timelineInitialPositionReady"), QJSValue(true));
                    set(root, QStringLiteral("unreadBoundaryPending"), QJSValue(false));
                    set(root, QStringLiteral("restoreEventId"), QJSValue(QString()));
                } else if (boolean(root.property(QStringLiteral("timelineInitialFillActive")))) {
                    call(root.property(QStringLiteral("timelineInitialFillTimerObject")),
                         QStringLiteral("restart"));
                }
            }
            signal(root, QStringLiteral("timelinePaginationFinished"));
        }
        callRoot(root, QStringLiteral("updateTimelineLoadingState"));
        return undefined();
    }
    if (type == QStringLiteral("sync_freshness_changed")) {
        const int epoch = qRound(number(message.property(QStringLiteral("session_epoch"))));
        if (epoch <= 0 || (root.property(QStringLiteral("activeSessionEpoch")).toInt() > 0
                           && epoch != root.property(QStringLiteral("activeSessionEpoch")).toInt()))
            return undefined();
        set(root, QStringLiteral("syncFreshnessEpoch"), QJSValue(epoch));
        QString freshness = string(message.property(QStringLiteral("freshness")));
        if (freshness.isEmpty())
            freshness = QStringLiteral("offline");
        set(root, QStringLiteral("syncFreshness"), QJSValue(freshness));
        if (epoch == root.property(QStringLiteral("timelineSessionEpoch")).toInt()) {
            set(root, QStringLiteral("timelineFreshness"), QJSValue(freshness));
            callRoot(root, QStringLiteral("refreshTimelineReadState"));
            callRoot(root, QStringLiteral("updateTimelineLoadingState"));
        }
        return undefined();
    }
    if (type == QStringLiteral("room_invitation")) {
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        if (!roomId.isEmpty())
            setMapValue(engine, root, QStringLiteral("knownInvitedRoomIds"), roomId,
                        QJSValue(true));
        signal(root, QStringLiteral("roomInvitationReceived"), {
            QJSValue(roomId), message.property(QStringLiteral("room_name")),
            message.property(QStringLiteral("inviter"))
        });
        return undefined();
    }
    if (type == QStringLiteral("typing_users_changed")) {
        const int epoch = qRound(number(message.property(QStringLiteral("session_epoch"))));
        if (epoch <= 0 || (root.property(QStringLiteral("activeSessionEpoch")).toInt() > 0
                           && epoch != root.property(QStringLiteral("activeSessionEpoch")).toInt()))
            return undefined();
        const QString roomId = string(message.property(QStringLiteral("room_id")));
        if (roomId.isEmpty())
            return undefined();
        const QJSValue userIds = valueOrArray(engine,
            message.property(QStringLiteral("user_ids")));
        setMapValue(engine, root, QStringLiteral("typingUserIdsByRoom"), roomId,
                    cloneArray(engine, userIds), length(userIds) == 0);
        return undefined();
    }
    if (type == QStringLiteral("typing_notice_result")) {
        callRoot(root, QStringLiteral("takePendingCommand"),
                 {message.property(QStringLiteral("request_id"))});
        return undefined();
    }
    if (type == QStringLiteral("upload_media_progress")) {
        const QString requestId = string(message.property(QStringLiteral("request_id")));
        QJSValue pending = cloneObject(engine, root.property(QStringLiteral("pendingCommands")));
        QJSValue pendingCommand = pending.property(requestId);
        if (pendingCommand.isObject()) {
            pendingCommand.setProperty(QStringLiteral("deadline"), QJSValue(double(nowMs()
                + callRoot(root, QStringLiteral("commandTimeoutMs"),
                           {QJSValue(QStringLiteral("upload_media"))}).toInt())));
            pending.setProperty(requestId, pendingCommand);
            set(root, QStringLiteral("pendingCommands"), pending);
        }
        signal(root, QStringLiteral("uploadProgressChanged"), {
            QJSValue(requestId), QJSValue(number(message.property(QStringLiteral("current")))),
            QJSValue(number(message.property(QStringLiteral("total"))))
        });
        return undefined();
    }

    QJSValue responseCommand = nullValue();
    const QString requestId = string(message.property(QStringLiteral("request_id")));
    if (!requestId.isEmpty()) {
        responseCommand = callRoot(root, QStringLiteral("takePendingCommand"),
                                   {QJSValue(requestId)});
        if (!responseCommand.isObject())
            return undefined();
    }

    if (isAccountType(type))
        accountEvent(root, engine, message);
    else if (isSecurityType(type))
        securityEvent(root, engine, message);
    else if (isStorageType(type))
        storageEvent(root, engine, message);
    else if (isRoomType(type))
        roomEvent(root, engine, message, responseCommand);
    else if (isMessageType(type))
        messageEvent(root, engine, message, responseCommand);
    return undefined();
}

} // namespace FrontendMatrixLogic

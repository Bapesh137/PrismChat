#include "frontend_logic.h"

#include "frontend_logic_support.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTextStream>

#include <limits>

using namespace FrontendLogicSupport;

namespace {

QString json(const QJSValue &value)
{
    const QVariant variant = value.toVariant();
    if (variant.metaType().id() == QMetaType::QVariantList)
        return QString::fromUtf8(QJsonDocument::fromVariant(variant).toJson(QJsonDocument::Compact));
    return QString::fromUtf8(QJsonDocument::fromVariant(variant).toJson(QJsonDocument::Compact));
}

QString displayName(const QString &sender)
{
    if (sender.isEmpty())
        return QStringLiteral("?");
    QString name = sender.section(QLatin1Char(':'), 0, 0);
    if (name.startsWith(QLatin1Char('@')))
        name.remove(0, 1);
    return name;
}

int arrayIndexOf(const QJSValue &arrayValue, const QString &needle)
{
    const int count = length(arrayValue);
    for (int index = 0; index < count; ++index) {
        if (string(arrayValue.property(index)) == needle)
            return index;
    }
    return -1;
}

QJSValue roomRecord(const QJSValue &root, const QString &roomId)
{
    if (roomId.isEmpty())
        return nullValue();
    const QJSValue model = root.property(QStringLiteral("roomsModelObject"));
    for (int index = 0; index < modelCount(model); ++index) {
        const QJSValue room = modelGet(model, index);
        if (string(room.property(QStringLiteral("room_id"))) == roomId)
            return room;
    }
    return nullValue();
}

QJSValue notificationModelForType(const QJSValue &root, const QString &type)
{
    return type == QStringLiteral("room_invitation")
        ? root.property(QStringLiteral("invitationNotificationsModelObject"))
        : root.property(QStringLiteral("mentionNotificationsModelObject"));
}

QJSValue notificationModelForId(const QJSValue &root, const QString &id)
{
    return id.startsWith(QStringLiteral("invite:"))
        ? root.property(QStringLiteral("invitationNotificationsModelObject"))
        : root.property(QStringLiteral("mentionNotificationsModelObject"));
}

int notificationIndex(const QJSValue &model, const QString &id)
{
    for (int index = 0; index < modelCount(model); ++index) {
        if (string(modelGet(model, index).property(QStringLiteral("notification_id"))) == id)
            return index;
    }
    return -1;
}

void recalculateNotificationCount(const QJSValue &root)
{
    int count = 0;
    const QJSValue invitations = root.property(QStringLiteral("invitationNotificationsModelObject"));
    const QJSValue mentions = root.property(QStringLiteral("mentionNotificationsModelObject"));
    for (int index = 0; index < modelCount(invitations); ++index)
        count += boolean(modelGet(invitations, index).property(QStringLiteral("unread"))) ? 1 : 0;
    for (int index = 0; index < modelCount(mentions); ++index)
        count += boolean(modelGet(mentions, index).property(QStringLiteral("unread"))) ? 1 : 0;
    set(root, QStringLiteral("notificationUnreadCount"), QJSValue(count));
}

void markNotificationModelRead(const QJSValue &model)
{
    for (int index = 0; index < modelCount(model); ++index)
        modelSetProperty(model, index, QStringLiteral("unread"), QJSValue(false));
}

QJSValue commandObject(QJSEngine *engine,
                       const QList<QPair<QString, QJSValue>> &properties)
{
    QJSValue result = object(engine);
    for (const auto &property : properties)
        result.setProperty(property.first, property.second);
    return result;
}

QJSValue shortcutResult(QJSEngine *engine, bool ok,
                        const QString &path = QString(),
                        const QString &errorCode = QString())
{
    QJSValue result = object(engine);
    result.setProperty(QStringLiteral("ok"), QJSValue(ok));
    result.setProperty(QStringLiteral("path"), QJSValue(path));
    result.setProperty(QStringLiteral("error"), QJSValue(errorCode));
    return result;
}

#if defined(Q_OS_LINUX)
QString desktopEntryArgument(QString value)
{
    value.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    value.replace(QLatin1Char('"'), QStringLiteral("\\\""));
    value.replace(QLatin1Char('`'), QStringLiteral("\\`"));
    value.replace(QLatin1Char('$'), QStringLiteral("\\$"));
    return QLatin1Char('"') + value + QLatin1Char('"');
}
#endif

QJSValue createDesktopShortcut(QJSEngine *engine)
{
    const QString desktopPath =
        QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (desktopPath.isEmpty() || !QDir().mkpath(desktopPath))
        return shortcutResult(engine, false, {}, QStringLiteral("desktop-unavailable"));

#if defined(Q_OS_WIN)
    const QString launcherPath = QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("Start-PrismChat.exe"));
    if (!QFileInfo::exists(launcherPath))
        return shortcutResult(engine, false, {}, QStringLiteral("launcher-missing"));

    const QString shortcutPath = QDir(desktopPath)
        .filePath(QStringLiteral("PrismChat.lnk"));
    if (QFileInfo::exists(shortcutPath) && !QFile::remove(shortcutPath))
        return shortcutResult(engine, false, {}, QStringLiteral("replace-failed"));
    if (!QFile::link(QDir::toNativeSeparators(launcherPath),
                     QDir::toNativeSeparators(shortcutPath)))
        return shortcutResult(engine, false, {}, QStringLiteral("create-failed"));
    return shortcutResult(engine, true, QDir::toNativeSeparators(shortcutPath));
#elif defined(Q_OS_LINUX)
    QString launcherPath = qEnvironmentVariable("APPIMAGE");
    if (launcherPath.isEmpty())
        launcherPath = qEnvironmentVariable("PRISMCHAT_LAUNCHER_PATH");
    if (launcherPath.isEmpty()) {
        const QString appDir = qEnvironmentVariable("APPDIR");
        if (!appDir.isEmpty())
            launcherPath = QDir(appDir).filePath(QStringLiteral("AppRun"));
    }
    if (launcherPath.isEmpty())
        launcherPath = QStandardPaths::findExecutable(QStringLiteral("PrismChat"));
    if (launcherPath.isEmpty())
        launcherPath = QStandardPaths::findExecutable(QStringLiteral("prismchat"));
    if (launcherPath.isEmpty() || !QFileInfo::exists(launcherPath))
        return shortcutResult(engine, false, {}, QStringLiteral("launcher-missing"));

    QString iconValue = QStringLiteral("prismchat");
    const QString appDir = qEnvironmentVariable("APPDIR");
    const QString bundledIcon = appDir.isEmpty()
        ? QString() : QDir(appDir).filePath(QStringLiteral("prismchat.png"));
    if (!bundledIcon.isEmpty() && QFileInfo::exists(bundledIcon)) {
        const QString iconDirectory = QDir(
            QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
            .filePath(QStringLiteral("icons/hicolor/512x512/apps"));
        if (QDir().mkpath(iconDirectory)) {
            const QString iconPath = QDir(iconDirectory)
                .filePath(QStringLiteral("prismchat.png"));
            if (QFileInfo::exists(iconPath))
                QFile::remove(iconPath);
            if (QFile::copy(bundledIcon, iconPath))
                iconValue = iconPath;
        }
    }

    const QString shortcutPath = QDir(desktopPath)
        .filePath(QStringLiteral("PrismChat.desktop"));
    QSaveFile shortcut(shortcutPath);
    if (!shortcut.open(QIODevice::WriteOnly | QIODevice::Text))
        return shortcutResult(engine, false, {}, QStringLiteral("create-failed"));
    QTextStream stream(&shortcut);
    stream << "[Desktop Entry]\n"
           << "Type=Application\n"
           << "Name=PrismChat\n"
           << "Comment=Matrix client\n"
           << "Exec=" << desktopEntryArgument(QFileInfo(launcherPath).absoluteFilePath()) << "\n"
           << "Icon=" << iconValue << "\n"
           << "Terminal=false\n"
           << "Categories=Network;Chat;InstantMessaging;\n"
           << "StartupWMClass=PrismChat\n";
    stream.flush();
    if (stream.status() != QTextStream::Ok || !shortcut.commit())
        return shortcutResult(engine, false, {}, QStringLiteral("create-failed"));
    const QFile::Permissions permissions = QFile::permissions(shortcutPath)
        | QFileDevice::ExeOwner | QFileDevice::ExeUser
        | QFileDevice::ExeGroup | QFileDevice::ExeOther;
    if (!QFile::setPermissions(shortcutPath, permissions))
        return shortcutResult(engine, false, {}, QStringLiteral("permissions-failed"));
    return shortcutResult(engine, true, shortcutPath);
#else
    return shortcutResult(engine, false, {}, QStringLiteral("unsupported-platform"));
#endif
}

} // namespace

QJSValue FrontendLogic::invokeWindow(const QString &operation,
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

    if (operation == QStringLiteral("createDesktopShortcut"))
        return createDesktopShortcut(engine);

    if (operation == QStringLiteral("clearMainState")) {
        set(root, QStringLiteral("currentRoomId"), QJSValue(QString()));
        set(root, QStringLiteral("currentRoomName"),
            QJSValue(translated(root, QStringLiteral("Выберите чат"))));
        set(root, QStringLiteral("currentRoomMembers"), array(engine));
        const QStringList emptyStrings = {
            QStringLiteral("pendingRoomDetailsRequestId"),
            QStringLiteral("pendingDirectMessageRequestId"),
            QStringLiteral("pendingDirectoryRoomId"),
            QStringLiteral("pendingDirectoryRoomName"),
            QStringLiteral("pendingProfileDetailsRequestId"),
            QStringLiteral("pendingDisplayNameRequestId"),
            QStringLiteral("pendingInviteRoomId"),
            QStringLiteral("pendingInviteRoomName"),
            QStringLiteral("displayNameStatusText")
        };
        for (const QString &property : emptyStrings)
            set(root, property, QJSValue(QString()));
        set(root, QStringLiteral("pendingDirectoryIsSpace"), QJSValue(false));
        set(root, QStringLiteral("displayNameBusy"), QJSValue(false));
        return undefined();
    }

    if (operation == QStringLiteral("setAccountIdentity")) {
        QJSValue identity = object(engine);
        identity.setProperty(QStringLiteral("user_id"), QJSValue(string(first)));
        identity.setProperty(QStringLiteral("display_name"), QJSValue(string(second)));
        identity.setProperty(QStringLiteral("avatar_url"), QJSValue(string(third)));
        identity.setProperty(QStringLiteral("known"), QJSValue(boolean(fourth)));
        set(root, QStringLiteral("accountIdentity"), identity);
        return undefined();
    }

    if (operation == QStringLiteral("applyAccountIdentityDetails")) {
        const QJSValue details = first;
        if (!details.isObject()
            || !boolean(details.property(QStringLiteral("is_self")))
            || boolean(details.property(QStringLiteral("room_member"))))
            return undefined();
        const QString currentUserId = string(root.property(QStringLiteral("currentUserId")));
        const QString userId = string(details.property(QStringLiteral("user_id")));
        if (currentUserId.isEmpty() || userId != currentUserId)
            return undefined();
        QString name = string(details.property(QStringLiteral("global_display_name")));
        if (name.isEmpty())
            name = string(details.property(QStringLiteral("display_name")));
        if (name.isEmpty())
            name = displayName(userId.isEmpty() ? currentUserId : userId);
        QString avatar = string(details.property(QStringLiteral("global_avatar_url")));
        if (avatar.isEmpty())
            avatar = string(details.property(QStringLiteral("avatar_url")));
        callRoot(root, QStringLiteral("setAccountIdentity"),
                 {QJSValue(userId.isEmpty() ? currentUserId : userId), QJSValue(name),
                  QJSValue(avatar), QJSValue(true)});
        return undefined();
    }

    if (operation == QStringLiteral("refreshAccountIdentity")) {
        const QString currentUserId = string(root.property(QStringLiteral("currentUserId")));
        if (currentUserId.isEmpty())
            return undefined();
        const QJSValue matrix = root.property(QStringLiteral("matrixConnectionObject"));
        const QString suffix = string(first).isEmpty() ? QStringLiteral("identity") : string(first);
        const QJSValue requestId = call(matrix, QStringLiteral("nextRequestId"), {QJSValue(suffix)});
        set(root, QStringLiteral("pendingProfileDetailsRequestId"), requestId);
        call(matrix, QStringLiteral("sendCommand"),
             {commandObject(engine, {
                 {QStringLiteral("type"), QJSValue(QStringLiteral("get_user_details"))},
                 {QStringLiteral("request_id"), requestId},
                 {QStringLiteral("user_id"), QJSValue(currentUserId)}
             })});
        return undefined();
    }

    if (operation == QStringLiteral("updateCurrentDeviceIdFromProfiles")) {
        set(root, QStringLiteral("currentDeviceId"), QJSValue(QString()));
        const QJSValue profiles = root.property(QStringLiteral("profiles"));
        const QString profileId = string(root.property(QStringLiteral("currentProfileId")));
        for (int index = 0; index < length(profiles); ++index) {
            const QJSValue profile = profiles.property(index);
            if (string(profile.property(QStringLiteral("profile_id"))) == profileId) {
                set(root, QStringLiteral("currentDeviceId"),
                    QJSValue(string(profile.property(QStringLiteral("device_id")))));
                break;
            }
        }
        return undefined();
    }

    if (operation == QStringLiteral("maybeFinishStartupIntro")) {
        const QJSValue loader = root.property(QStringLiteral("startupIntroLoaderObject"));
        if (!boolean(loader.property(QStringLiteral("active")))
            || !boolean(root.property(QStringLiteral("startupIntroMinimumFinished")))
            || !boolean(root.property(QStringLiteral("startupSessionResolved"))))
            return undefined();
        if (string(root.property(QStringLiteral("currentPage"))) == QStringLiteral("main")
            && !boolean(root.property(QStringLiteral("startupInitialDataReady"))))
            return undefined();
        set(loader, QStringLiteral("active"), QJSValue(false));
        return undefined();
    }

    if (operation == QStringLiteral("showMain")) {
        const QString userId = string(first);
        const QString server = string(second);
        const QString avatar = string(third);
        const QString profileId = string(fourth);
        const bool resetUi = boolean(fifth);
        if (resetUi) {
            callRoot(root, QStringLiteral("clearMainState"));
            callRoot(root, QStringLiteral("clearCenterNotifications"));
            set(root.property(QStringLiteral("matrixConnectionObject")),
                QStringLiteral("knownInvitedRoomIds"), object(engine));
            set(root, QStringLiteral("selectedSpaceId"), QJSValue(QString()));
            set(root, QStringLiteral("selectedSpaceName"),
                QJSValue(translated(root, QStringLiteral("Чаты"))));
            set(root, QStringLiteral("spaceLobbyOpen"), QJSValue(false));
            set(root, QStringLiteral("roomMembersCache"), object(engine));
            set(root, QStringLiteral("roomMembersCacheUpdatedAt"), object(engine));
            set(root, QStringLiteral("roomMembersCacheLastAccess"), object(engine));
        }
        set(root, QStringLiteral("sessionServer"), QJSValue(server));
        callRoot(root, QStringLiteral("setAccountIdentity"),
                 {QJSValue(userId), QJSValue(QString()), QJSValue(avatar), QJSValue(false)});
        QString nextProfileId = profileId;
        if (nextProfileId.isEmpty() && !resetUi)
            nextProfileId = string(root.property(QStringLiteral("currentProfileId")));
        set(root, QStringLiteral("currentProfileId"), QJSValue(nextProfileId));
        set(root, QStringLiteral("currentPage"), QJSValue(QStringLiteral("main")));
        set(root, QStringLiteral("addingAccountMode"), QJSValue(false));
        const QString currentRoomId = string(root.property(QStringLiteral("currentRoomId")));
        set(root, QStringLiteral("pendingLastRoomRestoreProfileId"),
            QJSValue(currentRoomId.isEmpty() ? nextProfileId : QString()));
        const QJSValue cache = root.property(QStringLiteral("roomMembersCache"));
        const QJSValue cachedMembers = cache.property(currentRoomId);
        set(root, QStringLiteral("currentRoomMembers"),
            currentRoomId.isEmpty() || cachedMembers.isUndefined()
                ? array(engine) : cachedMembers);
        const QJSValue matrix = root.property(QStringLiteral("matrixConnectionObject"));
        call(matrix, QStringLiteral("requestRooms"));
        call(matrix, QStringLiteral("requestProfiles"));
        callRoot(root, QStringLiteral("refreshAccountIdentity"),
                 {QJSValue(QStringLiteral("startup-profile"))});
        if (string(root.property(QStringLiteral("pendingSettingsProfileId"))) == nextProfileId) {
            set(root, QStringLiteral("pendingSettingsProfileId"), QJSValue(QString()));
            callRoot(root, QStringLiteral("openSettingsDialog"), {QJSValue(0)});
        }
        return undefined();
    }

    if (operation == QStringLiteral("beginAddAccount")) {
        set(root, QStringLiteral("addingAccountMode"), QJSValue(true));
        set(root, QStringLiteral("currentPage"), QJSValue(QStringLiteral("login")));
        const QJSValue login = root.property(QStringLiteral("loginScreen"));
        if (login.isObject()) {
            set(login, QStringLiteral("errorText"), QJSValue(QString()));
            call(login, QStringLiteral("resetLoginState"));
        }
        return undefined();
    }

    if (operation == QStringLiteral("leaveLoginScreen")) {
        if (!string(root.property(QStringLiteral("currentUserId"))).isEmpty()) {
            set(root, QStringLiteral("currentPage"), QJSValue(QStringLiteral("main")));
            set(root, QStringLiteral("addingAccountMode"), QJSValue(false));
        }
        return undefined();
    }

    if (operation == QStringLiteral("logout")) {
        const QJSValue matrix = root.property(QStringLiteral("matrixConnectionObject"));
        const QJSValue requestId = call(matrix, QStringLiteral("nextRequestId"),
                                        {QJSValue(QStringLiteral("logout"))});
        call(matrix, QStringLiteral("sendCommand"),
             {commandObject(engine, {
                 {QStringLiteral("type"), QJSValue(QStringLiteral("logout"))},
                 {QStringLiteral("request_id"), requestId}
             })});
        return undefined();
    }

    if (operation == QStringLiteral("roomRecord"))
        return roomRecord(root, string(first));

    if (operation == QStringLiteral("roomNameForId")) {
        const QString roomId = string(first);
        const QJSValue room = roomRecord(root, roomId);
        if (room.isObject()) {
            const QString name = string(room.property(QStringLiteral("name")));
            return QJSValue(name.isEmpty()
                                ? string(room.property(QStringLiteral("room_id")))
                                : name);
        }
        return QJSValue(roomId.isEmpty()
                            ? translated(root, QStringLiteral("PrismChat"))
                            : roomId);
    }

    if (operation == QStringLiteral("updateCurrentRoomMemberCount")) {
        const QJSValue room = roomRecord(root, string(root.property(QStringLiteral("currentRoomId"))));
        const int count = room.isObject()
            ? qMax(0, qRound(number(room.property(QStringLiteral("member_count"))))) : 0;
        set(root, QStringLiteral("currentRoomMemberCount"), QJSValue(count));
        return undefined();
    }

    if (operation == QStringLiteral("updateCurrentRoomEncryptionState")) {
        const QString roomId = string(root.property(QStringLiteral("currentRoomId")));
        if (roomId.isEmpty()) {
            set(root, QStringLiteral("currentRoomEncryptionState"), QJSValue(-1));
            return undefined();
        }
        const QJSValue room = roomRecord(root, roomId);
        if (room.isObject())
            set(root, QStringLiteral("currentRoomEncryptionState"),
                QJSValue(boolean(room.property(QStringLiteral("is_encrypted"))) ? 1 : 0));
        return undefined();
    }

    if (operation == QStringLiteral("rememberLastOpenedRoom")) {
        const QString profileId = string(root.property(QStringLiteral("currentProfileId")));
        const QString roomId = string(first);
        if (profileId.isEmpty() || roomId.isEmpty())
            return undefined();
        QJSValue remembered = cloneObject(engine,
            root.property(QStringLiteral("lastRoomIdsByProfile")));
        if (string(remembered.property(profileId)) == roomId)
            return undefined();
        remembered.setProperty(profileId, QJSValue(roomId));
        set(root, QStringLiteral("lastRoomIdsByProfile"), remembered);
        const QJSValue settings = root.property(QStringLiteral("appSettingsObject"));
        set(settings, QStringLiteral("lastRoomIdsByProfileJson"), QJSValue(json(remembered)));
        call(settings, QStringLiteral("sync"));
        return undefined();
    }

    if (operation == QStringLiteral("forgetLastOpenedRoom")) {
        const QString profileId = string(first);
        const QJSValue current = root.property(QStringLiteral("lastRoomIdsByProfile"));
        if (profileId.isEmpty() || !current.property(profileId).toBool())
            return undefined();
        QJSValue remembered = cloneObject(engine, current);
        remembered.deleteProperty(profileId);
        set(root, QStringLiteral("lastRoomIdsByProfile"), remembered);
        const QJSValue settings = root.property(QStringLiteral("appSettingsObject"));
        set(settings, QStringLiteral("lastRoomIdsByProfileJson"), QJSValue(json(remembered)));
        call(settings, QStringLiteral("sync"));
        return undefined();
    }

    if (operation == QStringLiteral("restoreLastOpenedRoom")) {
        const QString profileId = string(root.property(QStringLiteral("pendingLastRoomRestoreProfileId")));
        set(root, QStringLiteral("pendingLastRoomRestoreProfileId"), QJSValue(QString()));
        if (profileId.isEmpty()
            || string(root.property(QStringLiteral("currentPage"))) != QStringLiteral("main")
            || string(root.property(QStringLiteral("currentProfileId"))) != profileId
            || !string(root.property(QStringLiteral("currentRoomId"))).isEmpty())
            return undefined();
        const QString roomId = string(root.property(QStringLiteral("lastRoomIdsByProfile"))
                                          .property(profileId));
        if (roomId.isEmpty())
            return undefined();
        const QJSValue room = roomRecord(root, roomId);
        if (!room.isObject()
            || boolean(room.property(QStringLiteral("is_invited")))
            || boolean(room.property(QStringLiteral("is_space")))
            || boolean(callRoot(root, QStringLiteral("roomIsArchived"), {QJSValue(roomId)})))
            return undefined();
        set(root, QStringLiteral("spaceLobbyOpen"), QJSValue(false));
        set(root, QStringLiteral("currentRoomId"), QJSValue(roomId));
        const QString roomName = string(room.property(QStringLiteral("name")));
        set(root, QStringLiteral("currentRoomName"),
            QJSValue(roomName.isEmpty() ? roomId : roomName));
        const QJSValue cachedMembers = root.property(QStringLiteral("roomMembersCache")).property(roomId);
        set(root, QStringLiteral("currentRoomMembers"),
            cachedMembers.isUndefined() ? array(engine) : cachedMembers);
        call(root.property(QStringLiteral("matrixConnectionObject")),
             QStringLiteral("requestMessages"), {QJSValue(roomId)});
        callRoot(root, QStringLiteral("requestRoomMembersIfNeeded"), {QJSValue(roomId)});
        return undefined();
    }

    if (operation == QStringLiteral("setRoomPinned")
        || operation == QStringLiteral("setRoomMuted")
        || operation == QStringLiteral("setRoomArchived")) {
        const QString roomId = string(first);
        const bool enabled = boolean(second);
        if (roomId.isEmpty())
            return undefined();
        const bool pinned = operation == QStringLiteral("setRoomPinned");
        const bool muted = operation == QStringLiteral("setRoomMuted");
        const QString property = pinned ? QStringLiteral("pinnedRoomIds")
            : muted ? QStringLiteral("mutedRoomIds") : QStringLiteral("archivedRoomIds");
        const QString settingsProperty = pinned ? QStringLiteral("pinnedRoomIdsJson")
            : muted ? QStringLiteral("mutedRoomIdsJson") : QStringLiteral("archivedRoomIdsJson");
        Values rooms = values(root.property(property));
        int index = -1;
        for (int i = 0; i < rooms.size(); ++i) {
            if (string(rooms.at(i)) == roomId) {
                index = i;
                break;
            }
        }
        if (enabled && index < 0)
            pinned ? rooms.prepend(QJSValue(roomId)) : rooms.append(QJSValue(roomId));
        else if (!enabled && index >= 0)
            rooms.removeAt(index);
        else
            return undefined();
        const QJSValue result = arrayFromValues(engine, rooms);
        set(root, property, result);
        const QJSValue settings = root.property(QStringLiteral("appSettingsObject"));
        set(settings, settingsProperty, QJSValue(json(result)));
        if (muted)
            call(settings, QStringLiteral("sync"));
        if (!pinned && !muted && enabled) {
            if (boolean(callRoot(root, QStringLiteral("roomIsPinned"), {QJSValue(roomId)})))
                callRoot(root, QStringLiteral("setRoomPinned"), {QJSValue(roomId), QJSValue(false)});
            if (string(root.property(QStringLiteral("currentRoomId"))) == roomId)
                callRoot(root, QStringLiteral("clearMainState"));
        }
        return undefined();
    }

    if (operation == QStringLiteral("setArchiveInSpaceRail")) {
        const bool enabled = boolean(first);
        set(root, QStringLiteral("archiveInSpaceRail"), QJSValue(enabled));
        set(root.property(QStringLiteral("appSettingsObject")),
            QStringLiteral("archiveInSpaceRail"), QJSValue(enabled));
        return undefined();
    }

    if (operation == QStringLiteral("openSpace")) {
        const QString spaceId = string(first);
        const QString spaceName = string(second);
        set(root, QStringLiteral("selectedSpaceId"), QJSValue(spaceId));
        set(root, QStringLiteral("selectedSpaceName"),
            QJSValue(spaceName.isEmpty() ? translated(root, QStringLiteral("Чаты")) : spaceName));
        const QJSValue sidebar = root.property(QStringLiteral("sidebar"));
        if (sidebar.isObject())
            set(sidebar, QStringLiteral("archiveMode"), QJSValue(false));
        callRoot(root, QStringLiteral("clearMainState"));
        set(root, QStringLiteral("spaceLobbyOpen"), QJSValue(!spaceId.isEmpty()));
        const QJSValue lobby = root.property(QStringLiteral("spaceLobby"));
        if (lobby.isObject()) {
            set(lobby, QStringLiteral("hierarchyRooms"), array(engine));
            set(lobby, QStringLiteral("hierarchyError"), QJSValue(QString()));
            set(lobby, QStringLiteral("hierarchyReady"), QJSValue(false));
            set(lobby, QStringLiteral("hierarchyNextBatch"), QJSValue(QString()));
            set(lobby, QStringLiteral("hierarchyLoading"), QJSValue(!spaceId.isEmpty()));
        }
        if (!spaceId.isEmpty())
            call(root.property(QStringLiteral("matrixConnectionObject")),
                 QStringLiteral("requestSpaceHierarchy"), {QJSValue(spaceId)});
        return undefined();
    }

    if (operation == QStringLiteral("requestRoomMembersIfNeeded")) {
        const QString roomId = string(first);
        if (roomId.isEmpty())
            return undefined();
        QJSValue access = cloneObject(engine,
            root.property(QStringLiteral("roomMembersCacheLastAccess")));
        access.setProperty(roomId, QJSValue(double(nowMs())));
        set(root, QStringLiteral("roomMembersCacheLastAccess"), access);
        const QJSValue times = root.property(QStringLiteral("roomMembersCacheUpdatedAt"));
        const qint64 age = nowMs() - qint64(number(times.property(roomId)));
        const QJSValue cache = root.property(QStringLiteral("roomMembersCache"));
        if (!cache.property(roomId).isUndefined() && age >= 0 && age < 300000)
            return undefined();
        call(root.property(QStringLiteral("matrixConnectionObject")),
             QStringLiteral("requestRoomMembers"), {QJSValue(roomId)});
        return undefined();
    }

    if (operation == QStringLiteral("trimRoomMembersCache")) {
        const QString preferredRoomId = string(first);
        QJSValue cache = cloneObject(engine, root.property(QStringLiteral("roomMembersCache")));
        QJSValue times = cloneObject(engine, root.property(QStringLiteral("roomMembersCacheUpdatedAt")));
        QJSValue access = cloneObject(engine, root.property(QStringLiteral("roomMembersCacheLastAccess")));
        const int maxMembers = qMax(0, root.property(QStringLiteral("maxCachedMembersPerRoom")).toInt());
        QStringList roomIds;
        QJSValueIterator cacheIterator(cache);
        while (cacheIterator.hasNext()) {
            cacheIterator.next();
            const QString roomId = cacheIterator.name();
            roomIds.append(roomId);
            if (roomId == preferredRoomId)
                continue;
            const QJSValue members = cacheIterator.value();
            if (length(members) > maxMembers) {
                Values truncated;
                for (int index = 0; index < maxMembers; ++index)
                    truncated.append(members.property(index));
                cache.setProperty(roomId, arrayFromValues(engine, truncated));
                times.setProperty(roomId, QJSValue(0));
            }
        }
        const int maxRooms = qMax(0, root.property(QStringLiteral("maxCachedMemberRooms")).toInt());
        const QString currentRoomId = string(root.property(QStringLiteral("currentRoomId")));
        while (roomIds.size() > maxRooms) {
            QString victim;
            double victimAccess = std::numeric_limits<double>::max();
            for (const QString &candidate : std::as_const(roomIds)) {
                if (candidate == currentRoomId)
                    continue;
                double accessed = number(access.property(candidate));
                if (accessed == 0)
                    accessed = number(times.property(candidate));
                if (accessed < victimAccess) {
                    victim = candidate;
                    victimAccess = accessed;
                }
            }
            if (victim.isEmpty())
                break;
            cache.deleteProperty(victim);
            times.deleteProperty(victim);
            access.deleteProperty(victim);
            roomIds.removeAll(victim);
        }
        set(root, QStringLiteral("roomMembersCache"), cache);
        set(root, QStringLiteral("roomMembersCacheUpdatedAt"), times);
        set(root, QStringLiteral("roomMembersCacheLastAccess"), access);
        return undefined();
    }

    if (operation == QStringLiteral("activateRoomFromNotification")) {
        const QString roomId = string(first);
        const QJSValue room = roomRecord(root, roomId);
        if (!room.isObject() || boolean(room.property(QStringLiteral("is_invited"))))
            return undefined();
        set(root, QStringLiteral("currentPage"), QJSValue(QStringLiteral("main")));
        set(root, QStringLiteral("spaceLobbyOpen"), QJSValue(false));
        set(root, QStringLiteral("currentRoomId"), QJSValue(roomId));
        const QString name = string(room.property(QStringLiteral("name")));
        set(root, QStringLiteral("currentRoomName"), QJSValue(name.isEmpty() ? roomId : name));
        const QJSValue members = root.property(QStringLiteral("roomMembersCache")).property(roomId);
        set(root, QStringLiteral("currentRoomMembers"),
            members.isUndefined() ? array(engine) : members);
        call(root.property(QStringLiteral("matrixConnectionObject")),
             QStringLiteral("requestMessages"), {QJSValue(roomId)});
        callRoot(root, QStringLiteral("requestRoomMembersIfNeeded"), {QJSValue(roomId)});
        return undefined();
    }

    if (operation == QStringLiteral("systemNotificationTypeEnabled")) {
        if (!boolean(root.property(QStringLiteral("systemNotificationsEnabled"))))
            return QJSValue(false);
        const QString type = string(first);
        if (type == QStringLiteral("room_invitation"))
            return QJSValue(boolean(root.property(QStringLiteral("systemInvitationNotificationsEnabled"))));
        if (type == QStringLiteral("mention"))
            return QJSValue(boolean(root.property(QStringLiteral("systemMentionNotificationsEnabled"))));
        return QJSValue(false);
    }

    if (operation == QStringLiteral("systemNotificationAllowed")) {
        const QString roomId = string(first);
        const QString type = string(second);
        const bool allowed = string(root.property(QStringLiteral("currentPage"))) == QStringLiteral("main")
            && !boolean(root.property(QStringLiteral("active")))
            && boolean(callRoot(root, QStringLiteral("systemNotificationTypeEnabled"), {QJSValue(type)}))
            && (type == QStringLiteral("room_invitation")
                || !boolean(callRoot(root, QStringLiteral("roomIsMuted"), {QJSValue(roomId)})))
            && boolean(callRoot(root, QStringLiteral("systemNotificationsAvailable")));
        return QJSValue(allowed);
    }

    if (operation == QStringLiteral("systemNotificationsAvailable")) {
        const QJSValue notifier = root.property(QStringLiteral("nativeSystemNotifier"));
        return QJSValue(notifier.isObject()
                            ? boolean(notifier.property(QStringLiteral("available"))) : true);
    }

    if (operation == QStringLiteral("showSystemNotification")) {
        const QString title = string(first).isEmpty() ? QStringLiteral("PrismChat") : string(first);
        const QString body = string(second).trimmed();
        const QString roomId = string(third);
        if (body.isEmpty()
            || !boolean(callRoot(root, QStringLiteral("systemNotificationsAvailable"))))
            return undefined();
        const QJSValue notifier = root.property(QStringLiteral("nativeSystemNotifier"));
        if (notifier.isObject()) {
            call(notifier, QStringLiteral("showNotification"),
                 {QJSValue(title), QJSValue(body), QJSValue(roomId)});
            return undefined();
        }
        const QJSValue matrix = root.property(QStringLiteral("matrixConnectionObject"));
        const QJSValue requestId = call(matrix, QStringLiteral("nextRequestId"),
                                        {QJSValue(QStringLiteral("system-notification"))});
        call(matrix, QStringLiteral("sendCommand"),
             {commandObject(engine, {
                 {QStringLiteral("type"), QJSValue(QStringLiteral("show_system_notification"))},
                 {QStringLiteral("request_id"), requestId},
                 {QStringLiteral("title"), QJSValue(title)},
                 {QStringLiteral("message"), QJSValue(body)}
             })});
        return undefined();
    }

    if (operation == QStringLiteral("bringApplicationToFront")) {
        callRoot(root, QStringLiteral("showNormal"));
        callRoot(root, QStringLiteral("raise"));
        callRoot(root, QStringLiteral("requestActivate"));
        return undefined();
    }

    if (operation == QStringLiteral("notificationBody")) {
        const QJSValue message = first;
        QString body = string(message.property(QStringLiteral("body"))).trimmed();
        if (body.isEmpty()) {
            const bool encrypted = boolean(message.property(QStringLiteral("is_encrypted")))
                || string(message.property(QStringLiteral("msg_type"))) == QStringLiteral("m.encrypted");
            body = translated(root, encrypted ? QStringLiteral("🔒 Сообщение зашифровано")
                                              : QStringLiteral("Вложение"));
        }
        return QJSValue(body.size() > 180 ? body.left(177) + QStringLiteral("...") : body);
    }

    if (operation == QStringLiteral("messageMentionsCurrentUser")) {
        const QJSValue message = first;
        const QString userId = string(root.property(QStringLiteral("currentUserId")));
        if (!message.isObject() || userId.isEmpty())
            return QJSValue(false);
        if (boolean(message.property(QStringLiteral("mentions_room"))))
            return QJSValue(true);
        const QJSValue mentioned = message.property(QStringLiteral("mentioned_user_ids"));
        const int count = length(mentioned);
        for (int index = 0; index < count; ++index) {
            QJSValue value = mentioned.property(index);
            if (value.isUndefined())
                value = modelGet(mentioned, index);
            if (string(value) == userId)
                return QJSValue(true);
        }
        const QString body = string(message.property(QStringLiteral("body"))).toLower();
        const QString normalizedUserId = userId.toLower();
        if (body.contains(normalizedUserId))
            return QJSValue(true);
        const int colon = normalizedUserId.indexOf(QLatin1Char(':'));
        const QString localMention = colon > 1 ? normalizedUserId.left(colon) : normalizedUserId;
        if (localMention.size() < 2)
            return QJSValue(false);
        static const QString punctuation = QStringLiteral(".,!?;:()[]{}<>");
        qsizetype position = body.indexOf(localMention);
        while (position >= 0) {
            const QChar before = position > 0 ? body.at(position - 1) : QChar();
            const qsizetype afterIndex = position + localMention.size();
            const QChar after = afterIndex < body.size() ? body.at(afterIndex) : QChar();
            const bool beforeBoundary = before.isNull() || before.isSpace()
                || punctuation.contains(before);
            const bool afterBoundary = after.isNull() || after.isSpace()
                || punctuation.contains(after);
            if (beforeBoundary && afterBoundary)
                return QJSValue(true);
            position = body.indexOf(localMention, position + localMention.size());
        }
        return QJSValue(false);
    }

    if (operation == QStringLiteral("centerNotificationModel"))
        return notificationModelForType(root, string(first));
    if (operation == QStringLiteral("centerNotificationModelForId"))
        return notificationModelForId(root, string(first));
    if (operation == QStringLiteral("centerNotificationIndex")) {
        const QJSValue model = second.isObject()
            ? second : notificationModelForId(root, string(first));
        return QJSValue(notificationIndex(model, string(first)));
    }
    if (operation == QStringLiteral("recalculateNotificationUnreadCount")) {
        recalculateNotificationCount(root);
        return undefined();
    }

    if (operation == QStringLiteral("addCenterNotification")) {
        const QString id = string(first);
        const QString type = string(second);
        const QString title = string(third).isEmpty() ? QStringLiteral("PrismChat") : string(third);
        const QString body = string(fourth);
        const QString roomId = string(fifth);
        const QString roomName = string(sixth).isEmpty() ? roomId : string(sixth);
        if (id.isEmpty() || body.isEmpty()
            || (type != QStringLiteral("room_invitation") && type != QStringLiteral("mention")))
            return undefined();
        const QJSValue model = notificationModelForType(root, type);
        const int existing = notificationIndex(model, id);
        if (existing >= 0) {
            modelSetProperty(model, existing, QStringLiteral("title"), QJSValue(title));
            modelSetProperty(model, existing, QStringLiteral("body"), QJSValue(body));
            modelSetProperty(model, existing, QStringLiteral("room_name"), QJSValue(roomName));
            if (existing > 0)
                call(model, QStringLiteral("move"),
                     {QJSValue(existing), QJSValue(0), QJSValue(1)});
            return undefined();
        }
        const QJSValue entry = commandObject(engine, {
            {QStringLiteral("notification_id"), QJSValue(id)},
            {QStringLiteral("notification_type"), QJSValue(type)},
            {QStringLiteral("title"), QJSValue(title)},
            {QStringLiteral("body"), QJSValue(body)},
            {QStringLiteral("room_id"), QJSValue(roomId)},
            {QStringLiteral("room_name"), QJSValue(roomName)},
            {QStringLiteral("created_at"), QJSValue(double(nowMs()))},
            {QStringLiteral("unread"), QJSValue(true)}
        });
        call(model, QStringLiteral("insert"), {QJSValue(0), entry});
        while (modelCount(model) > 100)
            call(model, QStringLiteral("remove"), {QJSValue(modelCount(model) - 1)});
        recalculateNotificationCount(root);
        return undefined();
    }

    if (operation == QStringLiteral("markNotificationModelRead")) {
        markNotificationModelRead(first);
        return undefined();
    }

    if (operation == QStringLiteral("markCenterNotificationsRead")) {
        const QString type = string(first);
        if (type == QStringLiteral("room_invitation") || type == QStringLiteral("mention"))
            markNotificationModelRead(notificationModelForType(root, type));
        else {
            markNotificationModelRead(root.property(QStringLiteral("invitationNotificationsModelObject")));
            markNotificationModelRead(root.property(QStringLiteral("mentionNotificationsModelObject")));
        }
        recalculateNotificationCount(root);
        return undefined();
    }

    if (operation == QStringLiteral("markCenterNotificationRead")) {
        const QString id = string(first);
        const QJSValue model = notificationModelForId(root, id);
        const int index = notificationIndex(model, id);
        if (index >= 0 && boolean(modelGet(model, index).property(QStringLiteral("unread")))) {
            modelSetProperty(model, index, QStringLiteral("unread"), QJSValue(false));
            recalculateNotificationCount(root);
        }
        return undefined();
    }

    if (operation == QStringLiteral("dismissCenterNotification")) {
        const QString id = string(first);
        const QJSValue model = notificationModelForId(root, id);
        const int index = notificationIndex(model, id);
        if (index >= 0) {
            call(model, QStringLiteral("remove"), {QJSValue(index)});
            recalculateNotificationCount(root);
        }
        return undefined();
    }

    if (operation == QStringLiteral("clearCenterNotifications")) {
        const QString type = string(first);
        if (type == QStringLiteral("room_invitation") || type == QStringLiteral("mention"))
            modelClear(notificationModelForType(root, type));
        else {
            modelClear(root.property(QStringLiteral("invitationNotificationsModelObject")));
            modelClear(root.property(QStringLiteral("mentionNotificationsModelObject")));
        }
        recalculateNotificationCount(root);
        return undefined();
    }

    if (operation == QStringLiteral("activateCenterNotification")) {
        const QString id = string(first);
        const QString type = string(second);
        const QString roomId = string(third);
        const QString roomName = string(fourth);
        callRoot(root, QStringLiteral("markCenterNotificationRead"), {QJSValue(id)});
        if (type == QStringLiteral("room_invitation")) {
            set(root, QStringLiteral("pendingInviteRoomId"), QJSValue(roomId));
            set(root, QStringLiteral("pendingInviteRoomName"),
                QJSValue(roomName.isEmpty() ? roomId : roomName));
            call(root.property(QStringLiteral("matrixConnectionObject")),
                 QStringLiteral("acceptRoomInvite"), {QJSValue(roomId)});
            return undefined();
        }
        callRoot(root, QStringLiteral("dismissCenterNotification"), {QJSValue(id)});
        callRoot(root, QStringLiteral("activateRoomFromNotification"), {QJSValue(roomId)});
        return undefined();
    }

    return error(engine, QStringLiteral("window.") + operation);
}

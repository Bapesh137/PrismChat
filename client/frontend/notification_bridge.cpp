#include "notification_bridge.h"

#include <QIcon>

namespace {
QIcon prismIcon()
{
    return QIcon(QStringLiteral(":/app/prismchat.png"));
}
} // namespace

NotificationBridge::NotificationBridge(QObject *parent)
    : QObject(parent)
{
    m_trayIcon.setIcon(prismIcon());
    m_trayIcon.setToolTip(QStringLiteral("PrismChat"));
    m_trayIcon.setVisible(QSystemTrayIcon::isSystemTrayAvailable());

    connect(&m_trayIcon, &QSystemTrayIcon::messageClicked, this, [this] {
        emit applicationActivationRequested();
        if (!m_lastRoomId.isEmpty())
            emit notificationActivated(m_lastRoomId);
    });
    connect(&m_trayIcon, &QSystemTrayIcon::activated, this,
            [this](QSystemTrayIcon::ActivationReason reason) {
                if (reason == QSystemTrayIcon::Trigger
                    || reason == QSystemTrayIcon::DoubleClick) {
                    emit applicationActivationRequested();
                }
            });
}

bool NotificationBridge::available() const
{
    return QSystemTrayIcon::isSystemTrayAvailable();
}

void NotificationBridge::showNotification(const QString &title,
                                           const QString &message,
                                           const QString &roomId)
{
    if (!available() || message.trimmed().isEmpty())
        return;

    m_lastRoomId = roomId;
    m_trayIcon.showMessage(title.isEmpty() ? QStringLiteral("PrismChat") : title,
                           message,
                           QSystemTrayIcon::Information,
                           8000);
}

#pragma once

#include <QObject>
#include <QString>
#include <QSystemTrayIcon>

class NotificationBridge final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit NotificationBridge(QObject *parent = nullptr);

    bool available() const;

    Q_INVOKABLE void showNotification(const QString &title,
                                      const QString &message,
                                      const QString &roomId);

signals:
    void notificationActivated(const QString &roomId);
    void applicationActivationRequested();

private:
    QSystemTrayIcon m_trayIcon;
    QString m_lastRoomId;
};

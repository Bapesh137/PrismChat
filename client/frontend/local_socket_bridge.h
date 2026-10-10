#pragma once

#include <QByteArray>
#include <QLocalSocket>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class LocalSocketBridge : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(LocalSocket)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString endpoint READ endpoint WRITE setEndpoint NOTIFY endpointChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)

public:
    explicit LocalSocketBridge(QObject *parent = nullptr);
    ~LocalSocketBridge() override;

    bool connected() const;
    QString endpoint() const;
    void setEndpoint(const QString &endpoint);
    QString errorString() const;

    Q_INVOKABLE void connectToServer();
    Q_INVOKABLE void disconnectFromServer();
    Q_INVOKABLE void abort();
    Q_INVOKABLE bool sendTextMessage(const QString &message);

signals:
    void connectedChanged();
    void endpointChanged();
    void errorStringChanged();
    void opened();
    void closed();
    void errorOccurred(const QString &errorText);
    void textMessageReceived(const QString &message);

private:
    static QString defaultEndpoint();
    void readMessages();
    void failProtocol(const QString &errorText);
    void setErrorString(const QString &errorText);

    static constexpr qsizetype MaxCommandBytes = 256 * 1024;
    static constexpr qsizetype MaxResponseBytes = 8 * 1024 * 1024;

    QLocalSocket m_socket;
    QByteArray m_readBuffer;
    QString m_endpoint;
    QString m_errorString;
};

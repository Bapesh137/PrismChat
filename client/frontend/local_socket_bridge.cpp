#include "local_socket_bridge.h"

#include <QDir>
#include <QStandardPaths>

LocalSocketBridge::LocalSocketBridge(QObject *parent)
    : QObject(parent)
    , m_endpoint(defaultEndpoint())
{
    m_socket.setReadBufferSize(MaxResponseBytes + 2);

    connect(&m_socket, &QLocalSocket::connected, this, [this] {
        setErrorString({});
        emit connectedChanged();
        emit opened();
    });
    connect(&m_socket, &QLocalSocket::disconnected, this, [this] {
        m_readBuffer.clear();
        emit connectedChanged();
        emit closed();
    });
    connect(&m_socket, &QLocalSocket::readyRead, this, &LocalSocketBridge::readMessages);
    connect(&m_socket, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) {
        setErrorString(m_socket.errorString());
        emit errorOccurred(m_errorString);
    });
}

LocalSocketBridge::~LocalSocketBridge()
{
    m_socket.blockSignals(true);
    m_socket.abort();
    QObject::disconnect(&m_socket, nullptr, this, nullptr);
}

bool LocalSocketBridge::connected() const
{
    return m_socket.state() == QLocalSocket::ConnectedState;
}

QString LocalSocketBridge::endpoint() const
{
    return m_endpoint;
}

void LocalSocketBridge::setEndpoint(const QString &endpoint)
{
    if (connected() || m_socket.state() == QLocalSocket::ConnectingState || endpoint == m_endpoint)
        return;

    m_endpoint = endpoint;
    emit endpointChanged();
}

QString LocalSocketBridge::errorString() const
{
    return m_errorString;
}

void LocalSocketBridge::connectToServer()
{
    if (m_socket.state() != QLocalSocket::UnconnectedState)
        m_socket.abort();

    m_readBuffer.clear();
    setErrorString({});
    m_socket.connectToServer(m_endpoint);
}

void LocalSocketBridge::disconnectFromServer()
{
    m_socket.disconnectFromServer();
}

void LocalSocketBridge::abort()
{
    m_socket.abort();
}

bool LocalSocketBridge::sendTextMessage(const QString &message)
{
    if (!connected()) {
        setErrorString(QStringLiteral("Локальный IPC не подключён"));
        emit errorOccurred(m_errorString);
        return false;
    }

    QByteArray payload = message.toUtf8();
    if (payload.size() > MaxCommandBytes || payload.contains('\n') || payload.contains('\r')) {
        setErrorString(QStringLiteral("Некорректный размер или формат IPC-команды"));
        emit errorOccurred(m_errorString);
        return false;
    }

    payload.append('\n');
    if (m_socket.write(payload) != payload.size()) {
        setErrorString(m_socket.errorString());
        emit errorOccurred(m_errorString);
        return false;
    }

    m_socket.flush();
    return true;
}

QString LocalSocketBridge::defaultEndpoint()
{
#ifdef Q_OS_WIN
    return QStringLiteral("prismchat");
#else
    const QString configured = qEnvironmentVariable("PRISMCHAT_UDS_PATH");
    if (!configured.isEmpty())
        return configured;

    QString directory = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (directory.isEmpty())
        directory = QDir::tempPath();
    return QDir(directory).filePath(QStringLiteral("prismchat.sock"));
#endif
}

void LocalSocketBridge::readMessages()
{
    m_readBuffer.append(m_socket.readAll());

    while (true) {
        const qsizetype newline = m_readBuffer.indexOf('\n');
        if (newline < 0) {
            if (m_readBuffer.size() > MaxResponseBytes)
                failProtocol(QStringLiteral("Ответ IPC превышает лимит 8 МиБ"));
            return;
        }

        QByteArray message = m_readBuffer.left(newline);
        m_readBuffer.remove(0, newline + 1);
        if (message.endsWith('\r'))
            message.chop(1);
        if (message.size() > MaxResponseBytes) {
            failProtocol(QStringLiteral("Ответ IPC превышает лимит 8 МиБ"));
            return;
        }

        emit textMessageReceived(QString::fromUtf8(message));
    }
}

void LocalSocketBridge::failProtocol(const QString &errorText)
{
    setErrorString(errorText);
    emit errorOccurred(m_errorString);
    m_socket.abort();
}

void LocalSocketBridge::setErrorString(const QString &errorText)
{
    if (m_errorString == errorText)
        return;

    m_errorString = errorText;
    emit errorStringChanged();
}

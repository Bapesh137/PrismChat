#include "voice_web_profile.h"
#include <QFile>
#include <QHostAddress>
#include <QMimeDatabase>
#include <QTcpSocket>
#include <QUrl>
#include <QWebEngineUrlRequestInterceptor>
#include <QtWebEngineQuick/QQuickWebEngineDownloadRequest>

namespace {
class Requests final : public QWebEngineUrlRequestInterceptor {
public:
    explicit Requests(quint16 assetPort, QObject *parent)
        : QWebEngineUrlRequestInterceptor(parent), assetPort_(assetPort) {}
    void interceptRequest(QWebEngineUrlRequestInfo &request) override {
        const auto url = request.requestUrl();
        const auto scheme = url.scheme();
        // Block local files and insecure remote endpoints. HTTPS/WSS belong to
        // the homeserver and its federated MatrixRTC/LiveKit infrastructure.
        const bool loopbackAsset = scheme == "http" && url.host() == "127.0.0.1"
            && url.port() == assetPort_;
        if (!loopbackAsset && scheme != "https" && scheme != "wss"
            && scheme != "blob" && scheme != "data") request.block(true);
    }

private:
    quint16 assetPort_;
};
}
VoiceWebProfile::VoiceWebProfile(QObject *parent) : QQuickWebEngineProfile(parent) {
    setOffTheRecord(true);
    // Off-the-record profiles keep their HTTP cache in RAM. Element Call is
    // recreated between calls, so keep that shared cache bounded as a second
    // line of defence against long sessions retaining excessive assets.
    setHttpCacheMaximumSize(64 * 1024 * 1024);
    setPersistentPermissionsPolicy(QQuickWebEngineProfile::PersistentPermissionsPolicy::AskEveryTime);
    connect(this, &QQuickWebEngineProfile::downloadRequested, this,
            [](QQuickWebEngineDownloadRequest *download) { download->cancel(); });

    connect(&assetServer_, &QTcpServer::newConnection, this, [this] {
        while (auto *socket = assetServer_.nextPendingConnection()) serveAsset(socket);
    });
    if (assetServer_.listen(QHostAddress::LocalHost, 0)) {
        assetOrigin_ = QStringLiteral("http://127.0.0.1:%1").arg(assetServer_.serverPort());
        assetBaseUrl_ = assetOrigin_ + QStringLiteral("/index.html");
    }
    setUrlRequestInterceptor(new Requests(assetServer_.serverPort(), this));
}
QString VoiceWebProfile::bridgeScript() const {
    QFile channel(":/qtwebchannel/qwebchannel.js");
    QFile bridge(":/voice/bridge.js");
    if (!channel.open(QIODevice::ReadOnly) || !bridge.open(QIODevice::ReadOnly)) return {};
    return QString::fromUtf8(channel.readAll()) + '\n' + QString::fromUtf8(bridge.readAll());
}

void VoiceWebProfile::serveAsset(QTcpSocket *socket) {
    socket->setParent(&assetServer_);
    connect(socket, &QTcpSocket::readyRead, socket, [socket] {
        QByteArray request = socket->property("request").toByteArray();
        request += socket->readAll();
        if (request.size() > 16 * 1024) {
            socket->disconnectFromHost();
            return;
        }
        if (!request.contains("\r\n\r\n")) {
            socket->setProperty("request", request);
            return;
        }

        const auto requestLine = request.left(request.indexOf("\r\n"));
        const auto parts = requestLine.split(' ');
        if (parts.size() != 3 || parts[0] != "GET") {
            socket->write("HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
            socket->disconnectFromHost();
            return;
        }

        QByteArray target = parts[1];
        if (const auto query = target.indexOf('?'); query >= 0) target.truncate(query);
        QString path = QUrl::fromPercentEncoding(target);
        if (path == QStringLiteral("/")) path = QStringLiteral("/index.html");
        if (!path.startsWith('/') || path.contains(QStringLiteral(".."))
            || path.contains('\\') || path.contains(QChar::Null)) {
            socket->write("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
            socket->disconnectFromHost();
            return;
        }

        // This deployment does not advertise MSC4354 sticky-event support.
        // Pin Element Call to its state-event compatibility mode instead of
        // forcing Matrix 2.0 and failing before the call can be joined.
        if (path == QStringLiteral("/config.json")) {
            const QByteArray body = R"({"matrix_rtc_mode":"compatibility","matrix_rtc_session":{"wait_for_key_rotation_ms":5000}})";
            QByteArray response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                "Cache-Control: no-store\r\nContent-Length: " + QByteArray::number(body.size())
                + "\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n";
            response += body;
            socket->write(response);
            socket->disconnectFromHost();
            return;
        }

        QFile asset(QStringLiteral(":/element-call") + path);
        if (!asset.open(QIODevice::ReadOnly)) {
            socket->write("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
            socket->disconnectFromHost();
            return;
        }
        const QByteArray body = asset.readAll();
        QByteArray mime = QMimeDatabase().mimeTypeForFile(path).name().toUtf8();
        if (path.endsWith(QStringLiteral(".js"))) mime = "text/javascript";
        if (path.endsWith(QStringLiteral(".wasm"))) mime = "application/wasm";
        QByteArray response = "HTTP/1.1 200 OK\r\nContent-Type: " + mime
            + "\r\nContent-Length: " + QByteArray::number(body.size())
            + "\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n";
        response += body;
        socket->write(response);
        socket->disconnectFromHost();
    });
    connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
}

#pragma once
#include <QTcpServer>
#include <QtWebEngineQuick/QQuickWebEngineProfile>
#include <QtQml/qqmlregistration.h>

// A private, memory-only Chromium profile. No Matrix login cookies or tokens.
class VoiceWebProfile : public QQuickWebEngineProfile {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString bridgeScript READ bridgeScript CONSTANT)
    Q_PROPERTY(QString assetBaseUrl READ assetBaseUrl CONSTANT)
    Q_PROPERTY(QString assetOrigin READ assetOrigin CONSTANT)
public:
    explicit VoiceWebProfile(QObject *parent = nullptr);
    QString bridgeScript() const;
    QString assetBaseUrl() const { return assetBaseUrl_; }
    QString assetOrigin() const { return assetOrigin_; }

private:
    void serveAsset(QTcpSocket *socket);

    QTcpServer assetServer_;
    QString assetBaseUrl_;
    QString assetOrigin_;
};

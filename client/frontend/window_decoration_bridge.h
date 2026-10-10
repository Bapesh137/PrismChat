#pragma once

#include <QColor>
#include <QObject>

class WindowDecorationBridge final : public QObject
{
    Q_OBJECT

public:
    explicit WindowDecorationBridge(QObject *parent = nullptr);

    Q_INVOKABLE bool apply(const QColor &surface,
                           const QColor &background,
                           const QColor &textPrimary,
                           const QColor &textSecondary,
                           const QColor &accent);

private:
    QString m_lastSignature;
    bool m_useAlternateFile = false;
};

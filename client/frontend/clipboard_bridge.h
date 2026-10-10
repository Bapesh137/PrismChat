#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class ClipboardBridge : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(ClipboardBridge)

public:
    explicit ClipboardBridge(QObject *parent = nullptr);

    Q_INVOKABLE QVariantMap pasteContents() const;
    Q_INVOKABLE QString mimeTypeForFile(const QString &path) const;
    Q_INVOKABLE qint64 fileSizeForPath(const QString &path) const;
};

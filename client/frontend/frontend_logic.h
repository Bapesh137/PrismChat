#pragma once

#include <QJSValue>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class FrontendLogic : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(FrontendLogic)
    QML_SINGLETON

public:
    explicit FrontendLogic(QObject *parent = nullptr);

    Q_INVOKABLE QJSValue invoke(const QString &operation,
                                const QJSValue &root,
                                const QJSValue &arguments);

private:
    QJSValue invokeWindow(const QString &operation,
                          const QJSValue &root,
                          const QJSValue &arguments);
    QJSValue invokeChat(const QString &operation,
                        const QJSValue &root,
                        const QJSValue &arguments);
    QJSValue invokeComposer(const QString &operation,
                            const QJSValue &root,
                            const QJSValue &arguments);
    QJSValue invokeAttachments(const QString &operation,
                               const QJSValue &root,
                               const QJSValue &arguments);
    QJSValue invokeMatrix(const QString &operation,
                          const QJSValue &root,
                          const QJSValue &arguments);
};

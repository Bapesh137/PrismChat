#include "frontend_logic.h"

#include "frontend_logic_support.h"

using namespace FrontendLogicSupport;

FrontendLogic::FrontendLogic(QObject *parent)
    : QObject(parent)
{
}

QJSValue FrontendLogic::invoke(const QString &operation,
                               const QJSValue &root,
                               const QJSValue &arguments)
{
    if (operation.startsWith(QStringLiteral("window.")))
        return invokeWindow(operation.sliced(7), root, arguments);
    if (operation.startsWith(QStringLiteral("chat.")))
        return invokeChat(operation.sliced(5), root, arguments);
    if (operation.startsWith(QStringLiteral("composer.")))
        return invokeComposer(operation.sliced(9), root, arguments);
    if (operation.startsWith(QStringLiteral("attachments.")))
        return invokeAttachments(operation.sliced(12), root, arguments);
    if (operation.startsWith(QStringLiteral("matrix.")))
        return invokeMatrix(operation.sliced(7), root, arguments);
    return error(engineFor(root), operation);
}

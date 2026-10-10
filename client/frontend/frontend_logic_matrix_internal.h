#pragma once

#include "frontend_logic_support.h"

#include <optional>

namespace FrontendMatrixLogic {

using Result = std::optional<QJSValue>;

Result invokeCommandsAndRequests(const QString &operation,
                                 const QJSValue &root,
                                 const QJSValue &arguments);
Result invokeModelsAndState(const QString &operation,
                            const QJSValue &root,
                            const QJSValue &arguments);
Result invokeCacheAndTimeline(const QString &operation,
                              const QJSValue &root,
                              const QJSValue &arguments);
Result invokeEvents(const QString &operation,
                    const QJSValue &root,
                    const QJSValue &arguments);

inline QJSValue nextRequestId(const QJSValue &root, const QString &suffix)
{
    return FrontendLogicSupport::callRoot(
        root, QStringLiteral("nextRequestId"), {QJSValue(suffix)});
}

inline QJSValue sendCommand(const QJSValue &root, const QJSValue &command)
{
    return FrontendLogicSupport::callRoot(
        root, QStringLiteral("sendCommand"), {command});
}

inline void signal(const QJSValue &root,
                   const QString &name,
                   const FrontendLogicSupport::Values &arguments = {})
{
    FrontendLogicSupport::callRoot(root, name, arguments);
}

inline void feedback(const QJSValue &root, const QString &text, bool isError)
{
    signal(root, QStringLiteral("operationFeedback"),
           {QJSValue(text), QJSValue(isError)});
}

inline QString tr(const QJSValue &root, const QString &text)
{
    const QJSValue result = FrontendLogicSupport::callRoot(
        root, QStringLiteral("tr"), {QJSValue(text)});
    return result.isString() ? result.toString() : text;
}

} // namespace FrontendMatrixLogic

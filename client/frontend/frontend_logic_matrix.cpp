#include "frontend_logic.h"

#include "frontend_logic_matrix_internal.h"

using namespace FrontendLogicSupport;

QJSValue FrontendLogic::invokeMatrix(const QString &operation,
                                     const QJSValue &root,
                                     const QJSValue &arguments)
{
    using namespace FrontendMatrixLogic;
    if (Result result = invokeCommandsAndRequests(operation, root, arguments))
        return *result;
    if (Result result = invokeModelsAndState(operation, root, arguments))
        return *result;
    if (Result result = invokeCacheAndTimeline(operation, root, arguments))
        return *result;
    if (Result result = invokeEvents(operation, root, arguments))
        return *result;
    return error(engineFor(root), QStringLiteral("matrix.") + operation);
}

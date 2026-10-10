cmake_minimum_required(VERSION 3.21)

project(PrismChatUi VERSION 0.1.0 LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Multimedia Network Qml Quick WebSockets Widgets WebEngineQuick WebChannel)

qt_standard_project_setup(REQUIRES 6.8)

include(voice/ElementCall.cmake)

set(PRISM_FRONTEND_LOGIC_SOURCES
    voice/voice_web_profile.cpp
    voice/voice_web_profile.h
    voice/voice.qrc
    ${PRISM_ELEMENT_CALL_QRC}
    frontend_logic.cpp
    frontend_logic.h
    frontend_logic_support.h
    frontend_logic_window.cpp
    frontend_logic_chat.cpp
    frontend_logic_composer.cpp
    frontend_logic_attachments.cpp
    frontend_logic_matrix.cpp
    frontend_logic_matrix_internal.h
    frontend_logic_matrix_commands.cpp
    frontend_logic_matrix_state.cpp
    frontend_logic_matrix_timeline.cpp
    frontend_logic_matrix_events.cpp
)

qt_add_qml_module(PrismIpc
    PLUGIN_TARGET PrismIpc
    URI Prism.Ipc
    VERSION 1.0
    SHARED
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml-modules/Prism/Ipc"
    SOURCES
        local_socket_bridge.cpp
        local_socket_bridge.h
        clipboard_bridge.cpp
        clipboard_bridge.h
        ${PRISM_FRONTEND_LOGIC_SOURCES}
)

target_link_libraries(PrismIpc PRIVATE Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::WebEngineQuick Qt6::WebChannel)
target_include_directories(PrismIpc PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/voice")

# The repository is also launched directly with `qml.exe -I ../qml ../qml/main.qml`.
# That small bootstrap reports component errors from PrismChatWindow.qml.
# during development. Deploy the native IPC module into that import tree so this
# mode uses the same secured QLocalSocket transport as PrismChatUi.
set(PRISM_DIRECT_QML_MODULE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../qml/Prism/Ipc")
add_custom_command(TARGET PrismIpc POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${PRISM_DIRECT_QML_MODULE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "$<TARGET_FILE:PrismIpc>"
        "${PRISM_DIRECT_QML_MODULE_DIR}/$<TARGET_FILE_NAME:PrismIpc>"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/qml-modules/Prism/Ipc/qmldir"
        "${PRISM_DIRECT_QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/qml-modules/Prism/Ipc/PrismIpc.qmltypes"
        "${PRISM_DIRECT_QML_MODULE_DIR}/PrismIpc.qmltypes"
    COMMENT "Deploying Prism.Ipc for direct qml.exe development runs"
)

qt_add_executable(PrismChatUi
    main.cpp
    clipboard_bridge.cpp
    clipboard_bridge.h
    local_socket_bridge.cpp
    local_socket_bridge.h
    notification_bridge.cpp
    notification_bridge.h
    window_decoration_bridge.cpp
    window_decoration_bridge.h
    app_icon.qrc
    qml.qrc
    ${PRISM_FRONTEND_LOGIC_SOURCES}
)

target_link_libraries(PrismChatUi PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::WebSockets
    Qt6::Widgets
    Qt6::WebEngineQuick
    Qt6::WebChannel
)
target_include_directories(PrismChatUi PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/voice")
qt_add_executable(PrismNotifier
    notification_main.cpp
    notification_bridge.cpp
    notification_bridge.h
    app_icon.qrc
)
if(WIN32)
    add_executable(PrismChatLauncher WIN32
        windows_launcher.cpp
        prismchat.rc
    )
    target_compile_definitions(PrismChatLauncher PRIVATE UNICODE _UNICODE)
    set_target_properties(PrismChatLauncher PROPERTIES OUTPUT_NAME "Start-PrismChat")
    target_sources(PrismChatUi PRIVATE prismchat.rc)
    target_sources(PrismNotifier PRIVATE prismchat.rc)
    target_link_libraries(PrismChatUi PRIVATE dwmapi)
    set_target_properties(PrismChatUi PrismNotifier PROPERTIES WIN32_EXECUTABLE TRUE)
endif()
target_link_libraries(PrismNotifier PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::WebEngineQuick
    Qt6::WebChannel
)

if(WIN32)
    find_program(PRISM_WINDEPLOYQT
        NAMES windeployqt windeployqt6
        HINTS "${Qt6_DIR}/../../../bin"
    )
    if(PRISM_WINDEPLOYQT)
        add_custom_command(TARGET PrismNotifier POST_BUILD
            COMMAND "${PRISM_WINDEPLOYQT}"
                --no-translations
                --compiler-runtime
                "$<TARGET_FILE:PrismNotifier>"
            COMMENT "Deploying the Qt runtime required by PrismNotifier"
        )
    else()
        message(WARNING "windeployqt was not found; PrismNotifier may require Qt in PATH")
    endif()
endif()


install(TARGETS PrismChatUi PrismNotifier
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
if(UNIX AND NOT APPLE)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/packaging/linux/prismchat.desktop"
        DESTINATION share/applications)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/assets/prismchat.png"
        DESTINATION share/icons/hicolor/512x512/apps)
endif()
if(BUILD_TESTING)
    find_program(PRISM_QMLTESTRUNNER
        NAMES qmltestrunner
        HINTS "${Qt6_DIR}/../../../bin"
    )
    if(PRISM_QMLTESTRUNNER)
        add_test(
            NAME PrismChatQmlStateTests
            COMMAND "${PRISM_QMLTESTRUNNER}"
                -platform offscreen
                -import "${CMAKE_CURRENT_SOURCE_DIR}/../qml"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/../qml/tests"
        )
    else()
        message(WARNING "qmltestrunner not found; PrismChat QML tests are disabled")
    endif()
endif()

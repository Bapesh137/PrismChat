# PrismChat QML frontend

The frontend prefers local operating-system IPC:

- `QLocalSocket` over the per-user Windows Named Pipe `prismchat`;
- `QLocalSocket` over a mode-0600 Unix Domain Socket `prismchat.sock`;
- loopback-only `ws://127.0.0.1:3042` as a compatibility fallback.

Set `PRISMCHAT_TRANSPORT` to `auto`, `native`, or `websocket` on the backend.
Qt 6.5 or newer is required with Core, Gui, Network, Qml, Quick and WebSockets.

```powershell
cmake -S frontend -B target/frontend -DCMAKE_PREFIX_PATH="C:/Qt/6.8.3/msvc2022_64"
cmake --build target/frontend --config Debug
```

`PrismChatUi` includes the QML resources and registers `LocalSocket` plus the
native `FrontendLogic` singleton. To run `qml/main.qml` directly, build this
CMake project and add the generated module directory to the QML import path:

```powershell
qml -I target/frontend/qml-modules qml/main.qml
```

Without the `Prism.Ipc` module the UI reports a local IPC error and does not
downgrade to a network listener. Set `PRISMCHAT_UDS_PATH` for both processes to
use a non-default Unix socket path.

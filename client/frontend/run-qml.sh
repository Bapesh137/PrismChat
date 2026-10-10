#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
native_ui=${PRISMCHAT_UI_BIN:-"$project_dir/target/frontend/PrismChatUi"}
backend_bin=${PRISMCHAT_BACKEND_BIN:-}
qml_bin=${QML_BIN:-}
backend_pid=
ui_pid=
ipc_socket=

cleanup_backend()
{
    if [ -n "$ui_pid" ]; then
        kill "$ui_pid" 2>/dev/null || true
        wait "$ui_pid" 2>/dev/null || true
    fi
    if [ -n "$backend_pid" ]; then
        kill "$backend_pid" 2>/dev/null || true
        wait "$backend_pid" 2>/dev/null || true
    fi
    if [ -n "$ipc_socket" ] && [ -S "$ipc_socket" ]; then
        rm -f -- "$ipc_socket"
    fi
}

trap cleanup_backend EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# SSH and waypipe shells often lose Plasma's desktop markers even though they
# connect to the already running KDE Wayland session. Without the KDE Qt
# platform theme, the server-side title bar cannot receive PrismChat's palette.
# Recover only the platform-theme marker; do not replace an explicit choice.
if [ -z "${QT_QPA_PLATFORMTHEME:-}" ]; then
    prism_kde_session=false
    case ":${XDG_CURRENT_DESKTOP:-}:" in
        *:KDE:*) prism_kde_session=true ;;
    esac
    if [ "${KDE_FULL_SESSION:-}" = true ]; then
        prism_kde_session=true
    elif [ "$prism_kde_session" = false ] && command -v systemctl >/dev/null 2>&1; then
        if systemctl --user show-environment 2>/dev/null \
            | grep -qE '^(KDE_FULL_SESSION=true|XDG_CURRENT_DESKTOP=.*KDE)'; then
            prism_kde_session=true
        fi
    fi
    if [ "$prism_kde_session" = true ]; then
        QT_QPA_PLATFORMTHEME=kde
        export QT_QPA_PLATFORMTHEME
    fi
fi

if [ ! -x "$native_ui" ] && [ -z "$qml_bin" ]; then
    for candidate in qml6 /usr/lib/qt6/bin/qml qml; do
        if command -v "$candidate" >/dev/null 2>&1; then
            qml_bin=$candidate
            break
        fi
    done
fi
if [ ! -x "$native_ui" ] \
    && { [ -z "$qml_bin" ] || ! command -v "$qml_bin" >/dev/null 2>&1; }; then
    echo "Qt 6 qml executable was not found" >&2
    exit 127
fi

# Respect an explicitly selected renderer. Waypipe --no-gpu otherwise needs
# software OpenGL (llvmpipe) and CPU video decoding before Qt starts.
# The Qt Quick raster backend cannot render the shader-based avatar masks.
if [ -z "${QT_QUICK_BACKEND:-}" ] && [ -z "${QSG_RHI_BACKEND:-}" ]; then
    QSG_RHI_BACKEND=opengl
    : "${LIBGL_ALWAYS_SOFTWARE:=1}"
    : "${GALLIUM_DRIVER:=llvmpipe}"
    export QSG_RHI_BACKEND LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER
fi
if [ "${QT_QUICK_BACKEND:-}" = software ] || [ "${LIBGL_ALWAYS_SOFTWARE:-}" = 1 ]; then
    : "${QT_FFMPEG_DECODING_HW_DEVICE_TYPES:=,}"
    : "${QT_FFMPEG_ENCODING_HW_DEVICE_TYPES:=,}"
    : "${QT_DISABLE_HW_TEXTURES_CONVERSION:=1}"
    export QT_FFMPEG_DECODING_HW_DEVICE_TYPES QT_FFMPEG_ENCODING_HW_DEVICE_TYPES QT_DISABLE_HW_TEXTURES_CONVERSION
fi

# Qt's informational FFmpeg stream dump prints the entire media URL, including
# the local proxy capability. Keep warnings/errors and explicit user log rules.
QT_LOGGING_RULES="qt.multimedia.ffmpeg.mediadataholder.info=false${QT_LOGGING_RULES:+;$QT_LOGGING_RULES}"
export QT_LOGGING_RULES

# The desktop launcher owns the Rust backend. A user therefore starts the full
# application with one click instead of keeping `cargo run` in another terminal.
# Developers can opt into an already running backend with
# PRISMCHAT_EXTERNAL_BACKEND=1.
if [ "${PRISMCHAT_EXTERNAL_BACKEND:-0}" != 1 ]; then
    if [ -z "$backend_bin" ]; then
        for candidate in \
            "$project_dir/target/release/PrismChat" \
            "$project_dir/target/debug/PrismChat"; do
            if [ -x "$candidate" ]; then
                backend_bin=$candidate
                break
            fi
        done
    fi
    if [ -z "$backend_bin" ] || [ ! -x "$backend_bin" ]; then
        message="PrismChat backend is not built. Install a packaged release or build it once with cargo build."
        echo "$message" >&2
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --error "$message" --title PrismChat || true
        fi
        exit 127
    fi

    runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
    ipc_socket=${PRISMCHAT_UDS_PATH:-"$runtime_dir/prismchat-$(id -u)-$$.sock"}
    PRISMCHAT_UDS_PATH=$ipc_socket
    PRISMCHAT_TRANSPORT=native
    export PRISMCHAT_UDS_PATH PRISMCHAT_TRANSPORT

    state_base=${XDG_STATE_HOME:-"${HOME:-/tmp}/.local/state"}
    log_dir="$state_base/prismchat"
    mkdir -p -- "$log_dir"
    "$backend_bin" >>"$log_dir/backend.log" 2>&1 &
    backend_pid=$!

    attempts=0
    while [ ! -S "$ipc_socket" ]; do
        if ! kill -0 "$backend_pid" 2>/dev/null; then
            echo "PrismChat backend stopped during startup. See $log_dir/backend.log" >&2
            exit 1
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 100 ]; then
            echo "PrismChat backend did not create its IPC socket. See $log_dir/backend.log" >&2
            exit 1
        fi
        sleep 0.05
    done
fi

# Calls require the C++ application: it registers VoiceWebProfile, the local
# socket transport and the WebEngine setup used for PipeWire screen capture.
# Running main.qml with qml6 alone can draw the shell, but leaves the call view
# empty. Keep qml6 only as a development fallback before the native UI exists.
if [ -x "$native_ui" ]; then
    "$native_ui" "$@" &
else
    "$qml_bin" -I "$project_dir/qml" "$project_dir/qml/main.qml" "$@" &
fi
ui_pid=$!
set +e
wait "$ui_pid"
ui_status=$?
set -e
ui_pid=
exit "$ui_status"

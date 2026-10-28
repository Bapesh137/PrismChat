#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/../.." && pwd)
target_dir=${CARGO_TARGET_DIR:-"$project_dir/target"}
package_dir="$target_dir/package"
release_dir="$target_dir/releases"
version=${PRISMCHAT_VERSION:-$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$project_dir/Cargo.toml" | head -n1)}
machine=$(uname -m)
case "$machine" in
    x86_64) appimage_arch=x86_64 ;;
    aarch64) appimage_arch=aarch64 ;;
    *) echo "Unsupported AppImage architecture: $machine" >&2; exit 2 ;;
esac

# Keep the Arch release name unchanged by default; allow portable build variants.
release_flavor=${PRISMCHAT_RELEASE_FLAVOR:-archlinux}
bundle_name="PrismChat-${version}-${release_flavor}-${machine}"
appdir="$package_dir/${bundle_name}.AppDir"
cmake_dir="$target_dir/frontend-release"

# Validate the Debian 13 WebRTC/PipeWire build before running Cargo/CMake.
case "$release_flavor" in
  debian13*)
    if [ -z "${PRISMCHAT_QTWEBENGINE_STAGE:-}" ]; then
        echo "Debian 13 requires PRISMCHAT_QTWEBENGINE_STAGE (custom Qt WebEngine install tree)." >&2
        exit 1
    fi
    webengine_cache=${PRISMCHAT_QTWEBENGINE_CMAKE_CACHE:-}
    if [ ! -f "$webengine_cache" ] || \
       ! grep -Fxq 'QT_FEATURE_webengine_webrtc:INTERNAL=ON' "$webengine_cache" || \
       ! grep -Fxq 'QT_FEATURE_webengine_webrtc_pipewire:INTERNAL=ON' "$webengine_cache"; then
        echo "Debian 13 requires PRISMCHAT_QTWEBENGINE_CMAKE_CACHE with WebRTC and PipeWire ON." >&2
        exit 1
    fi
    ;;
esac

for required in cargo cmake ninja ldd tar; do
    command -v "$required" >/dev/null 2>&1 || {
        echo "Required packaging command is missing: $required" >&2
        exit 127
    }
done

qtpaths=${QT_PATHS:-/usr/lib/qt6/bin/qtpaths}
if [ ! -x "$qtpaths" ]; then
    echo "Qt 6 qtpaths was not found. Set QT_PATHS to its full path." >&2
    exit 127
fi

qt_qml=$($qtpaths --query QT_INSTALL_QML)
qt_plugins=$($qtpaths --query QT_INSTALL_PLUGINS)
qt_libexecs=$($qtpaths --query QT_INSTALL_LIBEXECS)
qt_data=$($qtpaths --query QT_INSTALL_DATA)
qt_translations=$($qtpaths --query QT_INSTALL_TRANSLATIONS)

# qmlimportscanner records QML imports but does not make a missing runtime
# module fail the CMake build. Keep this list explicit so CI cannot publish an
# AppImage that exits immediately on a clean machine.
required_qml_modules=(
    "Qt5Compat/GraphicalEffects/qmldir"
    "QtMultimedia/qmldir"
    "QtQuick/Controls/qmldir"
    "QtWebEngine/qmldir"
)
for module_path in "${required_qml_modules[@]}"; do
    if [ ! -f "$qt_qml/$module_path" ]; then
        echo "Required QML module is missing: $qt_qml/$module_path" >&2
        echo "Install the corresponding Qt 6 QML package in the build image." >&2
        exit 1
    fi
done

echo "Building PrismChat backend (release)"
(cd "$project_dir" && cargo build --release --locked)

echo "Building PrismChat Qt frontend (release)"
cmake --fresh -S "$project_dir/frontend" -B "$cmake_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "$cmake_dir" --target PrismChatUi PrismNotifier --parallel

rm -rf -- "$appdir"
mkdir -p -- "$appdir/usr/bin" "$appdir/usr/lib" "$appdir/usr/libexec" \
    "$appdir/usr/resources" "$appdir/usr/translations" "$release_dir"
DESTDIR="$appdir" cmake --install "$cmake_dir" --strip
install -Dm755 "$target_dir/release/PrismChat" "$appdir/usr/bin/prismchat-backend"
install -Dm755 "$script_dir/AppRun" "$appdir/AppRun"
ln -s AppRun "$appdir/PrismChat"
install -Dm644 "$script_dir/prismchat.desktop" "$appdir/prismchat.desktop"
install -Dm644 "$project_dir/frontend/assets/prismchat.png" "$appdir/prismchat.png"

echo "Bundling Qt runtime"
cp -a -- "$qt_qml" "$appdir/usr/qml"
cp -a -- "$qt_plugins" "$appdir/usr/plugins"

install -Dm755 "$qt_libexecs/QtWebEngineProcess" "$appdir/usr/libexec/QtWebEngineProcess"
cp -a -- "$qt_data/resources/." "$appdir/usr/resources/"
cp -a -- "$qt_translations/qtwebengine_locales" \
    "$appdir/usr/translations/qtwebengine_locales"

for module_path in "${required_qml_modules[@]}"; do
    if [ ! -f "$appdir/usr/qml/$module_path" ]; then
        echo "Packaged QML module is missing: usr/qml/$module_path" >&2
        exit 1
    fi
done

declare -A copied_libraries=()
queue=()

enqueue_binary()
{
    local candidate=$1
    [ -f "$candidate" ] || return 0
    queue+=("$candidate")
}

copy_dependency()
{
    local dependency=$1
    local library_name destination
    library_name=$(basename -- "$dependency")
    case "$library_name" in
        ld-linux*.so*|libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|\
        libresolv.so.*|libutil.so.*|libanl.so.*|\
        libEGL.so.*|libGL.so.*|libGLX.so.*|libGLdispatch.so.*|libOpenGL.so.*|\
        libgbm.so.*|libdrm.so.*|libdrm_*.so.*|libvulkan.so.*)
            # GPU userspace libraries have to match the host's kernel driver
            # and DRI/Vulkan modules. Bundling the CI machine's copies made
            # QtWebEngine fail eglMakeCurrent in a tight allocation loop on
            # otherwise supported hosts.
            return 0
            ;;
    esac
    destination="$appdir/usr/lib/$library_name"
    if [ -n "${copied_libraries[$library_name]:-}" ]; then
        return 0
    fi
    copied_libraries[$library_name]=1
    cp -L -- "$dependency" "$destination"
    chmod u+w "$destination"
    enqueue_binary "$destination"
}

enqueue_binary "$appdir/usr/bin/PrismChatUi"
enqueue_binary "$appdir/usr/bin/PrismNotifier"
enqueue_binary "$appdir/usr/bin/prismchat-backend"
enqueue_binary "$appdir/usr/libexec/QtWebEngineProcess"
while IFS= read -r shared_object; do
    enqueue_binary "$shared_object"
done < <(find "$appdir/usr/plugins" "$appdir/usr/qml" -type f -name '*.so*' -print)

index=0
while [ "$index" -lt "${#queue[@]}" ]; do
    binary=${queue[$index]}
    index=$((index + 1))
    while IFS= read -r dependency; do
        [ -n "$dependency" ] && copy_dependency "$dependency"
    done < <(ldd "$binary" 2>/dev/null | awk \
        '/=> \/[^ ]+/ { print $3 } /^\/[[:graph:]]+/ { print $1 }')
done

# Debian 13 needs a Qt WebEngine built with WebRTC PipeWire support.
# The custom Qt installation is a DESTDIR tree; it is never installed into /usr.
webengine_stage=${PRISMCHAT_QTWEBENGINE_STAGE:-}
if [ -n "$webengine_stage" ]; then
    webengine_stage=${webengine_stage%/}
    if [ -d "$webengine_stage/usr" ]; then
        webengine_stage="$webengine_stage/usr"
    fi
    case "$machine" in
        x86_64) webengine_multiarch=x86_64-linux-gnu ;;
        aarch64) webengine_multiarch=aarch64-linux-gnu ;;
    esac
    webengine_libdir="$webengine_stage/lib/$webengine_multiarch"
    webengine_qml="$webengine_libdir/qt6/qml/QtWebEngine"
    webengine_process="$webengine_stage/lib/qt6/libexec/QtWebEngineProcess"
    webengine_resources="$webengine_stage/share/qt6/resources"
    webengine_locales="$webengine_stage/share/qt6/translations/qtwebengine_locales"

    for required in \
        "$webengine_libdir/libQt6WebEngineCore.so.6" \
        "$webengine_libdir/libQt6WebEngineQuick.so.6" \
        "$webengine_libdir/libQt6WebEngineQuickDelegatesQml.so.6" \
        "$webengine_libdir/libQt6WebEngineWidgets.so.6" \
        "$webengine_qml/qmldir" \
        "$webengine_qml/libqtwebenginequickplugin.so" \
        "$webengine_process" \
        "$webengine_resources/qtwebengine_resources.pak" \
        "$webengine_resources/v8_context_snapshot.bin" \
        "$webengine_locales/en-US.pak"; do
        if [ ! -f "$required" ]; then
            echo "Incomplete staged Qt WebEngine: $required" >&2
            exit 1
        fi
    done

    echo "Bundling staged Qt WebEngine from $webengine_stage"
    rm -f -- "$appdir/usr/lib"/libQt6WebEngine*.so*
    cp -a -- "$webengine_libdir"/libQt6WebEngine*.so* "$appdir/usr/lib/"
    install -Dm755 "$webengine_process" "$appdir/usr/libexec/QtWebEngineProcess"
    rm -rf -- "$appdir/usr/qml/QtWebEngine"
    cp -a -- "$webengine_qml" "$appdir/usr/qml/QtWebEngine"
    cp -a -- "$webengine_resources/." "$appdir/usr/resources/"
    rm -rf -- "$appdir/usr/translations/qtwebengine_locales"
    cp -a -- "$webengine_locales" "$appdir/usr/translations/qtwebengine_locales"

    # The system Qt dependency walk happened above. Walk the replacement
    # artifacts too so new direct/transitive dependencies are not omitted.
    enqueue_binary "$appdir/usr/libexec/QtWebEngineProcess"
    while IFS= read -r artifact; do
        enqueue_binary "$artifact"
    done < <(find "$appdir/usr/lib" -maxdepth 1 -type f -name 'libQt6WebEngine*.so*' -print)
    while IFS= read -r artifact; do
        enqueue_binary "$artifact"
    done < <(find "$appdir/usr/qml/QtWebEngine" -type f -name '*.so*' -print)
    while [ "$index" -lt "${#queue[@]}" ]; do
        binary=${queue[$index]}
        index=$((index + 1))
        dependencies=$(LD_LIBRARY_PATH="$appdir/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            ldd "$binary" 2>&1) || {
            echo "Cannot inspect staged Qt WebEngine dependency: $binary" >&2
            printf '%s\n' "$dependencies" >&2
            exit 1
        }
        if grep -q 'not found' <<< "$dependencies"; then
            echo "Unresolved staged Qt WebEngine dependency in $binary:" >&2
            printf '%s\n' "$dependencies" >&2
            exit 1
        fi
        while IFS= read -r dependency; do
            [ -n "$dependency" ] || continue
            library_name=$(basename -- "$dependency")
            # Never replace a staged WebEngine lib with the system version.
            if [ -e "$appdir/usr/lib/$library_name" ]; then
                continue
            fi
            copy_dependency "$dependency"
        done < <(printf '%s\n' "$dependencies" | awk \
            '/=> \/[^ ]+/ { print $3 } /^\/[[:graph:]]+/ { print $1 }')
    done
    if find "$appdir/usr/lib" -maxdepth 1 -name 'libQt6WebEngine*.so*' -xtype l \
        -print -quit | grep -q .; then
        echo "Staged Qt WebEngine contains broken library symlinks." >&2
        exit 1
    fi
fi

# Keep this invariant explicit: reintroducing one of these libraries can make
# the AppImage load a mixture of bundled Mesa and host DRI drivers.
for host_gpu_library in \
    'libEGL.so.*' 'libGL.so.*' 'libGLX.so.*' 'libGLdispatch.so.*' \
    'libOpenGL.so.*' 'libgbm.so.*' 'libdrm.so.*' 'libdrm_*.so.*' \
    'libvulkan.so.*'; do
    if compgen -G "$appdir/usr/lib/$host_gpu_library" >/dev/null; then
        echo "Host GPU library was accidentally bundled: $host_gpu_library" >&2
        exit 1
    fi
done

portable_archive="$release_dir/${bundle_name}-portable.tar.zst"
rm -f -- "$portable_archive"
tar --zstd -C "$package_dir" -cf "$portable_archive" "$(basename -- "$appdir")"

appimagetool=${PRISM_APPIMAGETOOL:-}
if [ -z "$appimagetool" ] && command -v appimagetool >/dev/null 2>&1; then
    appimagetool=$(command -v appimagetool)
fi
if [ -n "$appimagetool" ]; then
    appimage="$release_dir/${bundle_name}.AppImage"
    rm -f -- "$appimage"
    ARCH=$appimage_arch APPIMAGE_EXTRACT_AND_RUN=1 "$appimagetool" "$appdir" "$appimage"
    chmod 755 "$appimage"
    appimage_archive="$release_dir/${bundle_name}-AppImage.tar.zst"
    rm -f -- "$appimage_archive"
    tar --zstd -C "$release_dir" -cf "$appimage_archive" "$(basename -- "$appimage")"
else
    echo "appimagetool was not supplied; the portable archive was created without an AppImage." >&2
fi

checksum_file="$release_dir/${bundle_name}-SHA256SUMS.txt"
rm -f -- "$checksum_file"
(
    cd "$release_dir"
    find . -maxdepth 1 -type f -name "${bundle_name}*" ! -name '*-SHA256SUMS.txt' \
        -printf '%f\n' | sort | xargs -r sha256sum
) >"$checksum_file"
printf 'Release files:\n'
find "$release_dir" -maxdepth 1 -type f -name "${bundle_name}*" -printf '  %f\n' | sort

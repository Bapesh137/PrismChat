import QtQuick
import QtWebEngine
import QtWebChannel
import QtQuick.Controls
import "../../utils" as L10n
import "../../utils/CallControlTranslations.js" as CallControlTranslations

WebEngineView {
    id: view
    required property var session
    property bool desktopCaptureRequestInFlight: false
    readonly property string platformName: {
        // Qt 6.11 needs the C++-reported QPA name.
        // qmllint disable unqualified
        if (typeof prismPlatformName !== "undefined" && prismPlatformName)
            return String(prismPlatformName).toLowerCase()
        // qmllint enable unqualified
        return String(Qt.platform.pluginName || "").toLowerCase()
    }
    url: ""
    audioMuted: session.deafened || session.phase === "ending"
    lifecycleState: WebEngineView.Active
    backgroundColor: "#10171e"
    profile: session.webProfile
    settings.playbackRequiresUserGesture: false
    // Qt WebEngine requires explicit getDisplayMedia enablement.
    settings.screenCaptureEnabled: true
    settings.fullScreenSupportEnabled: true
    settings.javascriptCanOpenWindows: false
    settings.localContentCanAccessFileUrls: false
    settings.localContentCanAccessRemoteUrls: false
    webChannel: WebChannel {
        registeredObjects: [bridge]
    }
    QtObject {
        id: bridge
        WebChannel.id: "voiceBridge"
        function fromWidget(raw) { view.session.widgetMessage(raw) }
        function ready(id, secure, origin) {
            if (id !== view.session.callId) return
            if (!secure || origin !== view.session.webProfile.assetOrigin) {
                view.session.fail(L10n.I18n.tr("WebEngine не предоставил защищённый контекст звонка"))
                return
            }
            view.session.setWidgetBridgeReady(true)
        }
    }
    Connections {
        target: view.session
        function onToWidget(message) {
            // Forward serialized Widget API messages in MainWorld.
            var raw = String(message || "")
            if (!raw) return
            var script = "window.postMessage(" + raw + ", '*')"
            view.runJavaScript(script, 0, function(_) {})
        }
    }
    onPermissionRequested: function(permission) {
        // Qt 6.8 exposes capture permissions under PermissionType.
        var type = permission.permissionType
        var trustedOrigin = permission.origin.toString().startsWith(session.webProfile.assetOrigin)
        var mediaPermission = type === WebEnginePermission.PermissionType.MediaAudioCapture
                           || type === WebEnginePermission.PermissionType.MediaVideoCapture
                           || type === WebEnginePermission.PermissionType.MediaAudioVideoCapture
                           || type === WebEnginePermission.PermissionType.DesktopVideoCapture
                           || type === WebEnginePermission.PermissionType.DesktopAudioVideoCapture

        console.warn("[VoiceMediaPermission] origin=" + permission.origin
                     + " type=" + type
                     + " media=" + mediaPermission
                     + " trusted=" + trustedOrigin
                     + " active=" + session.active)

        if (trustedOrigin && mediaPermission
                && session.phase !== "ending" && session.active) {
            // Only the bundled Element Call origin may request media.
            permission.grant()
            console.warn("[VoiceMediaPermission] granted type=" + type)
            return
        }

        permission.deny()
        console.warn("[VoiceMediaPermission] denied type=" + type)
    }

    // Qt delegates getDisplayMedia source selection to the embedder.
    onDesktopMediaRequested: function(request) {
        if (session.phase === "ending" || !session.active) {
            request.cancel()
            return
        }

        // Keep one desktop capturer or portal session at a time.
        if (desktopCaptureRequestInFlight) {
            request.cancel()
            console.warn("[VoiceScreenShare] duplicate desktop request cancelled")
            return
        }

        var screenCount = request.screensModel ? request.screensModel.rowCount() : 0
        var windowCount = request.windowsModel ? request.windowsModel.rowCount() : 0
        var wayland = view.platformName.indexOf("wayland") >= 0
        console.warn("[VoiceScreenShare] request screens=" + screenCount
                     + " windows=" + windowCount
                     + " platform=" + view.platformName)

        if (screenCount === 0 && windowCount === 0) {
            request.cancel()
            console.warn("[VoiceScreenShare] no desktop capture sources")
            return
        }

        if (wayland) {
            // Wayland source selection belongs to xdg-desktop-portal.
            desktopCaptureRequestInFlight = true
            desktopCaptureGuard.start()
            if (screenCount > 0) {
                request.selectScreen(request.screensModel.index(0, 0))
                console.warn("[VoiceScreenShare] delegated selection to Wayland portal")
            } else {
                request.selectWindow(request.windowsModel.index(0, 0))
                console.warn("[VoiceScreenShare] delegated window selection to Wayland portal")
            }
            return
        }

        desktopCaptureRequestInFlight = true
        desktopMediaDialog.request = request
        desktopMediaKind.currentIndex = screenCount > 0 ? 0 : 1
        desktopMediaSource.currentIndex = 0
        desktopMediaDialog.open()
    }

    Timer {
        id: desktopCaptureGuard
        // Recovery timeout for a portal request that never settles.
        interval: 120000
        repeat: false
        onTriggered: view.desktopCaptureRequestInFlight = false
    }

    Dialog {
        id: desktopMediaDialog
        property var request: null
        title: L10n.I18n.tr("Демонстрация экрана")
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Ok | Dialog.Cancel
        closePolicy: Popup.NoAutoClose
        width: Math.min(520, Math.max(360, view.width - 48))

        Column {
            width: parent.width
            spacing: 10

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                text: L10n.I18n.tr("Выберите экран или окно, которое будет видно участникам звонка.")
            }

            ComboBox {
                id: desktopMediaKind
                width: parent.width
                model: [L10n.I18n.tr("Экран"), L10n.I18n.tr("Окно")]
                enabled: desktopMediaDialog.request !== null
            }

            ComboBox {
                id: desktopMediaSource
                width: parent.width
                textRole: "display"
                model: {
                    if (!desktopMediaDialog.request) return null
                    return desktopMediaKind.currentIndex === 0
                        ? desktopMediaDialog.request.screensModel
                        : desktopMediaDialog.request.windowsModel
                }
            }

            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: desktopMediaSource.count === 0
                text: desktopMediaKind.currentIndex === 0
                    ? L10n.I18n.tr("Qt WebEngine не нашёл доступных экранов.")
                    : L10n.I18n.tr("Qt WebEngine не нашёл доступных окон.")
            }
        }

        onAccepted: {
            var r = request
            if (!r) return

            var model = desktopMediaKind.currentIndex === 0
                ? r.screensModel : r.windowsModel
            var row = desktopMediaSource.currentIndex
            if (!model || row < 0 || row >= model.rowCount()) {
                r.cancel()
                request = null
                view.desktopCaptureRequestInFlight = false
                desktopCaptureGuard.stop()
                console.warn("[VoiceScreenShare] invalid desktop source selection")
                return
            }

            var index = model.index(row, 0)
            if (desktopMediaKind.currentIndex === 0) {
                r.selectScreen(index)
                console.warn("[VoiceScreenShare] sharing screen row=" + row)
            } else {
                r.selectWindow(index)
                console.warn("[VoiceScreenShare] sharing window row=" + row)
            }
            request = null
            desktopCaptureGuard.restart()
        }

        onRejected: {
            if (request) request.cancel()
            request = null
            view.desktopCaptureRequestInFlight = false
            desktopCaptureGuard.stop()
            console.warn("[VoiceScreenShare] request cancelled")
        }
    }
    onNavigationRequested: function(request) {
        if (!request.url.toString().startsWith(session.webProfile.assetOrigin + "/"))
            request.reject()
    }
    onNewWindowRequested: function(request) { /* No external call windows. */ }
    onFullScreenRequested: function(request) {
        session.panelFullscreen = request.toggleOn
        request.accept()
    }
    onContextMenuRequested: function(request) { request.accepted = true }
    onLoadingChanged: function(info) {
        if (info.status === WebEngineView.LoadStartedStatus)
            session.setWidgetBridgeReady(false)
        if (info.status === WebEngineView.LoadFailedStatus && session.active && session.phase !== "ending")
            session.fail(L10n.I18n.tr("Не удалось загрузить встроенный Element Call: ") + info.errorString)
    }
    onRenderProcessTerminated: session.fail(L10n.I18n.tr("Процесс голосового звонка завершился. Подключитесь заново."))
    // Redact transient credentials before logging Element Call diagnostics.
    onJavaScriptConsoleMessage: function(level, message, line, source) {
        var s = String(message || "")
        if (s.indexOf("__PRISM_DISPLAY_CAPTURE_SETTLED__") >= 0) {
            desktopCaptureGuard.stop()
            desktopCaptureRequestInFlight = false
            return
        }
        var lower = s.toLowerCase()
        var interesting = lower.indexOf("error") >= 0
                       || lower.indexOf("rtc") >= 0
                       || lower.indexOf("transport") >= 0
                       || lower.indexOf("livekit") >= 0
                       || lower.indexOf("openid") >= 0
                       || lower.indexOf("membership") >= 0
        if (!interesting) return

        s = s.replace(/bearer\s+[a-z0-9._~+\/=-]+/ig, "Bearer <redacted>")
        s = s.replace(/("?(?:access_token|id_token|token)"?\s*[:=]\s*")([^"]+)"/ig,
                      '$1<redacted>"')
        console.warn("[ElementCall] " + s)
    }
    Component.onCompleted: {
        // Install the bridge before Element Call begins its handshake.
        var script = WebEngine.script()
        script.name = "PrismVoiceTransport"
        script.injectionPoint = WebEngineScript.DocumentCreation
        script.worldId = WebEngineScript.MainWorld
        script.runsOnSubFrames = false
        script.sourceCode = session.webProfile.bridgeScript
        view.userScripts.insert(script)

        // Coalesce concurrent getDisplayMedia calls into one native chooser.
        var captureGuardScript = WebEngine.script()
        captureGuardScript.name = "PrismDisplayCaptureGuard"
        captureGuardScript.injectionPoint = WebEngineScript.DocumentCreation
        captureGuardScript.worldId = WebEngineScript.MainWorld
        captureGuardScript.runsOnSubFrames = false
        captureGuardScript.sourceCode = "(() => {"
            + "const md = navigator.mediaDevices;"
            + "if (!md || typeof md.getDisplayMedia !== 'function' || md.__prismGuarded) return;"
            + "const original = md.getDisplayMedia.bind(md); let pending = null;"
            + "Object.defineProperty(md, '__prismGuarded', { value: true });"
            + "md.getDisplayMedia = constraints => {"
            + "if (pending) return pending;"
            + "pending = original(constraints);"
            + "pending.then(() => console.info('__PRISM_DISPLAY_CAPTURE_SETTLED__'),"
            + "             () => console.info('__PRISM_DISPLAY_CAPTURE_SETTLED__'))"
            + "       .finally(() => { pending = null; });"
            + "return pending; };"
            + "})();"
        view.userScripts.insert(captureGuardScript)

        // Fill labels for locales not bundled by Element Call.
        var fallbackLabels = CallControlTranslations.labelsFor(L10n.I18n.language)
        if (Object.keys(fallbackLabels).length > 0) {
            var callControlsScript = WebEngine.script()
            callControlsScript.name = "PrismCallControlTranslations"
            callControlsScript.injectionPoint = WebEngineScript.DocumentReady
            callControlsScript.worldId = WebEngineScript.MainWorld
            callControlsScript.runsOnSubFrames = false
            var language = JSON.stringify(L10n.I18n.language)
            var labels = JSON.stringify(fallbackLabels)
            callControlsScript.sourceCode = "(() => {"
                + "const language=" + language + ",labels=" + labels + ";"
                + "const rtl=['ar','he','fa','ur'].includes(language);"
                + "document.documentElement.lang=language;"
                + "document.documentElement.dir=rtl?'rtl':'ltr';"
                + "const translateText=node=>{const raw=node.nodeValue||'';"
                + "const value=raw.trim(),translated=labels[value];"
                + "if(translated)node.nodeValue=raw.replace(value,translated);};"
                + "const visit=node=>{if(node.nodeType===Node.TEXT_NODE){translateText(node);return;}"
                + "if(node.nodeType!==Node.ELEMENT_NODE&&node.nodeType!==Node.DOCUMENT_NODE)return;"
                + "if(node.nodeType===Node.ELEMENT_NODE){for(const name of ['aria-label','title']){"
                + "const value=node.getAttribute(name);if(value&&labels[value])node.setAttribute(name,labels[value]);}}"
                + "for(const child of node.childNodes)visit(child);};"
                + "visit(document);new MutationObserver(records=>{for(const record of records){"
                + "if(record.type==='characterData')translateText(record.target);"
                + "if(record.type==='attributes')visit(record.target);"
                + "for(const node of record.addedNodes)visit(node);}})"
                + ".observe(document,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['aria-label','title']});"
                + "})();"
            view.userScripts.insert(callControlsScript)
        }
        view.url = session.widgetUrl
    }
    Component.onDestruction: {
        session.setWidgetBridgeReady(false)
        if (desktopMediaDialog.request) desktopMediaDialog.request.cancel()
        desktopCaptureGuard.stop()
        desktopCaptureRequestInFlight = false
    }
}

/* Matrix Widget API transport only. Element Call owns MatrixRTC and WebRTC. */
(() => {
    "use strict";
    if (location.protocol !== "http:" || location.hostname !== "127.0.0.1") return;

    const params = new URLSearchParams(location.hash.replace(/^#\/?/, ""));
    const widgetId = params.get("widgetId");
    if (!widgetId) return;

    let bridge = null;
    const waiting = [];

    const parseMessage = (value) => {
        if (typeof value !== "string") return value;
        try { return JSON.parse(value); } catch (_) { return null; }
    };

    const forward = (raw) => {
        if (bridge) {
            bridge.fromWidget(raw);
        } else if (waiting.length < 256) {
            waiting.push(raw);
        }
    };

    // Element Call -> host.  Do not require event.source === window: embedded
    // Widget API implementations can proxy postMessage while preserving the
    // same trusted loopback origin.
    window.addEventListener("message", (event) => {
        if (event.origin !== location.origin) return;
        const data = parseMessage(event.data);
        if (!data || data.widgetId !== widgetId) return;

        // Only page-originated traffic goes out through QWebChannel. Messages
        // injected by the host are echoed as message events too; forwarding
        // those would make WidgetDriver consume its own output.
        const widgetRequest = data.api === "fromWidget" && !("response" in data);
        const widgetResponse = data.api === "toWidget" && ("response" in data);
        if (!widgetRequest && !widgetResponse) return;

        const raw = JSON.stringify(data);
        if (raw.length <= 1048576) forward(raw);
    });

    const connectChannel = () => {
        if (bridge) return;
        if (typeof QWebChannel !== "function" || !window.qt || !qt.webChannelTransport) {
            setTimeout(connectChannel, 0);
            return;
        }
        new QWebChannel(qt.webChannelTransport, (channel) => {
            bridge = channel.objects.voiceBridge;
            if (!bridge) {
                setTimeout(connectChannel, 0);
                return;
            }
            for (const raw of waiting.splice(0)) bridge.fromWidget(raw);
            bridge.ready(widgetId, window.isSecureContext, location.origin);
        });
    };

    connectChannel();
})();

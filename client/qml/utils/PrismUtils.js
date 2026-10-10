function proxyUrl(mxc, mediaProxy, mediaFile, mimeType, thumbnailWidth, thumbnailHeight) {
    if (!mediaProxy || !mxc || mxc.indexOf("mxc://") !== 0)
        return ""
    // A URL fragment is never part of a Matrix media identifier. Some image
    // paths append "#auto"; forwarding it makes the local proxy reject the MXC.
    var fragmentIndex = mxc.indexOf("#")
    var normalizedMxc = fragmentIndex >= 0 ? mxc.substring(0, fragmentIndex) : mxc
    var source = mediaProxy + encodeURIComponent(normalizedMxc)
    if (mediaFile && mediaFile._prism_media_id)
        source += "&file_id=" + encodeURIComponent(mediaFile._prism_media_id)
    if (mimeType)
        source += "&mime=" + encodeURIComponent(mimeType)
    if (Number(thumbnailWidth) > 0 && Number(thumbnailHeight) > 0) {
        source += "&width=" + Math.round(Number(thumbnailWidth))
            + "&height=" + Math.round(Number(thumbnailHeight))
    }
    return source
}

function proxyDownloadUrl(mxc, mediaProxy, filename, mediaFile, mimeType) {
    var source = proxyUrl(mxc, mediaProxy, mediaFile, mimeType)
    if (source === "")
        return ""
    return source + "&download=1&filename="
        + encodeURIComponent(filename || "attachment")
}

function withRetryToken(source, retryToken) {
    var value = String(source || "")
    var token = Number(retryToken || 0)
    if (value === "" || token <= 0)
        return value
    return value + (value.indexOf("?") === -1 ? "?" : "&")
        + "retry=" + Math.round(token)
}

function escapeHtml(value) {
    return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;")
}

function linkifiedText(value) {
    var source = String(value || "")
    var pattern = /(?:https?:\/\/|www\.)[^\s<>"']+/gi
    var result = ""
    var lastIndex = 0
    var match

    while ((match = pattern.exec(source)) !== null) {
        var visibleUrl = match[0]
        var trailing = ""
        while (visibleUrl.length > 0 && /[),.!?;:\]\}]$/.test(visibleUrl)) {
            trailing = visibleUrl.charAt(visibleUrl.length - 1) + trailing
            visibleUrl = visibleUrl.substring(0, visibleUrl.length - 1)
        }

        result += escapeHtml(source.substring(lastIndex, match.index))
        if (visibleUrl !== "") {
            var targetUrl = visibleUrl.toLowerCase().indexOf("www.") === 0
                ? "https://" + visibleUrl : visibleUrl
            result += "<a href=\"" + escapeHtml(targetUrl) + "\">"
                + escapeHtml(visibleUrl) + "</a>" + escapeHtml(trailing)
        } else {
            result += escapeHtml(match[0])
        }
        lastIndex = match.index + match[0].length
    }

    return result + escapeHtml(source.substring(lastIndex))
}

function flagStyledText(value, fontFamily, escapeSource) {
    var source = escapeSource
        ? escapeHtml(value) : String(value || "")
    var family = escapeHtml(fontFamily || "Segoe UI Emoji")
    var flags = /\uD83C[\uDDE6-\uDDFF]\uD83C[\uDDE6-\uDDFF]/g
    var styled = source.replace(flags, function(flag) {
        return "<font face=\"" + family + "\">" + flag + "</font>"
    })
    return styled.replace(/\r\n|\r|\n/g, "<br>")
}

function singleLinePreview(value) {
    return String(value || "")
        .replace(/\r\n|\r|\n/g, " ")
        .replace(/\s+/g, " ")
        .trim()
}

function fencedCodeSegments(value) {
    var source = String(value || "")
    var pattern = /```([^\n`]*)\n?([\s\S]*?)```/g
    var segments = []
    var lastIndex = 0
    var match
    while ((match = pattern.exec(source)) !== null) {
        if (match.index > lastIndex) {
            segments.push({
                kind: "text",
                content: source.substring(lastIndex, match.index)
            })
        }
        segments.push({
            kind: "code",
            language: String(match[1] || "").trim(),
            content: String(match[2] || "").replace(/\n$/, "")
        })
        lastIndex = match.index + match[0].length
    }
    if (lastIndex === 0)
        return [{kind: "text", content: source}]
    if (lastIndex < source.length)
        segments.push({kind: "text", content: source.substring(lastIndex)})
    return segments
}

function displayName(sender) {
    if (!sender)
        return "?"
    var name = sender.split(":")[0]
    if (name.charAt(0) === "@")
        name = name.substring(1)
    return name
}

function avatarColor(sender) {
    var colors = [
        "#e57373", "#81c784", "#64b5f6", "#ffd54f", "#ba68c8",
        "#4db6ac", "#ff8a65", "#a1887f", "#7986cb", "#aed581"
    ]
    var value = sender || ""
    var hash = 0
    for (var i = 0; i < value.length; i++)
        hash = (hash * 31 + value.charCodeAt(i)) % 9973
    return colors[Math.abs(hash) % colors.length]
}

function guessMime(filename) {
    var parts = (filename || "").split(".")
    var ext = parts.length > 1 ? parts.pop().toLowerCase() : ""
    var mimeByExtension = {
        png: "image/png",
        jpg: "image/jpeg",
        jpeg: "image/jpeg",
        gif: "image/gif",
        apng: "image/apng",
        webp: "image/webp",
        mp4: "video/mp4",
        m4v: "video/mp4",
        mov: "video/quicktime",
        mkv: "video/x-matroska",
        webm: "video/webm",
        avi: "video/x-msvideo",
        mpeg: "video/mpeg",
        mpg: "video/mpeg",
        ogv: "video/ogg",
        ts: "video/mp2t",
        mts: "video/mp2t",
        m2ts: "video/mp2t",
        "3gp": "video/3gpp",
        "3g2": "video/3gpp2",
        flv: "video/x-flv",
        mp3: "audio/mpeg",
        m4a: "audio/mp4",
        aac: "audio/aac",
        ogg: "audio/ogg",
        opus: "audio/ogg",
        wav: "audio/wav",
        flac: "audio/flac",
        pdf: "application/pdf"
    }
    return mimeByExtension[ext] || "application/octet-stream"
}

function localPath(fileUrl) {
    var path = fileUrl ? fileUrl.toString() : ""
    if (path === "")
        return ""

    // file:///home/user/image.png -> /home/user/image.png
    // file:///C:/Users/user/image.png -> /C:/Users/user/image.png
    if (path.indexOf("file://") === 0)
        path = path.substring(7)
    else if (path.indexOf("file:") === 0)
        path = path.substring(5)

    try {
        path = decodeURIComponent(path)
    } catch (error) {
        console.warn("Не удалось декодировать путь:", path, error)
    }

    // На Windows после удаления file:// остаётся лишний начальный слеш:
    // /C:/Users/... -> C:/Users/...
    if (/^\/[A-Za-z]:[\/\\]/.test(path))
        path = path.substring(1)

    return path
}

function formatMessageTimestamp(timestamp, dateFormat, timeFormat, yesterdayLabel) {
    var date = new Date(Number(timestamp))
    if (isNaN(date.getTime()))
        return ""

    var now = new Date()
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
    var messageDay = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    var timeText = Qt.formatDateTime(date, timeFormat)

    if (messageDay.getTime() === today.getTime())
        return timeText
    if (messageDay.getTime() === yesterday.getTime())
        return (yesterdayLabel || "вчера") + ", " + timeText
    return Qt.formatDateTime(date, dateFormat) + ", " + timeText
}

function formatMessageTime(timestamp, timeFormat) {
    var date = new Date(Number(timestamp))
    if (isNaN(date.getTime()))
        return ""
    return Qt.formatDateTime(date, timeFormat)
}

function formatMessageDate(timestamp, dateFormat) {
    var date = new Date(Number(timestamp))
    if (isNaN(date.getTime()))
        return ""
    return Qt.formatDateTime(date, dateFormat)
}

function shouldShowMessageHeader(messageModel, messageIndex, intervalMs) {
    if (!messageModel || messageIndex < 0 || messageIndex >= messageModel.count)
        return true
    if (messageIndex >= messageModel.count - 1)
        return true

    var currentMessage = messageModel.get(messageIndex)
    var olderMessage = messageModel.get(messageIndex + 1)
    if (olderMessage.sender !== currentMessage.sender)
        return true

    var oldestRunIndex = messageIndex
    while (oldestRunIndex + 1 < messageModel.count
           && messageModel.get(oldestRunIndex + 1).sender === currentMessage.sender) {
        oldestRunIndex++
    }

    var lastHeaderTimestamp = Number(messageModel.get(oldestRunIndex).timestamp)
    if (!isFinite(lastHeaderTimestamp) || lastHeaderTimestamp <= 0)
        return false

    for (var i = oldestRunIndex - 1; i >= messageIndex; i--) {
        var timestamp = Number(messageModel.get(i).timestamp)
        if (!isFinite(timestamp) || timestamp <= 0)
            continue
        if (timestamp - lastHeaderTimestamp >= intervalMs) {
            if (i === messageIndex)
                return true
            lastHeaderTimestamp = timestamp
        }
    }
    return false
}

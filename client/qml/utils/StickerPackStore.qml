pragma Singleton
import QtQuick
import QtCore
import "." as L10n

QtObject {
    id: root

    property var libraries: ({})
    readonly property int maxPacksPerAccount: 40
    readonly property int maxStickersPerPack: 120

    property Settings storeSettings: Settings {
        category: "StickerPacks"
        property string librariesJson: "{}"
    }

    property Timer persistTimer: Timer {
        interval: 180
        repeat: false
        onTriggered: root.persist()
    }

    Component.onCompleted: {
        try {
            var parsed = JSON.parse(storeSettings.librariesJson || "{}")
            libraries = parsed && typeof parsed === "object" ? parsed : ({})
        } catch (error) {
            libraries = ({})
        }
    }

    function accountKey(accountId) {
        var key = String(accountId || "").trim()
        return key !== "" ? key : "__anonymous__"
    }

    function safeId(value) {
        return String(value || "")
            .replace(/[^a-zA-Z0-9._-]/g, "-")
            .replace(/-+/g, "-")
            .substring(0, 96)
    }

    function generatedId(prefix) {
        return safeId((prefix || "pack") + "-" + Date.now().toString(36)
                      + "-" + Math.floor(Math.random() * 0xFFFFFF).toString(36))
    }

    function sanitizeShortcode(value, fallback) {
        var cleaned = String(value || "").trim()
            .replace(/[^a-zA-Z0-9_-]/g, "_")
            .replace(/_+/g, "_")
            .substring(0, 80)
        return cleaned !== "" ? cleaned : String(fallback || "sticker")
    }

    function normalizedSticker(source, fallbackIndex) {
        source = source || ({})
        var mediaFile = source.media_file && typeof source.media_file === "object"
            ? Object.assign({}, source.media_file) : null
        var mediaUrl = String(source.media_url || source.url
                              || (mediaFile ? mediaFile.url : "") || "")
        if (mediaUrl.indexOf("mxc://") !== 0)
            return null
        var body = String(source.body || source.shortcode || L10n.I18n.tr("Стикер")).substring(0, 160)
        var result = {
            shortcode: sanitizeShortcode(source.shortcode, "sticker_" + Number(fallbackIndex || 0)),
            body: body,
            media_url: mediaUrl,
            media_mime_type: String(source.media_mime_type || source.mimetype || "image/webp"),
            animated: !!source.animated || /(?:gif|webp|apng)$/i.test(String(source.media_mime_type || ""))
        }
        if (mediaFile)
            result.media_file = mediaFile
        return result
    }

    function normalizedPack(source) {
        source = source || ({})
        var images = []
        var rawImages = source.images || []
        if (typeof rawImages.length !== "number")
            rawImages = []
        for (var index = 0; index < rawImages.length && images.length < maxStickersPerPack; index++) {
            var sticker = normalizedSticker(rawImages[index], index + 1)
            if (sticker)
                images.push(sticker)
        }
        return {
            id: safeId(source.id || generatedId("pack")),
            display_name: String(source.display_name || L10n.I18n.tr("Набор стикеров")).substring(0, 80),
            attribution: String(source.attribution || "").substring(0, 240),
            source: String(source.source || "local").substring(0, 48),
            images: images,
            updated_at: Number(source.updated_at || Date.now())
        }
    }

    function packsFor(accountId) {
        var key = accountKey(accountId)
        var value = libraries[key]
        if (!Array.isArray(value))
            return []
        return value.slice(0)
    }

    function packById(accountId, packId) {
        var packs = packsFor(accountId)
        for (var index = 0; index < packs.length; index++) {
            if (String(packs[index].id || "") === String(packId || ""))
                return packs[index]
        }
        return null
    }

    function savePacks(accountId, packs) {
        var key = accountKey(accountId)
        var next = Object.assign({}, libraries)
        next[key] = packs.slice(0, maxPacksPerAccount)
        libraries = next
        persistTimer.restart()
    }

    function createPack(accountId, displayName) {
        var packs = packsFor(accountId)
        var pack = normalizedPack({
            id: generatedId("local"),
            display_name: String(displayName || L10n.I18n.tr("Мои стикеры")),
            source: "local",
            images: []
        })
        packs.unshift(pack)
        savePacks(accountId, packs)
        return pack
    }

    function addSticker(accountId, packId, sticker) {
        var packs = packsFor(accountId)
        var target = -1
        for (var index = 0; index < packs.length; index++) {
            if (String(packs[index].id || "") === String(packId || "")) {
                target = index
                break
            }
        }
        if (target < 0)
            return false
        var normalized = normalizedSticker(sticker, (packs[target].images || []).length + 1)
        if (!normalized)
            return false
        var images = (packs[target].images || []).slice(0)
        var duplicate = -1
        for (var imageIndex = 0; imageIndex < images.length; imageIndex++) {
            if (images[imageIndex].media_url === normalized.media_url) {
                duplicate = imageIndex
                break
            }
        }
        if (duplicate >= 0)
            images[duplicate] = normalized
        else
            images.push(normalized)
        images = images.slice(-maxStickersPerPack)
        packs[target] = Object.assign({}, packs[target], {
            images: images,
            updated_at: Date.now()
        })
        savePacks(accountId, packs)
        return true
    }


    function ensurePack(accountId, packId, displayName, sourceKind) {
        var wantedId = safeId(packId || "saved")
        var packs = packsFor(accountId)
        for (var index = 0; index < packs.length; index++) {
            if (String(packs[index].id || "") === wantedId)
                return packs[index]
        }
        var pack = normalizedPack({
            id: wantedId,
            display_name: String(displayName || L10n.I18n.tr("Стикеры")),
            source: String(sourceKind || "local"),
            images: []
        })
        packs.unshift(pack)
        savePacks(accountId, packs)
        return pack
    }

    function saveSticker(accountId, sticker, displayName) {
        var pack = ensurePack(accountId, "saved", displayName || L10n.I18n.tr("Стикеры"), "saved")
        if (!pack)
            return false
        return addSticker(accountId, pack.id, sticker)
    }

    function containsSticker(accountId, mediaUrl) {
        var wanted = String(mediaUrl || "")
        if (wanted === "")
            return false
        var packs = packsFor(accountId)
        for (var packIndex = 0; packIndex < packs.length; packIndex++) {
            var images = packs[packIndex].images || []
            for (var imageIndex = 0; imageIndex < images.length; imageIndex++) {
                if (String(images[imageIndex].media_url || "") === wanted)
                    return true
            }
        }
        return false
    }

    function installPack(accountId, sourcePack) {
        var incoming = normalizedPack(sourcePack)
        if (!incoming || incoming.images.length === 0)
            return false
        incoming = Object.assign({}, incoming, { source: "received", updated_at: Date.now() })
        var packs = packsFor(accountId)
        var replaced = false
        for (var index = 0; index < packs.length; index++) {
            if (packs[index].id === incoming.id) {
                packs[index] = incoming
                replaced = true
                break
            }
        }
        if (!replaced)
            packs.unshift(incoming)
        savePacks(accountId, packs)
        return true
    }

    function removePack(accountId, packId) {
        var packs = packsFor(accountId)
        var filtered = []
        for (var index = 0; index < packs.length; index++) {
            if (String(packs[index].id || "") !== String(packId || ""))
                filtered.push(packs[index])
        }
        if (filtered.length === packs.length)
            return false
        savePacks(accountId, filtered)
        return true
    }

    function persist() {
        try {
            storeSettings.librariesJson = JSON.stringify(libraries)
        } catch (error) {
            console.warn("StickerPackStore serialization failed:", error)
        }
    }

    function flush() {
        persistTimer.stop()
        persist()
        storeSettings.sync()
    }
}

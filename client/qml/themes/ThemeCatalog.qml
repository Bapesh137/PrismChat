pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel

Item {
    id: root

    width: 0
    height: 0
    visible: false

    readonly property var emergencyDarkTheme: ({
        id: "fallback-dark",
        name: "Fallback Dark",
        accent: "#20D500",
        icons: "#20D500",
        accentText: "#071007",
        background: "#07100A",
        surface: "#0B1710",
        elevated: "#102016",
        textPrimary: "#F2FFF4",
        textSecondary: "#A7B8AA",
        divider: "#29402E"
    })

    readonly property var emergencyLightTheme: ({
        id: "fallback-light",
        name: "Fallback Light",
        accent: "#20D500",
        icons: "#20D500",
        accentText: "#071007",
        background: "#F3F8F4",
        surface: "#FFFFFF",
        elevated: "#E7F0E9",
        textPrimary: "#172019",
        textSecondary: "#607064",
        divider: "#C5D2C8"
    })

    readonly property var requiredThemeKeys: [
        "id", "name", "accent", "icons", "accentText", "background",
        "surface", "elevated", "textPrimary", "textSecondary", "divider"
    ]

    // These arrays are always non-empty. Until the folder scan finishes,
    // the corresponding fallback is used.
    property var darkThemes: [emergencyDarkTheme]
    property var lightThemes: [emergencyLightTheme]

    property int darkLoadGeneration: 0
    property int lightLoadGeneration: 0

    FolderListModel {
        id: darkFolderModel
        folder: Qt.resolvedUrl("dark/")
        nameFilters: ["*.qml"]
        showDirs: false
        showDotAndDotDot: false
        showFiles: true
        showOnlyReadable: true
        sortField: FolderListModel.Name

        onStatusChanged: {
            if (status === FolderListModel.Ready)
                darkReloadTimer.restart()
        }
        onCountChanged: {
            if (status === FolderListModel.Ready)
                darkReloadTimer.restart()
        }
    }

    FolderListModel {
        id: lightFolderModel
        folder: Qt.resolvedUrl("light/")
        nameFilters: ["*.qml"]
        showDirs: false
        showDotAndDotDot: false
        showFiles: true
        showOnlyReadable: true
        sortField: FolderListModel.Name

        onStatusChanged: {
            if (status === FolderListModel.Ready)
                lightReloadTimer.restart()
        }
        onCountChanged: {
            if (status === FolderListModel.Ready)
                lightReloadTimer.restart()
        }
    }

    Timer {
        id: darkReloadTimer
        interval: 0
        repeat: false
        onTriggered: root.reloadFolder("dark", darkFolderModel)
    }

    Timer {
        id: lightReloadTimer
        interval: 0
        repeat: false
        onTriggered: root.reloadFolder("light", lightFolderModel)
    }

    Component.onCompleted: {
        if (darkFolderModel.status === FolderListModel.Ready)
            darkReloadTimer.restart()
        if (lightFolderModel.status === FolderListModel.Ready)
            lightReloadTimer.restart()
    }

    function normalizeTheme(rawTheme, sourceUrl) {
        if (!rawTheme || typeof rawTheme !== "object" || Array.isArray(rawTheme)) {
            console.warn("ThemeCatalog: themeData must be an object:", sourceUrl)
            return null
        }

        for (let index = 0; index < requiredThemeKeys.length; ++index) {
            const key = requiredThemeKeys[index]
            if (rawTheme[key] === undefined || rawTheme[key] === null
                    || String(rawTheme[key]).length === 0) {
                console.warn("ThemeCatalog: missing field", key, "in", sourceUrl)
                return null
            }
        }

        return {
            id: String(rawTheme.id),
            name: String(rawTheme.name),
            accent: String(rawTheme.accent),
            icons: String(rawTheme.icons),
            accentText: String(rawTheme.accentText),
            background: String(rawTheme.background),
            surface: String(rawTheme.surface),
            elevated: String(rawTheme.elevated),
            textPrimary: String(rawTheme.textPrimary),
            textSecondary: String(rawTheme.textSecondary),
            divider: String(rawTheme.divider)
        }
    }

    function loadTheme(sourceUrl, callback) {
        const component = Qt.createComponent(sourceUrl)
        let completed = false

        function finish(theme) {
            if (completed)
                return

            completed = true
            try {
                component.statusChanged.disconnect(componentStatusChanged)
            } catch (error) {
                // Synchronous components were never connected.
            }

            callback(theme)
            component.destroy()
        }

        function componentStatusChanged() {
            if (completed || component.status === Component.Loading)
                return

            if (component.status === Component.Error) {
                console.warn("ThemeCatalog: cannot compile", sourceUrl,
                             component.errorString())
                finish(null)
                return
            }

            if (component.status !== Component.Ready)
                return

            // Theme files may use QtObject as their root. Qt.createComponent()
            // supports that; Loader.item does not reliably do so on every Qt build.
            const themeObject = component.createObject(root)
            if (!themeObject) {
                console.warn("ThemeCatalog: cannot instantiate", sourceUrl,
                             component.errorString())
                finish(null)
                return
            }

            const theme = root.normalizeTheme(themeObject.themeData, sourceUrl)
            themeObject.destroy()
            finish(theme)
        }

        if (component.status === Component.Loading)
            component.statusChanged.connect(componentStatusChanged)
        else
            componentStatusChanged()
    }

    function reloadFolder(mode, folderModel) {
        const generation = mode === "light"
            ? ++lightLoadGeneration
            : ++darkLoadGeneration
        const fileCount = folderModel.count

        console.log("ThemeCatalog:", mode, "folder =", folderModel.folder,
                    "files =", fileCount)

        if (fileCount <= 0) {
            setThemes(mode, [])
            return
        }

        const loadedThemes = new Array(fileCount)
        let filesRemaining = fileCount

        function fileFinished(index, theme) {
            const currentGeneration = mode === "light"
                ? root.lightLoadGeneration
                : root.darkLoadGeneration

            if (generation !== currentGeneration)
                return

            loadedThemes[index] = theme
            --filesRemaining

            if (filesRemaining === 0)
                root.publishThemes(mode, loadedThemes)
        }

        for (let index = 0; index < fileCount; ++index) {
            const sourceUrl = folderModel.get(index, "fileUrl")
            loadTheme(sourceUrl, function(theme) {
                fileFinished(index, theme)
            })
        }
    }

    function publishThemes(mode, loadedThemes) {
        const themes = []
        const usedIds = ({})

        for (let index = 0; index < loadedThemes.length; ++index) {
            const theme = loadedThemes[index]
            if (!theme)
                continue

            if (usedIds[theme.id]) {
                console.warn("ThemeCatalog: duplicate id ignored:", theme.id)
                continue
            }

            usedIds[theme.id] = true
            themes.push(theme)
        }

        setThemes(mode, themes)
        console.log("ThemeCatalog:", mode, "loaded themes =", themes.length)
    }

    function setThemes(mode, themes) {
        const fallback = mode === "light"
            ? emergencyLightTheme
            : emergencyDarkTheme
        const result = themes.length > 0 ? themes : [fallback]

        if (mode === "light")
            lightThemes = result
        else
            darkThemes = result
    }

    function themesFor(mode) {
        return mode === "light" ? lightThemes : darkThemes
    }

    function theme(mode, themeId) {
        const themes = themesFor(mode)

        for (let index = 0; index < themes.length; ++index) {
            if (themes[index].id === themeId)
                return themes[index]
        }

        return themes.length > 0
            ? themes[0]
            : (mode === "light" ? emergencyLightTheme : emergencyDarkTheme)
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    // Fond animé (vidéo ou GIF) joué par-dessus l'image, seulement sur secteur
    readonly property string animatedPath: `${Paths.state}/wallpaper/animated.txt`
    property string animated
    // Vidéos du dossier : leur miniature (et l'image sur batterie) est une image tirée de la vidéo
    readonly property string framesDir: `${Quickshell.env("HOME")}/.local/share/caelestia/animated-frames`
    property int framesVersion // change quand de nouvelles miniatures sont prêtes
    readonly property string selected: animated || actualCurrent

    function isVideo(path: string): bool {
        return /\.(mp4|webm|mkv|mov|avi)$/i.test(path);
    }

    function thumbFor(path: string): string {
        if (!isVideo(path))
            return path;
        const name = path.slice(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
        return framesVersion > 0 ? `${framesDir}/${name}.jpg` : "";
    }
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setAnimated(path: string): void {
        animated = path;
        animatedView.setText(path ? path + "\n" : "");
    }

    function setRandom(): void {
        setAnimated("");
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    // Choisir une image fixe dans le sélecteur remplace le fond animé
    function setWallpaper(path: string): void {
        if (isVideo(path)) {
            // caelestia-animwall tire l'image fixe, la met en fond et lance la vidéo
            Quickshell.execDetached(["caelestia-animwall", path]);
            return;
        }
        setAnimated("");
        actualCurrent = path;
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = thumbFor(path);
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: [...wallpapers.entries, ...videos.entries]
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        function setAnimated(path: string): void {
            root.setAnimated(path);
        }

        function getAnimated(): string {
            return root.animated;
        }

        target: "wallpaper"
    }

    FileView {
        id: animatedView

        path: root.animatedPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.animated = text().trim()
        onLoadFailed: root.animated = ""
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    FileSystemModel {
        id: videos

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: ["*.mp4", "*.webm", "*.mkv", "*.mov", "*.avi"]
        onEntriesChanged: framesProc.running = true
    }

    // Crée les miniatures manquantes des vidéos
    Process {
        id: framesProc

        command: ["caelestia-animwall", "frames", ...videos.entries.map(v => v.path)]
        onExited: root.framesVersion++
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}

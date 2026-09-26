pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Liste de tâches de l'onglet Notes (mode « Tâches »).
// Source de vérité : ~/.local/share/caelestia/tasks.json ; copie lisible dans ~/Documents/Notes/Caelestia/Tâches.md
Singleton {
    id: root

    property list<var> tasks: []
    property bool loaded
    property bool dirty
    property var trashed: null

    readonly property int doneCount: tasks.filter(t => t.done).length
    readonly property int todoCount: tasks.length - doneCount
    // À faire d'abord (ordre d'ajout, plus récentes en haut), puis terminées (dernières cochées en haut)
    readonly property list<var> sorted: [...tasks].sort((a, b) => (a.done - b.done) || (a.done ? b.doneAt - a.doneAt : b.created - a.created))

    function add(text: string): void {
        const t = text.trim();
        if (!t)
            return;
        const now = Date.now();
        tasks = [{
                id: now.toString(36) + Math.random().toString(36).slice(2, 6),
                text: t,
                done: false,
                created: now,
                doneAt: 0
            }, ...tasks];
        scheduleSave();
    }

    function toggle(id: string): void {
        const task = tasks.find(t => t.id === id);
        if (!task)
            return;
        task.done = !task.done;
        task.doneAt = task.done ? Date.now() : 0;
        tasks = [...tasks];
        scheduleSave();
    }

    function edit(id: string, text: string): void {
        const task = tasks.find(t => t.id === id);
        if (!task || task.text === text.trim())
            return;
        if (!text.trim()) {
            remove(id);
            return;
        }
        task.text = text.trim();
        tasks = [...tasks];
        scheduleSave();
    }

    function remove(id: string): void {
        trashed = tasks.find(t => t.id === id) ?? null;
        tasks = tasks.filter(t => t.id !== id);
        scheduleSave();
    }

    function restore(): void {
        if (!trashed)
            return;
        tasks = [trashed, ...tasks];
        trashed = null;
        scheduleSave();
    }

    function clearDone(): void {
        tasks = tasks.filter(t => !t.done);
        scheduleSave();
    }

    function scheduleSave(): void {
        dirty = true;
        saveTimer.restart();
    }

    function saveNow(): void {
        if (!loaded || !dirty)
            return;
        saveTimer.stop();
        storage.setText(JSON.stringify(tasks, null, 2));
        const todo = sorted.filter(t => !t.done).map(t => `- [ ] ${t.text}`);
        const done = sorted.filter(t => t.done).map(t => `- [x] ${t.text}`);
        mdExport.environment = {
            DIR: Notes.exportDir,
            BODY: `# Tâches\n\n${[...todo, ...done].join("\n")}\n`
        };
        mdExport.running = true;
        dirty = false;
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: root.saveNow()
    }

    FileView {
        id: storage

        path: `${Paths.data}/tasks.json`
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.tasks = Array.isArray(data) ? data : [];
            } catch (e) {
                root.tasks = [];
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("[]"));
        }
    }

    Process {
        id: mdExport

        command: ["sh", "-c", 'mkdir -p "$DIR" && printf "%s" "$BODY" > "$DIR/Tâches.md"']
    }

    Component.onDestruction: saveNow()
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

// Bloc-notes du tableau de bord (Super+A → Notes).
// Source de vérité : ~/.local/share/caelestia/notes.json (écriture atomique).
// Chaque note est aussi copiée en Markdown dans ~/Documents/Notes/Caelestia pour rester lisible ailleurs.
Singleton {
    id: root

    readonly property string file: `${Paths.data}/notes.json`
    readonly property string exportDir: `${Quickshell.env("XDG_DOCUMENTS_DIR") || `${Paths.home}/Documents`}/Notes/Caelestia`

    property list<var> notes: []
    // Mode affiché dans l'onglet : "notes" ou "tasks" (retenu tant que le shell tourne)
    property string mode: "notes"
    property string currentId
    property bool loaded
    property bool dirty
    property real lastSaved

    readonly property var current: notes.find(n => n.id === currentId) ?? null
    // Épinglées d'abord, puis les plus récentes
    readonly property list<var> sorted: [...notes].sort((a, b) => (b.pinned - a.pinned) || (b.updated - a.updated))

    function titleOf(note: var): string {
        const first = (note?.body ?? "").split("\n").find(l => l.trim().length > 0) ?? "";
        return first.replace(/^#+\s*/, "").trim() || qsTr("Nouvelle note");
    }

    function previewOf(note: var): string {
        const lines = (note?.body ?? "").split("\n").filter(l => l.trim().length > 0);
        return lines.slice(1).join(" · ").trim();
    }

    function create(): string {
        // On réutilise une note vide existante plutôt que d'en empiler
        const empty = notes.find(n => !n.body.trim());
        if (empty) {
            currentId = empty.id;
            return empty.id;
        }
        const now = Date.now();
        const note = {
            id: now.toString(36) + Math.random().toString(36).slice(2, 6),
            body: "",
            pinned: false,
            created: now,
            updated: now
        };
        notes = [note, ...notes];
        currentId = note.id;
        scheduleSave();
        return note.id;
    }

    function update(id: string, body: string): void {
        const note = notes.find(n => n.id === id);
        if (!note || note.body === body)
            return;
        note.body = body;
        note.updated = Date.now();
        notes = [...notes];
        scheduleSave();
    }

    function togglePin(id: string): void {
        const note = notes.find(n => n.id === id);
        if (!note)
            return;
        note.pinned = !note.pinned;
        notes = [...notes];
        scheduleSave();
    }

    property var trashed: null

    function remove(id: string): void {
        const note = notes.find(n => n.id === id);
        if (!note)
            return;
        trashed = note;
        notes = notes.filter(n => n.id !== id);
        if (currentId === id)
            currentId = sorted[0]?.id ?? "";
        if (note.body.trim())
            Toaster.toast(qsTr("Note supprimée"), root.titleOf(note), "delete");
        scheduleSave();
    }

    function restore(): void {
        if (!trashed)
            return;
        notes = [trashed, ...notes];
        currentId = trashed.id;
        trashed = null;
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
        const data = notes.filter(n => n.body.trim() || n.id === currentId);
        storage.setText(JSON.stringify(data, null, 2));
        exportMd(data);
        dirty = false;
        lastSaved = Date.now();
    }

    property bool exportPending

    function exportMd(data: var): void {
        if (exporter.running) {
            exportPending = true;
            return;
        }
        const files = data.filter(n => n.body.trim()).map(n => [titleOf(n), n.body]);
        exporter.environment = {
            NOTES_DIR: exportDir,
            NOTES_JSON: JSON.stringify(files)
        };
        exporter.running = true;
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: root.saveNow()
    }

    FileView {
        id: storage

        path: root.file
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.notes = Array.isArray(data) ? data : [];
            } catch (e) {
                root.notes = [];
            }
            root.currentId = root.sorted[0]?.id ?? "";
            root.loaded = true;
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("[]"));
        }
    }

    Process {
        id: exporter

        // Nom de fichier = titre de la note. Seuls les fichiers créés ici (listés dans
        // .caelestia-notes) sont renommés ou supprimés : le reste du dossier n'est jamais touché.
        command: ["python3", "-c", `
import json, os, re
d = os.environ["NOTES_DIR"]
os.makedirs(d, exist_ok=True)
man = os.path.join(d, ".caelestia-notes")
try:
    old = set(json.load(open(man)))
except Exception:
    old = set()
new = []
for title, body in json.loads(os.environ["NOTES_JSON"]):
    base = re.sub(r'[\\/:*?"<>|\\n\\r\\t]', " ", title).strip(" .")[:80] or "Note"
    name, i = base + ".md", 2
    while name in new or (name not in old and os.path.exists(os.path.join(d, name))):
        name, i = f"{base} ({i}).md", i + 1
    new.append(name)
    p = os.path.join(d, name)
    if not os.path.exists(p) or open(p, encoding="utf-8").read() != body:
        open(p, "w", encoding="utf-8").write(body)
for name in old - set(new):
    try:
        os.remove(os.path.join(d, name))
    except OSError:
        pass
json.dump(new, open(man, "w"))
`]
        onExited: {
            if (root.exportPending) {
                root.exportPending = false;
                root.exportMd(root.notes);
            }
        }
    }

    Component.onDestruction: saveNow()
}

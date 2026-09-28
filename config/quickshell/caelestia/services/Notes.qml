pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

// Bloc-notes (Super+Maj+N et tableau de bord → Notes), synchronisé avec AetherNotes.
// Source de vérité partagée : ~/.local/share/aethernotes/notes.json, écrite sous verrou par
// ~/.local/bin/aethernotes-notes (le même script que scripts/notes_store.py de l'app).
// Fusion « le plus récent gagne » (updatedAt) ; une suppression l'emporte sur les versions plus anciennes.
// Chaque note est aussi copiée en Markdown dans ~/Documents/Notes/Caelestia pour rester lisible ailleurs.
Singleton {
    id: root

    readonly property string helper: `${Paths.home}/.local/bin/aethernotes-notes`
    readonly property string file: `${Quickshell.env("XDG_DATA_HOME") || `${Paths.home}/.local/share`}/aethernotes/notes.json`
    readonly property string legacyFile: `${Paths.data}/notes.json`
    readonly property string exportDir: `${Quickshell.env("XDG_DOCUMENTS_DIR") || `${Paths.home}/Documents`}/Notes/Caelestia`

    // Notes affichées : { id, body, pinned, created, updated, locked, full }
    property list<var> notes: []
    // Mode affiché dans l'onglet : "notes" ou "tasks" (retenu tant que le shell tourne)
    property string mode: "notes"
    property string currentId
    property bool loaded
    property bool dirty
    property bool syncFailed
    property real lastSaved

    // Modifications locales pas encore écrites, et suppressions à transmettre
    property var pending: ({})
    property var deletions: ({})

    // Une note ouverte a été modifiée ailleurs (dans AetherNotes)
    signal externalChange(id: string)

    readonly property var current: notes.find(n => n.id === currentId) ?? null
    // Épinglées d'abord, puis les plus récentes
    readonly property list<var> sorted: [...notes].sort((a, b) => (b.pinned - a.pinned) || (b.updated - a.updated))

    function titleOf(note: var): string {
        if (note?.locked)
            return note.full?.title || qsTr("Note chiffrée");
        const first = (note?.body ?? "").split("\n").find(l => l.trim().length > 0) ?? "";
        return first.replace(/^#+\s*/, "").trim() || qsTr("Nouvelle note");
    }

    function previewOf(note: var): string {
        if (note?.locked)
            return qsTr("Chiffrée · à ouvrir dans AetherNotes");
        const lines = (note?.body ?? "").split("\n").filter(l => l.trim().length > 0);
        return lines.slice(1).join(" · ").trim();
    }

    // ── Conversion AetherNotes ⇄ panneau ──

    function bodyOf(n: var): string {
        const content = n.content ?? "";
        const title = (n.title ?? "").trim();
        const first = (content.split("\n").find(l => l.trim().length > 0) ?? "").replace(/^#+\s*/, "").trim();
        if (!title || first === title)
            return content;
        return content.trim() ? `# ${title}\n\n${content}` : title;
    }

    function fromAether(n: var): var {
        return {
            id: n.id,
            body: n.isLocked ? "" : bodyOf(n),
            pinned: !!n.isPinned,
            created: n.createdAt || 0,
            updated: n.updatedAt || 0,
            locked: !!n.isLocked,
            full: n
        };
    }

    function toAether(note: var): var {
        const body = note.body;
        const words = body.trim() ? body.trim().split(/\s+/).length : 0;
        const total = (body.match(/-\s+\[[ xX]\]/g) ?? []).length;
        const done = (body.match(/-\s+\[[xX]\]/g) ?? []).length;
        return Object.assign({
            tags: [],
            workspaceId: "personal",
            isArchived: false,
            isLocked: false,
            revisions: []
        }, note.full ?? {}, {
            id: note.id,
            title: titleOf(note),
            content: body,
            createdAt: note.created,
            updatedAt: note.updated,
            isPinned: note.pinned,
            words: words,
            characters: body.length,
            readTimeMinutes: Math.max(1, Math.ceil(words / 200)),
            totalTasks: total,
            completedTasks: done,
            hasTasks: total > 0
        });
    }

    // ── Édition ──

    function touch(note: var): void {
        pending[note.id] = true;
        notes = [...notes];
        scheduleSave();
    }

    function create(): string {
        // On réutilise une note vide existante plutôt que d'en empiler
        const empty = notes.find(n => !n.locked && !n.body.trim());
        if (empty) {
            currentId = empty.id;
            return empty.id;
        }
        const now = Date.now();
        const note = {
            id: `note-${now.toString(36)}${Math.random().toString(36).slice(2, 6)}`,
            body: "",
            pinned: false,
            created: now,
            updated: now,
            locked: false,
            full: null
        };
        notes = [note, ...notes];
        currentId = note.id;
        return note.id;
    }

    function update(id: string, body: string): void {
        const note = notes.find(n => n.id === id);
        if (!note || note.locked || note.body === body)
            return;
        note.body = body;
        note.updated = Date.now();
        touch(note);
    }

    function togglePin(id: string): void {
        const note = notes.find(n => n.id === id);
        if (!note)
            return;
        note.pinned = !note.pinned;
        note.updated = Date.now();
        touch(note);
    }

    property var trashed: null

    function remove(id: string): void {
        const note = notes.find(n => n.id === id);
        if (!note)
            return;
        trashed = note;
        notes = notes.filter(n => n.id !== id);
        delete pending[id];
        if (note.full)
            deletions[id] = Date.now();
        if (currentId === id)
            currentId = sorted[0]?.id ?? "";
        if (note.locked || note.body.trim())
            Toaster.toast(qsTr("Note supprimée"), root.titleOf(note), "delete");
        scheduleSave();
    }

    function restore(): void {
        if (!trashed)
            return;
        const note = trashed;
        trashed = null;
        delete deletions[note.id];
        // Nouvelle date : la restauration passe devant la suppression déjà transmise
        note.updated = Date.now();
        notes = [note, ...notes];
        currentId = note.id;
        touch(note);
    }

    // ── Synchronisation ──

    function scheduleSave(): void {
        dirty = true;
        saveTimer.restart();
    }

    function saveNow(): void {
        if (!loaded || !dirty)
            return;
        if (syncer.running) {
            saveTimer.restart();
            return;
        }
        saveTimer.stop();
        // Une note vide n'est partagée que si elle l'était déjà
        const changed = notes.filter(n => pending[n.id] && (n.full || n.body.trim()));
        for (const n of changed)
            delete pending[n.id];
        syncer.payload = JSON.stringify({
            notes: changed.map(n => toAether(n)),
            deleted: deletions
        });
        deletions = {};
        syncer.running = true;
    }

    // État partagé relu (après notre écriture ou une modification d'AetherNotes)
    function applyState(state: var): void {
        const remote = (state.notes ?? []).filter(n => n && n.id && !n.isArchived);
        const local = new Map(notes.map(n => [n.id, n]));
        const next = [];
        for (const r of remote) {
            const mine = local.get(r.id);
            local.delete(r.id);
            // Une modification locale pas encore partagée reste prioritaire
            if (mine && pending[r.id] && mine.updated >= (r.updatedAt || 0)) {
                mine.full = r;
                next.push(mine);
                continue;
            }
            const note = fromAether(r);
            if (mine && mine.id === currentId && mine.body !== note.body)
                Qt.callLater(() => root.externalChange(note.id));
            next.push(note);
        }
        // Notes locales jamais partagées (nouvelle note en cours) : on les garde
        for (const mine of local.values())
            if (!mine.full && (pending[mine.id] || mine.id === currentId))
                next.push(mine);
        notes = next;
        if (!notes.some(n => n.id === currentId))
            currentId = sorted[0]?.id ?? "";
        exportMd(notes);
    }

    property bool exportPending

    function exportMd(data: var): void {
        if (exporter.running) {
            exportPending = true;
            return;
        }
        const files = data.filter(n => !n.locked && n.body.trim()).map(n => [titleOf(n), n.body]);
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

    Process {
        id: syncer

        property string payload

        command: [root.helper, "sync", "-"]
        stdinEnabled: true
        onStarted: {
            write(payload);
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            root.syncFailed = code !== 0;
            root.dirty = Object.keys(root.pending).length > 0;
            root.lastSaved = Date.now();
            if (root.dirty)
                saveTimer.restart();
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(text));
                } catch (e) {}
            }
        }
    }

    // Premier lancement : reprise unique des anciennes notes du panneau, puis lecture
    Process {
        id: firstLoad

        running: true
        command: [root.helper, "import-legacy", root.legacyFile]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(text));
                    root.currentId = root.sorted[0]?.id ?? "";
                } catch (e) {
                    console.warn("AetherNotes : lecture impossible", e);
                }
                root.loaded = true;
            }
        }
    }

    // Changements venus d'AetherNotes
    FileView {
        id: storage

        path: root.file
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (!root.loaded || syncer.running)
                return;
            try {
                root.applyState(JSON.parse(text()));
            } catch (e) {}
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

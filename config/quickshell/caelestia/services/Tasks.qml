pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Quick actions on AuraTask's shared local tasks. The helper locks the file so
// browser and shell changes cannot overwrite one another.
Singleton {
    id: root

    readonly property string helper: `${Paths.home}/.local/bin/auratask-tasks`
    property list<var> tasks: []
    property bool loaded
    property var trashed: null

    readonly property int doneCount: tasks.filter(t => t.done).length
    readonly property int todoCount: tasks.length - doneCount
    readonly property int overdueCount: tasks.filter(t => isOverdue(t)).length
    readonly property int todayCount: tasks.filter(t => !t.done && isToday(t)).length
    // À faire d'abord (en retard, échéance proche, priorité), puis les terminées récentes
    readonly property list<var> sorted: [...tasks].sort((a, b) => {
        if (a.done !== b.done)
            return a.done - b.done;
        if (a.done)
            return b.doneAt - a.doneAt;
        const da = a.due || Infinity, db = b.due || Infinity;
        if (da !== db)
            return da < db ? -1 : 1;
        return (rank[a.priority] ?? 2) - (rank[b.priority] ?? 2) || b.created - a.created;
    })

    readonly property var rank: ({ urgent: 0, high: 1, medium: 2, low: 3 })
    readonly property list<string> priorities: ["low", "medium", "high", "urgent"]

    // Minuit ce soir, pour « aujourd'hui » et « en retard »
    property real dayEnd: endOfDay(0)
    property real minuteTick: Date.now()

    function endOfDay(offset: int): real {
        const d = new Date();
        d.setHours(23, 59, 59, 0);
        return d.getTime() + offset * 86400000;
    }

    function isOverdue(t: var): bool {
        return !t.done && t.due > 0 && t.due < dayEnd - 86400000 + 1000;
    }

    function isToday(t: var): bool {
        return t.due > 0 && t.due <= dayEnd;
    }

    function priorityLabel(p: string): string {
        return { urgent: qsTr("Urgente"), high: qsTr("Haute"), medium: qsTr("Moyenne"), low: qsTr("Basse") }[p] ?? "";
    }

    function dueLabel(t: var): string {
        if (!t.due)
            return "";
        const days = Math.round((endOfDay(0) - t.due) / 86400000);
        if (days === 0)
            return qsTr("Aujourd'hui");
        if (days === -1)
            return qsTr("Demain");
        if (days === 1)
            return qsTr("Hier");
        if (days > 1)
            return qsTr("Il y a %1 j").arg(days);
        const d = new Date(t.due);
        return d.toLocaleDateString(Qt.locale(), days > -7 ? "dddd" : "d MMM");
    }

    function action(command: string, args: var): void {
        Quickshell.execDetached([helper, command, ...args]);
    }

    // Saisie rapide : « !haute » ou « ! », « !! » urgente, « aujourd'hui », « demain »
    function add(text: string): void {
        let title = text.trim();
        if (!title)
            return;
        let priority = "medium";
        let due = null;
        const take = (re, fn) => {
            const m = title.match(re);
            if (m) {
                fn(m);
                title = title.replace(re, " ").replace(/\s+/g, " ").trim();
            }
        };
        take(/(^|\s)!!(\s|$)|(^|\s)!urgent[e]?(\s|$)/i, () => priority = "urgent");
        take(/(^|\s)!(haute?|high)?(\s|$)/i, () => priority = "high");
        take(/(^|\s)!(basse?|low)(\s|$)/i, () => priority = "low");
        take(/(^|\s)(aujourd'hui|auj)(\s|$)/i, () => due = endOfDay(0));
        take(/(^|\s)demain(\s|$)/i, () => due = endOfDay(1));
        if (!title)
            return;
        // « surveille … » : tâche de surveillance web
        if (/^surveille[rz]?\s/i.test(title)) {
            addWatch(title.replace(/^surveille[rz]?\s+/i, ""));
            return;
        }
        upsertNew(newTask(title, priority, due, "Personnel & Santé", "", []));
    }

    function newTask(title: string, priority: string, due: real, category: string, description: string, tags: var): var {
        const now = new Date().toISOString().replace(/\.\d+Z$/, "Z");
        return {
            id: `quick_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
            title: title,
            description: description,
            priority: priority,
            status: "todo",
            category: category,
            dueDate: due ? new Date(due).toISOString() : null,
            estimatedMinutes: 30,
            timeSpentMinutes: 0,
            completed: false,
            completedAt: null,
            createdAt: now,
            updatedAt: now,
            tags: tags,
            subtasks: [],
            smartReminders: []
        };
    }

    function upsertNew(task: var): void {
        action("apply", [JSON.stringify([{ type: "upsert", task: task }])]);
    }

    // ── Surveillances : « Gemini 4 Argon dispo pour AI Pro chaque heure » ──
    // Vérifiées sur internet par ~/.local/bin/caelestia-watch (minuteur toutes les 5 min)
    readonly property string watcher: `${Paths.home}/.local/bin/caelestia-watch`
    property var watchState: ({})

    function addWatch(text: string): void {
        let title = text.trim();
        let every = 60;
        const take = (re, fn) => {
            const m = title.match(re);
            if (m) {
                fn(m);
                title = title.replace(re, " ").replace(/\s+/g, " ").trim();
            }
        };
        take(/(^|\s)(chaque|toutes les|tous les)\s+(\d+)\s*(min|minutes?)(\s|$)/i, m => every = Number(m[3]));
        take(/(^|\s)(chaque|toutes les|tous les)\s+(\d+)\s*(h|heures?)(\s|$)/i, m => every = Number(m[3]) * 60);
        take(/(^|\s)(chaque|toutes les)\s+heures?(\s|$)/i, () => every = 60);
        take(/(^|\s)(chaque jour|tous les jours|quotidien(nement)?)(\s|$)/i, () => every = 1440);
        take(/(^|\s)(chaque semaine|toutes les semaines)(\s|$)/i, () => every = 10080);
        if (!title)
            return;
        every = Math.max(15, every);
        const task = newTask(title, "medium", 0, "Surveillance", qsTr("Surveillance web automatique : vérifiée %1.").arg(everyLabel(every)), ["surveillance", `chaque:${every}`]);
        upsertNew(task);
        // Première vérification tout de suite (le temps que la tâche soit écrite)
        Qt.callLater(() => Quickshell.execDetached(["sh", "-c", `sleep 2; exec "${watcher}" now ${task.id}`]));
    }

    function checkNow(id: string): void {
        Quickshell.execDetached([watcher, "now", id]);
    }

    function everyLabel(min: int): string {
        if (min >= 10080)
            return qsTr("chaque semaine");
        if (min >= 1440)
            return min === 1440 ? qsTr("chaque jour") : qsTr("tous les %1 jours").arg(Math.round(min / 1440));
        if (min >= 60)
            return min === 60 ? qsTr("chaque heure") : qsTr("toutes les %1 h").arg(Math.round(min / 60));
        return qsTr("toutes les %1 min").arg(min);
    }

    function ago(ms: real): string {
        const m = Math.round((Date.now() - ms) / 60000);
        if (m < 1)
            return qsTr("à l'instant");
        if (m < 60)
            return qsTr("il y a %1 min").arg(m);
        if (m < 1440)
            return qsTr("il y a %1 h").arg(Math.round(m / 60));
        return qsTr("il y a %1 j").arg(Math.round(m / 1440));
    }

    // Ligne d'état d'une surveillance : dernière vérification et résultat
    function watchLabel(t: var): string {
        void minuteTick; // « il y a N min » se met à jour chaque minute
        const st = watchState[t.id] ?? {};
        if (t.found || st.status === "found")
            return qsTr("Trouvé ! %1").arg(st.summary ?? "");
        if (st.checking)
            return qsTr("Vérification en cours…");
        if (!st.last)
            return qsTr("Surveillance %1 · en attente").arg(everyLabel(t.every));
        if (st.status === "error")
            return qsTr("Erreur %1 · nouvel essai %2").arg(ago(st.last)).arg(everyLabel(t.every));
        return qsTr("Pas encore · vérifié %1 · %2").arg(ago(st.last)).arg(everyLabel(t.every)) + (st.summary ? ` — ${st.summary}` : "");
    }

    FileView {
        path: `${Paths.home}/.local/state/caelestia/watches.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.watchState = JSON.parse(text());
            } catch (e) {}
        }
    }

    function patch(id: string, fields: var): void {
        const full = tasks.find(t => t.id === id)?.full;
        if (!full)
            return;
        const task = Object.assign({}, full, fields, {
            updatedAt: new Date().toISOString().replace(/\.\d+Z$/, "Z")
        });
        action("apply", [JSON.stringify([{ type: "upsert", task: task }])]);
    }

    function cyclePriority(id: string): void {
        const t = tasks.find(t => t.id === id);
        if (t)
            patch(id, { priority: priorities[(priorities.indexOf(t.priority) + 1) % priorities.length] });
    }

    function toggle(id: string): void {
        action("toggle", [id]);
    }

    function edit(id: string, text: string): void {
        if (text.trim())
            action("edit", [id, text.trim()]);
    }

    function remove(id: string): void {
        trashed = tasks.find(t => t.id === id)?.full ?? null;
        action("remove", [id]);
    }

    function restore(): void {
        if (!trashed)
            return;
        action("apply", [JSON.stringify([{ type: "upsert", task: trashed }])]);
        trashed = null;
    }

    function clearDone(): void {
        action("clear-done", []);
    }

    FileView {
        id: storage

        path: `${Paths.home}/.local/share/auratask/tasks.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.tasks = (Array.isArray(data.tasks) ? data.tasks : []).map(t => ({
                    id: t.id,
                    text: t.title,
                    done: !!t.completed,
                    created: Date.parse(t.createdAt) || 0,
                    doneAt: Date.parse(t.completedAt) || 0,
                    priority: t.priority ?? "medium",
                    due: Date.parse(t.dueDate) || 0,
                    category: t.category ?? "",
                    subDone: (t.subtasks ?? []).filter(st => st.completed).length,
                    subTotal: (t.subtasks ?? []).length,
                    watch: (t.tags ?? []).includes("surveillance"),
                    every: Number(((t.tags ?? []).find(g => g.startsWith("chaque:")) ?? "chaque:60").slice(7)) || 60,
                    found: (t.tags ?? []).includes("trouvé"),
                    full: t
                }));
                root.loaded = true;
            } catch (e) {
                console.warn("AuraTask tasks could not be read", e);
            }
        }
    }

    Timer {
        id: firstLoad

        interval: 500
        repeat: true
        running: !root.loaded
        onTriggered: storage.reload()
    }

    // Changement de jour : « aujourd'hui » et « en retard » se recalculent
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            root.dayEnd = root.endOfDay(0);
            root.minuteTick = Date.now();
        }
    }

    Component.onCompleted: action("read", [])
}

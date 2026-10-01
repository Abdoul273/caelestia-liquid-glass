pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Agents IA en cours (Claude Code, Codex) pour la Dynamic Island.
// Sonde : ~/.local/bin/caelestia-agents watch (une ligne JSON à chaque changement).
// Permissions : le hook PermissionRequest de Claude Code (caelestia-agents hook) attend
// la réponse de l'île ; answer() la lui transmet.
Singleton {
    id: root

    property list<var> list: []
    property list<var> perms: []
    readonly property var perm: perms[0] ?? null
    readonly property int working: list.filter(a => a.status === "working").length
    readonly property bool busy: working > 0
    readonly property var lead: list.find(a => a.status === "working") ?? null
    property real now: Date.now()

    // Page de l'île : le travail en cours d'abord ; un agent qui a fini reste 10 min
    // (ou jusqu'à « Nettoyer » / ×), puis s'efface. Il revient dès qu'il se remet au travail.
    property var dismissed: ({}) // pid → `since` au moment du nettoyage
    readonly property list<var> shown: list.filter(a => a.status !== "idle" || (dismissed[a.id] !== a.since && now - a.since < 600000))
    readonly property int doneShown: shown.filter(a => a.status === "idle").length

    function dismiss(agent: var): void {
        const d = Object.assign({}, dismissed);
        d[agent.id] = agent.since;
        dismissed = d;
    }

    function clean(): void {
        const d = Object.assign({}, dismissed);
        for (const a of shown)
            if (a.status === "idle")
                d[a.id] = a.since;
        dismissed = d;
    }

    // Un agent qui travaillait vient de finir (pas une demande de permission)
    signal finished(var agent)

    property var prevStatus: ({})

    function answer(id: string, decision: string): void {
        perms = perms.filter(p => p.id !== id);
        Quickshell.execDetached(["caelestia-agents", "answer", id, decision]);
    }

    function focus(agent: var): void {
        if (!agent?.window)
            return;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${agent.window}" })` : `focuswindow address:0x${agent.window}`);
    }

    function focusPid(pid: int): void {
        root.focus(list.find(a => a.id === pid));
    }

    function elapsed(ms: real): string {
        const s = Math.max(0, Math.floor((now - ms) / 1000));
        if (s < 60)
            return `${s} s`;
        const m = Math.floor(s / 60);
        if (m < 60)
            return `${m} min`;
        return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")}`;
    }

    function kindName(kind: string): string {
        return kind === "codex" ? "Codex" : "Claude";
    }

    function kindColour(kind: string): color {
        return kind === "codex" ? "#64d2ff" : "#d97757";
    }

    Process {
        id: proc

        running: Island.agents
        command: ["caelestia-agents", "watch"]
        stdout: SplitParser {
            onRead: data => {
                let d;
                try {
                    d = JSON.parse(data);
                } catch (e) {
                    return;
                }
                const prev = root.prevStatus;
                const next = {};
                const waiting = new Set((d.perms ?? []).map(p => p.agentPid));
                for (const a of d.agents ?? []) {
                    next[a.id] = a.status;
                    if (prev[a.id] === "working" && a.status === "idle" && !waiting.has(a.id))
                        root.finished(a);
                }
                root.prevStatus = next;
                root.list = d.agents ?? [];
                root.perms = d.perms ?? [];
            }
        }
        onExited: {
            root.list = [];
            root.perms = [];
            if (Island.agents)
                restart.restart();
        }
    }

    Timer {
        id: restart

        interval: 3000
        onTriggered: proc.running = Qt.binding(() => Island.agents)
    }

    Timer {
        running: root.list.length > 0
        repeat: true
        interval: 1000
        onTriggered: root.now = Date.now()
    }
}

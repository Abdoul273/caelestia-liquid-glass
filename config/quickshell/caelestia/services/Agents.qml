pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Agent OS pour la Dynamic Island (Claude Code, Codex, Copilot, OpenCode, Antigravity App & CLI, Gemini, Aider).
// Sonde : ~/.local/bin/caelestia-agents watch (une ligne JSON à chaque changement).
// Permissions : le hook PermissionRequest de Claude Code (caelestia-agents hook) attend
// la réponse de l'île ; answer() la lui transmet.
Singleton {
    id: root

    property list<var> list: []
    property list<var> perms: []
    readonly property var perm: perms[0] ?? null

    readonly property int working: list.filter(a => a.status === "working").length
    readonly property int waiting: list.filter(a => a.status === "waiting").length
    readonly property int activeCount: working + waiting
    readonly property bool busy: activeCount > 0
    readonly property var lead: list.find(a => a.status === "waiting") ?? list.find(a => a.status === "working") ?? null
    property real now: Date.now()

    // Filtre & inspecteur de l'onglet Agent OS
    property string filter: "all" // "all" | "active" | kind
    property string expandedId: ""
    property bool launcherOpen: false

    // Page de l'île : actifs + processus CLI vivants + sessions DB finies depuis < 30 min (non masquées)
    property var dismissed: ({}) // id → `since` au moment du nettoyage
    readonly property list<var> shown: list.filter(a => {
        if (a.status !== "idle")
            return true;
        if (dismissed[a.id] === a.since)
            return false;
        return a.alive || (now - a.since < 1800000);
    })
    readonly property list<var> filteredShown: {
        if (filter === "all")
            return shown;
        if (filter === "active")
            return shown.filter(a => a.status !== "idle");
        return shown.filter(a => a.kind === filter);
    }
    readonly property int doneShown: shown.filter(a => a.status === "idle").length

    // Moteurs présents dans la liste affichée (pour la barre de filtres Agent OS)
    readonly property var presentKinds: {
        const seen = {};
        const order = [];
        for (const a of shown) {
            if (!seen[a.kind]) {
                seen[a.kind] = { kind: a.kind, total: 0, active: 0 };
                order.push(seen[a.kind]);
            }
            seen[a.kind].total += 1;
            if (a.status !== "idle")
                seen[a.kind].active += 1;
        }
        return order;
    }

    readonly property int totalSubagents: shown.reduce((acc, a) => acc + (a.subagents ?? 0), 0)
    readonly property int totalFiles: shown.reduce((acc, a) => acc + (a.files ?? 0), 0)
    readonly property int totalTokens: shown.reduce((acc, a) => acc + (a.tokens ?? 0), 0)

    readonly property var launchKinds: ["antigravity", "agy", "claude", "codex", "copilot", "opencode"]

    function setFilter(f: string): void {
        filter = (filter === f && f !== "all") ? "all" : f;
    }

    function toggleExpand(agent: var): void {
        if (!agent?.id)
            return;
        expandedId = expandedId === agent.id ? "" : agent.id;
    }

    function dismiss(agent: var): void {
        const d = Object.assign({}, dismissed);
        d[agent.id] = agent.since;
        dismissed = d;
        if (expandedId === agent.id)
            expandedId = "";
    }

    function clean(): void {
        const d = Object.assign({}, dismissed);
        for (const a of shown)
            if (a.status === "idle")
                d[a.id] = a.since;
        dismissed = d;
        if (expandedId && !shown.some(a => a.id === expandedId && a.status !== "idle"))
            expandedId = "";
    }

    // Un agent qui travaillait vient de finir (pas une demande de permission)
    signal finished(var agent)

    property var prevStatus: ({})

    function answer(id: string, decision: string): void {
        perms = perms.filter(p => p.id !== id);
        Quickshell.execDetached(["caelestia-agents", "answer", id, decision]);
    }

    function stop(agent: var): void {
        if (!agent?.canStop || !agent?.pid)
            return;
        Quickshell.execDetached(["caelestia-agents", "stop", String(agent.pid)]);
    }

    function launch(kind: string): void {
        if (!kind)
            return;
        launcherOpen = false;
        Quickshell.execDetached(["caelestia-agents", "launch", kind]);
    }

    function focus(agent: var): void {
        if (!agent)
            return;
        if (agent.window) {
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${agent.window}" })` : `focuswindow address:0x${agent.window}`);
            return;
        }
        if (agent.kind === "antigravity") {
            Hypr.dispatch(Hypr.usingLua ? 'hl.dsp.focus({ window = "class:^(?i)antigravity$" })' : "focuswindow class:^(?i)antigravity$");
        }
    }

    function focusPid(pid: var): void {
        if (!pid)
            return;
        const found = list.find(a => a.pid === pid || a.id === String(pid) || a.id === `pid:${pid}`);
        root.focus(found);
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

    function fmtTokens(n: int): string {
        if (n <= 0)
            return "";
        if (n >= 1000000)
            return `${(n / 1000000).toFixed(1).replace(".", ",")} M`;
        if (n >= 1000)
            return `${Math.round(n / 1000)} k`;
        return String(n);
    }

    function kindName(kind: string): string {
        switch (kind) {
        case "claude": return "Claude";
        case "codex": return "Codex";
        case "copilot": return "Copilot";
        case "opencode": return "OpenCode";
        case "antigravity": return "Antigravity";
        case "agy": return "AGY CLI";
        case "gemini": return "Gemini";
        case "aider": return "Aider";
        default: return kind ? kind.charAt(0).toUpperCase() + kind.slice(1) : "Agent";
        }
    }

    function kindShort(kind: string): string {
        switch (kind) {
        case "claude": return "CLAUDE";
        case "codex": return "CODEX";
        case "copilot": return "COPILOT";
        case "opencode": return "OPENCODE";
        case "antigravity": return "AGY APP";
        case "agy": return "AGY CLI";
        case "gemini": return "GEMINI";
        case "aider": return "AIDER";
        default: return (kind || "AI").toUpperCase();
        }
    }

    function kindLetter(kind: string): string {
        switch (kind) {
        case "claude": return "C";
        case "codex": return "X";
        case "copilot": return "P";
        case "opencode": return "O";
        case "antigravity": return "✦";
        case "agy": return "A";
        case "gemini": return "G";
        case "aider": return "Ai";
        default: return "✦";
        }
    }

    function kindColour(kind: string): color {
        switch (kind) {
        case "claude": return "#d97757";
        case "codex": return "#38bdf8";
        case "copilot": return "#a78bfa";
        case "opencode": return "#34d399";
        case "antigravity": return "#60a5fa";
        case "agy": return "#818cf8";
        case "gemini": return "#22d3ee";
        case "aider": return "#fbbf24";
        default: return "#60a5fa";
        }
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
                const waitingPids = new Set((d.perms ?? []).map(p => p.agentPid));
                for (const a of d.agents ?? []) {
                    next[a.id] = a.status;
                    if (prev[a.id] === "working" && a.status === "idle" && !waitingPids.has(a.pid))
                        root.finished(a);
                }
                root.prevStatus = next;
                root.list = d.agents ?? [];
                root.perms = d.perms ?? [];
                // Si le filtre courant n'a plus d'agent, revenir à "all"
                if (root.filter !== "all" && root.filter !== "active" && !root.shown.some(a => a.kind === root.filter))
                    root.filter = "all";
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

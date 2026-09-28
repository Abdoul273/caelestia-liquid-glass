pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Mode Concentration, relié à tout le shell :
//   notifications coupées, Dock masqué, messageries en sourdine, Pomodoro dans l'île,
//   éclairage de nuit (Sommeil). Durée au choix ; tout revient comme avant à la fin.
Singleton {
    id: root

    // Modes proposés (réglages par défaut, modifiables avant d'activer)
    readonly property var modes: ({
            dnd: { name: qsTr("Ne pas déranger"), icon: "do_not_disturb_on", tint: "#bf5af2", hideDock: false, muteApps: false, pomodoro: false, night: false },
            work: { name: qsTr("Travail"), icon: "work", tint: "#0a84ff", hideDock: true, muteApps: true, pomodoro: true, night: false },
            sleep: { name: qsTr("Sommeil"), icon: "bedtime", tint: "#5e5ce6", hideDock: true, muteApps: true, pomodoro: false, night: true }
        })
    readonly property list<string> order: ["dnd", "work", "sleep"]
    // Apps mises en sourdine (flux audio) pendant la concentration
    readonly property var mutedAppsPattern: /telegram|discord|vesktop|whatsapp|signal|slack|teams|element|messenger|thunderbird/i

    property string mode: "" // "" = inactif
    property real until: 0 // 0 = jusqu'à ce qu'on l'arrête
    property string lastMode: "dnd"
    property int lastMinutes: 60
    // Options de l'activation en cours (copiées du mode, ajustables)
    property bool hideDock
    property bool muteApps
    property bool pomodoro
    property bool night

    readonly property bool active: mode !== ""
    readonly property var info: modes[mode] ?? modes[lastMode] ?? modes.dnd

    // Pour tout remettre comme avant
    property bool dndBefore
    property bool nightBefore
    property list<var> mutedByUs: []
    property bool loaded

    signal startPomodoro
    signal stopPomodoro

    readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/caelestia/focus.json`

    function untilText(): string {
        if (!active)
            return "";
        if (until <= 0)
            return qsTr("jusqu'à l'arrêt");
        return qsTr("jusqu'à %1").arg(Qt.formatTime(new Date(until), "HH:mm"));
    }

    // minutes : 0 = sans limite, -1 = jusqu'à la fin de la journée
    function start(m: string, minutes: int, opts: var): void {
        if (active)
            stop(true);
        const def = modes[m] ?? modes.dnd;
        const o = opts ?? {};
        hideDock = o.hideDock ?? def.hideDock;
        muteApps = o.muteApps ?? def.muteApps;
        pomodoro = o.pomodoro ?? def.pomodoro;
        night = o.night ?? def.night;
        const now = new Date();
        until = minutes > 0 ? Date.now() + minutes * 60000 : minutes < 0 ? new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59).getTime() : 0;
        lastMode = m;
        lastMinutes = minutes;
        dndBefore = Notifs.dnd;
        nightBefore = NightLight.enabled;
        mode = m;
        Notifs.dnd = true;
        if (night && !NightLight.enabled)
            NightLight.toggle();
        if (muteApps)
            muteStreams();
        if (pomodoro)
            startPomodoro();
        save();
    }

    function stop(silent: bool): void {
        if (!active)
            return;
        const hadPomodoro = pomodoro;
        mode = "";
        until = 0;
        Notifs.dnd = dndBefore;
        if (night && !nightBefore && NightLight.enabled)
            NightLight.toggle();
        for (const n of mutedByUs)
            if (n?.audio)
                n.audio.muted = false;
        mutedByUs = [];
        if (hadPomodoro)
            stopPomodoro();
        save();
    }

    // Réglage modifié pendant la concentration : appliqué tout de suite
    function setOption(key: string, value: bool): void {
        if (key === "hideDock") {
            hideDock = value;
        } else if (key === "muteApps") {
            muteApps = value;
            if (active && value)
                muteStreams();
            else if (active) {
                for (const n of mutedByUs)
                    if (n?.audio)
                        n.audio.muted = false;
                mutedByUs = [];
            }
        } else if (key === "pomodoro") {
            pomodoro = value;
            if (active)
                value ? startPomodoro() : stopPomodoro();
        } else if (key === "night") {
            night = value;
            if (active && value !== NightLight.enabled)
                NightLight.toggle();
        }
        save();
    }

    function toggle(): void {
        if (active)
            stop(false);
        else
            start(lastMode, lastMinutes, null);
    }

    function isMessaging(n: var): bool {
        const p = n?.properties ?? {};
        return mutedAppsPattern.test(`${p["application.name"] ?? ""} ${p["application.process.binary"] ?? ""}`);
    }

    function muteStreams(): void {
        const list = [...mutedByUs];
        for (const n of Pipewire.nodes.values) {
            // Seulement le son qui sort (pas le micro d'un appel)
            if (!n?.isStream || !n.audio || n.audio.muted || n.properties?.["media.class"] !== "Stream/Output/Audio" || !isMessaging(n))
                continue;
            n.audio.muted = true;
            list.push(n);
        }
        mutedByUs = list;
    }

    PwObjectTracker {
        objects: root.active && root.muteApps ? Pipewire.nodes.values.filter(n => n?.isStream && root.isMessaging(n)) : []
    }

    // Une messagerie qui ouvre un nouveau son pendant la concentration est coupée aussi
    Connections {
        target: Pipewire.nodes

        function onValuesChanged(): void {
            if (root.active && root.muteApps)
                muteDelay.restart();
        }
    }
    Timer {
        id: muteDelay

        interval: 400
        onTriggered: root.muteStreams()
    }

    // Fin automatique
    Timer {
        running: root.active && root.until > 0
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (Date.now() >= root.until)
                root.stop(false);
        }
    }

    function save(): void {
        if (!loaded)
            return;
        stateView.setText(JSON.stringify({
            mode: mode,
            until: until,
            lastMode: lastMode,
            lastMinutes: lastMinutes,
            hideDock: hideDock,
            muteApps: muteApps,
            pomodoro: pomodoro,
            night: night,
            dndBefore: dndBefore,
            nightBefore: nightBefore
        }));
    }

    FileView {
        id: stateView

        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.lastMode = d.lastMode ?? "dnd";
                root.lastMinutes = d.lastMinutes ?? 60;
                // Reprise après un redémarrage du shell (sans relancer le Pomodoro)
                if (d.mode && (!(d.until > 0) || d.until > Date.now())) {
                    root.hideDock = !!d.hideDock;
                    root.muteApps = !!d.muteApps;
                    root.pomodoro = !!d.pomodoro;
                    root.night = !!d.night;
                    root.dndBefore = !!d.dndBefore;
                    root.nightBefore = !!d.nightBefore;
                    root.until = d.until ?? 0;
                    root.mode = d.mode;
                    Notifs.dnd = true;
                    if (root.muteApps)
                        muteDelay.restart();
                } else if (d.mode) {
                    Notifs.dnd = !!d.dndBefore; // fini pendant que le shell était arrêté
                }
            } catch (e) {}
            root.loaded = true;
            root.save();
        }
        onLoadFailed: root.loaded = true
    }

    IpcHandler {
        target: "focus"

        function toggle(): void {
            root.toggle();
        }
        function start(mode: string, minutes: int): void {
            root.start(mode || "dnd", minutes, null);
        }
        function stop(): void {
            root.stop(false);
        }
        function status(): string {
            return root.active ? `${root.mode} ${root.untilText()}` : "off";
        }
    }
}

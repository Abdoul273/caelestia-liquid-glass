pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Shapes
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import Caelestia.Internal
import Caelestia.Services
import qs.components
import qs.services

// Dynamic Island façon macOS, dessinée dans le même verre que le cadre (PanelBg dans
// ContentWindow) : elle sort du haut de l'écran et se fond dans la forme fluide.
// Musique, lecteur complet au survol, volume/luminosité, notifications, charge,
// enregistrement. Molette = volume, clic = lecture/pause.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property bool fullscreen

    // ── Sources ──
    readonly property MprisPlayer player: Players.active
    readonly property bool playing: player?.isPlaying ?? false
    readonly property bool hasMedia: !!player && (player.trackTitle ?? "").length > 0
    readonly property var brightMon: Brightness.getMonitorForScreen(screen)
    readonly property real brightness: brightMon?.brightness ?? 0
    // Batterie lue directement dans le noyau (charge_now / charge_full), plus précise et réactive qu'UPower
    property real sysBattery: -1
    property string sysBattStatus
    readonly property real battery: sysBattery >= 0 ? sysBattery : (UPower.displayDevice.percentage ?? 0)
    readonly property bool charging: !UPower.onBattery
    // Batterie au repos : icône toujours (sur portable), pourcentage seulement faible ou en charge
    readonly property bool showBattery: Island.battery && UPower.displayDevice.isLaptopBattery
    readonly property bool battCharging: sysBattStatus ? sysBattStatus === "Charging" : UPower.displayDevice.state === UPowerDeviceState.Charging

    // Lecture de la batterie toutes les 5 s (et tout de suite au branchement / débranchement).
    // Arrondie au pour cent : sinon chaque micro-variation relançait l'animation de l'icône
    // et faisait redessiner tout l'écran (flou compris) en continu → batterie vidée plus vite.
    Timer {
        id: battTimer

        running: UPower.displayDevice.isLaptopBattery
        repeat: true
        triggeredOnStart: true
        interval: 5000
        onTriggered: {
            if (!battProc.running)
                battProc.running = true;
        }
    }
    Connections {
        target: UPower

        function onOnBatteryChanged(): void {
            battTimer.restart();
            if (!battProc.running)
                battProc.running = true;
        }
    }

    Process {
        id: battProc

        command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do cat $b/status; if [ -e $b/charge_now ]; then cat $b/charge_now $b/charge_full; else cat $b/energy_now $b/energy_full; fi; break; done 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                const now = parseFloat(l[1]), full = parseFloat(l[2]);
                if (l.length >= 3 && full > 0) {
                    root.sysBattStatus = l[0].trim();
                    root.sysBattery = Math.round(Math.max(0, Math.min(1, now / full)) * 100) / 100;
                }
            }
        }
    }
    readonly property bool batteryPctShown: battCharging && battery < 0.995 || battery < 0.2

    // ── Couleurs du thème (le verre suit le thème clair/sombre) ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.62)
    readonly property color fgFaint: Qt.alpha(fg, 0.16)
    readonly property color accent: Colours.palette.m3primary
    readonly property color green: Colours.light ? "#1f9d3a" : "#32d74b"
    readonly property color red: Colours.light ? "#d70015" : "#ff453a"

    // ── État ──
    property string pulse: "" // level, notif, toast, shot, bt, charge, ws, caps, net, done
    property var notif: null
    property var toastData: null
    property list<var> queue: []
    property bool ready
    property bool hovered
    property bool expanded
    property bool levelHeld // doigt/souris sur la jauge : l'île reste ouverte
    // Dernières valeurs affichées (pas de liaison : elles ne doivent pas se mettre à jour toutes seules)
    property int lastVol: -1
    property bool lastMuted
    property int lastSink: -1
    property string levelKind: "volume"
    property string levelIcon: "volume_up"
    // Valeur en direct selon le type : chaque jauge garde la sienne, pas de glissement de l'une à l'autre
    readonly property real levelValue: levelKind === "volume" ? Audio.volume : brightness

    // Appareil Bluetooth qui vient de se connecter / déconnecter
    property BluetoothDevice btDevice: null
    property bool btOn
    readonly property bool btBattery: btDevice?.batteryAvailable ?? false
    readonly property real btLevel: btDevice?.battery ?? 0
    readonly property string btIcon: {
        const d = btDevice;
        if (!d)
            return "bluetooth";
        const icon = d.icon ?? "";
        const name = d.name ?? "";
        if (/pod|bud|tws|\bbx|cetw/i.test(name))
            return "earbuds";
        if (icon.includes("headset") || icon.includes("headphone") || icon.includes("audio"))
            return "headphones";
        if (icon.includes("keyboard"))
            return "keyboard";
        if (icon.includes("mouse"))
            return "mouse";
        if (icon.includes("phone"))
            return "smartphone";
        if (icon.includes("gaming") || icon.includes("joystick"))
            return "stadia_controller";
        return "bluetooth";
    }

    // Chargeur : état au moment de l'évènement + animation (remplissage, éclair, reflet)
    property bool chargePlugged
    property real chargeFill: 1
    property real chargeBolt: 1
    property real chargeShine: 0

    Timer {
        id: chargeSwap

        interval: 260
        onTriggered: {
            root.chargePlugged = root.charging;
            root.flash("charge", root.charging ? 3600 : 2600);
            chargeIntro.restart();
        }
    }

    SequentialAnimation {
        id: chargeIntro

        ScriptAction {
            script: {
                root.chargeFill = root.chargePlugged ? 0 : 1;
                root.chargeBolt = 0;
                root.chargeShine = 0;
            }
        }
        PauseAnimation {
            duration: 150
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "chargeBolt"
                to: 1
                duration: 560
                easing.type: Easing.OutBack
                easing.overshoot: 3
            }
            NumberAnimation {
                target: root
                property: "chargeFill"
                to: 1
                duration: 1100
                easing.type: Easing.OutCubic
            }
        }
        NumberAnimation {
            target: root
            property: "chargeShine"
            from: 0
            to: 1
            duration: 900
            easing.type: Easing.InOutQuad
        }
    }

    // Capture d'écran : fichier d'origine (pas la miniature en cache des notifications)
    property string shotPath: ""
    property bool shotSaved
    property real shotIn: 1

    readonly property string shotsDir: `${Quickshell.env("HOME")}/Images/Captures`

    function isShot(n: var): bool {
        return (n?.appName ?? "").startsWith("caelestia") && (n?.summary ?? "").startsWith("Capture d'écran");
    }

    function shotSource(n: var): string {
        const hints = n?.notification?.hints ?? n?.hints ?? {};
        let src = hints["image-path"] || n?.notification?.image || n?.notification?.appIcon || n?.image || n?.appIcon || "";
        return String(src).replace(/^file:\/\//, "");
    }

    function closeShot(): void {
        pulseTimer.stop();
        pulse = "";
        showNext();
    }

    SequentialAnimation {
        id: shotIntro

        ScriptAction {
            script: root.shotIn = 0
        }
        NumberAnimation {
            target: root
            property: "shotIn"
            to: 1
            duration: 700
            easing.type: Easing.OutBack
            easing.overshoot: 1.3
        }
    }

    // ── Bureaux ──
    readonly property HyprlandMonitor hyprMon: Hyprland.monitorFor(screen)
    readonly property int wsId: hyprMon?.activeWorkspace?.id ?? 1
    readonly property int wsLast: {
        let max = wsId;
        // Bureaux dynamiques : jusqu'au dernier bureau occupé (fenêtres réelles),
        // les bureaux vides déjà quittés ne comptent plus
        for (const t of Hypr.toplevels.values) {
            const id = t.workspace?.id ?? 0;
            if (id > max && t.workspace?.monitor?.name === hyprMon?.name)
                max = id;
        }
        return Math.max(max, 3);
    }

    onWsIdChanged: {
        if (Island.workspaces && wsId > 0 && pulse !== "notif" && pulse !== "toast" && pulse !== "shot")
            flash("ws", 1100);
    }

    // ── Micro et caméra utilisés (points orange / vert façon macOS) ──
    readonly property list<PwNode> recStreams: Pipewire.nodes.values.filter(n => {
        if (!n?.isStream)
            return false;
        const p = n.properties ?? {};
        if (p["media.class"] !== "Stream/Input/Audio" || p["stream.capture.sink"] === "true" || p["stream.monitor"] === "true")
            return false;
        const app = `${p["application.name"] ?? ""} ${p["node.name"] ?? ""} ${p["application.process.binary"] ?? ""}`.toLowerCase();
        return !/cava|quickshell|caelestia|bluez_capture_internal|pavucontrol|peak detect/.test(app);
    })
    readonly property bool micInUse: Island.privacy && recStreams.length > 0
    property bool camInUse

    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(n => n?.isStream)
    }

    Process {
        id: camProc

        command: ["sh", "-c", "for d in /dev/video*; do [ -e \"$d\" ] && fuser -s \"$d\" 2>/dev/null && exit 0; done; exit 1"]
        onExited: code => root.camInUse = Island.privacy && code === 0
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: camProc.running = true
    }

    // ── Appels et visio : micro pris par une app d'appel (ou micro + caméra ensemble) ──
    readonly property var callStream: recStreams.find(n => {
        const p = n.properties ?? {};
        const app = `${p["application.name"] ?? ""} ${p["application.process.binary"] ?? ""}`.toLowerCase();
        return !/gpu-screen-recorder|wf-recorder|obs|arecord|pw-record|parecord|easyeffects|audacity/.test(app);
    }) ?? null
    readonly property string callAppNow: callStream?.properties?.["application.name"] ?? ""
    // Retenu pendant tout l'appel (le flux peut disparaître un instant, ou à la fin)
    property string callAppName
    onCallAppNowChanged: if (callAppNow) callAppName = callAppNow
    property string callTitleKept
    readonly property string callBinary: (callStream?.properties?.["application.process.binary"] ?? "").toLowerCase()
    readonly property bool callAppKnown: /discord|vesktop|telegram|zoom|teams|slack|skype|signal|whatsapp|jitsi|webex|element|chrom|firefox|brave|edge|vivaldi|opera|zen/.test(`${callAppName} ${callBinary}`.toLowerCase())
    readonly property bool callWanted: Island.privacy && callStream !== null && (camInUse || callAppKnown)
    property bool inCall
    property real callStart: 0
    property real callElapsed: 0
    readonly property bool callMuted: Audio.sourceMuted || !!callStream?.audio?.muted

    // Fenêtre de l'appel : même processus, sinon même app (titre qui ressemble à un appel en priorité)
    readonly property var callWindow: {
        if (!inCall)
            return null;
        const pid = parseInt(callStream?.properties?.["application.process.id"] ?? "0");
        const wins = Hyprland.toplevels.values;
        const byPid = wins.find(t => pid > 0 && t.lastIpcObject?.pid === pid);
        if (byPid)
            return byPid;
        const key = (callBinary || callAppName.split(" ")[0] || "").toLowerCase().replace(/[-_].*$/, "");
        if (!key)
            return null;
        const same = wins.filter(t => `${t.lastIpcObject?.class ?? ""} ${t.lastIpcObject?.initialClass ?? ""}`.toLowerCase().includes(key));
        return same.find(t => /meet|zoom|teams|discord|appel|call|jitsi|whereby|webex|visio|réunion|meeting/i.test(t.title ?? "")) ?? same[0] ?? null;
    }
    readonly property string callTitle: {
        const t = (callWindow?.title ?? "").replace(/\s*[-–—|]\s*(Google Chrome|Chromium|Mozilla Firefox|Brave|Microsoft Edge|Vivaldi)$/i, "").trim();
        return t || callTitleKept || callAppName || qsTr("Appel en cours");
    }
    onCallWindowChanged: if (callWindow?.title) callTitleKept = callTitle

    Timer {
        interval: 2000
        running: root.callWanted && !root.inCall
        onTriggered: {
            root.callStart = Date.now();
            root.callElapsed = 0;
            root.callTitleKept = "";
            root.inCall = true;
        }
    }
    Timer {
        interval: 4000
        running: !root.callWanted && root.inCall
        onTriggered: root.inCall = false
    }
    Timer {
        interval: 1000
        running: root.inCall
        repeat: true
        onTriggered: root.callElapsed = (Date.now() - root.callStart) / 1000
    }

    // Coupe le micro pour l'appel seulement (son flux) ; si le micro entier était coupé, le rallume
    function toggleCallMic(): void {
        if (callMuted) {
            if (callStream?.audio)
                callStream.audio.muted = false;
            if (Audio.sourceMuted && Audio.source?.audio)
                Audio.source.audio.muted = false;
        } else if (callStream?.audio) {
            callStream.audio.muted = true;
        } else if (Audio.source?.audio) {
            Audio.source.audio.muted = true;
        }
    }

    function focusCall(): void {
        const t = callWindow;
        if (t)
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${t.address}" })` : `focuswindow address:0x${t.address}`);
    }

    function fmtLong(s: real): string {
        const h = Math.floor(s / 3600);
        return h > 0 ? `${h}:${Math.floor(s % 3600 / 60).toString().padStart(2, "0")}:${Math.floor(s % 60).toString().padStart(2, "0")}` : fmtTime(s);
    }

    TextMetrics {
        id: transferNameMetrics

        text: root.transfer?.name ?? ""
        font.pointSize: 9.5
        font.weight: Font.Medium
    }

    TextMetrics {
        id: callTitleMetrics

        text: root.callTitle
        font.pointSize: 9.5
        font.weight: Font.Medium
    }

    // ── Page Infos : pastilles d'état (seulement ce qui est actif, rien de la page Performances) ──
    function nextAlarm(): var {
        const now = new Date();
        let best = null;
        for (const a of alarms) {
            if (!a.enabled || !a.time)
                continue;
            const [h, m] = a.time.split(":").map(Number);
            const days = a.days ?? [];
            for (let off = 0; off < 8; off++) {
                const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + off, h, m);
                if (d <= now || (days.length > 0 && !days.includes(d.getDay())))
                    continue;
                if (!best || d < best.at)
                    best = { at: d, label: a.label || qsTr("Alarme") };
                break;
            }
        }
        return best;
    }

    function dayWord(d: var): string {
        const today = new Date();
        const t0 = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        const diff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() - t0) / 86400000);
        return diff === 0 ? "" : diff === 1 ? qsTr("demain ") : Qt.locale("fr_FR").toString(d, "ddd ");
    }

    readonly property list<var> infoChips: {
        void (now);
        void (Time.date);
        const out = [];
        const al = nextAlarm();
        if (al)
            out.push({ icon: "alarm", text: `${al.label} · ${dayWord(al.at)}${Qt.formatTime(al.at, "HH:mm")}`, tint: "#ff9f0a" });
        for (const d of btConnected)
            out.push({ icon: /audio|head|ear|phone/i.test(d?.icon ?? "") ? "headphones" : "bluetooth", text: (d.name || qsTr("Bluetooth")) + (d.batteryAvailable ? ` · ${Math.round(d.battery * 100)} %` : ""), tint: root.green });
        if (IdleInhibitor.enabled)
            out.push({ icon: "coffee", text: IdleInhibitor.until > 0 ? qsTr("Écran allumé · %1").arg(IdleInhibitor.remainingText()) : qsTr("Écran toujours allumé"), tint: root.accent });
        if (NightLight.enabled)
            out.push({ icon: "nightlight", text: qsTr("Nuit · %1 K").arg(NightLight.temperature), tint: "#ff9f0a" });
        if (FocusMode.active)
            out.push({ icon: FocusMode.info.icon, text: `${FocusMode.info.name} · ${FocusMode.untilText()}`, tint: FocusMode.info.tint });
        else if (Notifs.dnd)
            out.push({ icon: "do_not_disturb_on", text: qsTr("Ne pas déranger"), tint: "#bf5af2" });
        const late = Tasks.overdueCount;
        if (late > 0)
            out.push({ icon: "assignment_late", text: late > 1 ? qsTr("%1 tâches en retard").arg(late) : qsTr("1 tâche en retard"), tint: root.red });
        const next = Tasks.sorted.find(t => !t.done && t.due > Date.now() && Tasks.isToday(t));
        if (next)
            out.push({ icon: "task_alt", text: `${next.text} · ${Qt.formatTime(new Date(next.due), "HH:mm")}`, tint: "#0a84ff" });
        else if (Tasks.todayCount > 0)
            out.push({ icon: "task_alt", text: Tasks.todayCount > 1 ? qsTr("%1 tâches aujourd'hui").arg(Tasks.todayCount) : qsTr("1 tâche aujourd'hui"), tint: "#0a84ff" });
        const unread = Notifs.notClosed.length;
        if (unread > 0)
            out.push({ icon: "notifications", text: unread > 1 ? qsTr("%1 notifications").arg(unread) : qsTr("1 notification"), tint: root.fg });
        if (Audio.sourceMuted)
            out.push({ icon: "mic_off", text: qsTr("Micro coupé"), tint: root.red });
        if (Audio.muted)
            out.push({ icon: "volume_off", text: qsTr("Son coupé"), tint: root.red });
        if (VPN.connected)
            out.push({ icon: "vpn_key", text: qsTr("VPN"), tint: root.green });
        return out;
    }

    // ── Bluetooth connecté (icône verte au repos) ──
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d?.connected)
    readonly property bool btAudio: btConnected.some(d => /audio|head|ear|phone/i.test(d?.icon ?? ""))

    // ── Téléchargements et copies de fichiers (script caelestia-transfers) ──
    property list<var> transfers: []
    property var fileDone: null // dernier transfert terminé {kind, name, path}
    // Celui qu'on montre : de taille connue d'abord, puis le plus gros
    readonly property var transfer: transfers.length > 0 ? [...transfers].sort((a, b) => ((b.total > 0) - (a.total > 0)) || (b.total - a.total) || (b.done - a.done))[0] : null
    readonly property real transferProgress: transfer && transfer.total > 0 ? Math.min(1, transfer.done / transfer.total) : -1

    Process {
        id: transfersProc

        running: true
        command: [`${Quickshell.env("HOME")}/.local/bin/caelestia-transfers`]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const m = JSON.parse(line);
                    root.transfers = m.items ?? [];
                    const f = (m.finished ?? [])[0];
                    if (f && root.ready) {
                        root.fileDone = f;
                        root.playShort("transfert", "/usr/share/sounds/freedesktop/stereo/complete.oga");
                        root.flash("fileDone", 6000);
                    }
                } catch (e) {}
            }
        }
        // Relance s'il s'arrête (mise à jour du script, erreur…)
        onRunningChanged: if (!running) transfersRestart.start()
    }
    Timer {
        id: transfersRestart

        interval: 5000
        onTriggered: transfersProc.running = true
    }

    function fmtBytes(b: real): string {
        if (b >= 1073741824)
            return `${(b / 1073741824).toFixed(b >= 10737418240 ? 0 : 1).replace(".", ",")} Go`;
        if (b >= 1048576)
            return `${(b / 1048576).toFixed(b >= 104857600 ? 0 : 1).replace(".", ",")} Mo`;
        return `${Math.max(1, Math.round(b / 1024))} Ko`;
    }

    function transferEta(t: var): string {
        if (!t || t.total <= 0 || t.speed <= 0)
            return "";
        const s = (t.total - t.done) / t.speed;
        return s < 60 ? qsTr("%1 s").arg(Math.ceil(s)) : s < 3600 ? qsTr("%1 min").arg(Math.ceil(s / 60)) : qsTr("%1 h %2").arg(Math.floor(s / 3600)).arg(Math.round(s % 3600 / 60).toString().padStart(2, "0"));
    }

    // ── Rappels AuraTask : 15 min avant l'échéance, à l'échéance, et rappels intelligents ──
    property var taskAlert: null // {id, title, sub, key, late}
    property var remindersSeen: ({})
    property var snoozes: ({}) // id -> heure du rappel reporté

    FileView {
        id: remindersFile

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/task-reminders.json`
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.remindersSeen = d.seen ?? {};
                root.snoozes = d.snoozes ?? {};
            } catch (e) {}
        }
    }

    function saveReminders(): void {
        // On oublie ce qui date de plus de 3 jours
        const now = Date.now(), seen = {};
        for (const k in remindersSeen)
            if (now - remindersSeen[k] < 3 * 86400000)
                seen[k] = remindersSeen[k];
        remindersSeen = seen;
        remindersFile.setText(JSON.stringify({ seen: seen, snoozes: snoozes }));
    }

    function checkReminders(): void {
        if (!Tasks.loaded || taskAlert)
            return;
        const now = Date.now();
        const fresh = 10 * 60000; // un rappel manqué de plus de 10 min n'est plus montré
        for (const t of Tasks.tasks) {
            if (t.done)
                continue;
            const moments = [];
            if (t.due > 0) {
                moments.push({ key: `${t.id}:soon:${t.due}`, at: t.due - 15 * 60000, sub: qsTr("Dans 15 min · à %1").arg(Qt.formatTime(new Date(t.due), "HH:mm")), late: false });
                moments.push({ key: `${t.id}:due:${t.due}`, at: t.due, sub: qsTr("C'est l'heure · %1").arg(Qt.formatTime(new Date(t.due), "HH:mm")), late: true });
            }
            for (const r of t.full?.smartReminders ?? []) {
                const at = Date.parse(r.time) || 0;
                if (at > 0 && !r.triggered)
                    moments.push({ key: `${t.id}:smart:${r.id}`, at: at, sub: r.label || qsTr("Rappel"), late: false });
            }
            if (snoozes[t.id])
                moments.push({ key: `${t.id}:snooze:${snoozes[t.id]}`, at: snoozes[t.id], sub: qsTr("Rappel reporté"), late: true });
            for (const m of moments) {
                if (m.at > now || now - m.at > fresh || remindersSeen[m.key])
                    continue;
                const seen = Object.assign({}, remindersSeen);
                seen[m.key] = now;
                remindersSeen = seen;
                saveReminders();
                taskAlert = {
                    id: t.id,
                    title: t.text,
                    sub: m.sub,
                    priority: t.priority,
                    late: m.late
                };
                root.playShort("rappel", "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga");
                taskAlertTimeout.restart();
                return;
            }
        }
    }

    function taskAlertDone(): void {
        if (taskAlert)
            Tasks.toggle(taskAlert.id);
        taskAlert = null;
    }

    function taskAlertSnooze(min: int): void {
        if (taskAlert) {
            const s = Object.assign({}, snoozes);
            s[taskAlert.id] = Date.now() + min * 60000;
            snoozes = s;
            saveReminders();
        }
        taskAlert = null;
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkReminders()
    }
    // Sans réponse, le rappel se range après 2 min
    Timer {
        id: taskAlertTimeout

        interval: 120000
        onTriggered: root.taskAlert = null
    }

    // ── Compte à rebours avant un enregistrement ──
    property int countLeft: 0
    property list<string> recArgs: []

    Connections {
        target: Island

        function onRecordRequest(args: var, delay: int): void {
            if (root.screen !== Quickshell.screens[0])
                return;
            root.recArgs = args;
            if (delay <= 0) {
                Recorder.start(args);
                return;
            }
            root.countLeft = delay;
            countTimer.restart();
            countPop.restart();
        }
    }

    Timer {
        id: countTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.countLeft -= 1;
            if (root.countLeft <= 0) {
                stop();
                Recorder.start(root.recArgs);
            } else {
                countPop.restart();
            }
        }
    }

    // ── Verr. Maj, Wi-Fi, VPN ──
    property string blipIcon: ""
    property string blipText: ""
    property string blipSub: ""
    property bool blipOn: true

    function blip(icon: string, text: string, sub: string, on: bool): void {
        blipIcon = icon;
        blipText = text;
        blipSub = sub;
        blipOn = on;
        flash("blip", 1800);
    }

    // Hyprland ne signale pas Verr. Maj : on lit le voyant du clavier (/sys/class/leds/*::capslock)
    property bool capsLock
    property string capsLed: ""
    property bool capsKnown

    Process {
        running: true
        command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLed = text.trim() ? `${text.trim()}/brightness` : ""
        }
    }

    FileView {
        id: capsFile

        path: root.capsLed
        printErrors: false
        onLoaded: {
            const on = text().trim() !== "0";
            if (!root.capsKnown) {
                root.capsKnown = true;
                root.capsLock = on;
                return;
            }
            if (on !== root.capsLock)
                root.capsLock = on;
        }
    }

    Timer {
        running: root.capsLed !== ""
        interval: 250
        repeat: true
        onTriggered: capsFile.reload()
    }

    onCapsLockChanged: if (capsKnown && ready) blip(capsLock ? "keyboard_capslock_badge" : "keyboard_capslock", capsLock ? qsTr("Verr. Maj activé") : qsTr("Verr. Maj désactivé"), "", capsLock)

    readonly property string wifiName: Nmcli.active?.ssid ?? ""
    onWifiNameChanged: {
        if (wifiName)
            blip("wifi", wifiName, qsTr("Connecté"), true);
        else
            blip("wifi_off", qsTr("Wi-Fi"), qsTr("Déconnecté"), false);
    }

    readonly property bool vpnOn: VPN.connected
    onVpnOnChanged: blip(vpnOn ? "vpn_lock" : "vpn_key_off", qsTr("VPN"), vpnOn ? qsTr("Connecté") : qsTr("Déconnecté"), vpnOn)

    // ── Minuteur et chronomètre (IPC : qs -c caelestia ipc call island timer 5m) ──
    property string clockKind: "" // "", "timer", "stopwatch"
    property real clockEnd: 0 // minuteur : fin (ms)
    property real clockStart: 0 // chronomètre : départ (ms)
    property real clockPaused: 0 // ms figées pendant une pause (0 = en marche)
    property real clockTotal: 0
    property string clockLabel: ""

    TextMetrics {
        id: clockTitleMetrics

        font.family: Tokens.font.body.medium.family
        font.pointSize: 9
        font.weight: Font.Medium
        text: root.pomoOn ? qsTr("Pomodoro · %1 · session %2").arg(root.clockLabel).arg(root.pomoRound) : root.clockLabel ? qsTr("Minuteur · %1").arg(root.clockLabel) : ""
    }
    property list<real> laps: [] // chronomètre : temps écoulé à chaque tour (s)
    // Pomodoro : enchaîne travail / pause tout seul
    property bool pomoOn
    property real pomoWork: 25 * 60
    property real pomoRest: 5 * 60
    property string pomoPhase: "work"
    property int pomoRound: 1
    property string doneTitle: qsTr("Minuteur terminé")
    property string doneSub: ""
    property real now: Date.now()
    readonly property real clockValue: {
        const t = clockPaused > 0 ? clockPaused : now;
        if (clockKind === "timer")
            return Math.max(0, (clockEnd - t) / 1000);
        if (clockKind === "stopwatch")
            return (t - clockStart) / 1000;
        return 0;
    }

    Timer {
        running: root.clockKind !== ""
        interval: 100
        repeat: true
        onTriggered: {
            root.now = Date.now();
            if (root.clockKind === "timer" && root.clockPaused === 0 && root.now >= root.clockEnd)
                root.timerFinished();
        }
    }

    function parseDuration(txt: string): real {
        const t = String(txt).toLowerCase().replace(",", ".").trim();
        let total = 0;
        const re = /(\d+(?:\.\d+)?)\s*(h|m|min|s|sec)?/g;
        let m;
        while ((m = re.exec(t)) !== null) {
            const v = parseFloat(m[1]);
            const u = m[2] ?? "m";
            total += u === "h" ? v * 3600 : u === "s" || u === "sec" ? v : v * 60;
        }
        return total;
    }

    function startTimer(sec: real, label: string): void {
        if (!(sec > 0))
            return;
        clockKind = "timer";
        clockTotal = sec;
        clockLabel = label ?? "";
        clockPaused = 0;
        laps = [];
        now = Date.now();
        clockEnd = now + sec * 1000;
        saveClock();
    }

    function startStopwatch(): void {
        pomoOn = false;
        clockKind = "stopwatch";
        clockLabel = "";
        clockPaused = 0;
        laps = [];
        now = Date.now();
        clockStart = now;
        saveClock();
    }

    function startPomodoro(work: real, rest: real): void {
        pomoOn = true;
        pomoWork = work > 0 ? work : 25 * 60;
        pomoRest = rest > 0 ? rest : 5 * 60;
        pomoPhase = "work";
        pomoRound = 1;
        startTimer(pomoWork, qsTr("Focus"));
    }

    function addLap(): void {
        if (clockKind !== "stopwatch")
            return;
        laps = [...laps, clockValue];
        saveClock();
    }

    function addMinute(): void {
        if (clockKind !== "timer")
            return;
        clockEnd += 60000;
        clockTotal += 60;
        saveClock();
    }

    function timerFinished(): void {
        const label = clockLabel;
        const total = clockTotal;
        clockKind = "";
        if (pomoOn) {
            // Pomodoro : ça sonne, puis on choisit d'enchaîner (Pause / Reprendre) depuis l'île
            if (pomoPhase === "work")
                ring("pomoWork", qsTr("Focus terminé"), qsTr("Session %1 · place à %2 de pause").arg(pomoRound).arg(fmtHuman(pomoRest)), total);
            else
                ring("pomoRest", qsTr("Pause terminée"), qsTr("Prêt pour la session %1 ?").arg(pomoRound + 1), total);
            saveClock();
            return;
        }
        ring("timer", label || qsTr("Minuteur"), qsTr("Minuteur de %1 terminé").arg(fmtHuman(total)), total);
        saveClock();
    }

    // État publié pour l'app Horloge (~/.local/state/caelestia/island-clock.json)
    function saveClock(): void {
        clockState.setText(JSON.stringify({
            kind: clockKind,
            end: clockEnd,
            start: clockStart,
            paused: clockPaused,
            total: clockTotal,
            label: clockLabel,
            laps: laps,
            pomodoro: {
                on: pomoOn,
                work: pomoWork,
                rest: pomoRest,
                phase: pomoPhase,
                round: pomoRound
            },
            alarm: alarmRinging ? alarmLabel : null,
            ring: alarmRinging ? { kind: ringKind, label: alarmLabel, sub: ringSub, since: ringSince } : null
        }));
    }

    FileView {
        id: clockState

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/island-clock.json`
        printErrors: false
        atomicWrites: true
    }

    // ── Alarmes (écrites par l'app Horloge dans ~/.local/share/caelestia/alarms.json) ──
    property var alarms: []
    property bool alarmRinging
    property string alarmLabel: ""
    property string alarmTime: ""
    property string lastAlarmKey: ""

    FileView {
        id: alarmsFile

        path: `${Quickshell.env("HOME")}/.local/share/caelestia/alarms.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.alarms = JSON.parse(text()) ?? [];
            } catch (e) {
                root.alarms = [];
            }
        }
    }

    Timer {
        running: root.screen === Quickshell.screens[0] && root.alarms.length > 0
        interval: 1000
        repeat: true
        onTriggered: {
            const d = new Date();
            const hm = `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
            const key = `${d.toDateString()} ${hm}`;
            if (key === root.lastAlarmKey)
                return;
            let changed = false;
            for (const a of root.alarms) {
                if (!a.enabled || a.time !== hm)
                    continue;
                const days = a.days ?? [];
                if (days.length > 0 && !days.includes(d.getDay()))
                    continue;
                root.lastAlarmKey = key;
                root.ringAlarm(a.label || qsTr("Alarme"), hm);
                // Alarme ponctuelle : elle se désactive après avoir sonné
                if (days.length === 0) {
                    a.enabled = false;
                    changed = true;
                }
                break;
            }
            if (changed)
                alarmsFile.setText(JSON.stringify(root.alarms, null, 2));
        }
    }

    // ── Sonnerie commune : alarmes, fin de minuteur, fin de phase pomodoro ──
    // Elle continue tant qu'on ne l'arrête pas depuis l'île (ou l'app Horloge / IPC).
    property string ringKind: "" // alarm, timer, pomoWork, pomoRest
    property string ringSub: ""
    property real ringTotal: 0
    property real ringSince: 0
    property real ringElapsed: 0
    property int ringLoops: 0
    property list<var> ringPaused: [] // lecteurs mis en pause pendant la sonnerie
    // Son personnalisé : ~/.local/share/caelestia/sounds/alarme.* (sinon le son système)
    readonly property string ringSoundDir: `${Quickshell.env("HOME")}/.local/share/caelestia/sounds`

    function ringAlarm(label: string, hm: string): void {
        ring("alarm", label, hm, 0);
    }

    function ring(kind: string, label: string, sub: string, total: real): void {
        ringKind = kind;
        alarmLabel = label;
        alarmTime = kind === "alarm" ? sub : "";
        ringSub = sub;
        ringTotal = total;
        ringSince = Date.now();
        ringElapsed = 0;
        ringLoops = 0;
        // La musique se met en pause le temps de la sonnerie, puis reprend
        if (root.screen === Quickshell.screens[0]) {
            const paused = [];
            for (const pl of Mpris.players.values)
                if (pl.isPlaying && pl.canPause) {
                    pl.pause();
                    paused.push(pl);
                }
            ringPaused = paused;
        }
        alarmRinging = true;
        saveClock();
    }

    function stopAlarm(): void {
        if (!alarmRinging)
            return;
        alarmRinging = false;
        ringKind = "";
        ringPlayer.running = false;
        for (const pl of ringPaused)
            if (pl && pl.canPlay)
                pl.play();
        ringPaused = [];
        saveClock();
        if (pulse === "alarm") {
            pulseTimer.stop();
            pulse = "";
            if (queue.length > 0)
                showNext();
        }
    }

    // Répéter : alarme → dans 9 min ; minuteur → même durée ; +1 min
    function snoozeAlarm(): void {
        const kind = ringKind, label = alarmLabel, total = ringTotal;
        stopAlarm();
        if (kind === "timer")
            startTimer(total, label === qsTr("Minuteur") ? "" : label);
        else
            startTimer(9 * 60, qsTr("%1 (répétition)").arg(label));
    }

    function ringPlusOne(): void {
        const label = alarmLabel;
        stopAlarm();
        startTimer(60, label === qsTr("Minuteur") ? "" : label);
    }

    // Pomodoro : enchaîner sur la phase suivante
    function ringNextPhase(): void {
        const kind = ringKind;
        stopAlarm();
        if (kind === "pomoWork") {
            pomoPhase = "rest";
            startTimer(pomoRest, qsTr("Pause"));
        } else {
            pomoPhase = "work";
            pomoRound += 1;
            startTimer(pomoWork, qsTr("Focus"));
        }
    }

    function stopRingAll(): void {
        pomoOn = false;
        stopAlarm();
        saveClock();
    }

    // Un son par moment (~/Documents/Sons Caelestia, lien ~/.local/share/caelestia/sounds) :
    // premier passage = version « -intro » dont le volume monte en 20 s, puis boucle à plein volume.
    // Son absent → alarme.ogg → son système. Un seul écran joue.
    readonly property string ringSoundName: ({ timer: "minuteur", alarm: "alarme", pomoWork: "fin-focus", pomoRest: "fin-pause" })[ringKind] ?? "alarme"

    Process {
        id: ringPlayer

        command: ["sh", "-c", 'd="$1"; n="$2"; for f in "$d/$n$3.ogg" "$d/$n.ogg" "$d/alarme$3.ogg" "$d/alarme.ogg" /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga; do [ -f "$f" ] && exec pw-play --volume "$4" "$f"; done', "sh", root.ringSoundDir, root.ringSoundName, root.ringLoops === 0 ? "-intro" : "", "1.0"]
        onExited: if (root.alarmRinging) ringNext.restart()
    }

    // Sons courts : rappel de tâche, transfert terminé (son système si le fichier manque)
    function playShort(name: string, fallback: string): void {
        if (root.screen !== Quickshell.screens[0])
            return;
        Quickshell.execDetached(["sh", "-c", 'f="$1/$2.ogg"; [ -f "$f" ] || f="$3"; exec pw-play "$f"', "sh", root.ringSoundDir, name, fallback]);
    }
    Timer {
        id: ringNext

        interval: 150
        onTriggered: {
            if (!root.alarmRinging)
                return;
            root.ringLoops += 1;
            ringPlayer.running = true;
        }
    }
    onAlarmRingingChanged: {
        if (alarmRinging && screen === Quickshell.screens[0])
            ringPlayer.running = true;
    }
    Timer {
        running: root.alarmRinging
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.ringElapsed = (Date.now() - root.ringSince) / 1000
    }

    function openClockApp(): void {
        Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/caelestia-clock`]);
    }

    function togglePause(): void {
        if (clockKind === "")
            return;
        if (clockPaused > 0) {
            const shift = Date.now() - clockPaused;
            clockEnd += shift;
            clockStart += shift;
            clockPaused = 0;
        } else {
            clockPaused = Date.now();
        }
        now = Date.now();
        saveClock();
    }

    // Mode Concentration « Travail » : lance / arrête le Pomodoro
    Connections {
        target: FocusMode

        function onStartPomodoro(): void {
            if (root.screen === Quickshell.screens[0] && !root.pomoOn)
                root.startPomodoro(25 * 60, 5 * 60);
        }
        function onStopPomodoro(): void {
            if (root.screen !== Quickshell.screens[0])
                return;
            if (root.alarmRinging && root.ringKind.startsWith("pomo"))
                root.stopAlarm();
            if (root.pomoOn)
                root.stopClock();
        }
    }

    function stopClock(): void {
        clockKind = "";
        clockPaused = 0;
        clockLabel = "";
        pomoOn = false;
        laps = [];
        saveClock();
    }

    // « 10 min », « 1 h 30 », « 45 s »
    function fmtHuman(sec: real): string {
        sec = Math.round(Math.max(0, sec));
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
        if (h > 0)
            return m > 0 ? `${h} h ${m.toString().padStart(2, "0")}` : `${h} h`;
        if (m > 0)
            return s > 0 ? `${m} min ${s} s` : `${m} min`;
        return `${s} s`;
    }

    function fmtClock(sec: real): string {
        sec = Math.max(0, sec);
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        const s = Math.floor(sec % 60);
        const mm = m.toString().padStart(2, "0");
        const ss = s.toString().padStart(2, "0");
        return h > 0 ? `${h}:${mm}:${ss}` : `${m}:${ss}`;
    }

    // ── Paroles synchronisées (cache d'Aura, .lrc voisin, puis LRCLIB) ──
    property var lyrics: []
    property string lyricsKey: ""
    property real lyricPos: 0
    readonly property string lyricKeyNow: hasMedia ? `${player?.trackTitle ?? ""}|${player?.trackArtist ?? ""}` : ""
    readonly property int lyricIndex: {
        const l = lyrics;
        if (!l || l.length === 0)
            return -1;
        const t = lyricPos + 0.25;
        let lo = 0, hi = l.length - 1, ans = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (l[mid][0] <= t) {
                ans = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return ans;
    }
    readonly property string lyricLine: lyricIndex >= 0 ? (lyrics[lyricIndex][1] || "♪") : ""
    readonly property bool hasLyrics: Island.lyrics && lyrics.length > 0 && lyricIndex >= 0

    // Paroles réactivées dans les réglages : on les recharge pour le morceau en cours
    Connections {
        target: Island

        function onLyricsChanged(): void {
            if (Island.lyrics)
                lyricsDebounce.restart();
        }
    }

    onLyricKeyNowChanged: lyricsDebounce.restart()

    Timer {
        id: lyricsDebounce

        interval: 700
        onTriggered: {
            root.lyrics = [];
            root.lyricsKey = root.lyricKeyNow;
            if (!root.lyricKeyNow || !Island.lyrics)
                return;
            const len = root.player?.length ?? 0;
            lyricsProc.command = ["python3", Quickshell.shellPath("assets/island-lyrics.py"), root.player?.trackTitle ?? "", root.player?.trackArtist ?? "", String(len > 0 && len < 2147483 ? len : 0), String(root.player?.metadata?.["xesam:url"] ?? "")];
            lyricsProc.running = true;
        }
    }

    Process {
        id: lyricsProc

        property string key

        onStarted: key = root.lyricsKey
        stdout: StdioCollector {
            onStreamFinished: {
                if (lyricsProc.key !== root.lyricKeyNow)
                    return;
                try {
                    root.lyrics = JSON.parse(text).lines ?? [];
                } catch (e) {
                    root.lyrics = [];
                }
            }
        }
    }

    Timer {
        running: root.playing && root.lyrics.length > 0
        interval: 200
        repeat: true
        onTriggered: {
            root.player?.positionChanged();
            root.lyricPos = root.player?.position ?? 0;
        }
    }

    // ── Étagère : fichiers déposés sur l'île (partagée, dans services/Island.qml) ──
    readonly property list<string> shelf: Island.shelf
    property bool dropping

    readonly property bool hidden: !Island.enabled || fullscreen || (screenState?.dashboard ?? false)

    readonly property string mode: {
        if (hidden)
            return "hidden";
        if (countLeft > 0)
            return "count";
        if (Island.notifCenter && screen === Quickshell.screens[0])
            return "center";
        if (dropping)
            return "drop";
        if (alarmRinging)
            return "alarm";
        if (taskAlert)
            return "taskDue";
        if (pulse === "fileDone" && fileDone)
            return "fileDone";
        if (pulse === "level")
            return "level";
        if (pulse === "shot")
            return "shot";
        if (pulse === "notif" && notif)
            return "notif";
        if (pulse === "toast" && toastData)
            return "toast";
        if (pulse === "done")
            return "done";
        if (pulse === "bt" && btDevice)
            return "bt";
        if (pulse === "charge")
            return "charge";
        if (pulse === "blip")
            return "blip";
        if (pulse === "ws")
            return "ws";
        if (expanded)
            return pages[pageIndex];
        if (compactPick !== "")
            return compactPick;
        return "idle";
    }

    // Activités en cours affichables en compact ; celle qu'on a regardée en dernier passe devant
    readonly property list<string> compactActs: [...(inCall ? ["call"] : []), ...(transfer ? ["transfer"] : []), ...(Recorder.running ? ["record"] : []), ...(clockKind !== "" ? ["clockMini"] : []), ...(hasMedia && playing ? ["media"] : [])]
    readonly property string compactPick: {
        const fromPage = ({ callFull: "call", transferFull: "transfer", recordFull: "record", clock: "clockMini", player: "media" })[pageName];
        return fromPage && compactActs.includes(fromPage) ? fromPage : (compactActs[0] ?? "");
    }
    // Les autres activités, en petites icônes au bord de l'île compacte (+ caféine)
    readonly property list<string> otherActs: [...compactActs.filter(a => a !== mode), ...(IdleInhibitor.enabled ? ["caffeine"] : [])]
    readonly property bool compactActive: mode === "call" || mode === "transfer" || mode === "record" || mode === "clockMini" || mode === "media"
    readonly property real actsInset: compactActive && otherActs.length > 0 ? otherActs.length * 18 + 12 : 0

    function actIcon(a: string): string {
        return ({ call: callMuted ? "mic_off" : "call", transfer: transfer?.kind === "copy" ? "content_copy" : "download", record: "radio_button_checked", clockMini: "timer", media: "music_note", caffeine: "coffee" })[a] ?? "";
    }

    function actColour(a: string): color {
        return ({ call: callMuted ? "#ff453a" : root.green, transfer: "#0a84ff", record: "#ff453a", clockMini: "#ff9f0a", media: root.accent, caffeine: root.fg })[a] ?? root.fg;
    }

    // Seules les actions avec un texte donnent un bouton (kitty envoie une action « default » sans libellé)
    readonly property var notifButtons: (notif?.actions ?? []).filter(a => (a.text ?? "") !== "").slice(0, 3)
    readonly property bool notifHasActions: notifButtons.length > 0
    readonly property real shelfExtra: shelf.length > 0 ? 78 : 0
    // Même largeur pour les pages qu'on fait défiler : l'île ne rétrécit pas sous la souris
    readonly property real pageWidth: clockKind !== "" ? Math.min(640, Math.max(560, clockTitleMetrics.advanceWidth + 250)) : 560

    // Taille visible (depuis le haut de l'écran) pour chaque mode
    readonly property size target: {
        switch (mode) {
        case "hidden":
            return Qt.size(180, 0);
        case "level":
            return Qt.size(340, 52);
        case "notif":
            return Qt.size(430, hovered && notifHasActions ? 132 : 92);
        case "center":
            return Qt.size(460, Math.min(600, Math.max(170, 86 + centerList.contentHeight)));
        case "recordFull":
            return Qt.size(pageWidth, 86);
        case "caffeine":
            return Qt.size(pageWidth, 96);
        case "count":
            return Qt.size(200, 86);
        case "drop":
            return Qt.size(420, 110);
        case "toast":
            return Qt.size(400, toastData?.message ? 76 : 52);
        case "done":
            return Qt.size(380, 68);
        case "alarm":
            return Qt.size(ringKind === "alarm" ? 500 : 580, 118);
        case "blip":
            return Qt.size(blipSub ? 320 : 280, 44);
        case "ws":
            return Qt.size(Math.max(250, 150 + wsLast * 18), 44);
        case "clock":
            // Page de même largeur que les autres, élargie pour lire le libellé en entier (au-delà « … »)
            return Qt.size(pageWidth, 118 + (clockTitleMetrics.advanceWidth > pageWidth - 250 ? 16 : 0) + shelfExtra);
        case "clockMini":
            return Qt.size((clockLabel ? 290 : 230) + actsInset, 40);
        case "shot":
            return Qt.size(460, 100);
        case "bt":
            return btOn ? Qt.size(400, 76) : Qt.size(330, 48);
        case "charge":
            return chargePlugged ? Qt.size(420, 78) : Qt.size(330, 48);
        case "player":
            return Qt.size(pageWidth, (hasLyrics ? 202 : 178) + (shelf.length > 0 ? shelfExtra : 10));
        case "info":
            return Qt.size(pageWidth, 112 + (infoChips.length > 0 ? infoFlow.implicitHeight + 10 : 0) + shelfExtra);
        case "perf":
            return Qt.size(pageWidth, 150);
        case "record":
            return Qt.size(210 + actsInset, 40);
        case "transfer":
            return Qt.size(Math.min(330, 170 + transferNameMetrics.advanceWidth) + actsInset, 40);
        case "transferFull":
            return Qt.size(pageWidth, 112);
        case "taskDue":
            return Qt.size(460, 104);
        case "fileDone":
            return Qt.size(440, 76);
        case "call":
            return Qt.size(Math.min(340, 150 + callTitleMetrics.advanceWidth) + actsInset, 40);
        case "callFull":
            return Qt.size(pageWidth, 96);
        case "media":
            return Qt.size((hasLyrics ? 400 : 290) + actsInset, 40);
        default:
            // Au repos : juste l'heure (ou rien si Island.clock est coupé)
            // Heure au centre exact : les deux côtés prennent la largeur du plus large
            return Island.clock ? Qt.size(Math.max(250, idleTime.implicitWidth + 2 * (Math.max(idleDate.implicitWidth, idleIcons.implicitWidth) + 20 + 18)), 40) : Qt.size(150, 0);
        }
    }

    property real w: target.width
    property real h: target.height
    readonly property real radius: Math.min(h / 2, mode === "player" || mode === "info" || mode === "perf" || mode === "notif" || mode === "bt" || mode === "shot" || mode === "clock" || mode === "drop" || mode === "toast" || mode === "done" || mode === "alarm" || mode === "count" || mode === "recordFull" || mode === "callFull" || mode === "transferFull" || mode === "taskDue" || mode === "fileDone" || mode === "caffeine" || mode === "center" || (mode === "charge" && chargePlugged) ? 32 : h / 2)

    function flash(kind: string, ms: int): void {
        if (!ready)
            return;
        // Volume, bureau… par-dessus une notification : elle revient ensuite
        if ((pulse === "notif" && notif) || (pulse === "toast" && toastData)) {
            if (kind !== "notif" && kind !== "toast") {
                queue = [pulse === "notif" ? notif : toastData, ...queue];
                notif = null;
                toastData = null;
            }
        }
        pulse = kind;
        pulseTimer.interval = ms;
        pulseTimer.restart();
    }

    function showNext(): void {
        while (queue.length > 0) {
            const n = queue[0];
            queue = queue.slice(1);
            if (n?.isToast) {
                toastData = n;
                notif = null;
                flash("toast", n.type >= 2 ? 5000 : 3200);
                return;
            }
            if (n && !n.closed) {
                notif = n;
                toastData = null;
                flash("notif", n.urgency === 2 ? 9000 : 5000);
                return;
            }
        }
        notif = null;
        toastData = null;
    }

    function fmtTime(s: real): string {
        if (!isFinite(s) || s < 0 || s > 2147483)
            return "--:--";
        const m = Math.floor(s / 60);
        return `${m}:${Math.floor(s % 60).toString().padStart(2, "0")}`;
    }

    function setLevel(v: real): void {
        v = Math.max(0, Math.min(1, v));
        if (levelKind === "volume")
            Audio.setVolume(v);
        else
            brightMon?.setBrightness(v);
    }

    implicitWidth: w
    // Au repos, une bande invisible de 4 px en haut de l'écran garde le survol actif
    implicitHeight: Math.max(h, 4)
    clip: true

    Behavior on w {
        // Ressort plus souple : l'île s'ouvre en douceur au lieu de sauter à sa taille
        SpringAnimation {
            spring: 2.4
            damping: 0.3
            epsilon: 0.25
        }
    }
    Behavior on h {
        SpringAnimation {
            spring: 2.4
            damping: 0.34
            epsilon: 0.25
        }
    }

    Component.onCompleted: readyTimer.start()

    Timer {
        id: readyTimer

        interval: 1500
        onTriggered: {
            root.lastVol = Math.round(Audio.volume * 100);
            root.lastMuted = Audio.muted;
            root.lastSink = Audio.sink?.id ?? -1;
            root.lastBright = Math.round(root.brightness * 100);
            root.ready = true;
            if (root.screen === Quickshell.screens[0])
                root.saveClock();
        }
    }

    Timer {
        id: pulseTimer

        onTriggered: {
            // Survolée ou jauge tenue : on attend que la souris parte
            if (root.hovered || root.levelHeld) {
                restart();
                return;
            }
            if (root.queue.length > 0) {
                root.showNext();
                return;
            }
            root.pulse = "";
            root.notif = null;
            root.toastData = null;
        }
    }

    Timer {
        id: hoverTimer

        interval: root.hovered ? 320 : 480
        onTriggered: root.expanded = root.hovered && root.pulse === ""
    }

    onHoveredChanged: {
        hoverTimer.restart();
        if (Island.notifCenter)
            centerClose.restart();
    }

    // Centre de notifications : se referme quand la souris part (vite) ou n'est jamais venue (après 5 s)
    property bool centerVisited

    Connections {
        target: Island

        function onNotifCenterChanged(): void {
            root.centerVisited = root.hovered;
            if (Island.notifCenter)
                centerClose.restart();
        }
    }

    Timer {
        id: centerClose

        interval: root.centerVisited ? 700 : 5000
        onTriggered: {
            if (root.hovered) {
                root.centerVisited = true;
                return;
            }
            Island.notifCenter = false;
        }
    }

    // ── Déclencheurs ──
    Connections {
        target: Audio

        function onVolumeChanged(): void {
            // PipeWire renvoie parfois le même volume (nouveau flux, changement de sortie) : on ignore
            const v = Math.round(Audio.volume * 100);
            const sink = Audio.sink?.id ?? -1;
            const sameSink = sink === root.lastSink;
            root.lastSink = sink;
            if (v === root.lastVol && Audio.muted === root.lastMuted)
                return;
            root.lastVol = v;
            root.lastMuted = Audio.muted;
            // Changement de sortie (écouteurs qui passent en mode micro, etc.) : pas de jauge
            if (!sameSink)
                return;
            root.levelKind = "volume";
            root.levelIcon = Audio.muted || Audio.volume <= 0 ? "volume_off" : Audio.volume < 0.34 ? "volume_mute" : Audio.volume < 0.67 ? "volume_down" : "volume_up";
            root.flash("level", 1700);
        }

        function onMutedChanged(): void {
            onVolumeChanged();
        }
    }

    property int lastBright: -1

    onBrightnessChanged: {
        const b = Math.round(brightness * 100);
        if (b === lastBright)
            return;
        lastBright = b;
        levelKind = "brightness";
        levelIcon = brightness < 0.34 ? "brightness_low" : brightness < 0.67 ? "brightness_medium" : "brightness_high";
        flash("level", 1700);
    }

    onChargingChanged: {
        if (!UPower.displayDevice.ready || !UPower.displayDevice.isLaptopBattery)
            return;
        if (pulse === "charge") {
            // Laisse la vue précédente s'effacer avant d'afficher la nouvelle
            pulse = "";
            chargeSwap.restart();
            return;
        }
        chargePlugged = charging;
        flash("charge", charging ? 3600 : 2600);
        chargeIntro.restart();
    }

    // Connexion / déconnexion d'un appareil Bluetooth (on suit chaque appareil connu)
    Instantiator {
        model: Bluetooth.devices

        delegate: QtObject {
            required property BluetoothDevice modelData
            readonly property bool on: modelData?.connected ?? false

            onOnChanged: {
                if (!root.ready)
                    return;
                root.btDevice = modelData;
                root.btOn = on;
                root.flash("bt", on ? 4200 : 2200);
            }
        }
    }

    Connections {
        target: Island

        function onNotify(n: var): void {
            root.enqueue(n);
        }
    }

    function enqueue(n: var): void {
        {
            if (!root.ready)
                return;
            // Le point rouge de l'île montre déjà l'enregistrement : pas de notification en plus
            if ((n?.appName ?? "").startsWith("caelestia") && /^Enregistrement (démarré|en pause|repris)/.test(n?.summary ?? ""))
                return;
            if (Island.notifCenter && !n?.isToast)
                return;
            if (root.isShot(n)) {
                root.shotPath = root.shotSource(n);
                root.shotSaved = root.shotPath.startsWith(root.shotsDir);
                // La capture plein écran (caelestia screenshot) ne joue pas de son, la zone oui
                if (!root.shotPath.includes("caelestia-picker"))
                    Sounds.playScreenshot();
                root.flash("shot", 6500);
                shotIntro.restart();
                return;
            }
            if ((root.pulse === "notif" && root.notif) || (root.pulse === "toast" && root.toastData)) {
                root.queue = [...root.queue, n];
                return;
            }
            root.queue = [...root.queue, n];
            root.showNext();
        }
    }

    // Bulles de Caelestia (Ne pas déranger, batterie faible, thème…) : elles passent par l'île
    property var seenToasts: []

    Connections {
        target: Toaster

        function onToastsChanged(): void {
            const fresh = [];
            for (const t of Toaster.toasts)
                if (t && !t.closed && !root.seenToasts.includes(t))
                    fresh.push(t);
            root.seenToasts = [...Toaster.toasts];
            if (!Island.toasts)
                return;
            for (const t of fresh.reverse()) {
                const title = t.title ?? "";
                // Déjà montré autrement par l'île
                if (/^En cours de lecture|^Verrouillage majuscule|^Chargeur|^Batterie en charge/.test(title))
                    continue;
                root.enqueue({
                    isToast: true,
                    title: title,
                    message: t.message ?? "",
                    icon: t.icon || "info",
                    type: t.type ?? 0
                });
                t.close?.();
            }
        }
    }

    // Commandes : qs -c caelestia ipc call island timer 5m | stopwatch | pause | stop
    IpcHandler {
        target: "island"
        enabled: root.screen === Quickshell.screens[0]

        function timer(duration: string): void {
            root.pomoOn = false;
            root.startTimer(root.parseDuration(duration), "");
        }
        function timerFor(duration: string, label: string): void {
            root.pomoOn = false;
            root.startTimer(root.parseDuration(duration), label);
        }
        function stopwatch(): void {
            root.startStopwatch();
        }
        function lap(): void {
            root.addLap();
        }
        function pomodoro(work: string, rest: string): void {
            root.startPomodoro(root.parseDuration(work), root.parseDuration(rest));
        }
        function addMinute(): void {
            root.addMinute();
        }
        function pause(): void {
            root.togglePause();
        }
        function stop(): void {
            root.stopClock();
        }
        function stopAlarm(): void {
            root.stopAlarm();
        }
        function snooze(): void {
            root.snoozeAlarm();
        }
        function ringNext(): void {
            root.ringNextPhase();
        }
        function stopAll(): void {
            root.stopRingAll();
        }
        function testRing(kind: string): void {
            if (kind === "timer")
                root.ring("timer", qsTr("Pâtes"), qsTr("Minuteur de %1 terminé").arg(root.fmtHuman(600)), 600);
            else if (kind === "pomo")
                root.ring("pomoWork", qsTr("Focus terminé"), qsTr("Session 1 · place à 5 min de pause"), 1500);
            else
                root.ringAlarm(qsTr("Réveil"), Time.format("HH:mm"));
        }
        function testAlarm(label: string): void {
            root.ringAlarm(label || qsTr("Alarme"), Time.format("HH:mm"));
        }
        function state(): string {
            root.saveClock();
            return "ok";
        }
    }

    // Petit rebond quand un évènement arrive
    onPulseChanged: {
        if (pulse === "notif" || pulse === "toast" || pulse === "charge" || pulse === "bt" || pulse === "shot")
            bump.restart();
        if (pulse === "done")
            doneShake.restart();
        if (pulse === "bt" && btOn)
            btIntro.restart();
    }

    // Arrivée des écouteurs : l'icône surgit, deux ondes partent, l'anneau de batterie se remplit
    property real btPop: 1
    property real btWave: 1
    property real btRing: 1

    SequentialAnimation {
        id: btIntro

        ScriptAction {
            script: {
                root.btPop = 0;
                root.btWave = 0;
                root.btRing = 0;
            }
        }
        PauseAnimation {
            duration: 120
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "btPop"
                to: 1
                duration: 620
                easing.type: Easing.OutBack
                easing.overshoot: 2.4
            }
            NumberAnimation {
                target: root
                property: "btWave"
                to: 1
                duration: 1500
                easing.type: Easing.OutCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 250
                }
                NumberAnimation {
                    target: root
                    property: "btRing"
                    to: 1
                    duration: 1100
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    SequentialAnimation {
        id: countPop

        NumberAnimation {
            target: countNum
            property: "scale"
            from: 1.6
            to: 1
            duration: 500
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    SequentialAnimation {
        id: doneShake

        loops: 3
        NumberAnimation {
            target: root
            property: "swipeX"
            to: 7
            duration: 55
        }
        NumberAnimation {
            target: root
            property: "swipeX"
            to: -7
            duration: 90
        }
        NumberAnimation {
            target: root
            property: "swipeX"
            to: 0
            duration: 55
        }
    }

    SequentialAnimation {
        id: bump

        NumberAnimation {
            target: content
            property: "scale"
            to: 1.05
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: content
            property: "scale"
            to: 1
            duration: 460
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }
    }

    Timer {
        running: root.mode === "player" && root.playing
        interval: 500
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    ServiceRef {
        service: root.playing ? Audio.cava : null
    }

    // ── Interactions ──
    HoverHandler {
        onHoveredChanged: root.hovered = hovered
    }

    // Gestes : glisser à gauche/droite sur la musique = morceau suivant/précédent,
    // vers le haut sur une notification = la chasser ; molette verticale = volume
    property real swipeX: 0
    property real swipeY: 0
    property real wheelX: 0
    property real wheelY: 0

    // Pages de l'île ouverte : enregistrement et minuteur en cours d'abord (s'il y en a),
    // puis heure/météo ↔ performances du PC ↔ musique (si un lecteur est actif)
    readonly property list<string> pages: [...(inCall ? ["callFull"] : []), ...(transfer ? ["transferFull"] : []), ...(Recorder.running ? ["recordFull"] : []), ...(clockKind !== "" ? ["clock"] : []), ...(IdleInhibitor.enabled ? ["caffeine"] : []), "info", "perf", ...(hasMedia ? ["player"] : [])]
    // Page retenue par son nom : elle reste la même quand d'autres pages apparaissent ou disparaissent
    property string pageName: "info"
    readonly property int pageIndex: Math.max(0, pages.indexOf(pageName))
    readonly property bool paged: pages.includes(mode)

    // Ce qui démarre passe devant : musique, minuteur, enregistrement ; à l'arrêt, retour à l'heure
    onHasMediaChanged: {
        if (hasMedia)
            pageName = "player";
        else if (pageName === "player")
            pageName = "info";
    }
    onClockKindChanged: {
        if (clockKind !== "")
            pageName = "clock";
        else if (pageName === "clock")
            pageName = "info";
    }
    Connections {
        target: IdleInhibitor

        function onEnabledChanged(): void {
            if (IdleInhibitor.enabled)
                root.pageName = "caffeine";
            else if (root.pageName === "caffeine")
                root.pageName = "info";
        }
    }
    readonly property bool hasTransfer: transfer !== null
    onHasTransferChanged: {
        if (hasTransfer && pageName !== "callFull")
            pageName = "transferFull";
        else if (!hasTransfer && pageName === "transferFull")
            pageName = "info";
    }
    onInCallChanged: {
        if (inCall)
            pageName = "callFull";
        else if (pageName === "callFull")
            pageName = "info";
    }
    Connections {
        target: Recorder

        function onRunningChanged(): void {
            if (Recorder.running)
                root.pageName = "recordFull";
            else if (root.pageName === "recordFull")
                root.pageName = "info";
        }
    }

    // Sens de sortie d'une page : vers la gauche si elle est avant la page courante
    function pageSlide(name: string): real {
        const i = pages.indexOf(name);
        const cur = pages.indexOf(mode);
        if (i < 0 || cur < 0 || i === cur)
            return 0;
        return i < cur ? -90 : 90;
    }

    // Geste molette/pavé en cours : axe choisi au début, une seule page tournée par geste
    property string wheelAxis: ""
    property bool wheelDone

    function flipPage(dir: int): void {
        const next = Math.max(0, Math.min(pages.length - 1, pageIndex + dir));
        if (next === pageIndex) {
            // Bord : petit rebond élastique
            swipeX = -dir * 14;
            swipeReset.restart();
            return;
        }
        pageName = pages[next];
        swipeX = -dir * 26;
        swipeReset.restart();
    }

    // Capteurs actifs seulement quand l'île est ouverte (préchauffés sur la page 1)
    ServiceRef {
        service: root.paged ? Cpu : null
    }
    ServiceRef {
        service: root.paged ? Memory : null
    }
    ServiceRef {
        service: root.paged ? Storage : null
    }
    // Fréquence moyenne du processeur (GHz) et ventilateur (tr/min), relevés pendant la page Performances
    property real cpuGhz
    property int fanRpm: -1
    property real tempPeak

    Timer {
        running: root.mode === "perf"
        repeat: true
        triggeredOnStart: true
        interval: 1500
        onTriggered: {
            if (!sensorProc.running)
                sensorProc.running = true;
        }
    }

    Process {
        id: sensorProc

        command: ["sh", "-c", "f=0; n=0; for x in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do f=$((f + $(cat $x))); n=$((n + 1)); done; [ $n -gt 0 ] && echo $((f / n)) || echo 0; cat /sys/class/hwmon/*/fan1_input 2>/dev/null | head -1 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.cpuGhz = (parseInt(l[0]) || 0) / 1e6;
                root.fanRpm = l.length > 1 && l[1] !== "" ? parseInt(l[1]) : -1;
            }
        }
    }

    Connections {
        target: Cpu

        function onTemperatureChanged(): void {
            if (root.mode === "perf")
                root.tempPeak = Math.max(root.tempPeak, Cpu.temperature);
        }
    }

    // NetworkUsage est un singleton QML (compteur de références simple)
    onPagedChanged: NetworkUsage.refCount += paged ? 1 : -1
    Component.onDestruction: {
        if (paged)
            NetworkUsage.refCount--;
    }

    Behavior on swipeX {
        enabled: !dragH.active

        SpringAnimation {
            spring: 5
            damping: 0.4
        }
    }
    Behavior on swipeY {
        enabled: !dragH.active

        SpringAnimation {
            spring: 5
            damping: 0.4
        }
    }

    function swipeTrack(dir: int): void {
        if (dir > 0)
            player?.next();
        else
            player?.previous();
        swipeX = dir * 40;
        swipeReset.restart();
    }

    function dismissCurrent(): void {
        swipeY = -30;
        swipeReset.restart();
        pulseTimer.stop();
        pulse = "";
        notif = null;
        toastData = null;
        if (queue.length > 0)
            showNext();
    }

    Timer {
        id: swipeReset

        interval: 90
        onTriggered: {
            root.swipeX = 0;
            root.swipeY = 0;
        }
    }

    Timer {
        id: wheelReset

        interval: 260
        onTriggered: {
            root.wheelX = 0;
            root.wheelY = 0;
            root.wheelAxis = "";
            root.wheelDone = false;
            if (!dragH.active)
                root.swipeX = 0;
        }
    }

    // WheelHandler ignore les évènements hors de son orientation (verticale par défaut) :
    // un second, horizontal, reçoit les glissements à deux doigts gauche/droite
    // Chaque évènement n'est traité que par un des deux (sinon diagonale = page + volume)
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        orientation: Qt.Horizontal
        onWheel: e => {
            if (Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y))
                root.handleWheel(e);
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: e => {
            if (Math.abs(e.angleDelta.x) <= Math.abs(e.angleDelta.y))
                root.handleWheel(e);
        }
    }

    function handleWheel(e: var): void {
        // Dans le centre de notifications, la molette fait défiler la liste
        if (root.mode === "center")
            return;
        const media = root.mode === "media" || root.mode === "player";
        if (root.paged) {
            if (root.wheelAxis === "")
                root.wheelAxis = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? "x" : "y";
            // Toujours relancer la remise à zéro : sinon un geste vertical bloquait l'axe
            // sur « y » pour de bon et les glissements gauche/droite étaient ignorés
            wheelReset.restart();
            if (root.wheelAxis === "x") {
                if (root.wheelDone)
                    return; // reste du même geste (ou inertie) : ignoré
                root.wheelX += e.angleDelta.x;
                if (Math.abs(root.wheelX) > 150) {
                    root.wheelDone = true;
                    root.flipPage(root.wheelX < 0 ? 1 : -1);
                } else {
                    // L'île suit les doigts avant de basculer
                    root.swipeX = Math.max(-30, Math.min(30, root.wheelX * 0.18));
                }
                return;
            }
        }
        const notifLike = root.mode === "notif" || root.mode === "toast" || root.mode === "shot";
        if (media && Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y)) {
            root.wheelX += e.angleDelta.x;
            wheelReset.restart();
            if (Math.abs(root.wheelX) > 240) {
                root.swipeTrack(root.wheelX < 0 ? 1 : -1);
                root.wheelX = -root.wheelX * 4; // pas de double déclenchement dans le même geste
            }
            return;
        }
        if (notifLike && e.pixelDelta.y !== 0) {
            root.wheelY += e.angleDelta.y;
            wheelReset.restart();
            if (root.wheelY < -200) {
                root.dismissCurrent();
                root.wheelY = 10000;
            }
            return;
        }
        if (e.angleDelta.y > 0)
            Audio.incrementVolume();
        else if (e.angleDelta.y < 0)
            Audio.decrementVolume();
    }

    DragHandler {
        id: dragH

        target: null
        xAxis.enabled: root.mode === "media" || root.mode === "player" || root.paged
        yAxis.enabled: root.mode === "notif" || root.mode === "toast" || root.mode === "shot"
        onTranslationChanged: {
            if (active) {
                root.swipeX = translation.x * 0.35;
                root.swipeY = Math.min(0, translation.y * 0.5);
            }
        }
        onActiveChanged: {
            if (active)
                return;
            if (root.paged && Math.abs(translation.x) > 50)
                root.flipPage(translation.x < 0 ? 1 : -1);
            else if (xAxis.enabled && !root.paged && Math.abs(translation.x) > 70)
                root.swipeTrack(translation.x < 0 ? 1 : -1);
            else if (yAxis.enabled && translation.y < -35)
                root.dismissCurrent();
            root.swipeX = 0;
            root.swipeY = 0;
        }
    }

    // Déposer des fichiers sur l'île = les ranger sur l'étagère
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: root.dropping = true
        onExited: root.dropping = false
        onDropped: drop => {
            root.dropping = false;
            if (drop.hasUrls) {
                Island.addToShelf(drop.urls);
                drop.acceptProposedAction();
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        enabled: !dragH.active
        onTapped: (_, button) => {
            if (root.mode === "notif") {
                const n = root.notif;
                if (n?.actions?.length > 0)
                    n.actions[0].invoke();
                pulseTimer.stop();
                root.pulse = "";
                root.showNext();
            } else if (root.mode === "toast" || root.mode === "done") {
                root.dismissCurrent();
            } else if (root.mode === "record") {
                Recorder.stop();
            } else if (root.mode === "count") {
                countTimer.stop();
                root.countLeft = 0;
            } else if (root.mode === "clockMini") {
                root.togglePause();
            } else if (button === Qt.MiddleButton || root.mode === "media") {
                root.player?.togglePlaying();
            } else if (root.mode === "idle" || root.mode === "info" || root.mode === "perf") {
                Island.notifCenter = true;
            }
        }
    }

    // ════════════════════ Contenu ════════════════════
    Item {
        id: content

        // Mise en page sur la taille finale : le contenu ne se réagence pas pendant le ressort de l'île
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: root.swipeX
        y: root.swipeY
        width: root.target.width
        height: root.target.height
        transformOrigin: Item.Top

        // ── repos : date à gauche, heure bien au centre, état du système à droite ──
        Face {
            active: root.mode === "idle"

            StyledText {
                id: idleDate

                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const s = Qt.locale("fr_FR").toString(Time.date, "ddd d");
                    return s.charAt(0).toUpperCase() + s.slice(1);
                }
                color: root.fgDim
                font.pointSize: 10.5
                font.weight: Font.Medium
            }

            StyledText {
                id: idleTime

                anchors.centerIn: parent
                text: Time.format("HH:mm")
                color: root.fg
                font.pointSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 0.3
                font.features: {
                    "tnum": 1
                }
            }

            // À droite : micro / caméra, étagère, caféine, Bluetooth, batterie (et ce qui viendra)
            Row {
                id: idleIcons

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                PrivacyDot {
                    visible: root.micInUse
                    dotColor: "#ff9f0a"
                }
                PrivacyDot {
                    visible: root.camInUse
                    dotColor: root.green
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.shelf.length > 0
                    width: shelfCount.implicitWidth + 14
                    height: 20
                    radius: 10
                    color: root.fgFaint

                    Row {
                        id: shelfCount

                        anchors.centerIn: parent
                        spacing: 3

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "inventory_2"
                            color: root.fg
                            fontStyle: Tokens.font.icon.size(10).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.shelf.length
                            color: root.fg
                            font.pointSize: 8.5
                            font.weight: Font.Bold
                        }
                    }
                }
                IdleIcon {
                    shown: FocusMode.active
                    icon: FocusMode.info.icon
                    tint: FocusMode.info.tint
                }
                IdleIcon {
                    shown: root.btConnected.length > 0
                    icon: root.btAudio ? "headphones" : "bluetooth"
                    tint: root.green
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showBattery && root.batteryPctShown
                    text: `${Math.round(root.battery * 100)} %`
                    color: root.battCharging ? root.green : root.battery < 0.2 ? root.red : root.fgDim
                    font.pointSize: 9
                    font.weight: Font.DemiBold
                    font.features: {
                        "tnum": 1
                    }
                }

                // Même batterie que dans l'île ouverte ; pulse sous 10 %
                BatteryGlyph {
                    id: idleBatt

                    anchors.verticalCenter: parent.verticalCenter
                    pct: root.battery
                    charging: root.battCharging
                    visible: root.showBattery

                    SequentialAnimation on opacity {
                        running: root.showBattery && root.battery < 0.1 && !root.charging && root.mode === "idle"
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) idleBatt.opacity = 1
                        NumberAnimation {
                            to: 0.35
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            to: 1
                            duration: 800
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }

        // ── Bluetooth : connexion façon AirPods ──
        Face {
            active: root.mode === "bt"

            Item {
                id: btIconBox

                anchors.left: parent.left
                anchors.leftMargin: root.btOn ? 22 : 18
                anchors.verticalCenter: parent.verticalCenter
                width: root.btOn ? 46 : 28
                height: width

                // Ondes qui partent de l'icône
                Repeater {
                    model: 2

                    Rectangle {
                        required property int index
                        readonly property real t: Math.max(0, Math.min(1, root.btWave * 1.25 - index * 0.25))

                        anchors.centerIn: parent
                        width: parent.width * (1 + t * 0.9)
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: root.accent
                        opacity: root.btOn && t > 0 && t < 1 ? (1 - t) * 0.7 : 0
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: root.btOn ? Qt.alpha(root.accent, 0.22) : root.fgFaint
                    scale: 0.4 + 0.6 * root.btPop

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.btIcon
                        color: root.btOn ? root.accent : root.fgDim
                        fontStyle: Tokens.font.icon.size(root.btOn ? 20 : 13).build()
                        fill: 1
                    }
                }
            }

            Column {
                anchors.left: btIconBox.right
                anchors.leftMargin: 14
                anchors.right: btRight.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.btDevice?.name ?? ""
                    color: root.fg
                    font.pointSize: root.btOn ? 11 : 10
                    font.weight: Font.DemiBold
                }
                StyledText {
                    visible: root.btOn
                    width: parent.width
                    elide: Text.ElideRight
                    text: qsTr("Connecté")
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            Item {
                id: btRight

                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                width: root.btOn ? 42 : discLbl.implicitWidth
                height: 42

                StyledText {
                    id: discLbl

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.btOn
                    text: qsTr("Déconnecté")
                    color: root.fgDim
                    font.pointSize: 9
                    font.weight: Font.Medium
                }

                // Anneau de batterie (ou coche si l'appareil ne donne pas sa batterie)
                Shape {
                    anchors.fill: parent
                    visible: root.btOn
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 3.5
                        strokeColor: root.fgFaint
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: 21
                            centerY: 21
                            radiusX: 18
                            radiusY: 18
                            startAngle: -90
                            sweepAngle: 360
                        }
                    }

                    ShapePath {
                        readonly property color ring: !root.btBattery ? root.green : root.btLevel < 0.2 ? root.red : root.green

                        strokeWidth: 3.5
                        strokeColor: ring
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: 21
                            centerY: 21
                            radiusX: 18
                            radiusY: 18
                            startAngle: -90
                            sweepAngle: 360 * root.btRing * (root.btBattery ? root.btLevel : 1)
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.btOn && root.btBattery
                    text: Math.round(root.btLevel * 100)
                    color: root.fg
                    font.pointSize: 9
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.btOn && !root.btBattery
                    text: "check"
                    color: root.green
                    scale: root.btRing
                    fontStyle: Tokens.font.icon.size(14).build()
                    fill: 1
                }
            }
        }

        // ── musique compacte ──
        Face {
            active: root.mode === "media"
            inset: root.actsInset

            Cover {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                size: 24
                radius: 7
            }

            // Ligne de paroles en cours (sinon le titre)
            LyricLine {
                anchors.centerIn: parent
                width: parent.width - 120
                line: root.hasLyrics ? root.lyricLine : (root.player?.trackTitle ?? "")
                lineColor: root.fg
                size: root.hasLyrics ? 9.5 : 9
                bold: root.hasLyrics
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 44
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                PrivacyDot {
                    visible: root.micInUse
                    dotColor: "#ff9f0a"
                }
                PrivacyDot {
                    visible: root.camInUse
                    dotColor: root.green
                }
            }

            Bars {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                count: 5
                barWidth: 3
                maxHeight: 16
            }
        }

        // ── téléchargement / copie (compact) : anneau de progression, nom, pourcentage ──
        Face {
            active: root.mode === "transfer"
            inset: root.actsInset

            Item {
                id: trMiniIcon

                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 2.5
                        strokeColor: root.fgFaint
                        fillColor: "transparent"

                        PathAngleArc {
                            centerX: 12
                            centerY: 12
                            radiusX: 10.5
                            radiusY: 10.5
                            startAngle: 0
                            sweepAngle: 360
                        }
                    }
                    ShapePath {
                        strokeWidth: 2.5
                        strokeColor: "#0a84ff"
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: 12
                            centerY: 12
                            radiusX: 10.5
                            radiusY: 10.5
                            startAngle: -90
                            sweepAngle: root.transferProgress >= 0 ? 360 * root.transferProgress : 70

                            Behavior on sweepAngle {
                                NumberAnimation {
                                    duration: 700
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    // Taille inconnue : l'arc tourne
                    RotationAnimation on rotation {
                        running: root.mode === "transfer" && root.transferProgress < 0
                        from: 0
                        to: 360
                        duration: 1200
                        loops: Animation.Infinite
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.transfer?.kind === "copy" ? "content_copy" : "arrow_downward"
                    color: "#0a84ff"
                    fontStyle: Tokens.font.icon.size(11).build()
                    fill: 1
                }
            }

            StyledText {
                anchors.left: trMiniIcon.right
                anchors.leftMargin: 9
                anchors.right: trMiniPct.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.transfer?.name ?? ""
                elide: Text.ElideMiddle
                color: root.fgDim
                font.pointSize: 9.5
                font.weight: Font.Medium
            }

            StyledText {
                id: trMiniPct

                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: root.transferProgress >= 0 ? `${Math.floor(root.transferProgress * 100)} %` : root.fmtBytes(root.transfer?.done ?? 0)
                color: "#0a84ff"
                font.pointSize: 10
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── téléchargement / copie (île ouverte) ──
        Face {
            active: root.mode === "transferFull"
            slide: root.pageSlide("transferFull")

            Rectangle {
                id: trBadge

                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.top: parent.top
                anchors.topMargin: 20
                width: 44
                height: 44
                radius: 22
                color: Qt.alpha("#0a84ff", 0.2)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.transfer?.kind === "copy" ? "content_copy" : "download"
                    color: "#0a84ff"
                    fontStyle: Tokens.font.icon.size(19).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: trBadge.right
                anchors.leftMargin: 14
                anchors.right: trButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: trBadge.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: root.transfer?.name ?? ""
                    color: root.fg
                    font.pointSize: 11.5
                    font.weight: Font.Bold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: {
                        const t = root.transfer;
                        if (!t)
                            return "";
                        const parts = [t.total > 0 ? qsTr("%1 sur %2").arg(root.fmtBytes(t.done)).arg(root.fmtBytes(t.total)) : root.fmtBytes(t.done)];
                        if (t.speed > 0)
                            parts.push(`${root.fmtBytes(t.speed)}/s`);
                        const eta = root.transferEta(t);
                        if (eta)
                            parts.push(qsTr("encore %1").arg(eta));
                        if (root.transfers.length > 1)
                            parts.push(qsTr("+%1").arg(root.transfers.length - 1));
                        return parts.join(" · ");
                    }
                    color: root.fgDim
                    font.pointSize: 9
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Row {
                id: trButtons

                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: trBadge.verticalCenter

                ShotButton {
                    icon: "folder_open"
                    tip: qsTr("Ouvrir le dossier")
                    onClicked: Quickshell.execDetached(["xdg-open", root.transfer?.dir ?? Quickshell.env("HOME")])
                }
            }

            // Barre de progression (ou vague qui passe si la taille est inconnue)
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 22
                height: 6
                radius: 3
                color: root.fgFaint
                clip: true

                Rectangle {
                    visible: root.transferProgress >= 0
                    width: parent.width * Math.max(0, root.transferProgress)
                    height: parent.height
                    radius: 3
                    color: "#0a84ff"

                    Behavior on width {
                        NumberAnimation {
                            duration: 700
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                Rectangle {
                    id: trWave

                    visible: root.transferProgress < 0
                    width: parent.width * 0.3
                    height: parent.height
                    radius: 3
                    color: "#0a84ff"

                    NumberAnimation on x {
                        running: root.mode === "transferFull" && root.transferProgress < 0
                        from: -trWave.width
                        to: trWave.parent.width
                        duration: 1300
                        loops: Animation.Infinite
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }

        // ── transfert terminé ──
        Face {
            active: root.mode === "fileDone"

            Rectangle {
                id: fdIcon

                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                radius: 19
                color: Qt.alpha(root.green, 0.2)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "check"
                    color: root.green
                    fontStyle: Tokens.font.icon.size(19).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: fdIcon.right
                anchors.leftMargin: 14
                anchors.right: fdButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: root.fileDone?.name ?? ""
                    color: root.fg
                    font.pointSize: 11
                    font.weight: Font.DemiBold
                }
                StyledText {
                    text: root.fileDone?.kind === "copy" ? qsTr("Copie terminée") : qsTr("Téléchargement terminé")
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            Row {
                id: fdButtons

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                ShotButton {
                    icon: "folder_open"
                    tip: qsTr("Afficher dans le dossier")
                    onClicked: {
                        const p = root.fileDone?.path ?? "";
                        Quickshell.execDetached(["dbus-send", "--session", "--dest=org.freedesktop.FileManager1", "--type=method_call", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", `array:string:file://${p}`, "string:"]);
                        root.pulse = "";
                    }
                }
                ShotButton {
                    icon: "open_in_new"
                    tip: qsTr("Ouvrir")
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", root.fileDone?.path ?? ""]);
                        root.pulse = "";
                    }
                }
            }
        }

        // ── rappel AuraTask : la tâche, l'échéance, « Fait » / « Plus tard » ──
        Face {
            active: root.mode === "taskDue"

            readonly property color tint: root.taskAlert?.priority === "urgent" ? root.red : root.taskAlert?.priority === "high" ? "#ff9f0a" : root.accent

            Rectangle {
                id: tdIcon

                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 46
                radius: 23
                color: Qt.alpha(parent.tint, 0.2)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.taskAlert?.late ? "notifications_active" : "task_alt"
                    color: tdIcon.parent.tint
                    fontStyle: Tokens.font.icon.size(20).build()
                    fill: 1

                    SequentialAnimation on rotation {
                        running: root.mode === "taskDue" && (root.taskAlert?.late ?? false)
                        loops: 3
                        NumberAnimation {
                            to: 14
                            duration: 90
                        }
                        NumberAnimation {
                            to: -14
                            duration: 180
                        }
                        NumberAnimation {
                            to: 0
                            duration: 90
                        }
                        PauseAnimation {
                            duration: 500
                        }
                    }
                }
            }

            Column {
                anchors.left: tdIcon.right
                anchors.leftMargin: 14
                anchors.right: tdButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    width: parent.width
                    text: root.taskAlert?.title ?? ""
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    color: root.fg
                    font.pointSize: 11.5
                    font.weight: Font.Bold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.taskAlert?.sub ?? ""
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            Row {
                id: tdButtons

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                ShotButton {
                    icon: "snooze"
                    tip: qsTr("Dans 10 min")
                    onClicked: root.taskAlertSnooze(10)
                }
                // « Fait » : pastille verte avec son libellé
                Rectangle {
                    width: tdDoneRow.implicitWidth + 26
                    height: 40
                    radius: 20
                    color: tdDoneArea.containsMouse ? Qt.lighter(root.green, 1.1) : root.green
                    scale: tdDoneArea.pressed ? 0.93 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                        }
                    }

                    Row {
                        id: tdDoneRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "check"
                            color: "white"
                            fontStyle: Tokens.font.icon.size(15).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Fait")
                            color: "white"
                            font.pointSize: 10
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: tdDoneArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.taskAlertDone()
                    }
                }
                ShotButton {
                    icon: "close"
                    tip: qsTr("Ignorer")
                    onClicked: root.taskAlert = null
                }
            }
        }

        // ── appel en cours (compact) : combiné vert qui respire, titre, durée ──
        Face {
            active: root.mode === "call"
            inset: root.actsInset

            Item {
                id: callMiniIcon

                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24

                Rectangle {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    radius: 12
                    color: root.callMuted ? root.red : root.green
                    opacity: 0.35

                    SequentialAnimation on scale {
                        running: root.mode === "call" && !root.callMuted
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.7
                            to: 1.25
                            duration: 1300
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            to: 0.7
                            duration: 0
                        }
                    }
                    SequentialAnimation on opacity {
                        running: root.mode === "call" && !root.callMuted
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.45
                            to: 0
                            duration: 1300
                        }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: 10
                    color: root.callMuted ? root.red : root.green

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.callMuted ? "mic_off" : root.camInUse ? "videocam" : "call"
                        color: "white"
                        fontStyle: Tokens.font.icon.size(11).build()
                        fill: 1
                    }
                }
            }

            StyledText {
                anchors.left: callMiniIcon.right
                anchors.leftMargin: 9
                anchors.right: callMiniTime.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.callTitle
                elide: Text.ElideRight
                color: root.fgDim
                font.pointSize: 9.5
                font.weight: Font.Medium
            }

            StyledText {
                id: callMiniTime

                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtLong(root.callElapsed)
                color: root.callMuted ? root.red : root.green
                font.pointSize: 10
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── enregistrement ──
        Face {
            active: root.mode === "record"
            inset: root.actsInset

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: root.red

                SequentialAnimation on opacity {
                    running: root.mode === "record" && !Recorder.paused
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.3
                        duration: 700
                    }
                    NumberAnimation {
                        to: 1
                        duration: 700
                    }
                }
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtTime(Recorder.elapsed)
                color: root.red
                font.pointSize: 10
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── volume / luminosité, façon macOS : jauge épaisse, icône dedans, glissable ──
        Face {
            active: root.mode === "level"

            Rectangle {
                id: gauge

                anchors.left: parent.left
                anchors.right: pct.left
                anchors.leftMargin: 18
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: gaugeArea.pressed ? 26 : 22
                radius: height / 2
                color: root.fgFaint
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                // Une jauge par type (volume, luminosité), chacune liée à sa propre valeur
                Repeater {
                    model: ["volume", "brightness"]

                    Rectangle {
                        required property string modelData
                        readonly property real value: modelData === "volume" ? Audio.volume : root.brightness

                        visible: root.levelKind === modelData
                        height: parent.height
                        radius: parent.radius
                        width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, value)))
                        color: modelData === "volume" && Audio.muted ? Qt.alpha(root.fg, 0.35) : root.fg

                        Behavior on width {
                            enabled: !gaugeArea.pressed

                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                // L'icône change de couleur selon la partie remplie qu'elle recouvre
                MaterialIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.levelIcon
                    color: root.levelValue > 0.08 ? Colours.palette.m3surface : root.fg
                    fontStyle: Tokens.font.icon.size(11).build()
                    fill: 1
                }

                MouseArea {
                    id: gaugeArea

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: e => {
                        root.levelHeld = true;
                        root.setLevel(e.x / width);
                    }
                    onPositionChanged: e => {
                        if (pressed)
                            root.setLevel(e.x / width);
                    }
                    onReleased: root.levelHeld = false
                    onCanceled: root.levelHeld = false
                }
            }

            StyledText {
                id: pct

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                horizontalAlignment: Text.AlignRight
                text: Math.round(root.levelValue * 100)
                color: root.fgDim
                font.pointSize: 10
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── chargeur branché / débranché ──
        Face {
            id: chargeFace

            readonly property bool plugged: root.chargePlugged
            readonly property color tone: plugged ? root.green : root.battery < 0.2 ? root.red : root.fg

            active: root.mode === "charge"

            // Grande batterie : se remplit depuis zéro, reflet qui la traverse, éclair qui surgit
            Item {
                id: bigBatt

                anchors.left: parent.left
                anchors.leftMargin: chargeFace.plugged ? 24 : 20
                anchors.verticalCenter: parent.verticalCenter
                width: chargeFace.plugged ? 58 : 34
                height: chargeFace.plugged ? 28 : 17

                Rectangle {
                    id: shell

                    width: parent.width - (chargeFace.plugged ? 5 : 3)
                    height: parent.height
                    radius: height * 0.3
                    color: "transparent"
                    border.width: chargeFace.plugged ? 2 : 1.4
                    border.color: Qt.alpha(root.fg, 0.4)

                    Rectangle {
                        id: fillBar

                        readonly property real m: chargeFace.plugged ? 3.5 : 2.5

                        x: m
                        y: m
                        height: parent.height - m * 2
                        width: Math.max(radius * 2, (parent.width - m * 2) * root.battery * root.chargeFill)
                        radius: shell.radius - m / 2
                        color: chargeFace.tone
                        clip: true

                        // Reflet lumineux qui balaie la batterie pendant la charge
                        Rectangle {
                            visible: chargeFace.plugged
                            width: 22
                            height: parent.height * 2
                            y: -parent.height / 2
                            x: -width + (parent.width + width * 2) * root.chargeShine
                            rotation: 20
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0
                                    color: "transparent"
                                }
                                GradientStop {
                                    position: 0.5
                                    color: Qt.rgba(1, 1, 1, 0.55)
                                }
                                GradientStop {
                                    position: 1
                                    color: "transparent"
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: shell.right
                    anchors.leftMargin: 1.5
                    anchors.verticalCenter: shell.verticalCenter
                    width: chargeFace.plugged ? 3 : 2
                    height: shell.height * 0.36
                    radius: width / 2
                    color: Qt.alpha(root.fg, 0.4)
                }

                // Halo vert derrière l'éclair
                Rectangle {
                    anchors.centerIn: shell
                    visible: chargeFace.plugged
                    width: 30
                    height: 30
                    radius: 15
                    color: root.green
                    opacity: 0.35 * (1 - root.chargeBolt) * (root.chargeBolt > 0 ? 1 : 0)
                    scale: 0.6 + root.chargeBolt * 1.2
                }

                MaterialIcon {
                    anchors.centerIn: shell
                    visible: chargeFace.plugged
                    text: "bolt"
                    color: "white"
                    style: Text.Outline
                    styleColor: Qt.alpha("black", 0.25)
                    fontStyle: Tokens.font.icon.size(17).build()
                    fill: 1
                    scale: root.chargeBolt
                }
            }

            Column {
                anchors.left: bigBatt.right
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    text: chargeFace.plugged ? qsTr("En charge") : qsTr("Sur batterie")
                    color: root.fg
                    font.pointSize: chargeFace.plugged ? 11 : 10
                    font.weight: Font.DemiBold
                }
                StyledText {
                    visible: text.length > 0
                    text: {
                        const d = UPower.displayDevice;
                        const t = chargeFace.plugged ? d.timeToFull : d.timeToEmpty;
                        if (!t || t <= 0)
                            return chargeFace.plugged ? qsTr("Branché") : "";
                        const h = Math.floor(t / 3600);
                        const m = Math.round((t % 3600) / 60);
                        const dur = h > 0 ? `${h} h ${m.toString().padStart(2, "0")}` : `${m} min`;
                        return chargeFace.plugged ? qsTr("Pleine dans %1").arg(dur) : qsTr("%1 restantes").arg(dur);
                    }
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                text: `${Math.round(root.battery * 100 * root.chargeFill)} %`
                color: chargeFace.tone
                font.pointSize: chargeFace.plugged ? 18 : 11
                font.weight: Font.Bold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── capture d'écran : la miniature tombe dans l'île avec un flash d'obturateur ──
        Face {
            active: root.mode === "shot"

            Item {
                id: shotThumb

                readonly property real ratio: shotImg.status === Image.Ready && shotImg.implicitHeight > 0 ? shotImg.implicitWidth / shotImg.implicitHeight : 16 / 9

                x: 22
                anchors.verticalCenter: parent.verticalCenter
                height: 62
                width: Math.min(130, Math.max(44, height * ratio))
                scale: 1.9 - 0.9 * root.shotIn
                opacity: Math.min(1, root.shotIn * 2)
                transformOrigin: Item.Center

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: 12
                    color: Qt.alpha(root.fg, 0.25)
                }

                Rectangle {
                    id: shotClip

                    anchors.fill: parent
                    radius: 10
                    color: root.fgFaint
                    clip: true

                    Image {
                        id: shotImg

                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.height: 180
                        source: root.shotPath ? `file://${root.shotPath}` : ""
                    }

                    // Flash d'obturateur
                    Rectangle {
                        anchors.fill: parent
                        color: "white"
                        opacity: Math.max(0, 1 - root.shotIn * 1.6)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", root.shotPath]);
                        root.closeShot();
                    }
                }
            }

            Column {
                anchors.left: shotThumb.right
                anchors.leftMargin: 16
                anchors.right: shotBtns.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: qsTr("Capture d'écran")
                    color: root.fg
                    font.pointSize: 11
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.shotSaved ? qsTr("Enregistrée et copiée") : qsTr("Copiée dans le presse-papiers")
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            Row {
                id: shotBtns

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                ShotButton {
                    icon: "edit"
                    tip: qsTr("Annoter")
                    onClicked: {
                        Quickshell.execDetached(["swappy", "-f", root.shotPath]);
                        root.closeShot();
                    }
                }
                ShotButton {
                    icon: root.shotSaved ? "folder_open" : "download"
                    tip: root.shotSaved ? qsTr("Dossier") : qsTr("Enregistrer")
                    onClicked: {
                        if (root.shotSaved) {
                            Quickshell.execDetached(["xdg-open", root.shotsDir]);
                            root.closeShot();
                        } else {
                            const name = Qt.formatDateTime(new Date(), "yyyyMMddhhmmss") + ".png";
                            const dest = `${root.shotsDir}/${name}`;
                            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && cp "$2" "$3"', "sh", root.shotsDir, root.shotPath, dest]);
                            root.shotPath = dest;
                            root.shotSaved = true;
                            pulseTimer.restart();
                        }
                    }
                }
            }
        }

        // ── bulle Caelestia (Ne pas déranger, batterie faible, thème…) ──
        Face {
            active: root.mode === "toast"

            readonly property color tone: {
                switch (root.toastData?.type ?? 0) {
                case 1:
                    return root.green;
                case 2:
                    return "#ff9f0a";
                case 3:
                    return root.red;
                default:
                    return root.accent;
                }
            }

            Rectangle {
                id: toastIcon

                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                radius: 17
                color: Qt.alpha(parent.tone, 0.2)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.toastData?.icon ?? "info"
                    color: parent.parent.tone
                    fontStyle: Tokens.font.icon.size(15).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: toastIcon.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.toastData?.title ?? ""
                    color: root.fg
                    font.pointSize: 10
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    visible: text.length > 0
                    elide: Text.ElideRight
                    text: root.toastData?.message ?? ""
                    color: root.fgDim
                    font.pointSize: 9
                }
            }
        }

        // ── changement de bureau ──
        Face {
            active: root.mode === "ws"

            StyledText {
                id: wsLabel

                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Bureau %1").arg(root.wsId)
                color: root.fg
                font.pointSize: 10.5
                font.weight: Font.DemiBold
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Repeater {
                    model: root.wsLast

                    Rectangle {
                        required property int index
                        readonly property bool current: index + 1 === root.wsId

                        anchors.verticalCenter: parent.verticalCenter
                        width: current ? 24 : 8
                        height: 8
                        radius: 4
                        color: current ? root.accent : Qt.alpha(root.fg, 0.3)

                        Behavior on width {
                            NumberAnimation {
                                duration: 380
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.6
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 220
                            }
                        }
                    }
                }
            }
        }

        // ── Verr. Maj, Wi-Fi, VPN ──
        Face {
            active: root.mode === "blip"

            Rectangle {
                id: blipBadge

                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 14
                color: root.blipOn ? Qt.alpha(root.accent, 0.22) : root.fgFaint

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.blipIcon
                    color: root.blipOn ? root.accent : root.fgDim
                    fontStyle: Tokens.font.icon.size(13).build()
                    fill: 1
                }
            }

            StyledText {
                anchors.left: blipBadge.right
                anchors.leftMargin: 12
                anchors.right: blipSubText.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.blipText
                color: root.fg
                font.pointSize: 10
                font.weight: Font.DemiBold
            }

            StyledText {
                id: blipSubText

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 140)
                elide: Text.ElideRight
                text: root.blipSub
                color: root.blipOn ? root.green : root.fgDim
                font.pointSize: 9
                font.weight: Font.Medium
            }
        }

        // ── autres activités en cours : petites icônes au bord de l'île compacte ──
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            opacity: root.actsInset > 0 ? 1 : 0
            visible: opacity > 0.01
            layoutDirection: Qt.RightToLeft

            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                }
            }

            Repeater {
                model: root.compactActive ? root.otherActs : []

                MaterialIcon {
                    required property string modelData

                    anchors.verticalCenter: parent?.verticalCenter
                    width: 14
                    horizontalAlignment: Text.AlignHCenter
                    text: root.actIcon(modelData)
                    color: root.actColour(modelData)
                    opacity: 0.8
                    fontStyle: Tokens.font.icon.size(12).build()
                    fill: 1
                }
            }
        }

        // ── caféine : page de l'île ouverte ──
        Face {
            active: root.mode === "caffeine"
            slide: root.pageSlide("caffeine")

            Rectangle {
                id: caffBadge

                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -4
                width: 48
                height: 48
                radius: 24
                color: Qt.alpha(root.accent, 0.22)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "coffee"
                    color: root.accent
                    fontStyle: Tokens.font.icon.size(20).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: caffBadge.right
                anchors.leftMargin: 14
                anchors.right: caffButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: caffBadge.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: qsTr("L'écran reste allumé")
                    color: root.fg
                    font.pointSize: 12
                    font.weight: Font.Bold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: IdleInhibitor.until > 0 ? qsTr("Encore %1 · jusqu'à %2").arg(IdleInhibitor.remainingText()).arg(Qt.formatTime(new Date(IdleInhibitor.until), "HH:mm")) : qsTr("Sans limite · depuis %1").arg(Qt.formatTime(IdleInhibitor.enabledSince, "HH:mm"))
                    color: root.fgDim
                    font.pointSize: 9
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Row {
                id: caffButtons

                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: caffBadge.verticalCenter
                spacing: 10

                ShotButton {
                    visible: IdleInhibitor.until > 0
                    icon: "more_time"
                    tip: qsTr("+15 min")
                    onClicked: IdleInhibitor.extend(15)
                }
                ShotButton {
                    visible: IdleInhibitor.until > 0
                    icon: "all_inclusive"
                    tip: qsTr("Sans limite")
                    onClicked: IdleInhibitor.enableFor(0)
                }
                ShotButton {
                    icon: "stop"
                    tip: qsTr("Arrêter")
                    onClicked: IdleInhibitor.enabled = false
                }
            }
        }

        // ── minuteur / chronomètre compact ──
        Face {
            active: root.mode === "clockMini"
            inset: root.actsInset

            MaterialIcon {
                id: miniIcon

                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: root.clockKind === "timer" ? "timer" : "timer_play"
                color: "#ff9f0a"
                fontStyle: Tokens.font.icon.size(14).build()
                fill: 1
                opacity: root.clockPaused > 0 ? 0.45 : 1
            }

            // Mini anneau de progression du minuteur, juste avant le temps restant
            Shape {
                id: miniRing

                anchors.right: miniTime.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                visible: root.clockKind === "timer"
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 3
                    strokeColor: "#ff9f0a"
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: 10
                        centerY: 10
                        radiusX: 8
                        radiusY: 8
                        startAngle: -90
                        sweepAngle: 360 * (root.clockTotal > 0 ? root.clockValue / root.clockTotal : 0)
                    }
                }
            }

            // Libellé coupé avec « … » ; il s'affiche en entier au survol
            StyledText {
                anchors.left: miniIcon.right
                anchors.leftMargin: 10
                anchors.right: miniRing.visible ? miniRing.left : miniTime.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: root.clockLabel !== ""
                text: root.clockLabel
                elide: Text.ElideRight
                color: root.fgDim
                font.pointSize: 9.5
                font.weight: Font.Medium
            }

            StyledText {
                id: miniTime

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtClock(root.clockValue)
                color: root.pomoOn && root.pomoPhase === "rest" ? root.green : "#ff9f0a"
                opacity: root.clockPaused > 0 ? 0.55 : 1
                font.pointSize: 12
                font.weight: Font.Bold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── minuteur / chronomètre au survol ──
        Face {
            active: root.mode === "clock"
            slide: root.pageSlide("clock")

            Column {
                x: 30
                y: 22
                width: clockButtons.x - x - 20

                // Libellé entier : sur deux lignes s'il ne tient pas sur une (au-delà « … »)
                StyledText {
                    id: clockTitle

                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: {
                        if (root.pomoOn)
                            return qsTr("Pomodoro · %1 · session %2").arg(root.clockLabel).arg(root.pomoRound);
                        if (root.clockKind === "timer")
                            return root.clockLabel ? qsTr("Minuteur · %1").arg(root.clockLabel) : qsTr("Minuteur");
                        return root.laps.length > 0 ? qsTr("Chronomètre · %1 tours").arg(root.laps.length) : qsTr("Chronomètre");
                    }
                    color: root.fgDim
                    font.pointSize: 9
                    font.weight: Font.Medium
                }
                StyledText {
                    text: root.fmtClock(root.clockValue)
                    color: root.pomoOn && root.pomoPhase === "rest" ? root.green : "#ff9f0a"
                    font.pointSize: 30
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Row {
                id: clockButtons

                anchors.right: parent.right
                anchors.rightMargin: 26
                y: 38
                spacing: 10

                ShotButton {
                    visible: root.clockKind === "timer"
                    icon: "exposure_plus_1"
                    onClicked: root.addMinute()
                }
                ShotButton {
                    visible: root.clockKind === "stopwatch"
                    icon: "flag"
                    onClicked: root.addLap()
                }
                ShotButton {
                    icon: root.clockPaused > 0 ? "play_arrow" : "pause"
                    onClicked: root.togglePause()
                }
                ShotButton {
                    icon: "stop"
                    onClicked: root.stopClock()
                }
                ShotButton {
                    icon: "open_in_new"
                    onClicked: root.openClockApp()
                }
            }
        }

        // ── minuteur terminé ──
        Face {
            active: root.mode === "done"

            Rectangle {
                id: doneIcon

                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                radius: 19
                color: Qt.alpha("#ff9f0a", 0.22)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "alarm"
                    color: "#ff9f0a"
                    fontStyle: Tokens.font.icon.size(17).build()
                    fill: 1
                }
            }

            StyledText {
                anchors.left: doneIcon.right
                anchors.leftMargin: 14
                anchors.right: doneSubText.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.doneTitle
                color: root.fg
                font.pointSize: 11
                font.weight: Font.DemiBold
            }

            StyledText {
                id: doneSubText

                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 120)
                elide: Text.ElideRight
                text: root.doneSub
                color: root.fgDim
                font.pointSize: 10
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── ça sonne : alarme, fin de minuteur, fin de phase pomodoro ──
        Face {
            id: ringFace

            active: root.mode === "alarm"

            readonly property color tint: root.ringKind === "pomoRest" ? root.green : root.ringKind === "pomoWork" ? "#5e9eff" : "#ff9f0a"
            readonly property bool isTimer: root.ringKind === "timer"
            readonly property bool isPomo: root.ringKind === "pomoWork" || root.ringKind === "pomoRest"

            // Lueur qui respire dans le verre, du côté de l'icône
            Rectangle {
                anchors.fill: parent
                radius: 32
                opacity: 0.55
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: Qt.alpha(ringFace.tint, 0.28)
                    }
                    GradientStop {
                        position: 0.55
                        color: "transparent"
                    }
                }

                SequentialAnimation on opacity {
                    running: root.mode === "alarm"
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.95
                        duration: 700
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0.35
                        duration: 900
                        easing.type: Easing.InOutSine
                    }
                }
            }

            Item {
                id: ringIconBox

                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                width: 54
                height: 54

                // Ondes qui partent de l'icône
                Repeater {
                    model: 3

                    Rectangle {
                        id: wave

                        required property int index

                        anchors.centerIn: parent
                        width: 54
                        height: 54
                        radius: 27
                        color: "transparent"
                        border.width: 2
                        border.color: ringFace.tint
                        opacity: 0

                        SequentialAnimation {
                            running: root.mode === "alarm"
                            loops: Animation.Infinite

                            PauseAnimation {
                                duration: wave.index * 520
                            }
                            ParallelAnimation {
                                NumberAnimation {
                                    target: wave
                                    property: "scale"
                                    from: 1
                                    to: 1.9
                                    duration: 1560
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: wave
                                    property: "opacity"
                                    from: 0.7
                                    to: 0
                                    duration: 1560
                                    easing.type: Easing.OutCubic
                                }
                            }
                            PauseAnimation {
                                duration: (2 - wave.index) * 520
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 27
                    color: ringFace.tint

                    MaterialIcon {
                        id: ringGlyph

                        anchors.centerIn: parent
                        text: ringFace.isTimer ? "timer" : root.ringKind === "pomoWork" ? "self_improvement" : root.ringKind === "pomoRest" ? "bolt" : "alarm"
                        color: "white"
                        fontStyle: Tokens.font.icon.size(24).build()
                        fill: 1

                        // Petite secousse de réveil
                        SequentialAnimation on rotation {
                            running: root.mode === "alarm"
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 16
                                duration: 70
                            }
                            NumberAnimation {
                                to: -16
                                duration: 140
                            }
                            NumberAnimation {
                                to: 12
                                duration: 120
                            }
                            NumberAnimation {
                                to: -8
                                duration: 100
                            }
                            NumberAnimation {
                                to: 0
                                duration: 80
                            }
                            PauseAnimation {
                                duration: 900
                            }
                        }
                    }
                }
            }

            Column {
                anchors.left: ringIconBox.right
                anchors.leftMargin: 18
                anchors.right: ringButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.ringKind === "alarm" ? root.alarmTime : root.alarmLabel
                    color: root.fg
                    font.pointSize: root.ringKind === "alarm" ? 22 : 15
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.ringKind === "alarm" ? root.alarmLabel : root.ringSub
                    color: root.fgDim
                    font.pointSize: 9.5
                }
                // Depuis combien de temps ça sonne (comme sur iPhone)
                StyledText {
                    text: qsTr("Sonne depuis %1").arg(root.fmtTime(root.ringElapsed))
                    color: ringFace.tint
                    font.pointSize: 8.5
                    font.weight: Font.DemiBold
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Row {
                id: ringButtons

                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Bouton secondaire : +1 min (minuteur), Répéter (alarme), Terminer (pomodoro)
                Rectangle {
                    visible: ringFace.isTimer
                    width: 44
                    height: 44
                    radius: 22
                    color: Qt.alpha(root.fg, plusArea.pressed ? 0.26 : plusArea.containsMouse ? 0.2 : 0.12)
                    scale: plusArea.pressed ? 0.92 : 1

                    StyledText {
                        anchors.centerIn: parent
                        text: "+1"
                        color: root.fg
                        font.pointSize: 11
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: plusArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.ringPlusOne()
                    }
                }
                Rectangle {
                    width: snoozeLbl.implicitWidth + 30
                    height: 44
                    radius: 22
                    color: Qt.alpha(root.fg, snoozeArea.pressed ? 0.26 : snoozeArea.containsMouse ? 0.2 : 0.12)
                    scale: snoozeArea.pressed ? 0.94 : 1

                    StyledText {
                        id: snoozeLbl

                        anchors.centerIn: parent
                        text: ringFace.isPomo ? qsTr("Terminer") : ringFace.isTimer ? qsTr("Relancer") : qsTr("Répéter")
                        color: root.fg
                        font.pointSize: 10
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: snoozeArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ringFace.isPomo ? root.stopRingAll() : root.snoozeAlarm()
                    }
                }
                // Bouton principal : Arrêter (ou Pause / Reprendre pour le pomodoro)
                Rectangle {
                    width: stopRow.implicitWidth + 32
                    height: 44
                    radius: 22
                    color: stopArea.containsMouse ? Qt.lighter(ringFace.tint, 1.12) : ringFace.tint
                    scale: stopArea.pressed ? 0.94 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                        }
                    }

                    Row {
                        id: stopRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ringKind === "pomoWork" ? "coffee" : root.ringKind === "pomoRest" ? "play_arrow" : "stop"
                            color: "white"
                            fontStyle: Tokens.font.icon.size(16).build()
                            fill: 1
                        }
                        StyledText {
                            id: stopLbl

                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ringKind === "pomoWork" ? qsTr("Pause") : root.ringKind === "pomoRest" ? qsTr("Reprendre") : qsTr("Arrêter")
                            color: "white"
                            font.pointSize: 10.5
                            font.weight: Font.Bold
                        }
                    }
                    MouseArea {
                        id: stopArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ringFace.isPomo ? root.ringNextPhase() : root.stopAlarm()
                    }
                }
            }
        }

        // ── Centre de notifications (clic sur l'île, Super + N) ──
        Face {
            active: root.mode === "center"

            Item {
                id: centerHead

                x: 22
                y: 16
                width: parent.width - 44
                height: 36

                Column {
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        text: qsTr("Notifications")
                        color: root.fg
                        font.pointSize: 13
                        font.weight: Font.Bold
                    }
                    StyledText {
                        text: Notifs.notClosed.length === 0 ? qsTr("Tout est lu") : Notifs.notClosed.length === 1 ? qsTr("1 notification") : qsTr("%1 notifications").arg(Notifs.notClosed.length)
                        color: root.fgDim
                        font.pointSize: 8.5
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Ne pas déranger
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Notifs.dnd ? root.accent : Qt.alpha(root.fg, dndArea.containsMouse ? 0.16 : 0.1)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: Notifs.dnd ? "do_not_disturb_on" : "do_not_disturb_off"
                            color: Notifs.dnd ? Colours.palette.m3onPrimary : root.fg
                            fontStyle: Tokens.font.icon.size(13).build()
                            fill: 1
                        }
                        MouseArea {
                            id: dndArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.dnd = !Notifs.dnd
                        }
                    }

                    // Tout effacer
                    Rectangle {
                        visible: Notifs.notClosed.length > 0
                        width: clearLbl.implicitWidth + 26
                        height: 34
                        radius: 17
                        color: Qt.alpha(root.fg, clearArea.containsMouse ? 0.16 : 0.1)

                        StyledText {
                            id: clearLbl

                            anchors.centerIn: parent
                            text: qsTr("Tout effacer")
                            color: root.fg
                            font.pointSize: 9
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: clearArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                for (const n of [...Notifs.notClosed])
                                    n.close();
                            }
                        }
                    }
                }
            }

            ListView {
                id: centerList

                x: 14
                anchors.top: centerHead.bottom
                anchors.topMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                width: parent.width - 28
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: Notifs.notClosed

                add: Transition {
                    NumberAnimation {
                        properties: "opacity"
                        from: 0
                        to: 1
                        duration: 250
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            to: 0
                            duration: 200
                        }
                        NumberAnimation {
                            property: "x"
                            to: 80
                            duration: 220
                            easing.type: Easing.InCubic
                        }
                    }
                }
                displaced: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Rectangle {
                    id: card

                    required property var modelData
                    readonly property string icon: modelData.appIcon ? Quickshell.iconPath(modelData.appIcon, true) : ""

                    width: centerList.width
                    height: cardBody.implicitHeight + 24
                    radius: 18
                    color: Qt.alpha(root.fg, cardArea.containsMouse ? 0.1 : 0.065)
                    border.width: 1
                    border.color: Qt.alpha(root.fg, 0.07)

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    // Icône de l'app ou image de la notification
                    Rectangle {
                        id: cardIcon

                        x: 12
                        y: 12
                        width: 38
                        height: 38
                        radius: 11
                        color: root.fgFaint
                        clip: true

                        Image {
                            id: cardImg

                            anchors.fill: parent
                            anchors.margins: card.modelData.image ? 0 : 6
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(76, 76)
                            source: card.modelData.image || card.icon
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: cardImg.status !== Image.Ready
                            text: "notifications"
                            color: root.fg
                            fontStyle: Tokens.font.icon.size(14).build()
                            fill: 1
                        }
                    }

                    Column {
                        id: cardBody

                        anchors.left: cardIcon.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        y: 11
                        spacing: 2

                        Item {
                            width: parent.width
                            height: cardApp.implicitHeight

                            StyledText {
                                id: cardApp

                                anchors.left: parent.left
                                anchors.right: cardTime.left
                                anchors.rightMargin: 8
                                elide: Text.ElideRight
                                text: card.modelData.appName || qsTr("Notification")
                                color: root.fgDim
                                font.pointSize: 8
                                font.weight: Font.Medium
                            }
                            StyledText {
                                id: cardTime

                                anchors.right: parent.right
                                anchors.rightMargin: cardArea.containsMouse ? 26 : 0
                                text: card.modelData.timeStr
                                color: root.fgDim
                                font.pointSize: 8

                                Behavior on anchors.rightMargin {
                                    NumberAnimation {
                                        duration: 150
                                    }
                                }
                            }
                        }
                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: card.modelData.summary
                            color: root.fg
                            font.pointSize: 9.5
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            width: parent.width
                            visible: text.length > 0
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: (card.modelData.body ?? "").replace(/<[^>]*>/g, "")
                            color: Qt.alpha(root.fg, 0.78)
                            font.pointSize: 8.5
                        }
                    }

                    MouseArea {
                        id: cardArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const n = card.modelData;
                            if (n.actions?.length > 0)
                                n.actions[0].invoke();
                            n.close();
                        }
                    }

                    // Fermer (au survol)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        y: 8
                        width: 22
                        height: 22
                        radius: 11
                        opacity: cardArea.containsMouse || xArea.containsMouse ? 1 : 0
                        color: Qt.alpha(root.fg, xArea.containsMouse ? 0.22 : 0.13)

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            color: root.fg
                            fontStyle: Tokens.font.icon.size(10).build()
                        }
                        MouseArea {
                            id: xArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.modelData.close()
                        }
                    }
                }

                // Rien à lire
                Column {
                    anchors.centerIn: parent
                    visible: centerList.count === 0
                    spacing: 6

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "notifications_paused"
                        color: root.fgDim
                        fontStyle: Tokens.font.icon.size(22).build()
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Aucune notification")
                        color: root.fgDim
                        font.pointSize: 9.5
                    }
                }
            }
        }

        // ── enregistrement, vue ouverte : chrono + pause / arrêter ──
        Face {
            active: root.mode === "recordFull"
            slide: root.pageSlide("recordFull")

            Rectangle {
                id: recFullDot

                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: root.red

                SequentialAnimation on opacity {
                    running: root.mode === "recordFull" && !Recorder.paused
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.3
                        duration: 700
                    }
                    NumberAnimation {
                        to: 1
                        duration: 700
                    }
                }
            }

            Column {
                anchors.left: recFullDot.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: root.fmtTime(Recorder.elapsed)
                    color: root.fg
                    font.pointSize: 18
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
                StyledText {
                    text: Recorder.paused ? qsTr("En pause") : qsTr("Enregistrement")
                    color: root.fgDim
                    font.pointSize: 8.5
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                ShotButton {
                    icon: Recorder.paused ? "play_arrow" : "pause"
                    onClicked: Recorder.togglePause()
                }
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: stopRecArea.containsMouse ? Qt.lighter("#ff453a", 1.1) : "#ff453a"
                    scale: stopRecArea.pressed ? 0.9 : 1

                    Rectangle {
                        anchors.centerIn: parent
                        width: 13
                        height: 13
                        radius: 3
                        color: "white"
                    }

                    MouseArea {
                        id: stopRecArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Recorder.stop()
                    }
                }
            }
        }

        // ── appel en cours (île ouverte) : qui, depuis quand, micro, retour à l'appel ──
        Face {
            active: root.mode === "callFull"
            slide: root.pageSlide("callFull")

            Rectangle {
                id: callBadge

                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48
                radius: 24
                color: Qt.alpha(root.callMuted ? root.red : root.green, 0.22)

                Behavior on color {
                    ColorAnimation {
                        duration: 250
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.camInUse ? "videocam" : "call"
                    color: root.callMuted ? root.red : root.green
                    fontStyle: Tokens.font.icon.size(20).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: callBadge.right
                anchors.leftMargin: 14
                anchors.right: callButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: callBadge.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.callTitle
                    color: root.fg
                    font.pointSize: 12
                    font.weight: Font.Bold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: `${root.fmtLong(root.callElapsed)} · ${root.callMuted ? qsTr("micro coupé") : root.camInUse ? qsTr("visio") : qsTr("appel")}${root.callWindow && root.callAppName && !root.callTitle.includes(root.callAppName) ? " · " + root.callAppName : ""}`
                    color: root.callMuted ? root.red : root.fgDim
                    font.pointSize: 9
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Row {
                id: callButtons

                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: callBadge.verticalCenter
                spacing: 10

                ShotButton {
                    visible: root.callWindow !== null
                    icon: "open_in_new"
                    tip: qsTr("Aller à l'appel")
                    onClicked: root.focusCall()
                }
                // Micro : rouge quand il est coupé
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: root.callMuted ? root.red : Qt.alpha(Colours.palette.m3onSurface, callMicArea.pressed ? 0.24 : callMicArea.containsMouse ? 0.17 : 0.1)
                    scale: callMicArea.pressed ? 0.9 : 1

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.callMuted ? "mic_off" : "mic"
                        color: root.callMuted ? "white" : root.fg
                        fontStyle: Tokens.font.icon.size(17).build()
                        fill: 1
                    }

                    MouseArea {
                        id: callMicArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleCallMic()
                    }
                }
            }
        }

        // ── compte à rebours avant l'enregistrement : gros chiffre qui pulse ──
        Face {
            active: root.mode === "count"

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: root.red
            }

            StyledText {
                id: countNum

                anchors.centerIn: parent
                text: root.countLeft
                color: root.fg
                font.pointSize: 32
                font.weight: Font.Bold
                font.features: {
                    "tnum": 1
                }
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("clic : annuler")
                color: root.fgDim
                font.pointSize: 7.5
            }
        }

        // ── fichier glissé au-dessus de l'île ──
        Face {
            active: root.mode === "drop"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 14
                anchors.topMargin: 12
                radius: 22
                color: Qt.alpha(root.accent, 0.1)
                border.width: 2
                border.color: Qt.alpha(root.accent, 0.6)

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "move_to_inbox"
                        color: root.accent
                        fontStyle: Tokens.font.icon.size(20).build()
                        fill: 1
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Déposer sur l'étagère")
                        color: root.fg
                        font.pointSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        // ── étagère (en bas des vues étendues) ──
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.shelfExtra
            visible: root.shelf.length > 0 && (root.mode === "player" || root.mode === "info" || root.mode === "clock")

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                height: 1
                color: root.fgFaint
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.right: clearShelf.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                clip: true

                Repeater {
                    model: root.shelf

                    ShelfTile {}
                }
            }

            ShotButton {
                id: clearShelf

                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                icon: "delete_sweep"
                onClicked: Island.shelf = []
            }
        }

        // ── notification ──
        Face {
            active: root.mode === "notif"

            Rectangle {
                id: notifIconBox

                x: 22
                y: 22
                width: 48
                height: 48
                radius: 14
                color: root.fgFaint
                clip: true

                Image {
                    id: notifImg

                    anchors.fill: parent
                    anchors.margins: root.notif?.image ? 0 : 8
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(96, 96)
                    source: root.notif?.image || (root.notif?.appIcon ? Quickshell.iconPath(root.notif.appIcon, true) : "")
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: notifImg.status !== Image.Ready
                    text: "notifications"
                    color: root.fg
                    fontStyle: Tokens.font.icon.size(16).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: notifIconBox.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: notifIconBox.verticalCenter
                spacing: 1

                Item {
                    width: parent.width
                    height: appLbl.height

                    StyledText {
                        id: appLbl

                        anchors.left: parent.left
                        anchors.right: moreLbl.left
                        elide: Text.ElideRight
                        text: root.notif?.appName ?? ""
                        color: root.fgDim
                        font.pointSize: 8
                        font.weight: Font.Medium
                    }
                    StyledText {
                        id: moreLbl

                        anchors.right: parent.right
                        text: root.queue.length > 0 ? `+${root.queue.length}` : qsTr("maintenant")
                        color: root.queue.length > 0 ? root.accent : root.fgDim
                        font.pointSize: 8
                        font.weight: Font.Medium
                    }
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.notif?.summary ?? ""
                    color: root.fg
                    font.pointSize: 10
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    text: (root.notif?.body ?? "").replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                    color: Qt.alpha(root.fg, 0.78)
                    font.pointSize: 9
                }
            }

            // Actions au survol
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 88
                spacing: 8
                opacity: root.hovered && root.notifHasActions ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Repeater {
                    model: root.notifButtons

                    Rectangle {
                        id: act

                        required property var modelData

                        width: Math.min(150, Math.max(90, actLbl.implicitWidth + 28))
                        height: 30
                        radius: 15
                        color: actArea.containsMouse ? Qt.alpha(root.fg, 0.2) : Qt.alpha(root.fg, 0.1)

                        StyledText {
                            id: actLbl

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, act.width - 24)
                            elide: Text.ElideRight
                            text: act.modelData.text
                            color: root.fg
                            font.pointSize: 9
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: actArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                act.modelData.invoke();
                                pulseTimer.stop();
                                root.pulse = "";
                                root.showNext();
                            }
                        }
                    }
                }
            }
        }

        // ── page Infos : heure, date, météo détaillée, batterie + pastilles d'état ──
        Face {
            active: root.mode === "info"
            slide: root.pageSlide("info")

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 30
                y: 24

                StyledText {
                    text: Time.format("HH:mm")
                    color: root.fg
                    font.pointSize: 26
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
                StyledText {
                    text: {
                        const s = Qt.locale("fr_FR").toString(Time.date, "dddd d MMMM");
                        return s.charAt(0).toUpperCase() + s.slice(1);
                    }
                    color: root.fgDim
                    font.pointSize: 9
                    font.weight: Font.Medium
                }
            }

            // Météo détaillée + batterie
            Column {
                anchors.right: parent.right
                anchors.rightMargin: 30
                y: 22
                spacing: 3

                Row {
                    anchors.right: parent.right
                    spacing: 7

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.icon
                        color: root.accent
                        fontStyle: Tokens.font.icon.size(18).build()
                        fill: 1
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.cc ? Weather.temp : "—"
                        color: root.fg
                        font.pointSize: 17
                        font.weight: Font.Bold
                    }
                }
                StyledText {
                    anchors.right: parent.right
                    visible: !!Weather.cc
                    text: Weather.description
                    color: root.fgDim
                    font.pointSize: 8.5
                    font.weight: Font.Medium
                }
                Row {
                    anchors.right: parent.right
                    spacing: 10

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!Weather.cc
                        text: qsTr("Ressenti %1 · %2 %").arg(Weather.feelsLike).arg(Weather.humidity)
                        color: root.fgDim
                        font.pointSize: 8
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        visible: UPower.displayDevice.isLaptopBattery

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${Math.round(root.battery * 100)} %`
                            color: root.battCharging ? root.green : root.battery < 0.2 ? root.red : root.fgDim
                            font.pointSize: 8.5
                            font.weight: Font.DemiBold
                        }
                        BatteryGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            pct: root.battery
                            charging: root.battCharging
                        }
                    }
                }
            }

            // Pastilles d'état : alarme, Bluetooth, caféine, nuit, tâches…
            Flow {
                id: infoFlow

                x: 26
                y: 92
                width: parent.width - 52
                spacing: 6

                add: Transition {
                    NumberAnimation {
                        property: "scale"
                        from: 0.6
                        to: 1
                        duration: 320
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 220
                    }
                }
                move: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: 280
                        easing.type: Easing.OutCubic
                    }
                }

                Repeater {
                    model: root.infoChips

                    Rectangle {
                        id: chip

                        required property var modelData

                        width: Math.min(chipRow.implicitWidth + 20, infoFlow.width)
                        height: 26
                        radius: 13
                        color: Qt.alpha(chip.modelData.tint, 0.14)
                        border.width: 1
                        border.color: Qt.alpha(chip.modelData.tint, 0.22)

                        Row {
                            id: chipRow

                            anchors.verticalCenter: parent.verticalCenter
                            x: 9
                            spacing: 5

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.icon
                                color: chip.modelData.tint
                                fontStyle: Tokens.font.icon.size(12).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, infoFlow.width - 50)
                                elide: Text.ElideRight
                                text: chip.modelData.text
                                color: root.fg
                                font.pointSize: 8.5
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }
            }
        }

        // ── performances en direct : CPU, RAM, disque, réseau ──
        Face {
            active: root.mode === "perf"
            slide: root.pageSlide("perf")

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -3
                spacing: 8

                PerfRing {
                    icon: "memory"
                    label: "CPU"
                    value: Cpu.percentage
                    sub: root.cpuGhz > 0 ? `${root.cpuGhz.toFixed(1).replace(".", ",")} GHz` : ""
                }
                // Température en direct : bleu au calme, orange vers 71 °C, rouge vers 86 °C
                PerfRing {
                    icon: Cpu.temperature >= 86 ? "local_fire_department" : "device_thermostat"
                    label: qsTr("Temp.")
                    value: Math.max(0, Math.min(1, (Cpu.temperature - 35) / 60))
                    centerText: Cpu.temperature > 0 ? `${Math.round(Cpu.temperature)}°` : "—"
                    sub: root.fanRpm > 0 ? qsTr("Ventilo %1").arg(root.fanRpm) : root.fanRpm === 0 ? qsTr("Ventilo arrêté") : root.tempPeak > 0 ? qsTr("Max %1°").arg(Math.round(root.tempPeak)) : ""
                }
                PerfRing {
                    icon: "memory_alt"
                    label: "RAM"
                    value: Memory.percentage
                    sub: root.kibText(Memory.used, Memory.total)
                }
                PerfRing {
                    icon: "hard_drive"
                    label: "Disque"
                    value: Storage.primaryDisk?.perc ?? 0
                    sub: Storage.primaryDisk ? root.freeText(Storage.primaryDisk.total - Storage.primaryDisk.used) : ""
                }
            }

            // Réseau : débit descendant / montant + courbe
            Item {
                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -3
                width: 140
                height: 90

                Rectangle {
                    anchors.fill: parent
                    radius: 18
                    color: Qt.alpha(root.fg, 0.06)
                    border.width: 1
                    border.color: Qt.alpha(root.fg, 0.08)
                }

                SparklineItem {
                    id: netSpark

                    property real targetMax: 1024
                    property real smoothMax: targetMax

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    height: 34
                    line1: NetworkUsage.uploadBuffer // qmllint disable missing-type
                    line1Color: Colours.palette.m3secondary
                    line1FillAlpha: 0.12
                    line2: NetworkUsage.downloadBuffer // qmllint disable missing-type
                    line2Color: Colours.palette.m3tertiary
                    line2FillAlpha: 0.22
                    maxValue: smoothMax
                    historyLength: NetworkUsage.historyLength

                    Connections {
                        function onValuesChanged(): void {
                            netSpark.targetMax = Math.max(NetworkUsage.downloadBuffer.maximum, NetworkUsage.uploadBuffer.maximum, 1024);
                            netSlide.restart();
                        }

                        target: NetworkUsage.downloadBuffer
                    }

                    NumberAnimation {
                        id: netSlide

                        target: netSpark
                        property: "slideProgress"
                        from: 0
                        to: 1
                        duration: GlobalConfig.dashboard.resourceUpdateInterval
                    }

                    Behavior on smoothMax {
                        NumberAnimation {
                            duration: 600
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.topMargin: 9
                    spacing: 1

                    NetLine {
                        icon: "south"
                        tint: Colours.palette.m3tertiary
                        speed: NetworkUsage.downloadSpeed
                        big: true
                    }
                    NetLine {
                        icon: "north"
                        tint: Colours.palette.m3secondary
                        speed: NetworkUsage.uploadSpeed
                    }
                }
            }
        }

        // Points de page (heure ↔ performances) : la pastille active s'allonge
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            spacing: 5
            opacity: root.paged && root.shelf.length === 0 ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                }
            }

            Repeater {
                model: root.pages.length

                Rectangle {
                    required property int index
                    readonly property bool current: root.pageIndex === index

                    anchors.verticalCenter: parent.verticalCenter
                    width: current ? 16 : 5
                    height: 5
                    radius: 2.5
                    color: current ? Qt.alpha(root.fg, 0.85) : Qt.alpha(root.fg, 0.28)

                    Behavior on width {
                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.6
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 300
                        }
                    }

                    TapHandler {
                        margin: 6
                        onTapped: root.flipPage(parent.index - root.pageIndex)
                    }
                }
            }
        }

        // ── lecteur complet ──
        Face {
            active: root.mode === "player"
            slide: root.pageSlide("player")

            Cover {
                id: bigCover

                x: 26
                y: 26
                size: 66
                radius: 15
            }

            Column {
                anchors.left: bigCover.right
                anchors.leftMargin: 14
                anchors.right: bigBars.left
                anchors.rightMargin: 12
                anchors.verticalCenter: bigCover.verticalCenter
                spacing: 2

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackTitle ?? ""
                    color: root.fg
                    font.pointSize: 11
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackArtist || Players.getIdentity(root.player)
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            LyricLine {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                y: 102
                visible: root.hasLyrics
                line: root.lyricLine
                lineColor: root.accent
                size: 10.5
                bold: true
            }

            Bars {
                id: bigBars

                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: bigCover.verticalCenter
                count: 6
                barWidth: 3
                maxHeight: 22
            }

            Item {
                id: progress

                readonly property real len: root.player?.length ?? 0
                readonly property real pos: root.player?.position ?? 0
                readonly property bool known: len > 0 && len < 2147483

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                y: root.hasLyrics ? 130 : 104
                height: 16

                StyledText {
                    id: posText

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    text: root.fmtTime(progress.pos)
                    color: root.fgDim
                    font.pointSize: 7.5
                    font.features: {
                        "tnum": 1
                    }
                }

                Rectangle {
                    id: seekTrack

                    anchors.left: posText.right
                    anchors.right: lenText.left
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: seekArea.containsMouse ? 8 : 5
                    radius: height / 2
                    color: root.fgFaint

                    Behavior on height {
                        NumberAnimation {
                            duration: 150
                        }
                    }

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width: progress.known ? parent.width * Math.min(1, progress.pos / progress.len) : 0
                        color: root.fg
                    }

                    MouseArea {
                        id: seekArea

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        enabled: progress.known && (root.player?.canSeek ?? false)
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: e => {
                            const ratio = Math.max(0, Math.min(1, (e.x - 6) / seekTrack.width));
                            root.player.position = ratio * progress.len;
                        }
                    }
                }

                StyledText {
                    id: lenText

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    horizontalAlignment: Text.AlignRight
                    text: progress.known ? root.fmtTime(progress.len) : ""
                    color: root.fgDim
                    font.pointSize: 7.5
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.hasLyrics ? 154 : 128
                spacing: 28

                IslandButton {
                    icon: "skip_previous"
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.player?.previous()
                }
                IslandButton {
                    icon: root.playing ? "pause" : "play_arrow"
                    big: true
                    enabled: root.player?.canTogglePlaying ?? false
                    onClicked: root.player?.togglePlaying()
                }
                IslandButton {
                    icon: "skip_next"
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player?.next()
                }
            }
        }
    }

    // ════════════════════ Composants ════════════════════

    // Une vue de l'île : l'ancienne s'efface vite, la nouvelle attend que l'île ait
    // commencé à s'ouvrir puis apparaît en fondu avec un léger zoom (pas de saut brutal)
    function kibText(used: real, total: real): string {
        if (!(total > 0))
            return "";
        const f = UsageFmt.formatKib(used, total);
        const unit = f.unit.replace("GiB", "Go").replace("MiB", "Mo").replace("TiB", "To");
        return `${+f.value.toFixed(1)}/${Math.round(f.total)} ${unit}`;
    }

    // Espace libre lisible : « 46,9 Go libres »
    function freeText(kib: real): string {
        if (!(kib > 0))
            return "plein";
        const gib = kib / 1048576;
        const v = gib >= 1024 ? `${(gib / 1024).toFixed(1)} To` : gib >= 100 ? `${Math.round(gib)} Go` : `${gib.toFixed(1)} Go`;
        return `${v.replace(".", ",")} libres`;
    }

    // Anneau de jauge animé (couleur qui chauffe avec la charge)
    component PerfRing: Column {
        id: ring

        property string icon
        property string label
        property string sub
        property string centerText
        property real value
        property real shown: value
        readonly property color tint: shown > 0.85 ? root.red : shown > 0.6 ? (Colours.light ? "#c77700" : "#ff9f0a") : root.accent

        spacing: 2
        width: 80

        Behavior on shown {
            NumberAnimation {
                duration: 700
                easing.type: Easing.OutCubic
            }
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 56
            height: 56

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.alpha(root.fg, 0.1)
                    strokeWidth: 5
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: 28
                        centerY: 28
                        radiusX: 25
                        radiusY: 25
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: ring.tint
                    strokeWidth: 5
                    capStyle: ShapePath.RoundCap

                    Behavior on strokeColor {
                        ColorAnimation {
                            duration: 500
                        }
                    }

                    PathAngleArc {
                        centerX: 28
                        centerY: 28
                        radiusX: 25
                        radiusY: 25
                        startAngle: -90
                        sweepAngle: Math.max(0.01, Math.min(1, ring.shown)) * 360
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: -2

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ring.icon
                    color: root.fgDim
                    fontStyle: Tokens.font.icon.size(10).build()
                    fill: 1
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ring.centerText || Math.round(ring.shown * 100) + "%"
                    color: root.fg
                    font.pointSize: 10.5
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ring.label
            color: root.fg
            font.pointSize: 8
            font.weight: Font.DemiBold
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: -3
            width: Math.min(implicitWidth, ring.width)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: ring.sub
            visible: text !== ""
            color: root.fgDim
            font.pointSize: 7
            font.weight: Font.Medium
            font.features: {
                "tnum": 1
            }
        }
    }

    // Ligne de débit réseau (valeur lissée pour un défilement fluide)
    component NetLine: Row {
        id: nl

        property string icon
        property color tint
        property real speed
        property real shown: speed
        property bool big

        spacing: 4

        Behavior on shown {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutCubic
            }
        }

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: nl.icon
            color: nl.tint
            fontStyle: Tokens.font.icon.size(nl.big ? 12 : 10).build()
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const f = NetworkUsage.formatBytes(nl.shown);
                const unit = f.unit.replace("KB/s", "Ko/s").replace("MB/s", "Mo/s").replace("GB/s", "Go/s").replace("B/s", "o/s");
                return `${f.value.toFixed(f.value < 10 ? 1 : 0)} ${unit}`;
            }
            color: nl.big ? root.fg : root.fgDim
            font.pointSize: nl.big ? 12 : 9
            font.weight: nl.big ? Font.Bold : Font.DemiBold
            font.features: {
                "tnum": 1
            }
        }
    }

    component Face: Item {
        id: face

        property bool active
        property real slide // décalage de sortie (pages qu'on fait glisser)
        property real inset // place laissée à droite (icônes des autres activités)

        transform: Translate {
            x: face.active ? 0 : face.slide

            Behavior on x {
                NumberAnimation {
                    duration: 480
                    easing.type: Easing.OutCubic
                }
            }
        }

        anchors.fill: parent
        anchors.rightMargin: inset
        opacity: active ? 1 : 0
        scale: active ? 1 : 0.95
        visible: opacity > 0.01
        enabled: active

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation {
                    duration: face.active ? 70 : 0
                }
                NumberAnimation {
                    duration: face.active ? 340 : 150
                    easing.type: face.active ? Easing.OutCubic : Easing.InCubic
                }
            }
        }
        Behavior on scale {
            SequentialAnimation {
                PauseAnimation {
                    duration: face.active ? 70 : 0
                }
                NumberAnimation {
                    duration: face.active ? 520 : 150
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    component Cover: Rectangle {
        property real size: 22

        width: size
        height: size
        color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
        clip: true

        Image {
            id: coverImg

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(parent.size * 2, parent.size * 2)
            source: Players.getArtUrl(Players.active)
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: coverImg.status !== Image.Ready
            text: "music_note"
            color: Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.size(parent.size / 2.6).build()
            fill: 1
        }
    }

    component Bars: Row {
        id: bars

        property int count: 5
        property real barWidth: 3
        property real maxHeight: 16

        spacing: 2.5
        height: maxHeight

        Repeater {
            model: bars.count

            Rectangle {
                required property int index
                readonly property int total: Audio.cava.values.length
                readonly property real v: {
                    if (!(Players.active?.isPlaying ?? false) || total === 0)
                        return 0.15;
                    const i = Math.floor((index + 0.5) / bars.count * total);
                    return Math.max(0.15, Math.min(1, Audio.cava.values[i] ?? 0));
                }

                anchors.verticalCenter: parent.verticalCenter
                width: bars.barWidth
                height: Math.max(bars.barWidth, bars.maxHeight * v)
                radius: bars.barWidth / 2
                color: Colours.palette.m3primary

                Behavior on height {
                    NumberAnimation {
                        duration: 90
                    }
                }
            }
        }
    }

    // Batterie façon barre de menus macOS, identique au repos et dans l'île ouverte :
    // niveau réel, vert + éclair en charge, prise quand c'est branché et plein, rouge sous 20 %
    component BatteryGlyph: Item {
        id: glyph

        // Niveau réel (0-1) et charge en cours, fournis par l'île
        property real pct: UPower.displayDevice.percentage ?? 0
        property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging
        readonly property color fg: Colours.palette.m3onSurface
        // Blanc (pleine ou normale) · vert en charge · rouge quand elle est presque vide
        readonly property color fillColour: charging ? (Colours.light ? "#1f9d3a" : "#32d74b") : pct < 0.2 ? "#ff453a" : fg

        width: 26
        height: 12

        Rectangle {
            id: glyphShell

            width: 23
            height: 12
            radius: 3.5
            color: "transparent"
            border.width: 1.2
            border.color: Qt.alpha(glyph.fg, 0.5)

            // Jauge au pixel près (largeur fractionnaire, lissée)
            Rectangle {
                x: 2
                y: 2
                height: parent.height - 4
                width: Math.max(1.5, (parent.width - 4) * Math.max(0, Math.min(1, glyph.pct)))
                radius: 2
                antialiasing: true
                color: glyph.fillColour

                Behavior on width {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 300
                    }
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: glyph.charging
                text: "bolt"
                color: "white"
                style: Text.Outline
                styleColor: Qt.alpha("black", 0.3)
                fontStyle: Tokens.font.icon.size(8).build()
                fill: 1
            }
        }

        Rectangle {
            x: 24
            y: 4
            width: 2
            height: 4
            radius: 1
            color: Qt.alpha(glyph.fg, 0.5)
        }
    }

    // Icône d'état de l'île au repos : entre et sort en douceur (largeur + fondu + petit zoom)
    component IdleIcon: Item {
        id: ii

        property bool shown
        property string icon
        property color tint

        anchors.verticalCenter: parent?.verticalCenter
        width: shown ? 15 : 0
        height: 16
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.6
        visible: opacity > 0.01

        Behavior on width {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 260
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: ii.icon
            color: ii.tint
            fontStyle: Tokens.font.icon.size(13).build()
            fill: 1
        }
    }

    component PrivacyDot: Rectangle {
        property color dotColor

        anchors.verticalCenter: parent?.verticalCenter
        width: 7
        height: 7
        radius: 3.5
        color: dotColor

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 2.4
            height: width
            radius: width / 2
            color: parent.dotColor
            opacity: 0.25
        }
    }

    // Ligne de texte qui change avec un fondu + glissement vers le haut (paroles)
    component LyricLine: Item {
        id: ll

        property string line
        property color lineColor
        property real size: 10
        property bool bold

        implicitHeight: shown.implicitHeight
        height: implicitHeight
        clip: false

        onLineChanged: swapAnim.restart()

        StyledText {
            id: shown

            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: ll.lineColor
            font.pointSize: ll.size
            font.weight: ll.bold ? Font.DemiBold : Font.Medium
            Component.onCompleted: text = ll.line
        }

        SequentialAnimation {
            id: swapAnim

            ParallelAnimation {
                NumberAnimation {
                    target: shown
                    property: "opacity"
                    to: 0
                    duration: 120
                }
                NumberAnimation {
                    target: shown
                    property: "y"
                    to: -6
                    duration: 120
                }
            }
            ScriptAction {
                script: {
                    shown.text = ll.line;
                    shown.y = 8;
                }
            }
            ParallelAnimation {
                NumberAnimation {
                    target: shown
                    property: "opacity"
                    to: 1
                    duration: 260
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: shown
                    property: "y"
                    to: 0
                    duration: 320
                    easing.type: Easing.OutBack
                }
            }
        }
    }

    // Fichier de l'étagère : clic = ouvrir, glisser = le déposer ailleurs
    component ShelfTile: Item {
        id: tile

        required property string modelData
        readonly property string path: decodeURIComponent(modelData.replace(/^file:\/\//, ""))
        readonly property string fileName: path.split("/").pop()
        readonly property bool isImage: /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(path)

        width: 58
        height: 58

        Drag.active: tileDrag.active
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.mimeData: {
            "text/uri-list": tile.modelData + "\r\n"
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.alpha(Colours.palette.m3onSurface, tileArea.containsMouse ? 0.16 : 0.08)
            clip: true

            Image {
                anchors.fill: parent
                visible: tile.isImage
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(116, 116)
                source: tile.isImage ? tile.modelData : ""
            }

            Column {
                anchors.centerIn: parent
                visible: !tile.isImage
                spacing: 1

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: /\.(pdf)$/i.test(tile.path) ? "picture_as_pdf" : /\.(mp3|flac|ogg|wav|m4a|opus)$/i.test(tile.path) ? "music_note" : /\.(mp4|mkv|webm|mov)$/i.test(tile.path) ? "movie" : /\.(zip|tar|gz|xz|7z|rar)$/i.test(tile.path) ? "folder_zip" : "description"
                    color: Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.size(16).build()
                    fill: 1
                }
                StyledText {
                    width: 52
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: tile.fileName
                    color: Colours.palette.m3onSurface
                    font.pointSize: 6.5
                }
            }
        }

        DragHandler {
            id: tileDrag

            target: null
        }

        MouseArea {
            id: tileArea

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: e => {
                if (e.button === Qt.MiddleButton) {
                    Island.removeFromShelf(tile.modelData);
                } else {
                    Quickshell.execDetached(["xdg-open", tile.path]);
                }
            }
        }
    }

    component ShotButton: Rectangle {
        id: sb

        property string icon
        property string tip
        signal clicked

        width: 40
        height: 40
        radius: 20
        color: Qt.alpha(Colours.palette.m3onSurface, sbArea.pressed ? 0.24 : sbArea.containsMouse ? 0.17 : 0.1)
        scale: sbArea.pressed ? 0.9 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutBack
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: sb.icon
            color: Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.size(15).build()
            fill: 1
        }

        MouseArea {
            id: sbArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sb.clicked()
        }
    }

    component IslandButton: Item {
        id: btn

        property string icon
        property bool big
        signal clicked

        width: big ? 36 : 30
        height: width
        opacity: enabled ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colours.palette.m3onSurface
            opacity: area.pressed ? 0.18 : area.containsMouse ? 0.1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: btn.icon
            color: Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.size(btn.big ? 18 : 14).build()
            fill: 1
            scale: area.pressed ? 0.85 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutBack
                }
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}

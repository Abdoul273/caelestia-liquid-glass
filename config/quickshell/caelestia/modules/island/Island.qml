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
    readonly property real battery: UPower.displayDevice.percentage ?? 0
    readonly property bool charging: !UPower.onBattery
    // Batterie au repos : icône toujours (sur portable), pourcentage seulement faible ou en charge
    readonly property bool showBattery: Island.battery && UPower.displayDevice.isLaptopBattery
    readonly property bool batteryPctShown: charging && battery < 0.995 || battery < 0.2

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
        for (const w of Hypr.workspaces.values)
            if (w.id > max && w.monitor?.name === hyprMon?.name)
                max = w.id;
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
        Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]);
        if (pomoOn) {
            // Pomodoro : on enchaîne tout seul sur la phase suivante
            if (pomoPhase === "work") {
                pomoPhase = "rest";
                doneTitle = qsTr("Focus terminé");
                doneSub = qsTr("Pause de %1").arg(fmtClock(pomoRest));
                startTimer(pomoRest, qsTr("Pause"));
            } else {
                pomoPhase = "work";
                pomoRound += 1;
                doneTitle = qsTr("Pause terminée");
                doneSub = qsTr("Session %1").arg(pomoRound);
                startTimer(pomoWork, qsTr("Focus"));
            }
            flash("done", 4500);
            return;
        }
        doneTitle = label ? qsTr("%1 : terminé").arg(label) : qsTr("Minuteur terminé");
        doneSub = fmtClock(total);
        saveClock();
        flash("done", 8000);
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
            alarm: alarmRinging ? alarmLabel : null
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

    function ringAlarm(label: string, hm: string): void {
        alarmLabel = label;
        alarmTime = hm;
        alarmRinging = true;
        saveClock();
        flash("alarm", 5 * 60 * 1000);
    }

    function stopAlarm(): void {
        alarmRinging = false;
        saveClock();
        if (pulse === "alarm") {
            pulseTimer.stop();
            pulse = "";
            if (queue.length > 0)
                showNext();
        }
    }

    function snoozeAlarm(): void {
        const label = alarmLabel;
        stopAlarm();
        startTimer(9 * 60, qsTr("%1 (répétition)").arg(label));
    }

    // Sonnerie qui se répète tant que l'alarme n'est pas arrêtée
    Timer {
        running: root.alarmRinging
        interval: 2600
        repeat: true
        triggeredOnStart: true
        onTriggered: Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
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

    function stopClock(): void {
        clockKind = "";
        clockPaused = 0;
        clockLabel = "";
        pomoOn = false;
        laps = [];
        saveClock();
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
        if (expanded && Recorder.running)
            return "recordFull";
        if (expanded)
            return clockKind !== "" && !hasMedia ? "clock" : hasMedia ? "player" : "info";
        if (Recorder.running)
            return "record";
        if (clockKind !== "")
            return "clockMini";
        if (hasMedia && playing)
            return "media";
        return "idle";
    }

    readonly property bool notifHasActions: (notif?.actions?.length ?? 0) > 0
    readonly property real shelfExtra: shelf.length > 0 ? 78 : 0

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
            return Qt.size(360, 76);
        case "count":
            return Qt.size(200, 86);
        case "drop":
            return Qt.size(420, 110);
        case "toast":
            return Qt.size(400, toastData?.message ? 76 : 52);
        case "done":
            return Qt.size(380, 68);
        case "alarm":
            return Qt.size(430, 96);
        case "blip":
            return Qt.size(blipSub ? 320 : 280, 44);
        case "ws":
            return Qt.size(Math.max(250, 150 + wsLast * 18), 44);
        case "clock":
            return Qt.size(360, 118 + shelfExtra);
        case "clockMini":
            return Qt.size(clockLabel ? 290 : 230, 40);
        case "shot":
            return Qt.size(460, 100);
        case "bt":
            return btOn ? Qt.size(400, 76) : Qt.size(330, 48);
        case "charge":
            return chargePlugged ? Qt.size(420, 78) : Qt.size(330, 48);
        case "player":
            return Qt.size(450, (hasLyrics ? 202 : 178) + shelfExtra);
        case "info":
            return Qt.size(390, 118 + shelfExtra);
        case "record":
            return Qt.size(210, 40);
        case "media":
            return Qt.size(hasLyrics ? 400 : 290, 40);
        default:
            // Au repos : juste l'heure (ou rien si Island.clock est coupé)
            return Island.clock ? Qt.size(240 + (showBattery ? 34 : 0) + (showBattery && batteryPctShown ? 42 : 0) + (micInUse || camInUse ? 24 : 0) + (shelf.length > 0 ? 34 : 0), 40) : Qt.size(150, 0);
        }
    }

    property real w: target.width
    property real h: target.height
    readonly property real radius: Math.min(h / 2, mode === "player" || mode === "info" || mode === "notif" || mode === "bt" || mode === "shot" || mode === "clock" || mode === "drop" || mode === "toast" || mode === "done" || mode === "alarm" || mode === "count" || mode === "recordFull" || mode === "center" || (mode === "charge" && chargePlugged) ? 32 : h / 2)

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

        interval: 350
        onTriggered: {
            root.wheelX = 0;
            root.wheelY = 0;
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: e => {
            // Dans le centre de notifications, la molette fait défiler la liste
            if (root.mode === "center")
                return;
            const media = root.mode === "media" || root.mode === "player";
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
    }

    DragHandler {
        id: dragH

        target: null
        xAxis.enabled: root.mode === "media" || root.mode === "player"
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
            if (xAxis.enabled && Math.abs(translation.x) > 70)
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
            } else if (root.mode === "idle" || root.mode === "info") {
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

        // ── repos : date à gauche, heure à droite, comme de part et d'autre d'une encoche ──
        Face {
            active: root.mode === "idle"

            StyledText {
                id: idleDate

                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const s = Qt.locale("fr_FR").toString(Time.date, "ddd d");
                    return s.charAt(0).toUpperCase() + s.slice(1);
                }
                color: root.fgDim
                font.pointSize: 10.5
                font.weight: Font.Medium
            }

            // Après la date : notifications non lues (accent), micro (orange), caméra (vert), étagère
            Row {
                anchors.left: idleDate.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notifs.notClosed.length > 0 && !root.micInUse && !root.camInUse
                    width: 6
                    height: 6
                    radius: 3
                    color: root.accent
                    opacity: 0.9
                }
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
                    width: shelfCount.implicitWidth + 16
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
            }

            // À droite : batterie (façon barre de menus macOS) puis l'heure
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showBattery && root.batteryPctShown
                    text: `${Math.round(root.battery * 100)} %`
                    color: root.charging ? root.green : root.battery < 0.2 ? root.red : root.fgDim
                    font.pointSize: 9
                    font.weight: Font.DemiBold
                    font.features: {
                        "tnum": 1
                    }
                }

                // Icône de batterie : se vide selon le niveau, éclair en charge, pulse sous 10 %
                Item {
                    id: idleBatt

                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showBattery
                    width: 25
                    height: 12

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

                    Rectangle {
                        id: battShell

                        width: 22
                        height: 12
                        radius: 3.5
                        color: "transparent"
                        border.width: 1.2
                        border.color: Qt.alpha(root.fg, 0.55)

                        Rectangle {
                            x: 2
                            y: 2
                            height: parent.height - 4
                            width: Math.max(2, (parent.width - 4) * root.battery)
                            radius: 1.8
                            color: root.charging ? root.green : root.battery < 0.2 ? root.red : root.fg

                            Behavior on width {
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: root.charging
                            text: "bolt"
                            color: "white"
                            style: Text.Outline
                            styleColor: Qt.alpha("black", 0.35)
                            fontStyle: Tokens.font.icon.size(8).build()
                            fill: 1
                        }
                    }

                    Rectangle {
                        anchors.left: battShell.right
                        anchors.leftMargin: 1
                        anchors.verticalCenter: battShell.verticalCenter
                        width: 2
                        height: 4
                        radius: 1
                        color: Qt.alpha(root.fg, 0.55)
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Time.format("HH:mm")
                    color: root.fg
                    font.pointSize: 14
                    font.weight: Font.Bold
                    font.letterSpacing: 0.3
                    font.features: {
                        "tnum": 1
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

        // ── enregistrement ──
        Face {
            active: root.mode === "record"

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
                text: root.blipSub
                color: root.blipOn ? root.green : root.fgDim
                font.pointSize: 9
                font.weight: Font.Medium
            }
        }

        // ── minuteur / chronomètre compact ──
        Face {
            active: root.mode === "clockMini"

            MaterialIcon {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: root.clockKind === "timer" ? "timer" : "timer_play"
                color: "#ff9f0a"
                fontStyle: Tokens.font.icon.size(14).build()
                fill: 1
                opacity: root.clockPaused > 0 ? 0.45 : 1
            }

            // Mini anneau de progression du minuteur
            Shape {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.clockLabel ? 30 : 0
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

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: 44
                anchors.verticalCenter: parent.verticalCenter
                visible: root.clockLabel !== ""
                text: root.clockLabel
                color: root.fgDim
                font.pointSize: 9.5
                font.weight: Font.Medium
            }

            StyledText {
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

            Column {
                x: 30
                y: 22

                StyledText {
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
                anchors.verticalCenter: parent.verticalCenter
                text: root.doneTitle
                color: root.fg
                font.pointSize: 11
                font.weight: Font.DemiBold
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                text: root.doneSub
                color: root.fgDim
                font.pointSize: 10
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── alarme qui sonne ──
        Face {
            active: root.mode === "alarm"

            Rectangle {
                id: alarmIcon

                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48
                radius: 24
                color: Qt.alpha("#ff9f0a", 0.22)

                SequentialAnimation on scale {
                    running: root.mode === "alarm"
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 1.12
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        to: 1
                        duration: 520
                        easing.type: Easing.InOutQuad
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "alarm"
                    color: "#ff9f0a"
                    fontStyle: Tokens.font.icon.size(20).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: alarmIcon.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: root.alarmTime
                    color: root.fg
                    font.pointSize: 20
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
                StyledText {
                    text: root.alarmLabel
                    color: root.fgDim
                    font.pointSize: 9.5
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Rectangle {
                    width: snoozeLbl.implicitWidth + 28
                    height: 38
                    radius: 19
                    color: Qt.alpha(root.fg, snoozeArea.containsMouse ? 0.2 : 0.12)

                    StyledText {
                        id: snoozeLbl

                        anchors.centerIn: parent
                        text: qsTr("Répéter")
                        color: root.fg
                        font.pointSize: 9.5
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: snoozeArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.snoozeAlarm()
                    }
                }
                Rectangle {
                    width: stopLbl.implicitWidth + 28
                    height: 38
                    radius: 19
                    color: stopArea.containsMouse ? Qt.lighter("#ff9f0a", 1.1) : "#ff9f0a"

                    StyledText {
                        id: stopLbl

                        anchors.centerIn: parent
                        text: qsTr("Arrêter")
                        color: "#1c1206"
                        font.pointSize: 9.5
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: stopArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.stopAlarm()
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
                    model: (root.notif?.actions ?? []).slice(0, 3)

                    Rectangle {
                        id: act

                        required property var modelData

                        width: Math.max(90, actLbl.implicitWidth + 28)
                        height: 30
                        radius: 15
                        color: actArea.containsMouse ? Qt.alpha(root.fg, 0.2) : Qt.alpha(root.fg, 0.1)

                        StyledText {
                            id: actLbl

                            anchors.centerIn: parent
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

        // ── survol sans musique : heure, date, météo, batterie ──
        Face {
            active: root.mode === "info"

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 4

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

            Column {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 4
                spacing: 8

                Row {
                    anchors.right: parent.right
                    spacing: 6

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.icon
                        color: root.accent
                        fontStyle: Tokens.font.icon.size(14).build()
                        fill: 1
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.cc ? Weather.temp : "—"
                        color: root.fg
                        font.pointSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8
                    visible: UPower.displayDevice.isLaptopBattery

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${Math.round(root.battery * 100)} %`
                        color: root.charging ? root.green : root.fgDim
                        font.pointSize: 10
                        font.weight: Font.DemiBold
                    }
                    BatteryGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // ── lecteur complet ──
        Face {
            active: root.mode === "player"

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
    component Face: Item {
        id: face

        property bool active

        anchors.fill: parent
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

    component BatteryGlyph: Item {
        readonly property real pct: UPower.displayDevice.percentage ?? 0
        readonly property color fg: Colours.palette.m3onSurface

        width: 26
        height: 12

        Rectangle {
            width: 23
            height: 12
            radius: 3.5
            color: "transparent"
            border.width: 1.2
            border.color: Qt.alpha(parent.fg, 0.5)

            Rectangle {
                x: 2
                y: 2
                height: parent.height - 4
                width: Math.max(2, (parent.width - 4) * parent.parent.pct)
                radius: 2
                color: !UPower.onBattery ? (Colours.light ? "#1f9d3a" : "#32d74b") : parent.parent.pct < 0.2 ? "#ff453a" : parent.parent.fg
            }
        }

        Rectangle {
            x: 24
            y: 4
            width: 2
            height: 4
            radius: 1
            color: Qt.alpha(parent.fg, 0.5)
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

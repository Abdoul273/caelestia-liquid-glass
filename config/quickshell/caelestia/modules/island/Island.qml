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
import Caelestia.Components
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.effects
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
    readonly property int playerCount: Players.list.filter(p => (p?.trackTitle ?? "").length > 0).length
    readonly property bool playing: player?.isPlaying ?? false
    readonly property bool hasMedia: !!player && (player.trackTitle ?? "").length > 0
    readonly property string playerOutputLabel: {
        if (Audio.muted)
            return I18n.tr("Muet");
        if (root.btConnected.length > 0 && (root.btEarbuds || root.btAudio))
            return root.btConnected[0].name || I18n.tr("Bluetooth");
        const desc = Audio.sink?.description ?? "";
        if (/headphone|headset|ear|casque/i.test(desc))
            return I18n.tr("Casque");
        return I18n.tr("Haut-parleurs");
    }
    readonly property string playerOutputIcon: {
        if (Audio.muted)
            return "volume_off";
        if (root.btEarbuds)
            return "earbuds";
        if (root.btAudio || /headphone|headset|ear|casque/i.test(Audio.sink?.description ?? ""))
            return "headphones";
        return "speaker";
    }

    function cyclePlayer(): void {
        const list = Players.list.filter(p => (p?.trackTitle ?? "").length > 0);
        if (list.length <= 1)
            return;
        const idx = list.indexOf(root.player);
        Players.manualActive = list[(idx + 1) % list.length];
    }
    readonly property var brightMon: Brightness.getMonitorForScreen(screen)
    readonly property real brightness: brightMon?.brightness ?? 0
    // Batterie lue directement dans le noyau (charge_now / charge_full), plus précise et réactive qu'UPower
    property real sysBattery: -1
    property string sysBattStatus
    property real sysWatts: 0
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

        command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do cat $b/status; if [ -e $b/charge_now ]; then cat $b/charge_now $b/charge_full; else cat $b/energy_now $b/energy_full; fi; if [ -e $b/power_now ]; then cat $b/power_now; echo 1; elif [ -e $b/current_now ] && [ -e $b/voltage_now ]; then cat $b/current_now $b/voltage_now; fi; break; done 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                const now = parseFloat(l[1]), full = parseFloat(l[2]);
                if (l.length >= 3 && full > 0) {
                    root.sysBattStatus = l[0].trim();
                    root.sysBattery = Math.round(Math.max(0, Math.min(1, now / full)) * 100) / 100;
                }
                if (l.length >= 5) {
                    const a = parseFloat(l[3]), b = parseFloat(l[4]);
                    if (!isNaN(a) && !isNaN(b)) {
                        const w = b === 1 ? (a / 1e6) : ((a / 1e6) * (b / 1e6));
                        root.sysWatts = Math.round(w * 10) / 10;
                    }
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

    // Chargeur : état au moment de l'évènement + chorégraphie MagSafe / cellule plasma liquide
    property bool chargePlugged
    property real chargeFill: 1
    property real chargeBolt: 1
    property real chargeShine: 0
    property real chargeWave: 1
    property real chargeRing: 1
    property real chargeLivePhase: 0

    NumberAnimation on chargeLivePhase {
        running: root.mode === "charge"
        from: 0
        to: 1
        duration: 1600
        loops: Animation.Infinite
    }

    Timer {
        id: chargeSwap

        interval: 260
        onTriggered: {
            root.chargePlugged = root.charging;
            root.flash("charge", root.charging ? 4400 : 3200);
            chargeIntro.restart();
        }
    }

    SequentialAnimation {
        id: chargeIntro

        ScriptAction {
            script: {
                root.chargeFill = root.chargePlugged ? 0 : 1.12;
                root.chargeBolt = 0;
                root.chargeShine = 0;
                root.chargeWave = 0;
                root.chargeRing = 0;
            }
        }
        PauseAnimation {
            duration: 80
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "chargeBolt"
                to: 1
                duration: 620
                easing.type: Easing.OutBack
                easing.overshoot: 2.4
            }
            NumberAnimation {
                target: root
                property: "chargeWave"
                to: 1
                duration: 1350
                easing.type: Easing.OutQuart
            }
            NumberAnimation {
                target: root
                property: "chargeFill"
                to: 1
                duration: 1150
                easing.type: Easing.OutExpo
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 160
                }
                NumberAnimation {
                    target: root
                    property: "chargeRing"
                    to: 1
                    duration: 1100
                    easing.type: Easing.OutExpo
                }
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 280
                }
                NumberAnimation {
                    target: root
                    property: "chargeShine"
                    from: 0
                    to: 1
                    duration: 950
                    easing.type: Easing.InOutCubic
                }
            }
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
        return t || callTitleKept || callAppName || I18n.tr("Appel en cours");
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
                    best = { at: d, label: a.label || I18n.tr("Alarme") };
                break;
            }
        }
        return best;
    }

    function dayWord(d: var): string {
        const today = new Date();
        const t0 = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        const diff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() - t0) / 86400000);
        return diff === 0 ? "" : diff === 1 ? I18n.tr("demain ") : I18n.locale.toString(d, "ddd ");
    }

    // Beaucoup d'écouteurs (clones AirPods…) n'envoient leur batterie qu'à la connexion :
    // BlueZ garde alors une valeur figée. On retient quand chaque valeur a été reçue et on
    // affiche son âge au bout de 10 min pour ne pas la faire passer pour du direct.
    property var btBattSeen: ({})

    function btBatteryText(d: BluetoothDevice): string {
        if (!d?.batteryAvailable)
            return "";
        const pct = Math.round(d.battery * 100);
        const key = d.address || d.name;
        const t = Date.now();
        let seen = btBattSeen[key];
        if (!seen || seen.p !== pct)
            seen = btBattSeen[key] = { p: pct, t };
        const min = Math.floor((t - seen.t) / 60000);
        if (min < 10)
            return ` · ${pct} %`;
        return ` · ${pct} % ` + (min < 60 ? I18n.tr("il y a %1 min").arg(min) : I18n.tr("il y a %1 h").arg(Math.floor(min / 60)));
    }

    function openInfoDrop(kind: string): void {
        const s = root.screenState;
        if (!s)
            return;
        root.expanded = false;
        s.controlCenter = false;
        s.dashboard = false;
        if (kind === "controlCenter") {
            s.controlCenter = true;
        } else if (kind === "tasks") {
            s.quickNotes = false;
            s.quickTasks = true;
            s.dashboardTab = 0;
            s.dashboard = true;
        } else if (kind in s) {
            s[kind] = true;
        }
    }

    function runInfoChip(action: string): void {
        if (action === "alarm")
            openInfoDrop("clock");
        else if (action === "earbuds")
            openInfoDrop("earbuds");
        else if (action === "cc")
            openInfoDrop("controlCenter");
        else if (action === "caffeine")
            pageName = "caffeine";
        else if (action === "night")
            NightLight.toggle();
        else if (action === "focus")
            FocusMode.stop();
        else if (action === "dnd")
            Notifs.dnd = false;
        else if (action === "tasks")
            openInfoDrop("tasks");
        else if (action === "notifs")
            Island.notifCenter = true;
        else if (action === "unmuteMic") {
            if (Audio.source?.ready && Audio.source?.audio)
                Audio.source.audio.muted = false;
        } else if (action === "unmuteAudio") {
            if (Audio.sink?.ready && Audio.sink?.audio)
                Audio.sink.audio.muted = false;
        }
    }

    readonly property string infoWeatherRange: {
        const today = Weather.forecast && Weather.forecast.length > 0 ? Weather.forecast[0] : null;
        if (!today || today.minTempC === undefined || today.maxTempC === undefined)
            return Weather.windSpeed > 0 ? `${Math.round(Weather.windSpeed)} km/h` : "";
        const lo = Weather.formatTemp(today.minTempC).replace(/[CF]$/, "");
        const hi = Weather.formatTemp(today.maxTempC).replace(/[CF]$/, "");
        return `${lo}/${hi}`;
    }

    readonly property string infoBattSub: {
        const w = root.sysWatts > 0.2 ? `${root.sysWatts.toFixed(root.sysWatts >= 10 ? 0 : 1).replace(".", ",")} W` : "";
        if (BatteryInfo.full)
            return I18n.tr("Chargée");
        if (root.battCharging) {
            const dur = BatteryInfo.fmtDuration(BatteryInfo.timeToFull);
            if (dur && w)
                return `${dur} · ${w}`;
            if (dur)
                return dur;
            return w ? `${I18n.tr("En charge")} · ${w}` : I18n.tr("En charge");
        }
        if (!UPower.onBattery)
            return I18n.tr("Sur secteur");
        const dur = BatteryInfo.fmtDuration(BatteryInfo.timeToEmpty);
        if (dur && w)
            return `${dur} · ${w}`;
        if (dur)
            return dur;
        return w || I18n.tr("Sur batterie");
    }

    readonly property list<var> infoChips: {
        void (now);
        void (Time.date);
        const out = [];
        const al = nextAlarm();
        if (al)
            out.push({ icon: "alarm", text: `${al.label} · ${dayWord(al.at)}${Qt.formatTime(al.at, "HH:mm")}`, tint: "#ff9f0a", action: "alarm" });
        for (const d of btConnected) {
            const isBuds = /pod|bud|tws|\bbx|cetw/i.test(d?.name ?? "");
            const icon = isBuds ? "earbuds" : /audio|head|ear|phone/i.test(d?.icon ?? "") ? "headphones" : "bluetooth";
            out.push({ icon, text: (d.name || I18n.tr("Bluetooth")) + btBatteryText(d), tint: root.green, action: isBuds ? "earbuds" : "cc" });
        }
        if (IdleInhibitor.enabled)
            out.push({ icon: "coffee", text: IdleInhibitor.until > 0 ? I18n.tr("Écran allumé · %1").arg(IdleInhibitor.remainingText()) : I18n.tr("Écran toujours allumé"), tint: root.accent, action: "caffeine" });
        if (NightLight.enabled)
            out.push({ icon: "nightlight", text: I18n.tr("Nuit · %1 K").arg(NightLight.temperature), tint: "#ff9f0a", action: "night" });
        if (FocusMode.active)
            out.push({ icon: FocusMode.info.icon, text: `${FocusMode.info.name} · ${FocusMode.untilText()}`, tint: FocusMode.info.tint, action: "focus" });
        else if (Notifs.dnd)
            out.push({ icon: "do_not_disturb_on", text: I18n.tr("Ne pas déranger"), tint: "#bf5af2", action: "dnd" });
        const late = Tasks.overdueCount;
        if (late > 0)
            out.push({ icon: "assignment_late", text: late > 1 ? I18n.tr("%1 tâches en retard").arg(late) : I18n.tr("1 tâche en retard"), tint: root.red, action: "tasks" });
        const next = Tasks.sorted.find(t => !t.done && t.due > Date.now() && Tasks.isToday(t));
        if (next)
            out.push({ icon: "task_alt", text: `${next.text} · ${Qt.formatTime(new Date(next.due), "HH:mm")}`, tint: "#0a84ff", action: "tasks" });
        else if (Tasks.todayCount > 0)
            out.push({ icon: "task_alt", text: Tasks.todayCount > 1 ? I18n.tr("%1 tâches aujourd'hui").arg(Tasks.todayCount) : I18n.tr("1 tâche aujourd'hui"), tint: "#0a84ff", action: "tasks" });
        const unread = Notifs.notClosed.length;
        if (unread > 0)
            out.push({ icon: "notifications", text: unread > 1 ? I18n.tr("%1 notifications").arg(unread) : I18n.tr("1 notification"), tint: root.accent, action: "notifs" });
        if (Audio.sourceMuted)
            out.push({ icon: "mic_off", text: I18n.tr("Micro coupé"), tint: root.red, action: "unmuteMic" });
        if (Audio.muted)
            out.push({ icon: "volume_off", text: I18n.tr("Son coupé"), tint: root.red, action: "unmuteAudio" });
        if (VPN.connected)
            out.push({ icon: "vpn_lock", text: I18n.tr("VPN"), tint: root.green, action: "cc" });
        if ((Nmcli.deviceStatus !== null && !Nmcli.isConnected && !Nmcli.active && !Nmcli.hasAvailableEthernet) || (!Nmcli.wifiEnabled && !Nmcli.activeEthernet))
            out.push({ icon: "wifi_off", text: I18n.tr("Hors ligne"), tint: "#ff9f0a", action: "cc" });
        return out;
    }

    // ── Bluetooth connecté (icône verte au repos) ──
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d?.connected)
    readonly property bool btAudio: btConnected.some(d => /audio|head|ear|phone/i.test(d?.icon ?? ""))
    readonly property bool btEarbuds: btConnected.some(d => /pod|bud|tws|\bbx|cetw/i.test(d?.name ?? ""))

    // ── Capsule au repos : teinte contextuelle, bureaux occupés, météo diurne/nocturne, horloge ──
    readonly property var wsOccupied: {
        const map = {};
        map[wsId] = true;
        for (const t of Hypr.toplevels.values) {
            const id = t.workspace?.id ?? 0;
            if (id > 0 && t.workspace?.monitor?.name === hyprMon?.name)
                map[id] = true;
        }
        return map;
    }
    readonly property int idleUnread: Notifs.notClosed.length
    readonly property string idleHourStr: Time.format(GlobalConfig.services.useTwelveHourClock ? "hh" : "HH")
    readonly property string idleMinStr: Time.format("mm")
    readonly property color idleAccent: {
        if (battCharging)
            return green;
        if (showBattery && battery < 0.2)
            return red;
        if (FocusMode.active)
            return FocusMode.info.tint;
        if (Notifs.dnd)
            return "#bf5af2";
        if (Agents.busy)
            return Agents.waiting > 0 ? "#ff9f0a" : Agents.kindColour(Agents.lead?.kind ?? "");
        return accent;
    }
    readonly property bool showIdleWeather: Island.weather && !!Weather.cc
    readonly property string idleWeatherIcon: {
        if (!Weather.cc)
            return "";
        const code = String(Weather.cc.weatherCode ?? "");
        const isDay = Weather.cc.isDay !== 0;
        if ((code === "0" || code === "1") && !isDay)
            return "bedtime";
        if (code === "2" && !isDay)
            return "cloud";
        return Weather.icon;
    }
    readonly property color idleWeatherTint: {
        if (!Weather.cc)
            return fgDim;
        const code = Number(Weather.cc.weatherCode ?? -1);
        const isDay = Weather.cc.isDay !== 0;
        if (code === 0 || code === 1)
            return isDay ? (Colours.light ? "#d97706" : "#fbbf24") : (Colours.light ? "#4f46e5" : "#a5b4fc");
        if (code === 2)
            return isDay ? (Colours.light ? "#d97706" : "#fcd34d") : (Colours.light ? "#3b82f6" : "#93c5fd");
        if (code >= 95)
            return Colours.light ? "#7c3aed" : "#c084fc";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return Colours.light ? "#0284c7" : "#38bdf8";
        if (code >= 71 && code <= 86)
            return Colours.light ? "#0ea5e9" : "#bae6fd";
        return fgDim;
    }
    readonly property string idleTempShort: Weather.cc ? Weather.temp.replace(/[CF]$/, "") : ""

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
        return s < 60 ? I18n.tr("%1 s").arg(Math.ceil(s)) : s < 3600 ? I18n.tr("%1 min").arg(Math.ceil(s / 60)) : I18n.tr("%1 h %2").arg(Math.floor(s / 3600)).arg(Math.round(s % 3600 / 60).toString().padStart(2, "0"));
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
                moments.push({ key: `${t.id}:soon:${t.due}`, at: t.due - 15 * 60000, sub: I18n.tr("Dans 15 min · à %1").arg(Qt.formatTime(new Date(t.due), "HH:mm")), late: false });
                moments.push({ key: `${t.id}:due:${t.due}`, at: t.due, sub: I18n.tr("C'est l'heure · %1").arg(Qt.formatTime(new Date(t.due), "HH:mm")), late: true });
            }
            for (const r of t.full?.smartReminders ?? []) {
                const at = Date.parse(r.time) || 0;
                if (at > 0 && !r.triggered)
                    moments.push({ key: `${t.id}:smart:${r.id}`, at: at, sub: r.label || I18n.tr("Rappel"), late: false });
            }
            if (snoozes[t.id])
                moments.push({ key: `${t.id}:snooze:${snoozes[t.id]}`, at: snoozes[t.id], sub: I18n.tr("Rappel reporté"), late: true });
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

    property int blipTick // change à chaque pastille : relance le rebond du badge

    function blip(icon: string, text: string, sub: string, on: bool): void {
        blipTick++;
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

    onCapsLockChanged: if (capsKnown && ready) blip(capsLock ? "keyboard_capslock_badge" : "keyboard_capslock", capsLock ? I18n.tr("Verr. Maj activé") : I18n.tr("Verr. Maj désactivé"), "", capsLock)

    readonly property string wifiName: Nmcli.active?.ssid ?? ""
    readonly property bool wifiHwEnabled: Nmcli.wifiEnabled
    property bool wifiKnown: false
    property bool wifiOn: false
    property string wifiSsid: ""
    readonly property int wifiStrength: Nmcli.active?.strength ?? 88
    readonly property int wifiFreq: Nmcli.active?.frequency ?? 5180
    readonly property string wifiBand: wifiFreq >= 5900 ? "6 GHz" : wifiFreq >= 4900 ? "5 GHz" : wifiFreq > 0 ? "2,4 GHz" : "5 GHz"
    readonly property bool wifiSecure: Nmcli.active?.isSecure ?? true
    readonly property string wifiSecLabel: (Nmcli.active?.security ?? "") !== "" ? Nmcli.active.security : (wifiSecure ? "WPA3" : I18n.tr("Ouvert"))
    readonly property string wifiQualityText: wifiStrength >= 80 ? I18n.tr("Signal excellent") : wifiStrength >= 55 ? I18n.tr("Signal fort") : wifiStrength >= 35 ? I18n.tr("Signal moyen") : I18n.tr("Signal faible")

    onWifiNameChanged: {
        if (!wifiKnown) {
            wifiKnown = true;
            wifiOn = wifiName !== "";
            if (wifiName)
                wifiSsid = wifiName;
            return;
        }
        if (!ready)
            return;
        wifiOn = wifiName !== "";
        if (wifiName)
            wifiSsid = wifiName;
        flash("wifi", wifiOn ? 4400 : 2800);
    }

    onWifiHwEnabledChanged: {
        if (!wifiKnown || !ready)
            return;
        if (!wifiHwEnabled && wifiOn) {
            wifiOn = false;
            flash("wifi", 2800);
        }
    }

    readonly property bool vpnOn: VPN.connected
    onVpnOnChanged: blip(vpnOn ? "vpn_lock" : "vpn_key_off", I18n.tr("VPN"), vpnOn ? I18n.tr("Connecté") : I18n.tr("Déconnecté"), vpnOn)

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
        text: root.pomoOn ? I18n.tr("Pomodoro · %1 · session %2").arg(root.clockLabel).arg(root.pomoRound) : root.clockLabel ? I18n.tr("Minuteur · %1").arg(root.clockLabel) : ""
    }
    property list<real> laps: [] // chronomètre : temps écoulé à chaque tour (s)
    // Pomodoro : enchaîne travail / pause tout seul
    property bool pomoOn
    property real pomoWork: 25 * 60
    property real pomoRest: 5 * 60
    property string pomoPhase: "work"
    property int pomoRound: 1
    property string doneTitle: I18n.tr("Minuteur terminé")
    // Agent IA qui vient de finir (Claude Code, Codex) : {id, kind, project, title, reply, window}
    property var agentDone: null
    Connections {
        target: Agents

        function onFinished(agent: var): void {
            // Pas la peine si on regarde déjà son terminal
            if (agent.window && Hypr.activeToplevel?.address === agent.window)
                return;
            root.agentDone = agent;
            root.flash("agentDone", 7000);
        }
        function onShownChanged(): void {
            if (!Island.agents && root.pageName === "agents")
                root.pageName = "info";
        }
    }
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
        startTimer(pomoWork, I18n.tr("Focus"));
    }

    function addLap(): void {
        if (clockKind !== "stopwatch")
            return;
        laps = [...laps, clockValue];
        saveClock();
    }

    function addMinutes(m: int): void {
        if (clockKind !== "timer" || m <= 0)
            return;
        clockEnd += m * 60000;
        clockTotal += m * 60;
        saveClock();
    }

    function addMinute(): void {
        addMinutes(1);
    }

    function timerFinished(): void {
        const label = clockLabel;
        const total = clockTotal;
        clockKind = "";
        if (pomoOn) {
            // Pomodoro : ça sonne, puis on choisit d'enchaîner (Pause / Reprendre) depuis l'île
            if (pomoPhase === "work")
                ring("pomoWork", I18n.tr("Focus terminé"), I18n.tr("Session %1 · place à %2 de pause").arg(pomoRound).arg(fmtHuman(pomoRest)), total);
            else
                ring("pomoRest", I18n.tr("Pause terminée"), I18n.tr("Prêt pour la session %1 ?").arg(pomoRound + 1), total);
            saveClock();
            return;
        }
        ring("timer", label || I18n.tr("Minuteur"), I18n.tr("Minuteur de %1 terminé").arg(fmtHuman(total)), total);
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
                root.ringAlarm(a.label || I18n.tr("Alarme"), hm);
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
            startTimer(total, label === I18n.tr("Minuteur") ? "" : label);
        else
            startTimer(9 * 60, I18n.tr("%1 (répétition)").arg(label));
    }

    function ringPlusOne(): void {
        const label = alarmLabel;
        stopAlarm();
        startTimer(60, label === I18n.tr("Minuteur") ? "" : label);
    }

    // Pomodoro : enchaîner sur la phase suivante
    function ringNextPhase(): void {
        const kind = ringKind;
        stopAlarm();
        if (kind === "pomoWork") {
            pomoPhase = "rest";
            startTimer(pomoRest, I18n.tr("Pause"));
        } else {
            pomoPhase = "work";
            pomoRound += 1;
            startTimer(pomoWork, I18n.tr("Focus"));
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

    // ── Paroles synchronisées (Onde CLI / Onde Web, cache d'Aura, .lrc voisin, puis LRCLIB) ──
    property var lyrics: []
    property string lyricsKey: ""
    property real lyricPos: 0
    property bool lyricsRetried: false
    readonly property string lyricKeyNow: hasMedia ? `${player?.trackTitle ?? ""}|${player?.trackArtist ?? ""}` : ""
    readonly property int lyricIndex: {
        const l = lyrics;
        if (!l || l.length === 0)
            return -1;
        const t = lyricPos + 0.04;
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
        if (ans < 0)
            return 0;
        if (l[ans][1] === "♪" && ans + 1 < l.length && (l[ans + 1][0] - t) <= 1.2)
            return ans + 1;
        return ans;
    }
    readonly property string lyricLine: lyricIndex >= 0 ? (lyrics[lyricIndex][1] || "♪") : ""
    readonly property bool hasLyrics: Island.lyrics && lyrics.length > 0 && lyricIndex >= 0

    // Paroles réactivées dans les réglages : on les recharge pour le morceau en cours
    Connections {
        target: Island

        function onCopied(): void {
            if (root.ready)
                root.blip("content_copy", I18n.tr("Copié"), I18n.tr("Presse-papiers"), true);
        }
    }

    Connections {
        target: Island

        function onLyricsChanged(): void {
            if (Island.lyrics)
                lyricsDebounce.restart();
        }
    }

    Connections {
        target: root.player

        function onPositionChanged(): void {
            root.lyricPos = root.player?.position ?? 0;
        }

        function onPlaybackStateChanged(): void {
            root.player?.positionChanged();
            root.lyricPos = root.player?.position ?? 0;
        }

        function onPostTrackChanged(): void {
            root.lyricPos = root.player?.position ?? 0;
        }
    }

    onLyricKeyNowChanged: {
        root.lyricsRetried = false;
        root.lyricPos = root.player?.position ?? 0;
        lyricsDebounce.restart();
    }

    Timer {
        id: lyricsDebounce

        interval: 250
        onTriggered: {
            root.lyrics = [];
            root.lyricsKey = root.lyricKeyNow;
            root.lyricPos = root.player?.position ?? 0;
            if (!root.lyricKeyNow || !Island.lyrics)
                return;
            const len = root.player?.length ?? 0;
            lyricsProc.command = ["python3", Quickshell.shellPath("assets/island-lyrics.py"), root.player?.trackTitle ?? "", root.player?.trackArtist ?? "", String(len > 0 && len < 2147483 ? len : 0), String(root.player?.metadata?.["xesam:url"] ?? "")];
            lyricsProc.running = true;
        }
    }

    Timer {
        id: lyricsRetry

        interval: 2200
        onTriggered: {
            if (root.lyrics.length === 0 && root.lyricKeyNow && Island.lyrics && !lyricsProc.running) {
                const len = root.player?.length ?? 0;
                lyricsProc.command = ["python3", Quickshell.shellPath("assets/island-lyrics.py"), root.player?.trackTitle ?? "", root.player?.trackArtist ?? "", String(len > 0 && len < 2147483 ? len : 0), String(root.player?.metadata?.["xesam:url"] ?? "")];
                lyricsProc.running = true;
            }
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
                root.player?.positionChanged();
                root.lyricPos = root.player?.position ?? 0;
                try {
                    root.lyrics = JSON.parse(text).lines ?? [];
                } catch (e) {
                    root.lyrics = [];
                }
                if (root.lyrics.length === 0 && !root.lyricsRetried) {
                    root.lyricsRetried = true;
                    lyricsRetry.restart();
                }
            }
        }
    }

    Timer {
        running: root.playing && root.lyrics.length > 0
        interval: 80
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
        if (Agents.perm && Island.agents)
            return "perm";
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
        if (pulse === "agentDone" && agentDone)
            return "agentDone";
        if (pulse === "bt" && btDevice)
            return "bt";
        if (pulse === "wifi")
            return "wifi";
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
    readonly property list<string> allActs: [...(inCall ? ["call"] : []), ...(transfer ? ["transfer"] : []), ...(Recorder.running ? ["record"] : []), ...(clockKind !== "" ? ["clockMini"] : []), ...(Agents.busy ? ["agentsMini"] : []), ...(hasMedia && playing ? ["media"] : [])]
    // Agents et musique ne prennent l'île repliée que si c'est leur page qu'on regardait ;
    // sinon l'île revient au repos (heure, date…) avec juste une petite icône à droite
    readonly property list<string> compactActs: allActs.filter(a => (a !== "agentsMini" || pageName === "agents") && (a !== "media" || pageName === "player"))
    readonly property string compactPick: {
        const fromPage = ({ callFull: "call", transferFull: "transfer", recordFull: "record", clock: "clockMini", agents: "agentsMini", player: "media" })[pageName];
        return fromPage && compactActs.includes(fromPage) ? fromPage : (compactActs[0] ?? "");
    }
    // Les autres activités, en petites icônes au bord de l'île compacte (+ caféine)
    readonly property list<string> otherActs: [...allActs.filter(a => a !== mode), ...(IdleInhibitor.enabled ? ["caffeine"] : [])]
    readonly property bool compactActive: mode === "call" || mode === "transfer" || mode === "record" || mode === "clockMini" || mode === "agentsMini" || mode === "media"
    readonly property real actsInset: compactActive && otherActs.length > 0 ? otherActs.length * 18 + 12 : 0

    function actIcon(a: string): string {
        return ({ call: callMuted ? "mic_off" : "call", transfer: transfer?.kind === "copy" ? "content_copy" : transfer?.kind === "upload" ? "cloud_upload" : "download", record: "radio_button_checked", clockMini: "timer", agentsMini: "smart_toy", media: "music_note", caffeine: "coffee" })[a] ?? "";
    }

    function actColour(a: string): color {
        return ({ call: callMuted ? "#ff453a" : root.green, transfer: "#0a84ff", record: "#ff453a", clockMini: "#ff9f0a", agentsMini: Agents.waiting > 0 ? "#ff9f0a" : Agents.kindColour(Agents.lead?.kind ?? ""), media: root.accent, caffeine: root.fg })[a] ?? root.fg;
    }

    readonly property bool notifHasActions: (notif?.actions?.length ?? 0) > 0
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
            return Qt.size(500, Math.min(640, Math.max(210, 128 + centerList.contentHeight)));
        case "recordFull":
            return Qt.size(pageWidth, 112);
        case "caffeine":
            return Qt.size(pageWidth, 134);
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
            return Qt.size(pageWidth, 134 + shelfExtra);
        case "clockMini":
            return Qt.size((clockLabel ? 290 : 230) + actsInset, 40);
        case "agentsMini":
            return Qt.size(364 + actsInset, 40);
        case "agents": {
            const list = Agents.filteredShown;
            const hasFilters = Agents.presentKinds.length > 1 || Agents.shown.length > 2;
            const hasLauncher = Agents.launcherOpen && Agents.shown.length > 0;
            let bodyH = 112;
            if (list.length > 0) {
                let sum = 0;
                for (let i = 0; i < list.length; i++)
                    sum += (list[i].id === Agents.expandedId ? 124 : 68) + (i > 0 ? 6 : 0);
                bodyH = Math.min(316, sum);
            }
            const extra = (hasFilters ? 32 : 0) + (hasLauncher ? 36 : 0);
            return Qt.size(Math.max(pageWidth, 610), 66 + extra + bodyH);
        }
        case "perm":
            return Qt.size(Math.max(pageWidth, 600), 148);
        case "agentDone":
            return Qt.size(460, 80);
        case "shot":
            return Qt.size(460, 100);
        case "bt":
            return btOn ? Qt.size(400, 76) : Qt.size(330, 48);
        case "wifi":
            return wifiOn ? Qt.size(456, 86) : Qt.size(364, 58);
        case "charge":
            return chargePlugged ? Qt.size(464, 88) : Qt.size(410, 74);
        case "player":
            return Qt.size(pageWidth, (hasLyrics ? 218 : 188) + (shelf.length > 0 ? shelfExtra : 0));
        case "info":
            return Qt.size(pageWidth, (infoChips.length > 0 ? 108 + infoFlow.implicitHeight + 24 : 116) + shelfExtra);
        case "perf":
            return Qt.size(pageWidth, 222);
        case "record":
            return Qt.size(210 + actsInset, 40);
        case "transfer":
            return Qt.size(Math.min(330, 170 + transferNameMetrics.advanceWidth) + actsInset, 40);
        case "transferFull":
            return Qt.size(pageWidth, 134);
        case "taskDue":
            return Qt.size(460, 104);
        case "fileDone":
            return Qt.size(440, 76);
        case "call":
            return Qt.size(Math.min(340, 150 + callTitleMetrics.advanceWidth) + actsInset, 40);
        case "callFull":
            return Qt.size(pageWidth, 112);
        case "media":
            return Qt.size((hasLyrics ? 400 : 290) + actsInset, 40);
        default:
            // Au repos : capsule équilibrée (zéro vide mort, espacement optique égal des deux côtés de l'heure)
            return Island.clock ? Qt.size(Math.max(264, 18 + idleDate.implicitWidth + 24 + idleTime.implicitWidth + 24 + idleIcons.implicitWidth + 18), 40) : Qt.size(150, 0);
        }
    }

    property real w: target.width
    property real h: target.height
    readonly property real radius: Math.min(h / 2, mode === "player" || mode === "info" || mode === "perf" || mode === "notif" || mode === "bt" || mode === "wifi" || mode === "shot" || mode === "clock" || mode === "drop" || mode === "toast" || mode === "done" || mode === "alarm" || mode === "count" || mode === "recordFull" || mode === "callFull" || mode === "transferFull" || mode === "taskDue" || mode === "fileDone" || mode === "caffeine" || mode === "center" || mode === "agents" || mode === "perm" || mode === "agentDone" || mode === "charge" ? 32 : h / 2)

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

    // ── Centre de notifications : piles rétractables par appli ou par espèce, filtres et masquage ──
    property string expandedApp
    property var expandedGroups: ({})
    property var hiddenGroups: ({})
    property bool showHiddenGroups: false
    property string centerCat: "all" // "all", "messages", "system", "media", "apps"
    property string centerGroupBy: "app" // "app" (par application) ou "cat" (par espèce/catégorie)

    function notifCat(n: var): string {
        const s = `${n?.appName ?? ""} ${n?.appIcon ?? ""} ${n?.summary ?? ""}`.toLowerCase();
        if (/whatsapp|telegram|discord|signal|slack|mail|thunderbird|gmail|messag|chat|element|teams| matrix|sms/.test(s))
            return "messages";
        if (/spotify|onde|vlc|mpv|youtube|music|audio|player|steam|prisme|obs|media/.test(s))
            return "media";
        if (/caelestia|hypr|quickshell|network|wifi|bluetooth|batter|upower|pacman|yay|arcadia|kitty|terminal|drive|transfer|capture|agent|claude|codex|antigravity|syst/.test(s))
            return "system";
        return "apps";
    }

    function notifCatLabel(cat: string): string {
        return ({
            all: I18n.tr("Tout"),
            messages: I18n.tr("Messages"),
            system: I18n.tr("Système"),
            media: I18n.tr("Média"),
            apps: I18n.tr("Applis")
        })[cat] ?? I18n.tr("Applis");
    }

    function notifCatIcon(cat: string): string {
        return ({
            all: "dynamic_feed",
            messages: "forum",
            system: "tune",
            media: "play_circle",
            apps: "widgets"
        })[cat] ?? "notifications";
    }

    function notifCatColor(cat: string): color {
        return ({
            all: root.accent,
            messages: "#38bdf8",
            system: "#a78bfa",
            media: root.green,
            apps: "#ff9f0a"
        })[cat] ?? root.accent;
    }

    function groupKey(n: var): string {
        if (centerGroupBy === "cat")
            return `cat:${notifCat(n)}`;
        const a = (n?.appName ?? "").trim();
        return `app:${a || notifCatLabel(notifCat(n))}`;
    }

    function groupTitle(n: var): string {
        if (centerGroupBy === "cat")
            return notifCatLabel(notifCat(n));
        return (n?.appName ?? "").trim() || notifCatLabel(notifCat(n));
    }

    function isGroupExpanded(k: string): bool {
        return !!expandedGroups[k] || expandedApp === k;
    }

    function toggleGroupExpand(k: string): void {
        const next = Object.assign({}, expandedGroups);
        if (next[k])
            delete next[k];
        else
            next[k] = true;
        expandedGroups = next;
    }

    function isGroupHidden(k: string): bool {
        return !!hiddenGroups[k];
    }

    function toggleGroupHidden(k: string): void {
        const next = Object.assign({}, hiddenGroups);
        if (next[k])
            delete next[k];
        else {
            next[k] = true;
            const exp = Object.assign({}, expandedGroups);
            delete exp[k];
            expandedGroups = exp;
        }
        hiddenGroups = next;
        if (Object.keys(next).length === 0)
            showHiddenGroups = false;
    }

    readonly property int hiddenNotifCount: {
        let c = 0;
        for (const n of Notifs.notClosed) {
            if (hiddenGroups[groupKey(n)])
                c++;
        }
        return c;
    }

    readonly property bool anyStackExpandable: {
        const counts = {};
        for (const n of Notifs.notClosed) {
            if (centerCat !== "all" && notifCat(n) !== centerCat)
                continue;
            const k = groupKey(n);
            if (!showHiddenGroups && hiddenGroups[k])
                continue;
            counts[k] = (counts[k] ?? 0) + 1;
            if (counts[k] > 1)
                return true;
        }
        return false;
    }

    readonly property bool allStacksExpanded: {
        const counts = {};
        for (const n of Notifs.notClosed) {
            if (centerCat !== "all" && notifCat(n) !== centerCat)
                continue;
            const k = groupKey(n);
            if (!showHiddenGroups && hiddenGroups[k])
                continue;
            counts[k] = (counts[k] ?? 0) + 1;
        }
        let hasMulti = false;
        for (const k of Object.keys(counts)) {
            if (counts[k] > 1) {
                hasMulti = true;
                if (!expandedGroups[k])
                    return false;
            }
        }
        return hasMulti;
    }

    function toggleExpandAllStacks(): void {
        if (allStacksExpanded) {
            expandedGroups = ({});
            expandedApp = "";
            return;
        }
        const next = Object.assign({}, expandedGroups);
        for (const n of Notifs.notClosed)
            next[groupKey(n)] = true;
        expandedGroups = next;
    }

    function catCount(cat: string): int {
        let c = 0;
        for (const n of Notifs.notClosed) {
            if (!showHiddenGroups && hiddenGroups[groupKey(n)])
                continue;
            if (cat === "all" || notifCat(n) === cat)
                c++;
        }
        return c;
    }

    function groupMembers(n: var): var {
        const k = groupKey(n);
        return Notifs.notClosed.filter(m => {
            if (centerCat !== "all" && notifCat(m) !== centerCat)
                return false;
            return groupKey(m) === k;
        });
    }

    function centerItems(): var {
        const seen = {};
        const out = [];
        for (const n of Notifs.notClosed) {
            if (centerCat !== "all" && notifCat(n) !== centerCat)
                continue;
            const k = groupKey(n);
            if (!showHiddenGroups && hiddenGroups[k])
                continue;
            if (seen[k])
                continue;
            seen[k] = true;
            const members = groupMembers(n);
            if (isGroupExpanded(k) && members.length > 1)
                out.push(...members);
            else
                out.push(n);
        }
        return out;
    }

    // Texte de notification sans balises ni entités HTML (&quot; &amp; …)
    function plain(t: string): string {
        return (t ?? "").replace(/<[^>]*>/g, "").replace(/&quot;/g, "\"").replace(/&#0?39;|&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
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
                flash("notif", n.urgency === 2 ? 7000 : 4000);
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
            root.expandedApp = "";
            root.expandedGroups = ({});
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
        if (!battProc.running)
            battProc.running = true;
        if (pulse === "charge") {
            // Laisse la vue précédente s'effacer avant d'afficher la nouvelle
            pulse = "";
            chargeSwap.restart();
            return;
        }
        chargePlugged = charging;
        flash("charge", charging ? 4400 : 3200);
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
                root.ring("timer", I18n.tr("Pâtes"), I18n.tr("Minuteur de %1 terminé").arg(root.fmtHuman(600)), 600);
            else if (kind === "pomo")
                root.ring("pomoWork", I18n.tr("Focus terminé"), I18n.tr("Session 1 · place à 5 min de pause"), 1500);
            else
                root.ringAlarm(I18n.tr("Réveil"), Time.format("HH:mm"));
        }
        function testAlarm(label: string): void {
            root.ringAlarm(label || I18n.tr("Alarme"), Time.format("HH:mm"));
        }
        function testWifi(ssid: string): void {
            root.wifiSsid = (ssid && ssid !== "off") ? ssid : (root.wifiName || "Fibre-5G");
            root.wifiOn = ssid !== "off";
            root.flash("wifi", root.wifiOn ? 4400 : 2800);
        }
        function testCharge(state: string): void {
            root.chargePlugged = state !== "off";
            root.flash("charge", root.chargePlugged ? 4400 : 3200);
            chargeIntro.restart();
        }
        function state(): string {
            root.saveClock();
            return "ok";
        }
    }

    // Petit rebond quand un évènement arrive
    onPulseChanged: {
        if (pulse === "notif" || pulse === "toast" || pulse === "charge" || pulse === "bt" || pulse === "wifi" || pulse === "shot")
            bump.restart();
        if (pulse === "done")
            doneShake.restart();
        if (pulse === "bt" && btOn)
            btIntro.restart();
        if (pulse === "wifi") {
            if (wifiOn)
                wifiIntro.restart();
            else
                wifiOutro.restart();
        }
    }

    // ── Chorégraphie Wi-Fi : balayage séquentiel des 4 arcs vectoriels, flux de paquets et jauge ──
    property real wifiPop: 1
    property real wifiWave: 1
    property real wifiRing: 1
    property real wifiSlash: 0
    property real wifiLivePhase: 0

    NumberAnimation on wifiLivePhase {
        running: root.mode === "wifi"
        from: 0
        to: 1
        duration: 1500
        loops: Animation.Infinite
    }

    SequentialAnimation {
        id: wifiIntro

        ScriptAction {
            script: {
                root.wifiPop = 0;
                root.wifiWave = 0;
                root.wifiRing = 0;
                root.wifiSlash = 0;
            }
        }
        PauseAnimation {
            duration: 70
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "wifiPop"
                to: 1
                duration: 620
                easing.type: Easing.OutBack
                easing.overshoot: 2.1
            }
            NumberAnimation {
                target: root
                property: "wifiWave"
                to: 1
                duration: 1250
                easing.type: Easing.OutQuart
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 180
                }
                NumberAnimation {
                    target: root
                    property: "wifiRing"
                    to: 1
                    duration: 1100
                    easing.type: Easing.OutExpo
                }
            }
        }
    }

    SequentialAnimation {
        id: wifiOutro

        ScriptAction {
            script: {
                root.wifiPop = 0;
                root.wifiWave = 1;
                root.wifiRing = 0;
                root.wifiSlash = 0;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "wifiPop"
                to: 1
                duration: 480
                easing.type: Easing.OutBack
            }
            NumberAnimation {
                target: root
                property: "wifiWave"
                to: 0.18
                duration: 620
                easing.type: Easing.OutCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 160
                }
                NumberAnimation {
                    target: root
                    property: "wifiSlash"
                    to: 1
                    duration: 460
                    easing.type: Easing.OutCubic
                }
            }
        }
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
        id: islandHover

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
    readonly property list<string> pages: [...(inCall ? ["callFull"] : []), ...(transfer ? ["transferFull"] : []), ...(Recorder.running ? ["recordFull"] : []), ...(clockKind !== "" ? ["clock"] : []), ...(IdleInhibitor.enabled ? ["caffeine"] : []), ...(Island.agents ? ["agents"] : []), "info", "perf", ...(hasMedia ? ["player"] : [])]
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
    ServiceRef {
        service: root.paged && !("refCount" in NetworkUsage) ? NetworkUsage : null
    }
    // Fréquence moyenne CPU (GHz), ventilateur (tr/min), charge et top processus temps réel (actifs uniquement sur la page Perf)
    property real cpuGhz
    property int fanRpm: -1
    property real tempPeak
    property real perfLoad: 0
    property int perfProcCount: 0
    property string perfSort: "cpu" // "cpu" ou "ram"
    property var perfPrevSnap: null
    property list<var> perfApps: []

    readonly property list<var> topProcs: {
        const list = [...perfApps];
        if (perfSort === "ram")
            list.sort((a, b) => (b.rss - a.rss) || (b.cpu - a.cpu));
        else
            list.sort((a, b) => (b.cpu - a.cpu) || (b.rss - a.rss));
        return list.slice(0, 3);
    }

    function fmtRamKb(kb: real): string {
        if (!(kb > 0))
            return "0 Mo";
        if (kb >= 1048576)
            return `${(kb / 1048576).toFixed(kb >= 10485760 ? 0 : 1).replace(".", ",")} Go`;
        return `${Math.max(1, Math.round(kb / 1024))} Mo`;
    }

    function perfAppLabel(key: string): string {
        const k = (key ?? "").trim();
        const map = {
            chrome: "Chrome",
            chromium: "Chromium",
            firefox: "Firefox",
            antigravity: "Antigravity",
            code: "VS Code",
            quickshell: "Shell",
            kitty: "Kitty",
            Hyprland: "Hyprland",
            "node-MainThread": "Node.js",
            node: "Node.js",
            language_server: "LSP",
            nautilus: "Fichiers",
            pulsar: "Pulsar",
            onde: "Onde",
            pipewire: "PipeWire",
            wireplumber: "Audio"
        };
        if (map[k])
            return map[k];
        const clean = k.replace(/\.py$/i, "").replace(/^proton\.vpn\.daemon$/i, "Proton VPN");
        return clean.length > 0 ? clean.charAt(0).toUpperCase() + clean.slice(1) : "?";
    }

    function openMonitorApp(): void {
        root.expanded = false;
        Quickshell.execDetached(["sh", "-c", 'if [ -x "$HOME/.local/bin/pulsar" ]; then exec "$HOME/.local/bin/pulsar"; elif command -v pulsar >/dev/null 2>&1; then exec pulsar; elif command -v btop >/dev/null 2>&1; then exec kitty -e btop; else exec kitty -e top; fi']);
    }

    function focusProcessApp(key: string): void {
        const needle = (key ?? "").toLowerCase().replace(/\.py$/, "");
        if (needle) {
            for (const t of Hypr.toplevels.values) {
                const ipc = t.lastIpcObject ?? {};
                const cls = String(ipc.class ?? "").toLowerCase();
                const title = String(ipc.title ?? "").toLowerCase();
                if ((cls && (cls.includes(needle) || needle.includes(cls))) || (needle === "chrome" && /chrom|brave/.test(cls)) || (title && needle.length >= 4 && title.includes(needle))) {
                    const addr = String(ipc.address ?? "").replace(/^0x/, "");
                    if (addr) {
                        root.expanded = false;
                        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${addr}" })` : `focuswindow address:0x${addr}`);
                        return;
                    }
                }
            }
        }
        openMonitorApp();
    }

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

        command: ["python3", "-c", `
import glob, json, os
freqs = []
for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"):
    try: freqs.append(int(open(p).read().strip()))
    except Exception: pass
fan = -1
for p in glob.glob("/sys/class/hwmon/*/fan1_input"):
    try: fan = int(open(p).read().strip()); break
    except Exception: pass
load1 = 0.0
try: load1 = float(open("/proc/loadavg").read().split()[0])
except Exception: pass
pg = os.sysconf("SC_PAGE_SIZE") // 1024
hz = os.sysconf("SC_CLK_TCK")
ncpu = os.cpu_count() or 1
me = os.getpid()
apps = {}
total_p = 0
for pid in os.listdir("/proc"):
    if not pid.isdigit(): continue
    ipid = int(pid)
    if ipid == me: continue
    try:
        st = open(f"/proc/{pid}/stat").read()
        i, j = st.index("("), st.rindex(")")
        comm = st[i+1:j]
        f = st[j+2:].split()
        ticks = int(f[11]) + int(f[12])
        rss = int(f[21]) * pg
    except Exception: continue
    total_p += 1
    if rss == 0 or comm in ("fuser", "ps", "sh", "dash"): continue
    key = comm
    if comm.startswith("python"):
        try:
            args = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\\0")
            sc = next((os.path.basename(a.decode("utf-8", "ignore")) for a in args[1:] if a and not a.startswith(b"-")), "")
            if sc and not sc.startswith("-"): key = sc
        except Exception: pass
    elif comm.startswith("chrome") or comm == "chromium": key = "chrome"
    elif comm.startswith("firefox") or comm in ("Web Content", "Isolated Web Co", "RDD Process", "Socket Process"): key = "firefox"
    elif comm.startswith("antigravity"): key = "antigravity"
    elif comm.startswith("language_server"): key = "language_server"
    elif comm.startswith("node"): key = "node"
    elif comm.startswith("qs") or comm == "quickshell": key = "quickshell"
    if key.startswith("caelestia-") or key.startswith("ano-"): key = "quickshell"
    cur = apps.get(key)
    if cur:
        cur["t"] += ticks; cur["r"] += rss; cur["c"] += 1
    else:
        apps[key] = {"k": key, "t": ticks, "r": rss, "c": 1, "p": ipid}
vals = list(apps.values())
keep = {x["k"]: x for x in sorted(vals, key=lambda x: -x["r"])[:16]}
keep.update({x["k"]: x for x in sorted(vals, key=lambda x: -x["t"])[:16]})
print(json.dumps({"freq": sum(freqs)//len(freqs) if freqs else 0, "fan": fan, "load": round(load1, 2), "procs": total_p, "hz": hz, "ncpu": ncpu, "apps": list(keep.values())}))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.cpuGhz = (d.freq || 0) / 1e6;
                    root.fanRpm = d.fan !== undefined ? d.fan : -1;
                    root.perfLoad = d.load || 0;
                    root.perfProcCount = d.procs || 0;
                    const nowMs = Date.now();
                    const prev = root.perfPrevSnap;
                    const dt = prev ? (nowMs - prev.t) / 1000 : 0;
                    const hz = d.hz || 100;
                    const ncpu = d.ncpu || 1;
                    const nextTicks = {};
                    const out = [];
                    for (const a of (d.apps ?? [])) {
                        nextTicks[a.k] = a.t;
                        let cpu = 0;
                        if (prev && dt >= 0.25 && dt < 15 && prev.ticks[a.k] !== undefined) {
                            const delta = Math.max(0, a.t - prev.ticks[a.k]);
                            cpu = Math.min(100, (delta / hz / dt / ncpu) * 100);
                        }
                        out.push({
                            key: a.k,
                            name: root.perfAppLabel(a.k),
                            cpu: Math.round(cpu * 10) / 10,
                            rss: a.r || 0,
                            count: a.c || 1,
                            pid: a.p || 0
                        });
                    }
                    root.perfPrevSnap = { t: nowMs, ticks: nextTicks };
                    root.perfApps = out;
                } catch (e) {}
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

    // NetworkUsage : ServiceRef (2.5.0 C++) ou compteur refCount (singleton QML) ;
    // préchauffage d'un relevé de processus dès l'ouverture de l'île pour un % CPU instantané
    onPagedChanged: {
        if ("refCount" in NetworkUsage)
            NetworkUsage.refCount += paged ? 1 : -1;
        if (paged && !sensorProc.running)
            sensorProc.running = true;
    }
    Component.onDestruction: {
        if (paged && "refCount" in NetworkUsage)
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
            } else if (root.mode === "agentsMini") {
                Agents.focus(Agents.lead);
            } else if (root.mode === "agentDone") {
                Agents.focus(root.agentDone);
                root.dismissCurrent();
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

        // ── repos : cadran Liquid Glass horloger (bureaux + date à gauche, heure roulante au centre, météo + télémétrie + batterie à droite) ──
        Face {
            id: idleFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property bool mediaMiniOn: root.hasMedia && root.playing && root.pageName !== "player"
            readonly property bool agentsMiniOn: Agents.busy && root.pageName !== "agents"
            readonly property bool focusMiniOn: FocusMode.active || Notifs.dnd
            readonly property bool btMiniOn: root.btConnected.length > 0
            readonly property bool muteMiniOn: Audio.muted
            readonly property bool vpnMiniOn: root.vpnOn

            active: root.mode === "idle"

            // Halo céleste discret derrière l'horloge, teinté selon l'humeur du système (charge, focus, agents, thème)
            Rectangle {
                x: Math.round(idleTime.x + idleTime.width / 2 - width / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(Math.max(96, parent.width - 48), 152)
                height: 30
                radius: 15
                opacity: root.hovered ? 1 : (Colours.light ? 0.6 : 0.85)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha(root.idleAccent, Colours.light ? 0.06 : 0.08) }
                    GradientStop { position: 0.5; color: Qt.alpha(root.idleAccent, Colours.light ? 0.13 : 0.17) }
                    GradientStop { position: 0.75; color: Qt.alpha(root.idleAccent, Colours.light ? 0.06 : 0.08) }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 240 }
                }
            }

            // Voile spéculaire qui suit le curseur au survol (0 % CPU au repos)
            Rectangle {
                id: idleHoverSheen

                x: idleFace.hoverX - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 112
                height: 36
                radius: 18
                opacity: root.hovered ? 1 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: Qt.alpha("#ffffff", Colours.light ? 0.08 : 0.06) }
                    GradientStop { position: 0.5; color: Qt.alpha(root.idleAccent, Colours.light ? 0.12 : 0.14) }
                    GradientStop { position: 0.7; color: Qt.alpha("#ffffff", Colours.light ? 0.08 : 0.06) }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on x {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }

            // Caustique optique sur la lèvre inférieure de la capsule (teintée par l'état actif)
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(80, parent.width - 52)
                height: 1
                opacity: root.hovered ? 0.44 : 0.22
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.26; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(root.idleAccent, 0.92) }
                    GradientStop { position: 0.74; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 220 }
                }
            }

            // Point lumineux de caustique qui glisse sur le rebord sous le curseur
            Rectangle {
                x: Math.max(24, Math.min(idleFace.width - width - 24, idleFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 68
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.72 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on x {
                    NumberAnimation { duration: 95; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }
            }

            // ── Aile gauche : Piste de bureaux vitrée · Date éditoriale · Pastille notifications non lues ──
            Row {
                id: idleDate

                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                // Indicateur de bureaux cliquable dans une micro-piste vitrée (perles jusqu'à 5 bureaux, numéro au-delà)
                Item {
                    id: idleWsWrap

                    readonly property bool compactNum: root.wsLast > 5 || root.wsId > 5

                    anchors.verticalCenter: parent.verticalCenter
                    visible: Island.workspaces
                    width: visible ? wsTrack.implicitWidth + 8 : 0
                    height: 20

                    Rectangle {
                        id: wsTrack

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: idleWsWrap.compactNum ? Math.max(20, wsNumTxt.implicitWidth + 10) : wsBeadsRow.implicitWidth + 10
                        width: implicitWidth
                        height: 16
                        radius: 8
                        color: Qt.alpha(root.fg, root.hovered ? 0.1 : 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, root.hovered ? 0.2 : 0.14)

                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        // Reflet spéculaire supérieur sur la micro-piste
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.55
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.35 : 0.2
                        }

                        Row {
                            id: wsBeadsRow

                            anchors.centerIn: parent
                            visible: !idleWsWrap.compactNum
                            spacing: 3.5

                            Repeater {
                                model: idleWsWrap.compactNum ? 0 : Math.min(root.wsLast, 5)

                                Item {
                                    id: wsBead

                                    required property int index
                                    readonly property int wsNum: index + 1
                                    readonly property bool isCurrent: wsNum === root.wsId
                                    readonly property bool isOccupied: !!root.wsOccupied[wsNum]

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: isCurrent ? 13 : (isOccupied ? 4.5 : 3.5)
                                    height: 16

                                    Behavior on width {
                                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                                    }

                                    // Halo lumineux sous la pilule du bureau actif
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + 5
                                        height: 9
                                        radius: 4.5
                                        color: root.idleAccent
                                        opacity: wsBead.isCurrent ? (root.hovered ? 0.34 : 0.2) : 0
                                        visible: opacity > 0.01

                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                        Behavior on color { ColorAnimation { duration: 420 } }
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width
                                        height: wsBead.isCurrent ? 4.5 : (wsBead.isOccupied ? 4.5 : 3.5)
                                        radius: height / 2
                                        color: wsBead.isCurrent ? root.idleAccent : Qt.alpha(root.fg, wsBead.isOccupied ? 0.58 : 0.24)

                                        Behavior on color { ColorAnimation { duration: 240 } }
                                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (wsBead.wsNum !== root.wsId)
                                                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${wsBead.wsNum} })` : `workspace ${wsBead.wsNum}`);
                                        }
                                    }
                                }
                            }
                        }

                        // Repli compact au-delà de 5 bureaux
                        StyledText {
                            id: wsNumTxt

                            anchors.centerIn: parent
                            visible: idleWsWrap.compactNum
                            text: `${root.wsId}`
                            color: root.idleAccent
                            font.pointSize: 7.8
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                // Date éditoriale épurée (sans cadre lourd) : jour en petites capitales + quantième net
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4.5

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const s = I18n.locale.toString(Time.date, "ddd").replace(".", "");
                            return s.toUpperCase();
                        }
                        color: root.fgDim
                        font.pointSize: 8.4
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.65
                    }

                    StyledText {
                        id: dayNumText

                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.locale.toString(Time.date, "d")
                        color: root.fg
                        font.pointSize: 9.5
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }

                // Pastille concentrique des notifications non lues (Notifs.notClosed uniquement, zéro saut d'espacement)
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.idleUnread > 0 ? notifPill.implicitWidth + 7 : 0
                    height: 20
                    opacity: root.idleUnread > 0 ? 1 : 0
                    visible: opacity > 0.01
                    clip: true

                    Behavior on width {
                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 220 }
                    }

                    Rectangle {
                        id: notifPill

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: Math.max(20, notifBadgeRow.implicitWidth + 10)
                        width: implicitWidth
                        height: 18
                        radius: 9
                        scale: root.idleUnread > 0 ? 1 : 0.72
                        color: Qt.alpha(root.accent, Colours.light ? 0.16 : 0.15)
                        border.width: 0.5
                        border.color: Qt.alpha(root.accent, Colours.light ? 0.36 : 0.38)

                        Behavior on scale {
                            NumberAnimation { duration: 280; easing.type: Easing.OutBack }
                        }

                        // Micro reflet supérieur sur la pastille
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.5
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.35 : 0.22
                        }

                        Row {
                            id: notifBadgeRow

                            anchors.centerIn: parent
                            spacing: 2.5

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "notifications"
                                color: root.accent
                                fontStyle: Tokens.font.icon.size(9.5).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${root.idleUnread}`
                                color: root.fg
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }

            // Filet optique gauche effilé (toujours centré au pixel près entre aile gauche et horloge)
            Rectangle {
                visible: idleDate.implicitWidth > 2
                x: Math.round((18 + idleDate.implicitWidth + idleTime.x) / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 15
                radius: 0.5
                opacity: root.hovered ? 0.95 : 0.65
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.alpha(root.fg, 0.28) }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }

            // ── Centre : Horloge horlogère roulante (chiffres individuels + deux rubis optiques, 0 % CPU entre les minutes) ──
            Row {
                id: idleTime

                readonly property real leftBound: 18 + idleDate.implicitWidth
                readonly property real rightBound: idleFace.width - 18 - idleIcons.implicitWidth

                x: Math.round((leftBound + rightBound - width) / 2)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 0.5
                spacing: 0

                // Heures (2 chiffres à roulement indépendant)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -0.3

                    ClockDigit { digit: root.idleHourStr.charAt(0) || "0" }
                    ClockDigit { digit: root.idleHourStr.charAt(1) || "0" }
                }

                // Séparateur horloger : deux rubis optiques centrés + micro-pulsation unique à chaque minute
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 18

                    Column {
                        id: colonSep

                        anchors.centerIn: parent
                        spacing: 3.6
                        scale: root.hovered ? 1.12 : 1

                        Behavior on scale {
                            NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                        }

                        SequentialAnimation {
                            id: colonTick

                            NumberAnimation {
                                target: colonSep
                                property: "scale"
                                to: 1.28
                                duration: 140
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: colonSep
                                property: "scale"
                                to: 1.0
                                duration: 240
                                easing.type: Easing.OutBack
                            }
                        }

                        Connections {
                            target: Time

                            function onMinutesChanged(): void {
                                if (root.mode === "idle" && !root.hidden)
                                    colonTick.restart();
                            }
                        }

                        Repeater {
                            model: 2

                            Rectangle {
                                required property int index

                                width: 3
                                height: 3
                                radius: 1.5
                                color: root.idleAccent
                                opacity: root.hovered ? 1 : 0.92

                                Behavior on color { ColorAnimation { duration: 420 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 1.2
                                    height: 1.2
                                    radius: 0.6
                                    color: "#ffffff"
                                    opacity: 0.55
                                }
                            }
                        }
                    }
                }

                // Minutes (2 chiffres à roulement indépendant)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -0.3

                    ClockDigit { digit: root.idleMinStr.charAt(0) || "0" }
                    ClockDigit { digit: root.idleMinStr.charAt(1) || "0" }
                }
            }

            // Filet optique droit effilé (toujours centré au pixel près entre horloge et aile droite)
            Rectangle {
                visible: idleIcons.implicitWidth > 2
                x: Math.round((idleTime.x + idleTime.width + (idleFace.width - 18 - idleIcons.implicitWidth)) / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 15
                radius: 0.5
                opacity: root.hovered ? 0.95 : 0.65
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.alpha(root.fg, 0.28) }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }
            }

            // ── Aile droite : Météo en direct · Télémétrie concentrique (vie privée, étagère, média, agents, focus, BT, son, VPN) · Batterie ──
            Row {
                id: idleIcons

                readonly property bool hasBeforePrivacy: root.showIdleWeather
                readonly property bool hasBeforeShelf: hasBeforePrivacy || root.micInUse || root.camInUse
                readonly property bool hasBeforeMedia: hasBeforeShelf || root.shelf.length > 0
                readonly property bool hasBeforeAgents: hasBeforeMedia || idleFace.mediaMiniOn
                readonly property bool hasBeforeFocus: hasBeforeAgents || idleFace.agentsMiniOn
                readonly property bool hasBeforeBt: hasBeforeFocus || idleFace.focusMiniOn
                readonly property bool hasBeforeMute: hasBeforeBt || idleFace.btMiniOn
                readonly property bool hasBeforeVpn: hasBeforeMute || idleFace.muteMiniOn
                readonly property bool hasBeforeBatt: hasBeforeVpn || idleFace.vpnMiniOn

                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                // Complication météo en direct (icône jour/nuit teintée + halo subtil + température compacte)
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.showIdleWeather ? idleWeatherRow.implicitWidth : 0
                    height: 20
                    opacity: root.showIdleWeather ? 1 : 0
                    visible: opacity > 0.01
                    clip: true

                    Behavior on width {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 240 }
                    }

                    Row {
                        id: idleWeatherRow

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3.5

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15
                            height: 15

                            // Micro halo solaire / lunaire discret derrière le glyphe météo
                            Rectangle {
                                anchors.centerIn: parent
                                width: 15
                                height: 15
                                radius: 7.5
                                color: root.idleWeatherTint
                                opacity: Colours.light ? 0.14 : 0.18
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: root.idleWeatherIcon
                                color: root.idleWeatherTint
                                fontStyle: Tokens.font.icon.size(12.5).build()
                                fill: 1
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.idleTempShort
                            color: root.fg
                            font.pointSize: 9.2
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                // Points de confidentialité (micro orange / caméra verte)
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.micInUse ? 9 + (idleIcons.hasBeforePrivacy ? 6 : 0) : 0
                    height: 20
                    visible: width > 0.5

                    PrivacyDot {
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        anchors.verticalCenter: parent.verticalCenter
                        dotColor: "#ff9f0a"
                    }
                }
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.camInUse ? 9 + (idleIcons.hasBeforePrivacy || root.micInUse ? 6 : 0) : 0
                    height: 20
                    visible: width > 0.5

                    PrivacyDot {
                        anchors.right: parent.right
                        anchors.rightMargin: 1
                        anchors.verticalCenter: parent.verticalCenter
                        dotColor: root.green
                    }
                }

                // Étagère de fichiers déposés (pilule concentrique)
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.shelf.length > 0 ? shelfPill.implicitWidth + (idleIcons.hasBeforeShelf ? 6 : 0) : 0
                    height: 20
                    opacity: root.shelf.length > 0 ? 1 : 0
                    visible: opacity > 0.01
                    clip: true

                    Behavior on width {
                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 220 }
                    }

                    Rectangle {
                        id: shelfPill

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: shelfCount.implicitWidth + 12
                        width: implicitWidth
                        height: 20
                        radius: 10
                        color: Qt.alpha(root.fg, 0.09)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.18)

                        Row {
                            id: shelfCount

                            anchors.centerIn: parent
                            spacing: 3

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "inventory_2"
                                color: root.fg
                                fontStyle: Tokens.font.icon.size(9.5).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${root.shelf.length}`
                                color: root.fg
                                font.pointSize: 7.8
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }

                // Complication média en direct (pochette vinyle circulaire + micro-spectre Cava 3 bandes)
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: idleFace.mediaMiniOn ? 38 + (idleIcons.hasBeforeMedia ? 6 : 0) : 0
                    height: 20
                    opacity: idleFace.mediaMiniOn ? 1 : 0
                    visible: opacity > 0.01
                    clip: true

                    Behavior on width {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 240 }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        height: 20
                        radius: 10
                        scale: idleFace.mediaMiniOn ? 1 : 0.72
                        color: Qt.alpha(root.accent, Colours.light ? 0.14 : 0.13)
                        border.width: 0.5
                        border.color: Qt.alpha(root.accent, 0.3)

                        Behavior on scale {
                            NumberAnimation { duration: 300; easing.type: Easing.OutBack }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            Cover {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 14
                                radius: 7
                            }

                            Bars {
                                anchors.verticalCenter: parent.verticalCenter
                                count: 3
                                barWidth: 1.8
                                maxHeight: 10
                                spacing: 1.5
                            }
                        }
                    }
                }

                // Agents IA au travail (avec compteur si plusieurs)
                IdleIcon {
                    shown: idleFace.agentsMiniOn
                    icon: "smart_toy"
                    tint: Agents.waiting > 0 ? "#ff9f0a" : Agents.kindColour(Agents.lead?.kind ?? "")
                    count: Agents.activeCount
                    leadGap: idleIcons.hasBeforeAgents ? 6 : 0
                }

                // Concentration ou Ne pas déranger
                IdleIcon {
                    shown: idleFace.focusMiniOn
                    icon: FocusMode.active ? FocusMode.info.icon : "do_not_disturb_on"
                    tint: FocusMode.active ? FocusMode.info.tint : "#bf5af2"
                    leadGap: idleIcons.hasBeforeFocus ? 6 : 0
                }

                // Bluetooth connecté (icône écouteurs pour CETW572/BX012, casque pour audio, sinon Bluetooth)
                IdleIcon {
                    shown: idleFace.btMiniOn
                    icon: root.btEarbuds ? "earbuds" : root.btAudio ? "headphones" : "bluetooth"
                    tint: root.green
                    leadGap: idleIcons.hasBeforeBt ? 6 : 0
                }

                // Son coupé (utile quand la barre est masquée)
                IdleIcon {
                    shown: idleFace.muteMiniOn
                    icon: "volume_off"
                    tint: root.red
                    leadGap: idleIcons.hasBeforeMute ? 6 : 0
                }

                // VPN actif
                IdleIcon {
                    shown: idleFace.vpnMiniOn
                    icon: "vpn_lock"
                    tint: root.green
                    leadGap: idleIcons.hasBeforeVpn ? 6 : 0
                }

                // Bloc batterie matériel : pourcentage tabulaire (si charge ou faible) + jauge vectorielle
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showBattery
                    width: root.showBattery ? battRow.implicitWidth + (idleIcons.hasBeforeBatt ? 8 : 0) : 0
                    height: 20

                    Row {
                        id: battRow

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4.5

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.batteryPctShown
                            text: `${Math.round(root.battery * 100)}%`
                            color: root.battCharging ? root.green : root.battery < 0.2 ? root.red : root.fgDim
                            font.pointSize: 8.8
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }

                        BatteryGlyph {
                            id: idleBatt

                            anchors.verticalCenter: parent.verticalCenter
                            pct: root.battery
                            charging: root.battCharging

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
                    text: I18n.tr("Connecté")
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
                    text: I18n.tr("Déconnecté")
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

        // ── Wi-Fi : balise radar à arcs vectoriels courbes, flux de paquets temps réel et télémétrie spectre ──
        Face {
            active: root.mode === "wifi"

            // Balise d'ondes Wi-Fi vectorielles dessinées et animées arc par arc
            Item {
                id: wifiBeacon

                anchors.left: parent.left
                anchors.leftMargin: root.wifiOn ? 18 : 16
                anchors.verticalCenter: parent.verticalCenter
                width: root.wifiOn ? 62 : 44
                height: root.wifiOn ? 60 : 42

                readonly property real cx: width * 0.5
                readonly property real cy: root.wifiOn ? 46 : 33
                readonly property color wavePrimary: !root.wifiOn ? root.red : root.wifiStrength < 35 ? "#ff9f0a" : "#38bdf8"
                readonly property color waveSecondary: !root.wifiOn ? root.red : root.wifiStrength < 35 ? "#ffd60a" : root.green

                // Halo lumineux derrière les arcs Wi-Fi
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * (0.88 + 0.14 * Math.sin(root.wifiLivePhase * Math.PI * 2))
                    height: width
                    radius: width / 2
                    color: Qt.alpha(wifiBeacon.wavePrimary, root.wifiOn ? 0.14 : 0.12)
                    border.width: 1
                    border.color: Qt.alpha(wifiBeacon.waveSecondary, root.wifiOn ? 0.28 : 0.22)
                    scale: 0.45 + 0.55 * root.wifiPop
                }

                // Onde sonar externe qui s'échappe vers le haut en continu
                Shape {
                    anchors.fill: parent
                    visible: root.wifiOn
                    preferredRendererType: Shape.CurveRenderer
                    opacity: Math.max(0, (1 - root.wifiLivePhase) * 0.65 * root.wifiWave)

                    ShapePath {
                        strokeWidth: 2.2
                        strokeColor: wifiBeacon.waveSecondary
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: wifiBeacon.cx
                            centerY: wifiBeacon.cy
                            radiusX: 28 + root.wifiLivePhase * 13
                            radiusY: 28 + root.wifiLivePhase * 13
                            startAngle: -136
                            sweepAngle: 92
                        }
                    }
                }

                // Les 3 arcs courbes Wi-Fi qui s'ouvrent en éventail + ondulation lumineuse continue
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    scale: 0.55 + 0.45 * root.wifiPop

                    // Arc interne (1)
                    ShapePath {
                        readonly property real prog: Math.max(0, Math.min(1, root.wifiWave * 1.75))
                        readonly property real pulse: 0.5 + 0.5 * Math.sin((root.wifiLivePhase * 2 - 0.15) * Math.PI)
                        readonly property bool lit: root.wifiOn && root.wifiStrength >= 15

                        strokeWidth: 3.2 + (lit ? pulse * 0.7 : 0)
                        strokeColor: !root.wifiOn ? Qt.alpha(root.red, 0.45) : lit ? Qt.tint(wifiBeacon.wavePrimary, Qt.alpha(wifiBeacon.waveSecondary, pulse * 0.65)) : root.fgFaint
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: wifiBeacon.cx
                            centerY: wifiBeacon.cy
                            radiusX: root.wifiOn ? 10.5 : 8
                            radiusY: root.wifiOn ? 10.5 : 8
                            startAngle: -90 - 44 * Math.max(0.08, Math.min(1, root.wifiWave * 1.75))
                            sweepAngle: 88 * Math.max(0.08, Math.min(1, root.wifiWave * 1.75))
                        }
                    }

                    // Arc médian (2)
                    ShapePath {
                        readonly property real prog: Math.max(0, Math.min(1, (root.wifiWave - 0.16) * 1.65))
                        readonly property real pulse: 0.5 + 0.5 * Math.sin((root.wifiLivePhase * 2 - 0.55) * Math.PI)
                        readonly property bool lit: root.wifiOn && root.wifiStrength >= 45

                        strokeWidth: 3.2 + (lit ? pulse * 0.8 : 0)
                        strokeColor: !root.wifiOn ? Qt.alpha(root.red, 0.35) : lit ? Qt.tint(wifiBeacon.wavePrimary, Qt.alpha(wifiBeacon.waveSecondary, pulse * 0.75)) : root.fgFaint
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: wifiBeacon.cx
                            centerY: wifiBeacon.cy
                            radiusX: root.wifiOn ? 18.5 : 14
                            radiusY: root.wifiOn ? 18.5 : 14
                            startAngle: -90 - 45 * Math.max(0.04, Math.min(1, (root.wifiWave - 0.16) * 1.65))
                            sweepAngle: 90 * Math.max(0.04, Math.min(1, (root.wifiWave - 0.16) * 1.65))
                        }
                    }

                    // Arc externe (3)
                    ShapePath {
                        readonly property real prog: Math.max(0, Math.min(1, (root.wifiWave - 0.32) * 1.6))
                        readonly property real pulse: 0.5 + 0.5 * Math.sin((root.wifiLivePhase * 2 - 0.95) * Math.PI)
                        readonly property bool lit: root.wifiOn && root.wifiStrength >= 72

                        strokeWidth: 3.3 + (lit ? pulse * 0.9 : 0)
                        strokeColor: !root.wifiOn ? Qt.alpha(root.red, 0.25) : lit ? Qt.tint(wifiBeacon.waveSecondary, Qt.alpha("#ffffff", pulse * 0.35)) : root.fgFaint
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: wifiBeacon.cx
                            centerY: wifiBeacon.cy
                            radiusX: root.wifiOn ? 26.5 : 20
                            radiusY: root.wifiOn ? 26.5 : 20
                            startAngle: -90 - 46 * Math.max(0.02, Math.min(1, (root.wifiWave - 0.32) * 1.6))
                            sweepAngle: 92 * Math.max(0.02, Math.min(1, (root.wifiWave - 0.32) * 1.6))
                        }
                    }

                    // Trait diagonal rouge animé en cas de coupure Wi-Fi
                    ShapePath {
                        strokeWidth: !root.wifiOn && root.wifiSlash > 0.01 ? 3.2 : 0
                        strokeColor: !root.wifiOn && root.wifiSlash > 0.01 ? root.red : "transparent"
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathMove {
                            x: wifiBeacon.cx - 14
                            y: wifiBeacon.cy - 24
                        }
                        PathLine {
                            x: (wifiBeacon.cx - 14) + 28 * root.wifiSlash
                            y: (wifiBeacon.cy - 24) + 26 * root.wifiSlash
                        }
                    }
                }

                // Point émetteur central au pied des ondes
                Rectangle {
                    x: wifiBeacon.cx - width / 2
                    y: wifiBeacon.cy - height / 2
                    width: root.wifiOn ? 8 : 6
                    height: width
                    radius: width / 2
                    color: root.wifiOn ? wifiBeacon.waveSecondary : root.red
                    scale: 0.4 + 0.6 * root.wifiPop
                }
            }

            // Colonne centrale : SSID, pastilles bande/sécurité et pont de paquets animés
            Column {
                anchors.left: wifiBeacon.right
                anchors.leftMargin: 12
                anchors.right: wifiRight.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Row {
                    width: parent.width
                    spacing: 6

                    StyledText {
                        width: Math.min(implicitWidth, parent.width - (wifiBandPill.visible ? wifiBandPill.width + 6 : 0) - (wifiSecPill.visible ? wifiSecPill.width + 6 : 0))
                        elide: Text.ElideRight
                        text: root.wifiOn ? (root.wifiSsid || root.wifiName || I18n.tr("Wi-Fi")) : I18n.tr("Wi-Fi déconnecté")
                        color: root.fg
                        font.pointSize: root.wifiOn ? 11.5 : 10
                        font.weight: Font.Bold
                    }

                    // Pastille fréquence (5 GHz / 6 GHz / 2,4 GHz)
                    Rectangle {
                        id: wifiBandPill

                        visible: root.wifiOn
                        anchors.verticalCenter: parent.verticalCenter
                        width: bandTxt.implicitWidth + 12
                        height: 18
                        radius: 9
                        color: Qt.alpha("#38bdf8", 0.18)
                        border.width: 1
                        border.color: Qt.alpha("#38bdf8", 0.42)
                        scale: 0.6 + 0.4 * root.wifiRing
                        opacity: root.wifiRing

                        StyledText {
                            id: bandTxt

                            anchors.centerIn: parent
                            text: root.wifiBand
                            color: "#38bdf8"
                            font.pointSize: 7.5
                            font.weight: Font.Bold
                        }
                    }

                    // Pastille sécurité (icône cadenas + WPA3/WPA2)
                    Rectangle {
                        id: wifiSecPill

                        visible: root.wifiOn
                        anchors.verticalCenter: parent.verticalCenter
                        width: secRow.implicitWidth + 10
                        height: 18
                        radius: 9
                        color: Qt.alpha(root.green, 0.15)
                        border.width: 1
                        border.color: Qt.alpha(root.green, 0.35)
                        scale: 0.6 + 0.4 * root.wifiRing
                        opacity: root.wifiRing

                        Row {
                            id: secRow

                            anchors.centerIn: parent
                            spacing: 3

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.wifiSecure ? "lock" : "lock_open"
                                color: root.wifiSecure ? root.green : "#ff9f0a"
                                fontStyle: Tokens.font.icon.size(10).build()
                                fill: 1
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.wifiSecure ? I18n.tr("Sécurisé") : I18n.tr("Ouvert")
                                color: root.wifiSecure ? root.green : "#ff9f0a"
                                font.pointSize: 7
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // Conduit de données animé (Routeur ⇄ flux de paquets lumineux ⇄ Ordinateur)
                Row {
                    visible: root.wifiOn
                    spacing: 7
                    opacity: root.wifiRing

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "router"
                        color: "#38bdf8"
                        fontStyle: Tokens.font.icon.size(13).build()
                    }

                    // Piste de paquets bidirectionnels
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54
                        height: 10

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 2
                            radius: 1
                            color: Qt.alpha(root.fg, 0.14)
                        }

                        Repeater {
                            model: 3

                            Rectangle {
                                required property int index
                                readonly property real phase: (root.wifiLivePhase + index / 3) % 1

                                y: 2
                                x: phase * (parent.width - width)
                                width: 8
                                height: 6
                                radius: 3
                                color: index === 0 ? root.green : "#38bdf8"
                                opacity: Math.sin(phase * Math.PI) * 0.95
                            }
                        }
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "laptop_chromebook"
                        color: root.green
                        fontStyle: Tokens.font.icon.size(13).build()
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.wifiQualityText
                        color: root.fgDim
                        font.pointSize: 8.5
                        font.weight: Font.Medium
                    }
                }

                // Sous-titre quand le Wi-Fi est coupé
                StyledText {
                    visible: !root.wifiOn
                    text: I18n.tr("Aucune liaison sans fil active")
                    color: root.fgDim
                    font.pointSize: 8.5
                }
            }

            // Télémétrie droite : égaliseur d'ondes en direct + jauge double-arc de puissance
            Item {
                id: wifiRight

                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                width: root.wifiOn ? 92 : wifiOffBadge.width
                height: 54

                Rectangle {
                    id: wifiOffBadge

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.wifiOn
                    width: wifiOffLbl.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: Qt.alpha(root.red, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(root.red, 0.38)

                    StyledText {
                        id: wifiOffLbl

                        anchors.centerIn: parent
                        text: I18n.tr("Hors ligne")
                        color: root.red
                        font.pointSize: 8.5
                        font.weight: Font.Bold
                    }
                }

                // 5 barres spectrales animées en continu
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.wifiOn
                    spacing: 3
                    height: 28

                    Repeater {
                        model: 5

                        Rectangle {
                            required property int index
                            readonly property bool lit: root.wifiStrength >= (index + 1) * 18
                            readonly property real barGrow: Math.max(0, Math.min(1, root.wifiRing * 1.45 - index * 0.12))
                            readonly property real wave: lit ? (0.84 + 0.16 * Math.sin((root.wifiLivePhase * 2 + index * 0.28) * Math.PI)) : 1

                            anchors.bottom: parent.bottom
                            width: 3.5
                            height: (7 + index * 4.5) * (0.2 + 0.8 * barGrow) * wave
                            radius: 1.75
                            color: !lit ? root.fgFaint : index >= 3 ? root.green : "#38bdf8"
                        }
                    }
                }

                // Jauge double-arc (externe = % signal, interne = qualité bande)
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.wifiOn
                    width: 52
                    height: 52

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        // Piste externe
                        ShapePath {
                            strokeWidth: 4
                            strokeColor: root.fgFaint
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: 26
                                centerY: 26
                                radiusX: 21
                                radiusY: 21
                                startAngle: 135
                                sweepAngle: 270
                            }
                        }

                        // Piste interne
                        ShapePath {
                            strokeWidth: 2.4
                            strokeColor: Qt.alpha("#38bdf8", 0.16)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: 26
                                centerY: 26
                                radiusX: 15.5
                                radiusY: 15.5
                                startAngle: 135
                                sweepAngle: 270
                            }
                        }

                        // Arc externe animé (% signal)
                        ShapePath {
                            strokeWidth: 4
                            strokeColor: root.wifiStrength < 35 ? "#ff9f0a" : root.green
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: 26
                                centerY: 26
                                radiusX: 21
                                radiusY: 21
                                startAngle: 135
                                sweepAngle: 270 * root.wifiRing * Math.max(0.08, root.wifiStrength / 100)
                            }
                        }

                        // Arc interne animé (débit / bande)
                        ShapePath {
                            strokeWidth: 2.4
                            strokeColor: "#38bdf8"
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap

                            PathAngleArc {
                                centerX: 26
                                centerY: 26
                                radiusX: 15.5
                                radiusY: 15.5
                                startAngle: 135
                                sweepAngle: 270 * root.wifiRing * (root.wifiFreq >= 4900 ? 0.92 : 0.68)
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: -2

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: `${Math.round(root.wifiStrength * root.wifiRing)}`
                            color: root.fg
                            font.pointSize: 9.5
                            font.weight: Font.Bold
                            font.features: {
                                "tnum": 1
                            }
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "%"
                            color: root.fgDim
                            font.pointSize: 6.5
                            font.weight: Font.Bold
                        }
                    }
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
                        running: root.mode === "transfer" && root.transferProgress < 0 && !root.transfer?.paused
                        from: 0
                        to: 360
                        duration: 1200
                        loops: Animation.Infinite
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.transfer?.paused ? "pause" : root.transfer?.kind === "copy" ? "content_copy" : root.transfer?.kind === "upload" ? "arrow_upward" : "arrow_downward"
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

        // ── téléchargement / copie / synchro Drive (console Liquid Glass) ──
        Face {
            id: transferFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property bool isCopy: root.transfer?.kind === "copy"
            readonly property bool isUpload: root.transfer?.kind === "upload"
            readonly property bool isPaused: !!(root.transfer?.paused)
            readonly property color trTint: isPaused ? "#ff9f0a" : isUpload ? root.green : isCopy ? "#818cf8" : (Colours.light ? "#0284c7" : "#38bdf8")
            readonly property color trTintDeep: isPaused ? "#d97706" : isUpload ? "#10b981" : isCopy ? "#6366f1" : "#0a84ff"
            readonly property string trEta: root.transferEta(root.transfer)

            active: root.mode === "transferFull"
            slide: root.pageSlide("transferFull")

            // Aura douce derrière l'emblème de transfert
            Rectangle {
                x: 12
                y: 10
                width: 240
                height: 64
                radius: 32
                opacity: Colours.light ? 0.34 : 0.58
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: Qt.alpha(transferFace.trTint, 0.16) }
                    GradientStop { position: 0.72; color: Qt.alpha(transferFace.trTint, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Caustique optique inférieure + point lumineux sous le curseur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.38 : 0.18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(transferFace.trTint, 0.92) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                x: Math.max(32, Math.min(transferFace.width - width - 32, transferFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // ── Rangée haute : Emblème chronographe + badges + nom fichier + dock actions ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 16
                height: 54

                Rectangle {
                    id: trBadge

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54
                    height: 54
                    radius: 16
                    border.width: 0.5
                    border.color: Qt.alpha(transferFace.trTint, 0.36)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(transferFace.trTint, Colours.light ? 0.15 : 0.14) }
                        GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.035) }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 28
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.34 : 0.2
                    }

                    Shape {
                        anchors.centerIn: parent
                        width: 44
                        height: 44
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 2.6
                            strokeColor: Qt.alpha(root.fg, 0.12)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 22; centerY: 22
                                radiusX: 18; radiusY: 18
                                startAngle: 135; sweepAngle: 270
                            }
                        }
                        ShapePath {
                            strokeWidth: 6.2
                            strokeColor: Qt.alpha(transferFace.trTint, 0.24)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 22; centerY: 22
                                radiusX: 18; radiusY: 18
                                startAngle: 135; sweepAngle: root.transferProgress >= 0 ? 270 * Math.max(0.04, root.transferProgress) : 95
                            }
                        }
                        ShapePath {
                            strokeWidth: 2.8
                            strokeColor: transferFace.trTint
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 22; centerY: 22
                                radiusX: 18; radiusY: 18
                                startAngle: 135; sweepAngle: root.transferProgress >= 0 ? 270 * Math.max(0.04, root.transferProgress) : 95
                            }
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: transferFace.isCopy ? "content_copy" : transferFace.isUpload ? "cloud_upload" : "download"
                        color: transferFace.trTint
                        fontStyle: Tokens.font.icon.size(18).build()
                        fill: 1
                    }
                }

                Column {
                    anchors.left: trBadge.right
                    anchors.leftMargin: 14
                    anchors.right: trButtons.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: trBadge.verticalCenter
                    spacing: 3

                    Row {
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: trTagRow.implicitWidth + 12
                            height: 17
                            radius: 8.5
                            color: Qt.alpha(transferFace.trTint, 0.15)
                            border.width: 0.5
                            border.color: Qt.alpha(transferFace.trTint, 0.36)

                            Row {
                                id: trTagRow

                                anchors.centerIn: parent
                                spacing: 4

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: transferFace.trTint
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: transferFace.isPaused
                                        ? I18n.tr("EN PAUSE")
                                        : transferFace.isCopy
                                            ? I18n.tr("COPIE SYSTÈME")
                                            : transferFace.isUpload
                                                ? I18n.tr("SYNCHRO DRIVE")
                                                : I18n.tr("TÉLÉCHARGEMENT")
                                    color: transferFace.trTint
                                    font.pointSize: 6.4
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.65
                                }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.transferProgress >= 0
                            width: trPctTxt.implicitWidth + 10
                            height: 17
                            radius: 8.5
                            color: Qt.alpha(root.fg, 0.07)
                            border.width: 0.5
                            border.color: Qt.alpha(root.fg, 0.14)

                            StyledText {
                                id: trPctTxt

                                anchors.centerIn: parent
                                text: `${Math.round(root.transferProgress * 100)}%`
                                color: root.fg
                                font.pointSize: 7.4
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.transfers.length > 1
                            width: trMoreTxt.implicitWidth + 10
                            height: 17
                            radius: 8.5
                            color: Qt.alpha(root.fg, 0.06)
                            border.width: 0.5
                            border.color: Qt.alpha(root.fg, 0.13)

                            StyledText {
                                id: trMoreTxt

                                anchors.centerIn: parent
                                text: I18n.tr("+%1").arg(root.transfers.length - 1)
                                color: root.fgDim
                                font.pointSize: 7.2
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: root.transfer?.name ?? ""
                        color: root.fg
                        font.pointSize: 11.5
                        font.weight: Font.Bold
                    }
                }

                // Dock d'actions vitré (Pause/Reprendre Drive · Dossier)
                Row {
                    id: trButtons

                    anchors.right: parent.right
                    anchors.verticalCenter: trBadge.verticalCenter
                    spacing: 7

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: transferFace.isUpload
                        width: 34
                        height: 34
                        radius: 17
                        scale: trPauseArea.pressed ? 0.92 : 1
                        color: Qt.alpha(transferFace.trTint, trPauseArea.pressed ? 0.28 : trPauseArea.containsMouse ? 0.2 : 0.13)
                        border.width: 0.5
                        border.color: Qt.alpha(transferFace.trTint, trPauseArea.containsMouse ? 0.5 : 0.34)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 16
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.34 : 0.2
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: transferFace.isPaused ? "play_arrow" : "pause"
                            color: transferFace.trTint
                            fontStyle: Tokens.font.icon.size(16).build()
                            fill: 1
                        }

                        MouseArea {
                            id: trPauseArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/drive-sync`, transferFace.isPaused ? "resume" : "pause"])
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: trDirRow.implicitWidth + 18
                        height: 34
                        radius: 17
                        scale: trDirArea.pressed ? 0.94 : 1
                        color: Qt.alpha(root.fg, trDirArea.pressed ? 0.18 : trDirArea.containsMouse ? 0.13 : 0.07)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, trDirArea.containsMouse ? 0.3 : 0.15)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(14, parent.width - 18)
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.32 : 0.18
                        }

                        Row {
                            id: trDirRow

                            anchors.centerIn: parent
                            spacing: 5

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "folder_open"
                                color: transferFace.trTint
                                fontStyle: Tokens.font.icon.size(14).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Dossier")
                                color: root.fg
                                font.pointSize: 8.2
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: trDirArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["xdg-open", root.transfer?.dir ?? Quickshell.env("HOME")])
                        }
                    }
                }
            }

            // ── Barre de progression liquide biseautée ──
            Rectangle {
                id: trBarTrack

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 78
                height: 7
                radius: 3.5
                color: Qt.alpha(root.fg, 0.08)
                border.width: 0.5
                border.color: Qt.alpha(root.fg, 0.14)
                clip: true

                Rectangle {
                    visible: root.transferProgress >= 0
                    width: parent.width * Math.max(0, root.transferProgress)
                    height: parent.height
                    radius: 3.5
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: transferFace.trTintDeep }
                        GradientStop { position: 1.0; color: transferFace.trTint }
                    }

                    // Reflet lumineux au bout de la jauge
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.width > 12
                        width: 10
                        height: parent.height
                        radius: 3.5
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.alpha("#ffffff", 0.55) }
                        }
                    }

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
                    radius: 3.5
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: transferFace.trTint }
                        GradientStop { position: 1.0; color: "transparent" }
                    }

                    NumberAnimation on x {
                        running: root.mode === "transferFull" && root.transferProgress < 0 && !transferFace.isPaused
                        from: -trWave.width
                        to: trWave.parent.width
                        duration: 1300
                        loops: Animation.Infinite
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            // ── Rangée basse : Télémétrie (Volume transféré · Débit temps réel · ETA) ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 91
                height: 22

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Pilule volume transféré (ou numéro de fichier Drive)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: trSizeTxt.implicitWidth + 14
                        height: 20
                        radius: 10
                        color: Qt.alpha(root.fg, 0.06)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.13)

                        StyledText {
                            id: trSizeTxt

                            anchors.centerIn: parent
                            text: {
                                const t = root.transfer;
                                if (!t)
                                    return "";
                                const prefix = transferFace.isUpload && t.count ? `${I18n.tr("Fichier %1").arg(t.count)} · ` : "";
                                return prefix + (t.total > 0 ? I18n.tr("%1 / %2").arg(root.fmtBytes(t.done)).arg(root.fmtBytes(t.total)) : root.fmtBytes(t.done));
                            }
                            color: root.fg
                            font.pointSize: 7.4
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    // Pilule débit en direct
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !transferFace.isPaused && (root.transfer?.speed ?? 0) > 0
                        width: trSpdRow.implicitWidth + 14
                        height: 20
                        radius: 10
                        color: Qt.alpha(transferFace.trTint, 0.12)
                        border.width: 0.5
                        border.color: Qt.alpha(transferFace.trTint, 0.3)

                        Row {
                            id: trSpdRow

                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "speed"
                                color: transferFace.trTint
                                fontStyle: Tokens.font.icon.size(10.5).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${root.fmtBytes(root.transfer?.speed ?? 0)}/s`
                                color: transferFace.trTint
                                font.pointSize: 7.4
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }

                // Droite : Pilule ETA / état en pause
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: transferFace.isPaused || transferFace.trEta !== ""
                    width: trEtaRow.implicitWidth + 14
                    height: 20
                    radius: 10
                    color: transferFace.isPaused ? Qt.alpha("#ff9f0a", 0.14) : Qt.alpha(root.fg, 0.06)
                    border.width: 0.5
                    border.color: transferFace.isPaused ? Qt.alpha("#ff9f0a", 0.34) : Qt.alpha(root.fg, 0.13)

                    Row {
                        id: trEtaRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: transferFace.isPaused ? "pause_circle" : "schedule"
                            color: transferFace.isPaused ? "#ff9f0a" : root.fgDim
                            fontStyle: Tokens.font.icon.size(10.5).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: transferFace.isPaused ? I18n.tr("En pause") : I18n.tr("reste %1").arg(transferFace.trEta)
                            color: transferFace.isPaused ? "#ff9f0a" : root.fgDim
                            font.pointSize: 7.4
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
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
                    text: root.fileDone?.kind === "copy" ? I18n.tr("Copie terminée") : root.fileDone?.kind === "upload" ? I18n.tr("Sauvegardé sur Google Drive") : I18n.tr("Téléchargement terminé")
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
                    tip: I18n.tr("Afficher dans le dossier")
                    onClicked: {
                        const p = root.fileDone?.path ?? "";
                        Quickshell.execDetached(["dbus-send", "--session", "--dest=org.freedesktop.FileManager1", "--type=method_call", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems", `array:string:file://${p}`, "string:"]);
                        root.pulse = "";
                    }
                }
                ShotButton {
                    icon: root.fileDone?.kind === "upload" ? "cloud" : "open_in_new"
                    tip: root.fileDone?.kind === "upload" ? I18n.tr("Ouvrir Google Drive") : I18n.tr("Ouvrir")
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", root.fileDone?.kind === "upload" ? "https://drive.google.com/drive/search?q=Sauvegarde%20PC" : root.fileDone?.path ?? ""]);
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
                    tip: I18n.tr("Dans 10 min")
                    onClicked: root.taskAlertSnooze(10)
                }
                // « Fait » : pastille verte avec son libellé
                Rectangle {
                    width: tdDoneRow.implicitWidth + 26
                    height: 40
                    radius: 20
                    color: "transparent"
                    // Verre liquide (iOS 27) sous le contenu
                    GlassControl {
                        anchors.fill: parent
                        radius: parent.radius
                        bevel: parent.height > 60 ? 16 : 0
                        tintColour: tdDoneArea.containsMouse ? Qt.lighter(root.green, 1.1) : root.green
                        visible: tintColour.a > 0.01
                        pressed: tdDoneArea.pressed
                        hovered: tdDoneArea.containsMouse
                        pointer: tdDoneArea.containsMouse ? Qt.point(tdDoneArea.mouseX / Math.max(1, width), tdDoneArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                    }
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
                            text: I18n.tr("Fait")
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
                    tip: I18n.tr("Ignorer")
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
                color: "transparent"
                // Verre liquide (iOS 27) sous le contenu
                GlassControl {
                    anchors.fill: parent
                    radius: parent.radius
                    bevel: parent.height > 60 ? 16 : 0
                    tintColour: root.fgFaint
                    visible: tintColour.a > 0.01
                    pressed: gaugeArea.pressed
                    hovered: gaugeArea.containsMouse
                    pointer: gaugeArea.containsMouse ? Qt.point(gaugeArea.mouseX / Math.max(1, width), gaugeArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                }
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

        // ── chargeur branché / débranché : capsule plasma liquide, onde MagSafe, flux d'énergie et anneau double-arc ──
        Face {
            id: chargeFace

            readonly property bool plugged: root.chargePlugged
            readonly property bool lowBatt: !plugged && root.battery < 0.2
            readonly property color primaryTone: plugged ? root.green : lowBatt ? root.red : "#ff9f0a"
            readonly property color secondaryTone: plugged ? "#38bdf8" : lowBatt ? "#ff6961" : "#ffd60a"
            readonly property real shownLevel: Math.max(0.05, Math.min(1, root.battery * Math.min(1, root.chargeFill)))
            readonly property string timeText: {
                const d = UPower.displayDevice;
                const t = plugged ? d.timeToFull : d.timeToEmpty;
                if (!t || t <= 0)
                    return plugged ? (root.battery >= 0.99 ? I18n.tr("Charge complète") : I18n.tr("Alimentation secteur active")) : I18n.tr("Mode autonomie actif");
                const h = Math.floor(t / 3600);
                const m = Math.round((t % 3600) / 60);
                const dur = h > 0 ? `${h} h ${m.toString().padStart(2, "0")}` : `${m} min`;
                return plugged ? I18n.tr("Pleine dans %1").arg(dur) : I18n.tr("%1 d'autonomie").arg(dur);
            }

            active: root.mode === "charge"

            // Capsule d'énergie liquide + onde de choc MagSafe
            Item {
                id: bigBatt

                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: chargeFace.plugged ? 74 : 62
                height: chargeFace.plugged ? 36 : 30

                // Deux ondes MagSafe expansives au branchement / débranchement
                Repeater {
                    model: 2

                    Rectangle {
                        required property int index
                        readonly property real t: Math.max(0, Math.min(1, root.chargeWave * 1.35 - index * 0.24))

                        anchors.centerIn: shell
                        width: shell.width + t * 34
                        height: shell.height + t * 28
                        radius: height / 2
                        color: "transparent"
                        border.width: 2
                        border.color: index === 0 ? chargeFace.primaryTone : chargeFace.secondaryTone
                        opacity: t > 0 && t < 1 ? (1 - t) * 0.72 : 0
                    }
                }

                // Halo respirant derrière la cellule
                Rectangle {
                    anchors.centerIn: shell
                    width: shell.width + 14
                    height: shell.height + 12
                    radius: height / 2
                    color: Qt.alpha(chargeFace.primaryTone, chargeFace.plugged ? (0.14 + 0.08 * Math.sin(root.chargeLivePhase * Math.PI * 2)) : 0.1)
                    scale: 0.6 + 0.4 * root.chargeBolt
                }

                // Corps vitré de la batterie
                Rectangle {
                    id: shell

                    width: parent.width - 6
                    height: parent.height
                    radius: height * 0.34
                    color: Qt.alpha(root.fg, 0.06)
                    border.width: 2
                    border.color: Qt.alpha(chargeFace.primaryTone, chargeFace.plugged ? 0.65 : 0.45)
                    scale: 0.72 + 0.28 * Math.min(1, root.chargeBolt)

                    // Jauge plasma liquide avec dégradé dynamique
                    Rectangle {
                        id: fillBar

                        readonly property real m: 3.5

                        x: m
                        y: m
                        height: parent.height - m * 2
                        width: Math.max(radius * 2, (parent.width - m * 2) * chargeFace.shownLevel)
                        radius: shell.radius - m * 0.65
                        clip: true

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: chargeFace.plugged ? "#059669" : (chargeFace.lowBatt ? "#b91c1c" : "#d97706")
                            }
                            GradientStop {
                                position: 0.65
                                color: chargeFace.primaryTone
                            }
                            GradientStop {
                                position: 1.0
                                color: chargeFace.secondaryTone
                            }
                        }

                        // Particules / micro-bulles d'énergie qui traversent la cellule pendant la charge
                        Repeater {
                            model: chargeFace.plugged ? 5 : 0

                            Rectangle {
                                required property int index
                                readonly property real p: (root.chargeLivePhase + index * 0.2) % 1

                                x: p * Math.max(10, fillBar.width - 6)
                                y: (fillBar.height - height) * (0.2 + 0.6 * ((index * 37) % 10) / 10) + Math.sin((p + index) * Math.PI * 2) * 2.5
                                width: 4 + (index % 2) * 2
                                height: width
                                radius: width / 2
                                color: "#ffffff"
                                opacity: Math.sin(p * Math.PI) * 0.65
                            }
                        }

                        // Crête lumineuse au bord du liquide
                        Rectangle {
                            visible: chargeFace.plugged
                            anchors.right: parent.right
                            width: 6
                            height: parent.height
                            radius: 3
                            color: "#ffffff"
                            opacity: 0.45 + 0.35 * Math.sin(root.chargeLivePhase * Math.PI * 2)
                        }

                        // Balayage holographique continu
                        Rectangle {
                            visible: chargeFace.plugged
                            width: 24
                            height: parent.height * 2.2
                            y: -parent.height * 0.6
                            x: -width + (parent.width + width * 2) * ((root.chargeShine + root.chargeLivePhase * 0.6) % 1)
                            rotation: 22
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0
                                    color: "transparent"
                                }
                                GradientStop {
                                    position: 0.5
                                    color: Qt.rgba(1, 1, 1, 0.52)
                                }
                                GradientStop {
                                    position: 1
                                    color: "transparent"
                                }
                            }
                        }
                    }
                }

                // Borne positive (+) de la batterie
                Rectangle {
                    anchors.left: shell.right
                    anchors.leftMargin: 2
                    anchors.verticalCenter: shell.verticalCenter
                    width: 3.5
                    height: shell.height * 0.4
                    radius: width / 2
                    color: Qt.alpha(chargeFace.primaryTone, 0.7)
                    scale: 0.7 + 0.3 * Math.min(1, root.chargeBolt)
                }

                // Médaillon central : éclair MagSafe (branché) ou prise débranchée (sur batterie)
                Rectangle {
                    anchors.centerIn: shell
                    width: chargeFace.plugged ? 24 : 20
                    height: width
                    radius: width / 2
                    color: Qt.rgba(0.05, 0.08, 0.1, 0.62)
                    border.width: 1
                    border.color: Qt.alpha("#ffffff", 0.38)
                    scale: root.chargeBolt

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: chargeFace.plugged ? "bolt" : "power_off"
                        color: chargeFace.plugged ? "#ffd60a" : chargeFace.primaryTone
                        fontStyle: Tokens.font.icon.size(chargeFace.plugged ? 16 : 13).build()
                        fill: 1
                    }
                }
            }

            // Colonne centrale : titre + badge Watts + conduit d'énergie temps réel
            Column {
                anchors.left: bigBatt.right
                anchors.leftMargin: 14
                anchors.right: chargeRight.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Row {
                    width: parent.width
                    spacing: 6

                    StyledText {
                        elide: Text.ElideRight
                        text: chargeFace.plugged ? (root.battery >= 0.995 ? I18n.tr("Batterie chargée") : I18n.tr("Charge rapide")) : (chargeFace.lowBatt ? I18n.tr("Batterie faible") : I18n.tr("Sur batterie"))
                        color: root.fg
                        font.pointSize: chargeFace.plugged ? 11.5 : 10.5
                        font.weight: Font.Bold
                    }

                    // Pastille de puissance en Watts (ou Secteur / Autonomie)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: wattRow.implicitWidth + 10
                        height: 18
                        radius: 9
                        color: Qt.alpha(chargeFace.primaryTone, 0.17)
                        border.width: 1
                        border.color: Qt.alpha(chargeFace.primaryTone, 0.42)
                        scale: 0.6 + 0.4 * Math.min(1, root.chargeRing)
                        opacity: Math.min(1, root.chargeRing)

                        Row {
                            id: wattRow

                            anchors.centerIn: parent
                            spacing: 2

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chargeFace.plugged ? "bolt" : "eco"
                                color: chargeFace.primaryTone
                                fontStyle: Tokens.font.icon.size(10).build()
                                fill: 1
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.sysWatts >= 1 ? `${Math.round(root.sysWatts)} W` : (chargeFace.plugged ? "AC" : I18n.tr("Éco"))
                                color: chargeFace.primaryTone
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                            }
                        }
                    }
                }

                // Conduit d'impulsions énergétiques + estimation de durée
                Row {
                    spacing: 7
                    opacity: Math.min(1, root.chargeRing)

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chargeFace.plugged ? "power" : "schedule"
                        color: chargeFace.primaryTone
                        fontStyle: Tokens.font.icon.size(13).build()
                    }

                    // Piste d'impulsions lumineuses quand le chargeur alimente la batterie
                    Item {
                        visible: chargeFace.plugged
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 8

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 2
                            radius: 1
                            color: Qt.alpha(root.fg, 0.14)
                        }

                        Repeater {
                            model: 3

                            Rectangle {
                                required property int index
                                readonly property real p: (root.chargeLivePhase + index / 3) % 1

                                y: 1
                                x: p * (parent.width - width)
                                width: 8
                                height: 6
                                radius: 3
                                color: index === 0 ? "#38bdf8" : root.green
                                opacity: Math.sin(p * Math.PI) * 0.95
                            }
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chargeFace.timeText
                        color: root.fgDim
                        font.pointSize: 8.5
                        font.weight: Font.Medium
                    }
                }
            }

            // Anneau d'énergie MagSafe double-arc + compteur tabulaire à droite
            Item {
                id: chargeRight

                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                width: chargeFace.plugged ? 54 : 46
                height: width

                readonly property real ringR: width * 0.5 - 4.5
                readonly property real sweepDeg: 360 * chargeFace.shownLevel * Math.min(1, root.chargeRing)
                readonly property real tipRad: (-90 + sweepDeg) * Math.PI / 180

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    // Piste externe
                    ShapePath {
                        strokeWidth: 4.2
                        strokeColor: root.fgFaint
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: chargeRight.width * 0.5
                            centerY: chargeRight.height * 0.5
                            radiusX: chargeRight.ringR
                            radiusY: chargeRight.ringR
                            startAngle: -90
                            sweepAngle: 360
                        }
                    }

                    // Halo interne cyan/ambre
                    ShapePath {
                        strokeWidth: 1.8
                        strokeColor: Qt.alpha(chargeFace.secondaryTone, 0.25)
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: chargeRight.width * 0.5
                            centerY: chargeRight.height * 0.5
                            radiusX: chargeRight.ringR - 5
                            radiusY: chargeRight.ringR - 5
                            startAngle: -90
                            sweepAngle: 360 * Math.min(1, root.chargeRing)
                        }
                    }

                    // Arc principal de niveau de batterie
                    ShapePath {
                        strokeWidth: 4.2
                        strokeColor: chargeFace.primaryTone
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: chargeRight.width * 0.5
                            centerY: chargeRight.height * 0.5
                            radiusX: chargeRight.ringR
                            radiusY: chargeRight.ringR
                            startAngle: -90
                            sweepAngle: chargeRight.sweepDeg
                        }
                    }
                }

                // Perle lumineuse en tête de l'arc MagSafe
                Rectangle {
                    visible: chargeFace.plugged
                    x: chargeRight.width * 0.5 + Math.cos(chargeRight.tipRad) * chargeRight.ringR - width * 0.5
                    y: chargeRight.height * 0.5 + Math.sin(chargeRight.tipRad) * chargeRight.ringR - height * 0.5
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "#ffffff"
                    border.width: 1.5
                    border.color: chargeFace.secondaryTone
                }

                Column {
                    anchors.centerIn: parent
                    spacing: -2

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: `${Math.round(root.battery * 100 * Math.min(1, root.chargeFill))}`
                        color: root.fg
                        font.pointSize: chargeFace.plugged ? 10 : 9
                        font.weight: Font.Bold
                        font.features: {
                            "tnum": 1
                        }
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "%"
                        color: chargeFace.primaryTone
                        font.pointSize: 6.5
                        font.weight: Font.Bold
                    }
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
                    text: I18n.tr("Capture d'écran")
                    color: root.fg
                    font.pointSize: 11
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.shotSaved ? I18n.tr("Enregistrée et copiée") : I18n.tr("Copiée dans le presse-papiers")
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
                    tip: I18n.tr("Annoter")
                    onClicked: {
                        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "annotate", "open", root.shotPath]);
                        root.closeShot();
                    }
                }
                ShotButton {
                    icon: root.shotSaved ? "folder_open" : "download"
                    tip: root.shotSaved ? I18n.tr("Dossier") : I18n.tr("Enregistrer")
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
                text: I18n.tr("Bureau %1").arg(root.wsId)
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

                // Petit rebond à chaque pastille (copie, Wi-Fi, VPN, Verr. Maj)
                readonly property int tick: root.blipTick

                onTickChanged: if (Motion.enabled) blipBounce.restart()

                SequentialAnimation {
                    id: blipBounce

                    NumberAnimation {
                        target: blipBadge
                        property: "scale"
                        from: 0.55
                        to: 1.2
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: blipBadge
                        property: "scale"
                        to: 1
                        duration: 240
                        easing.type: Easing.OutBack
                    }
                }

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

        // ── caféine : cadran anti-veille Liquid Glass avec chronographe live et sélecteur rapide de durée ──
        Face {
            id: caffFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property bool timed: IdleInhibitor.until > 0
            readonly property color caffTint: timed ? (Colours.light ? "#c77700" : "#ff9f0a") : root.accent
            readonly property real totalSpan: timed ? Math.max(60000, IdleInhibitor.until - (IdleInhibitor.enabledSince ? IdleInhibitor.enabledSince.getTime() : IdleInhibitor.until - 3600000)) : 1
            readonly property real ratio: timed ? Math.max(0.02, Math.min(1, IdleInhibitor.remaining / totalSpan)) : 1

            active: root.mode === "caffeine"
            slide: root.pageSlide("caffeine")

            // Aura douce derrière l'emblème caféine
            Rectangle {
                x: 12
                y: 10
                width: 210
                height: 64
                radius: 32
                opacity: Colours.light ? 0.35 : 0.6
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: Qt.alpha(caffFace.caffTint, 0.14) }
                    GradientStop { position: 0.72; color: Qt.alpha(caffFace.caffTint, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Caustique optique inférieure + point lumineux sous le curseur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.36 : 0.18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(caffFace.caffTint, 0.9) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                x: Math.max(32, Math.min(caffFace.width - width - 32, caffFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // ── Rangée haute : Emblème chronographe vitré + état + bouton Désactiver ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 16
                height: 54

                Rectangle {
                    id: caffBadge

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52
                    height: 52
                    radius: 16
                    border.width: 0.5
                    border.color: Qt.alpha(caffFace.caffTint, 0.34)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(caffFace.caffTint, Colours.light ? 0.14 : 0.13) }
                        GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.035) }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 28
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.34 : 0.2
                    }

                    Shape {
                        anchors.centerIn: parent
                        width: 42
                        height: 42
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 2.6
                            strokeColor: Qt.alpha(root.fg, 0.12)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 21; centerY: 21
                                radiusX: 17.5; radiusY: 17.5
                                startAngle: 135; sweepAngle: 270
                            }
                        }
                        ShapePath {
                            strokeWidth: 6.2
                            strokeColor: Qt.alpha(caffFace.caffTint, 0.22)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 21; centerY: 21
                                radiusX: 17.5; radiusY: 17.5
                                startAngle: 135; sweepAngle: 270 * caffFace.ratio
                            }
                        }
                        ShapePath {
                            strokeWidth: 2.8
                            strokeColor: caffFace.caffTint
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 21; centerY: 21
                                radiusX: 17.5; radiusY: 17.5
                                startAngle: 135; sweepAngle: 270 * caffFace.ratio
                            }
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "coffee"
                        color: caffFace.caffTint
                        fontStyle: Tokens.font.icon.size(18).build()
                        fill: 1
                    }
                }

                Column {
                    anchors.left: caffBadge.right
                    anchors.leftMargin: 14
                    anchors.right: caffStopPill.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: caffBadge.verticalCenter
                    spacing: 2

                    Row {
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: caffTagTxt.implicitWidth + 12
                            height: 16
                            radius: 8
                            color: Qt.alpha(caffFace.caffTint, 0.14)
                            border.width: 0.5
                            border.color: Qt.alpha(caffFace.caffTint, 0.34)

                            StyledText {
                                id: caffTagTxt

                                anchors.centerIn: parent
                                text: caffFace.timed ? I18n.tr("MAINTIEN TEMPORISÉ") : I18n.tr("ANTI-VEILLE CONTINU")
                                color: caffFace.caffTint
                                font.pointSize: 6.6
                                font.weight: Font.Bold
                                font.letterSpacing: 0.65
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: caffFace.timed
                                ? I18n.tr("jusqu'à %1").arg(Qt.formatTime(new Date(IdleInhibitor.until), "HH:mm"))
                                : I18n.tr("depuis %1").arg(Qt.formatTime(IdleInhibitor.enabledSince, "HH:mm"))
                            color: root.fgDim
                            font.pointSize: 7.4
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: caffFace.timed ? I18n.tr("%1 restantes").arg(IdleInhibitor.remainingText()) : I18n.tr("L'écran reste allumé")
                        color: root.fg
                        font.pointSize: 12
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }

                // Pilule d'arrêt rapide rouge translucide
                Rectangle {
                    id: caffStopPill

                    anchors.right: parent.right
                    anchors.verticalCenter: caffBadge.verticalCenter
                    width: caffStopRow.implicitWidth + 22
                    height: 36
                    radius: 18
                    scale: caffStopArea.pressed ? 0.94 : 1
                    color: Qt.alpha(root.red, caffStopArea.pressed ? 0.28 : caffStopArea.containsMouse ? 0.22 : 0.14)
                    border.width: 0.5
                    border.color: Qt.alpha(root.red, caffStopArea.containsMouse ? 0.55 : 0.34)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 20
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.18
                    }

                    Row {
                        id: caffStopRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "stop_circle"
                            color: root.red
                            fontStyle: Tokens.font.icon.size(14).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Désactiver")
                            color: root.fg
                            font.pointSize: 8.4
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: caffStopArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: IdleInhibitor.enabled = false
                    }
                }
            }

            // Filet horizontal effilé
            Rectangle {
                x: 24
                y: 77
                width: parent.width - 48
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 0.8; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // ── Barre rapide de durées : bascule immédiate 15m / 30m / 1h / 2h / ∞ + prolongation +15 min ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 85
                height: 26

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: [
                            { m: 15, label: "15 min" },
                            { m: 30, label: "30 min" },
                            { m: 60, label: "1 h" },
                            { m: 120, label: "2 h" },
                            { m: 0, label: "∞" }
                        ]

                        Rectangle {
                            id: caffPreset

                            required property var modelData
                            readonly property bool isCurrent: modelData.m === 0 && !caffFace.timed

                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(40, caffPreTxt.implicitWidth + 18)
                            height: 24
                            radius: 12
                            scale: caffPreArea.pressed ? 0.94 : 1
                            color: isCurrent
                                ? Qt.alpha(caffFace.caffTint, 0.2)
                                : Qt.alpha(root.fg, caffPreArea.pressed ? 0.16 : caffPreArea.containsMouse ? 0.11 : 0.06)
                            border.width: 0.5
                            border.color: isCurrent
                                ? Qt.alpha(caffFace.caffTint, 0.48)
                                : Qt.alpha(root.fg, caffPreArea.containsMouse ? 0.26 : 0.13)

                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 14
                                height: 1
                                radius: 0.5
                                color: "#ffffff"
                                opacity: Colours.light ? 0.3 : 0.16
                            }

                            StyledText {
                                id: caffPreTxt

                                anchors.centerIn: parent
                                text: caffPreset.modelData.label
                                color: caffPreset.isCurrent ? caffFace.caffTint : root.fg
                                font.pointSize: caffPreset.modelData.m === 0 ? 10 : 7.8
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }

                            MouseArea {
                                id: caffPreArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: IdleInhibitor.enableFor(caffPreset.modelData.m)
                            }
                        }
                    }
                }

                // Bouton +15 min (visible en mode temporisé)
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: caffFace.timed
                    width: plusCaffRow.implicitWidth + 16
                    height: 24
                    radius: 12
                    scale: plusCaffArea.pressed ? 0.94 : 1
                    color: Qt.alpha(caffFace.caffTint, plusCaffArea.pressed ? 0.28 : plusCaffArea.containsMouse ? 0.2 : 0.13)
                    border.width: 0.5
                    border.color: Qt.alpha(caffFace.caffTint, plusCaffArea.containsMouse ? 0.52 : 0.34)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: plusCaffRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "more_time"
                            color: caffFace.caffTint
                            fontStyle: Tokens.font.icon.size(11.5).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("+15 min")
                            color: root.fg
                            font.pointSize: 7.8
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }

                    MouseArea {
                        id: plusCaffArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: IdleInhibitor.extend(15)
                    }
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

        // ── agents IA au travail (compact) : anneau qui tourne, moteur, projet, outil en cours ──
        Face {
            active: root.mode === "agentsMini"
            inset: root.actsInset

            readonly property var lead: Agents.lead
            readonly property bool isWait: (lead?.status ?? "") === "waiting"
            readonly property color tint: isWait ? "#ff9f0a" : Agents.kindColour(lead?.kind ?? "")

            AgentSpinner {
                id: amSpin

                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                tint: parent.tint
                spinning: root.mode === "agentsMini" && !parent.isWait
                letter: Agents.kindLetter(parent.lead?.kind ?? "")
            }

            Rectangle {
                id: amKindPill

                anchors.left: amSpin.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: amKindTxt.implicitWidth + 10
                height: 16
                radius: 8
                color: Qt.alpha(parent.tint, 0.18)
                border.width: 0.5
                border.color: Qt.alpha(parent.tint, 0.38)

                StyledText {
                    id: amKindTxt

                    anchors.centerIn: parent
                    text: Agents.kindShort(parent.parent.lead?.kind ?? "")
                    color: parent.parent.tint
                    font.pointSize: 6.2
                    font.weight: Font.Bold
                    font.letterSpacing: 0.45
                }
            }

            StyledText {
                id: amName

                anchors.left: amKindPill.right
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 108)
                elide: Text.ElideRight
                text: parent.lead?.project ?? ""
                color: root.fg
                font.pointSize: 9.6
                font.weight: Font.Bold
            }

            StyledText {
                anchors.left: amName.right
                anchors.leftMargin: 7
                anchors.right: amRight.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: parent.isWait ? I18n.tr("Attend validation…") : (parent.lead?.focus || parent.lead?.tool || I18n.tr("Réfléchit…"))
                color: parent.isWait ? "#ff9f0a" : root.fgDim
                font.pointSize: 8.8
            }

            StyledText {
                id: amRight

                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: Agents.activeCount > 1 ? `×${Agents.activeCount}` : Agents.elapsed(parent.lead?.since ?? Agents.now)
                color: parent.tint
                font.pointSize: 9.8
                font.weight: Font.Bold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── AGENT OS : cockpit multi-agents Liquid Glass (Antigravity, AGY CLI, Claude, Codex, Copilot, OpenCode…) ──
        Face {
            id: agentsFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property color leadTint: Agents.waiting > 0 ? "#ff9f0a" : (Agents.lead ? Agents.kindColour(Agents.lead.kind) : root.accent)
            readonly property bool showFilters: Agents.presentKinds.length > 1 || Agents.shown.length > 2
            readonly property bool showLauncherBar: Agents.launcherOpen && Agents.shown.length > 0

            active: root.mode === "agents"
            slide: root.pageSlide("agents")

            // Aura subtile en tête colorée par l'agent actif
            Rectangle {
                x: 16
                y: 8
                width: 280
                height: 46
                radius: 23
                opacity: Colours.light ? 0.34 : 0.58
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: Qt.alpha(agentsFace.leadTint, 0.15) }
                    GradientStop { position: 0.75; color: Qt.alpha(agentsFace.leadTint, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Caustique optique inférieure + point lumineux sous le curseur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.38 : 0.18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(agentsFace.leadTint, 0.9) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                x: Math.max(32, Math.min(agentsFace.width - width - 32, agentsFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // En-tête AGENT OS
            Item {
                id: agHead

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                y: 13
                height: 26

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        radius: 9
                        border.width: 0.5
                        border.color: Qt.alpha(agentsFace.leadTint, 0.4)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(agentsFace.leadTint, 0.2) }
                            GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.04) }
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 14
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.35 : 0.22
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "hub"
                            color: agentsFace.leadTint
                            fontStyle: Tokens.font.icon.size(14).build()
                            fill: 1
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("AGENT OS")
                        color: root.fg
                        font.pointSize: 8.6
                        font.weight: Font.Black
                        font.letterSpacing: 0.85
                    }

                    // Pastille d'état en direct
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: agStatusRow.implicitWidth + 14
                        height: 19
                        radius: 9.5
                        color: Agents.activeCount > 0 ? Qt.alpha(agentsFace.leadTint, 0.15) : Qt.alpha(root.fg, 0.065)
                        border.width: 0.5
                        border.color: Agents.activeCount > 0 ? Qt.alpha(agentsFace.leadTint, 0.36) : Qt.alpha(root.fg, 0.14)

                        Row {
                            id: agStatusRow

                            anchors.centerIn: parent
                            spacing: 4.5

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5.5
                                height: 5.5
                                radius: 2.75
                                color: Agents.activeCount > 0 ? agentsFace.leadTint : root.green

                                SequentialAnimation on opacity {
                                    running: Agents.activeCount > 0 && root.mode === "agents"
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.35; duration: 750; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutSine }
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (Agents.waiting > 0 && Agents.working > 0)
                                        return I18n.tr("%1 actif · %2 attente").arg(Agents.working).arg(Agents.waiting);
                                    if (Agents.waiting > 0)
                                        return I18n.tr("%1 en attente").arg(Agents.waiting);
                                    if (Agents.working > 0)
                                        return I18n.tr("%1 actif(s)").arg(Agents.working);
                                    return Agents.shown.length > 0 ? I18n.tr("En veille") : I18n.tr("Prêt");
                                }
                                color: Agents.activeCount > 0 ? agentsFace.leadTint : root.fgDim
                                font.pointSize: 7.3
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    // Pastille sous-agents actifs
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Agents.totalSubagents > 0
                        width: agSubTxt.implicitWidth + 12
                        height: 19
                        radius: 9.5
                        color: Qt.alpha("#a78bfa", 0.16)
                        border.width: 0.5
                        border.color: Qt.alpha("#a78bfa", 0.36)

                        StyledText {
                            id: agSubTxt

                            anchors.centerIn: parent
                            text: I18n.tr("+%1 sub").arg(Agents.totalSubagents)
                            color: "#a78bfa"
                            font.pointSize: 7.1
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Micro-télémétrie cumulée (tokens / fichiers)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Agents.totalTokens > 0 || Agents.totalFiles > 0
                        width: agStatTxt.implicitWidth + 12
                        height: 20
                        radius: 10
                        color: Qt.alpha(root.fg, 0.06)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.12)

                        StyledText {
                            id: agStatTxt

                            anchors.centerIn: parent
                            text: {
                                const parts = [];
                                if (Agents.totalFiles > 0)
                                    parts.push(I18n.tr("%1 fich.").arg(Agents.totalFiles));
                                if (Agents.totalTokens > 0)
                                    parts.push(`${Agents.fmtTokens(Agents.totalTokens)} tok`);
                                return parts.join(" · ");
                            }
                            color: root.fgDim
                            font.pointSize: 7.1
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    // Bouton lanceur rapide (+)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Agents.shown.length > 0
                        width: 24
                        height: 22
                        radius: 11
                        scale: launchToggleArea.pressed ? 0.92 : 1
                        color: Agents.launcherOpen
                            ? Qt.alpha(agentsFace.leadTint, 0.22)
                            : Qt.alpha(root.fg, launchToggleArea.containsMouse ? 0.14 : 0.07)
                        border.width: 0.5
                        border.color: Agents.launcherOpen
                            ? Qt.alpha(agentsFace.leadTint, 0.45)
                            : Qt.alpha(root.fg, launchToggleArea.containsMouse ? 0.3 : 0.15)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: Agents.launcherOpen ? "close" : "add"
                            color: Agents.launcherOpen ? agentsFace.leadTint : root.fg
                            fontStyle: Tokens.font.icon.size(13).build()
                        }

                        MouseArea {
                            id: launchToggleArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Agents.launcherOpen = !Agents.launcherOpen
                        }
                    }

                    // Pilule vitrée « Nettoyer » : retire les agents terminés
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Agents.doneShown > 0
                        width: cleanRow.implicitWidth + 14
                        height: 22
                        radius: 11
                        scale: cleanArea.pressed ? 0.94 : 1
                        color: Qt.alpha(root.fg, cleanArea.pressed ? 0.18 : cleanArea.containsMouse ? 0.13 : 0.07)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, cleanArea.containsMouse ? 0.3 : 0.15)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            id: cleanRow

                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "cleaning_services"
                                color: root.fgDim
                                fontStyle: Tokens.font.icon.size(11).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Agents.doneShown > 1 ? I18n.tr("Nettoyer (%1)").arg(Agents.doneShown) : I18n.tr("Nettoyer")
                                color: root.fg
                                font.pointSize: 7.4
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: cleanArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Agents.clean()
                        }
                    }
                }
            }

            // Séparateur horizontal effilé
            Rectangle {
                x: 22
                y: 44
                width: parent.width - 44
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 0.8; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Corps principal : lanceur rapide + filtres moteurs + liste scrollable des agents
            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.bottomMargin: 12
                y: 51
                spacing: 6

                // Tiroir Lanceur Rapide (quand ouvert via +)
                Row {
                    visible: agentsFace.showLauncherBar
                    width: parent.width
                    height: visible ? 30 : 0
                    spacing: 5

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Lancer")
                        color: root.fgDim
                        font.pointSize: 7.4
                        font.weight: Font.Bold
                    }

                    Repeater {
                        model: Agents.launchKinds

                        Rectangle {
                            id: lPill

                            required property string modelData
                            readonly property color tint: Agents.kindColour(modelData)

                            anchors.verticalCenter: parent.verticalCenter
                            width: lPillRow.implicitWidth + 14
                            height: 24
                            radius: 12
                            scale: lPillArea.pressed ? 0.93 : 1
                            color: Qt.alpha(tint, lPillArea.containsMouse ? 0.22 : 0.12)
                            border.width: 0.5
                            border.color: Qt.alpha(tint, lPillArea.containsMouse ? 0.52 : 0.28)

                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            Row {
                                id: lPillRow

                                anchors.centerIn: parent
                                spacing: 4

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Agents.kindLetter(lPill.modelData)
                                    color: lPill.tint
                                    font.pointSize: 7.2
                                    font.weight: Font.Black
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Agents.kindName(lPill.modelData)
                                    color: root.fg
                                    font.pointSize: 7.4
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                id: lPillArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Agents.launch(lPill.modelData)
                            }
                        }
                    }
                }

                // Barre de filtres moteurs Agent OS
                Flickable {
                    visible: agentsFace.showFilters
                    width: parent.width
                    height: visible ? 26 : 0
                    contentWidth: filterRow.implicitWidth
                    contentHeight: 26
                    clip: true
                    interactive: contentWidth > width
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: filterRow

                        height: 26
                        spacing: 5

                        // Pilule "Tous"
                        Rectangle {
                            readonly property bool sel: Agents.filter === "all"

                            anchors.verticalCenter: parent.verticalCenter
                            width: fAllTxt.implicitWidth + 14
                            height: 22
                            radius: 11
                            color: sel ? Qt.alpha(root.fg, 0.16) : Qt.alpha(root.fg, fAllArea.containsMouse ? 0.11 : 0.055)
                            border.width: 0.5
                            border.color: sel ? Qt.alpha(root.fg, 0.35) : Qt.alpha(root.fg, 0.12)

                            StyledText {
                                id: fAllTxt

                                anchors.centerIn: parent
                                text: I18n.tr("Tous (%1)").arg(Agents.shown.length)
                                color: sel ? root.fg : root.fgDim
                                font.pointSize: 7.3
                                font.weight: sel ? Font.Bold : Font.DemiBold
                                font.features: { "tnum": 1 }
                            }

                            MouseArea {
                                id: fAllArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Agents.setFilter("all")
                            }
                        }

                        // Pilule "Actifs" (si mélange actifs + terminés)
                        Rectangle {
                            readonly property bool sel: Agents.filter === "active"

                            visible: Agents.activeCount > 0 && Agents.doneShown > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: fActTxt.implicitWidth + 14
                            height: 22
                            radius: 11
                            color: sel ? Qt.alpha(agentsFace.leadTint, 0.22) : Qt.alpha(root.fg, fActArea.containsMouse ? 0.11 : 0.055)
                            border.width: 0.5
                            border.color: sel ? Qt.alpha(agentsFace.leadTint, 0.48) : Qt.alpha(root.fg, 0.12)

                            StyledText {
                                id: fActTxt

                                anchors.centerIn: parent
                                text: I18n.tr("Actifs (%1)").arg(Agents.activeCount)
                                color: sel ? agentsFace.leadTint : root.fgDim
                                font.pointSize: 7.3
                                font.weight: sel ? Font.Bold : Font.DemiBold
                                font.features: { "tnum": 1 }
                            }

                            MouseArea {
                                id: fActArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Agents.setFilter("active")
                            }
                        }

                        // Pilules par moteur présent
                        Repeater {
                            model: Agents.presentKinds

                            Rectangle {
                                id: fKindPill

                                required property var modelData
                                readonly property bool sel: Agents.filter === modelData.kind
                                readonly property color tint: Agents.kindColour(modelData.kind)

                                anchors.verticalCenter: parent.verticalCenter
                                width: fKindRow.implicitWidth + 14
                                height: 22
                                radius: 11
                                color: sel ? Qt.alpha(tint, 0.22) : Qt.alpha(tint, fKindArea.containsMouse ? 0.14 : 0.08)
                                border.width: 0.5
                                border.color: sel ? Qt.alpha(tint, 0.54) : Qt.alpha(tint, 0.22)

                                Row {
                                    id: fKindRow

                                    anchors.centerIn: parent
                                    spacing: 4.5

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: fKindPill.modelData.active > 0 ? fKindPill.tint : Qt.alpha(fKindPill.tint, 0.45)
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: `${Agents.kindName(fKindPill.modelData.kind)} ${fKindPill.modelData.total}`
                                        color: fKindPill.sel ? fKindPill.tint : root.fg
                                        font.pointSize: 7.3
                                        font.weight: fKindPill.sel ? Font.Bold : Font.DemiBold
                                        font.features: { "tnum": 1 }
                                    }
                                }

                                MouseArea {
                                    id: fKindArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Agents.setFilter(fKindPill.modelData.kind)
                                }
                            }
                        }
                    }
                }

                // État vide élégant avec lancement en 1 clic
                Rectangle {
                    visible: Agents.filteredShown.length === 0
                    width: parent.width
                    height: visible ? 106 : 0
                    radius: 14
                    color: Qt.alpha(root.fg, 0.045)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.12)

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 28
                        spacing: 10

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Agents.shown.length === 0
                                ? I18n.tr("Aucun agent actif — lance une session en un clic")
                                : I18n.tr("Aucun agent pour ce filtre")
                            color: root.fgDim
                            font.pointSize: 8.6
                            font.weight: Font.Medium
                        }

                        Flow {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Repeater {
                                model: Agents.launchKinds

                                Rectangle {
                                    id: emptyLPill

                                    required property string modelData
                                    readonly property color tint: Agents.kindColour(modelData)

                                    width: emptyLRow.implicitWidth + 16
                                    height: 28
                                    radius: 14
                                    scale: emptyLArea.pressed ? 0.94 : 1
                                    color: Qt.alpha(tint, emptyLArea.containsMouse ? 0.24 : 0.12)
                                    border.width: 0.5
                                    border.color: Qt.alpha(tint, emptyLArea.containsMouse ? 0.55 : 0.3)

                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                    Row {
                                        id: emptyLRow

                                        anchors.centerIn: parent
                                        spacing: 5

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Agents.kindLetter(emptyLPill.modelData)
                                            color: emptyLPill.tint
                                            font.pointSize: 8
                                            font.weight: Font.Black
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Agents.kindName(emptyLPill.modelData)
                                            color: root.fg
                                            font.pointSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    MouseArea {
                                        id: emptyLArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Agents.launch(emptyLPill.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Liste scrollable des cartes d'agents en verre biseauté
                Flickable {
                    id: agListFlick

                    visible: Agents.filteredShown.length > 0
                    width: parent.width
                    height: visible ? Math.min(316, agListCol.implicitHeight) : 0
                    contentWidth: width
                    contentHeight: agListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    Column {
                        id: agListCol

                        width: agListFlick.width
                        spacing: 6

                        Repeater {
                            model: Agents.filteredShown

                            Item {
                                id: agRow

                                required property var modelData
                                readonly property bool working: modelData.status === "working"
                                readonly property bool waiting: modelData.status === "waiting"
                                readonly property bool done: !working && !waiting
                                readonly property bool expanded: Agents.expandedId === modelData.id
                                readonly property color tint: Agents.kindColour(modelData.kind)
                                readonly property color stateCol: waiting ? "#ff9f0a" : working ? tint : root.green
                                readonly property bool hasSteps: (modelData.stepTotal ?? 0) > 0
                                readonly property bool hasMeta: Boolean(modelData.model || modelData.branch || (modelData.files ?? 0) > 0 || (modelData.tokens ?? 0) > 0 || hasSteps)

                                width: agListCol.width
                                height: expanded ? 124 : 68

                                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
                                    scale: agArea.pressed ? 0.988 : 1
                                    border.width: 0.5
                                    border.color: Qt.alpha(agRow.stateCol, agRow.expanded ? 0.52 : agArea.containsMouse ? 0.46 : 0.22)
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.alpha(agRow.stateCol, agArea.pressed ? 0.18 : agArea.containsMouse || agRow.expanded ? 0.13 : 0.085) }
                                        GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.03) }
                                    }

                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 160 } }

                                    // Reflet spéculaire supérieur sur la carte agent
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.topMargin: 1
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        height: 1
                                        radius: 0.5
                                        color: "#ffffff"
                                        opacity: Colours.light ? 0.32 : 0.16
                                    }

                                    // Épine lumineuse latérale d'état
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        y: 16
                                        width: 3
                                        height: agRow.expanded ? 90 : 36
                                        radius: 1.5
                                        color: agRow.stateCol

                                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }
                                }

                                MouseArea {
                                    id: agArea

                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    hoverEnabled: true
                                    cursorShape: (agRow.modelData.window || agRow.modelData.kind === "antigravity") ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton)
                                            Agents.toggleExpand(agRow.modelData);
                                        else
                                            Agents.focus(agRow.modelData);
                                    }
                                }

                                // Rangée principale (hauteur fixe 68px)
                                Item {
                                    id: agMainRow

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    y: 0
                                    height: 68

                                    AgentSpinner {
                                        id: agSpin

                                        anchors.left: parent.left
                                        anchors.leftMargin: 15
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 32
                                        tint: agRow.stateCol
                                        spinning: agRow.working && root.mode === "agents"
                                        done: agRow.done
                                        letter: Agents.kindLetter(agRow.modelData.kind)
                                    }

                                    Column {
                                        anchors.left: agSpin.right
                                        anchors.leftMargin: 11
                                        anchors.right: agRightCol.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2.5

                                        // Ligne 1 : Badge moteur + Projet · Titre + sous-agents
                                        Row {
                                            width: parent.width
                                            spacing: 5.5

                                            Rectangle {
                                                id: kindPill

                                                anchors.verticalCenter: parent.verticalCenter
                                                width: kindTxt.implicitWidth + 10
                                                height: 15
                                                radius: 7.5
                                                color: Qt.alpha(agRow.tint, 0.17)
                                                border.width: 0.5
                                                border.color: Qt.alpha(agRow.tint, 0.38)

                                                StyledText {
                                                    id: kindTxt

                                                    anchors.centerIn: parent
                                                    text: Agents.kindShort(agRow.modelData.kind)
                                                    color: agRow.tint
                                                    font.pointSize: 6.1
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0.45
                                                }
                                            }

                                            Rectangle {
                                                id: subPill

                                                visible: (agRow.modelData.subagents ?? 0) > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: subTxt.implicitWidth + 8
                                                height: 15
                                                radius: 7.5
                                                color: Qt.alpha("#a78bfa", 0.18)
                                                border.width: 0.5
                                                border.color: Qt.alpha("#a78bfa", 0.4)

                                                StyledText {
                                                    id: subTxt

                                                    anchors.centerIn: parent
                                                    text: `+${agRow.modelData.subagents}`
                                                    color: "#a78bfa"
                                                    font.pointSize: 6.2
                                                    font.weight: Font.Bold
                                                }
                                            }

                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.max(40, parent.width - kindPill.width - (subPill.visible ? subPill.width + 5.5 : 0) - 5.5)
                                                elide: Text.ElideRight
                                                text: `${agRow.modelData.project}${agRow.modelData.title ? " · " + agRow.modelData.title : ""}`
                                                color: root.fg
                                                font.pointSize: 9.1
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        // Ligne 2 : Activité temps réel (phase / outil / attente / réponse)
                                        StyledText {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: agRow.waiting
                                                ? (agRow.modelData.tool ? I18n.tr("Validation · %1").arg(agRow.modelData.tool) : I18n.tr("Attend ta réponse"))
                                                : agRow.working
                                                    ? (agRow.modelData.focus || agRow.modelData.tool || I18n.tr("Réfléchit…"))
                                                    : (agRow.modelData.reply || I18n.tr("Prêt"))
                                            color: agRow.waiting ? "#ff9f0a" : root.fgDim
                                            font.pointSize: 8.1
                                        }

                                        // Ligne 3 : Micro-télémétrie (modèle · branche · fichiers · tokens · progression)
                                        Row {
                                            visible: agRow.hasMeta
                                            width: parent.width
                                            spacing: 6

                                            StyledText {
                                                visible: Boolean(agRow.modelData.model)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: agRow.modelData.model
                                                color: Qt.alpha(agRow.tint, 0.92)
                                                font.pointSize: 6.9
                                                font.weight: Font.DemiBold
                                            }

                                            StyledText {
                                                visible: Boolean(agRow.modelData.branch)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: `⎇ ${agRow.modelData.branch}`
                                                color: root.fgDim
                                                font.pointSize: 6.9
                                                font.weight: Font.Medium
                                            }

                                            StyledText {
                                                visible: (agRow.modelData.files ?? 0) > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: I18n.tr("%1 fich.").arg(agRow.modelData.files)
                                                color: root.fgDim
                                                font.pointSize: 6.9
                                                font.features: { "tnum": 1 }
                                            }

                                            StyledText {
                                                visible: (agRow.modelData.tokens ?? 0) > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: `${Agents.fmtTokens(agRow.modelData.tokens)} tok`
                                                color: root.fgDim
                                                font.pointSize: 6.9
                                                font.features: { "tnum": 1 }
                                            }

                                            // Mini barre de progression des étapes (Antigravity update_steps)
                                            Row {
                                                visible: agRow.hasSteps
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 4

                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 34
                                                    height: 4
                                                    radius: 2
                                                    color: Qt.alpha(root.fg, 0.14)

                                                    Rectangle {
                                                        width: Math.max(4, parent.width * Math.min(1, (agRow.modelData.stepDone ?? 0) / Math.max(1, agRow.modelData.stepTotal ?? 1)))
                                                        height: parent.height
                                                        radius: 2
                                                        color: agRow.stateCol
                                                    }
                                                }
                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: `${agRow.modelData.stepDone}/${agRow.modelData.stepTotal}`
                                                    color: agRow.stateCol
                                                    font.pointSize: 6.8
                                                    font.weight: Font.Bold
                                                    font.features: { "tnum": 1 }
                                                }
                                            }
                                        }
                                    }

                                    // Colonne droite : durée + contrôles rapides (inspecter, stop, retirer)
                                    Row {
                                        id: agRightCol

                                        z: 2
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 5

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: agElapsedTxt.implicitWidth + 12
                                            height: 19
                                            radius: 9.5
                                            color: agRow.done ? Qt.alpha(root.fg, 0.065) : Qt.alpha(agRow.stateCol, 0.15)
                                            border.width: 0.5
                                            border.color: agRow.done ? Qt.alpha(root.fg, 0.13) : Qt.alpha(agRow.stateCol, 0.34)

                                            StyledText {
                                                id: agElapsedTxt

                                                anchors.centerIn: parent
                                                text: Agents.elapsed(agRow.modelData.since)
                                                color: agRow.done ? root.fgDim : agRow.stateCol
                                                font.pointSize: 7.5
                                                font.weight: Font.Bold
                                                font.features: { "tnum": 1 }
                                            }
                                        }

                                        // Bouton Stop (SIGINT doux) au survol d'un agent CLI en cours
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: agRow.working && agRow.modelData.canStop && rowHover.hovered
                                            width: 22
                                            height: 22
                                            radius: 11
                                            scale: agStopArea.pressed ? 0.88 : 1
                                            color: Qt.alpha(root.red, agStopArea.containsMouse ? 0.28 : 0.14)
                                            border.width: 0.5
                                            border.color: Qt.alpha(root.red, agStopArea.containsMouse ? 0.6 : 0.34)

                                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                text: "stop"
                                                color: root.red
                                                fontStyle: Tokens.font.icon.size(13).build()
                                                fill: 1
                                            }

                                            MouseArea {
                                                id: agStopArea

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Agents.stop(agRow.modelData)
                                            }
                                        }

                                        // Bouton inspecter / déplier
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: rowHover.hovered || agRow.expanded
                                            width: 22
                                            height: 22
                                            radius: 11
                                            scale: agExpArea.pressed ? 0.88 : 1
                                            color: Qt.alpha(root.fg, agExpArea.containsMouse ? 0.18 : 0.09)
                                            border.width: 0.5
                                            border.color: Qt.alpha(root.fg, agExpArea.containsMouse ? 0.34 : 0.16)

                                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                text: agRow.expanded ? "expand_less" : "expand_more"
                                                color: root.fg
                                                fontStyle: Tokens.font.icon.size(13).build()
                                            }

                                            MouseArea {
                                                id: agExpArea

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Agents.toggleExpand(agRow.modelData)
                                            }
                                        }

                                        // Bouton × concentrique au survol d'un agent terminé
                                        Rectangle {
                                            id: agCloseBtn

                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: agRow.done && rowHover.hovered
                                            width: 22
                                            height: 22
                                            radius: 11
                                            scale: agCloseArea.pressed ? 0.88 : 1
                                            color: Qt.alpha(root.fg, agCloseArea.containsMouse ? 0.18 : 0.1)
                                            border.width: 0.5
                                            border.color: Qt.alpha(root.fg, agCloseArea.containsMouse ? 0.34 : 0.18)

                                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                text: "close"
                                                color: root.fg
                                                fontStyle: Tokens.font.icon.size(11).build()
                                            }

                                            MouseArea {
                                                id: agCloseArea

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Agents.dismiss(agRow.modelData)
                                            }
                                        }
                                    }
                                }

                                // Panneau inspecteur détaillé (déplié via chevron ou clic droit)
                                Item {
                                    visible: agRow.expanded
                                    opacity: agRow.expanded ? 1 : 0
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 12
                                    anchors.bottomMargin: 8
                                    height: 48

                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    Rectangle {
                                        anchors.top: parent.top
                                        width: parent.width
                                        height: 1
                                        color: Qt.alpha(root.fg, 0.1)
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.topMargin: 6
                                        spacing: 8

                                        Column {
                                            width: parent.width - agDetailBtns.width - 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            StyledText {
                                                width: parent.width
                                                elide: Text.ElideRight
                                                text: agRow.modelData.reply || agRow.modelData.title || I18n.tr("Session active")
                                                color: root.fg
                                                font.pointSize: 7.7
                                            }
                                            StyledText {
                                                width: parent.width
                                                elide: Text.ElideMiddle
                                                text: agRow.modelData.cwd || (agRow.modelData.pid > 0 ? `PID ${agRow.modelData.pid}` : Agents.kindName(agRow.modelData.kind))
                                                color: root.fgDim
                                                font.family: "monospace"
                                                font.pointSize: 6.9
                                            }
                                        }

                                        Row {
                                            id: agDetailBtns

                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 5

                                            Rectangle {
                                                visible: Boolean(agRow.modelData.window || agRow.modelData.kind === "antigravity")
                                                width: fBtnTxt.implicitWidth + 14
                                                height: 22
                                                radius: 11
                                                color: Qt.alpha(agRow.tint, fBtnArea.containsMouse ? 0.28 : 0.16)
                                                border.width: 0.5
                                                border.color: Qt.alpha(agRow.tint, 0.44)

                                                StyledText {
                                                    id: fBtnTxt

                                                    anchors.centerIn: parent
                                                    text: I18n.tr("Ouvrir")
                                                    color: agRow.tint
                                                    font.pointSize: 7.2
                                                    font.weight: Font.Bold
                                                }
                                                MouseArea {
                                                    id: fBtnArea

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Agents.focus(agRow.modelData)
                                                }
                                            }

                                            Rectangle {
                                                visible: agRow.working && agRow.modelData.canStop
                                                width: sBtnTxt.implicitWidth + 14
                                                height: 22
                                                radius: 11
                                                color: Qt.alpha(root.red, sBtnArea.containsMouse ? 0.28 : 0.16)
                                                border.width: 0.5
                                                border.color: Qt.alpha(root.red, 0.44)

                                                StyledText {
                                                    id: sBtnTxt

                                                    anchors.centerIn: parent
                                                    text: I18n.tr("Stop")
                                                    color: root.red
                                                    font.pointSize: 7.2
                                                    font.weight: Font.Bold
                                                }
                                                MouseArea {
                                                    id: sBtnArea

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Agents.stop(agRow.modelData)
                                                }
                                            }
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: rowHover
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── un agent demande la permission : Autoriser / Refuser depuis l'île ──
        Face {
            id: permFace

            active: root.mode === "perm"

            readonly property var perm: Agents.perm
            readonly property var agent: Agents.list.find(a => a.pid === perm?.agentPid || a.id === `pid:${perm?.agentPid}`) ?? null

            Rectangle {
                id: permIcon

                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.top: parent.top
                anchors.topMargin: 18
                width: 44
                height: 44
                radius: 22
                color: Qt.alpha("#ff9f0a", 0.2)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "gpp_maybe"
                    color: "#ff9f0a"
                    fontStyle: Tokens.font.icon.size(20).build()
                    fill: 1

                    SequentialAnimation on scale {
                        running: root.mode === "perm"
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 1.12
                            duration: 600
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: 1
                            duration: 600
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            Column {
                anchors.left: permIcon.right
                anchors.leftMargin: 12
                anchors.right: permButtons.left
                anchors.rightMargin: 10
                anchors.verticalCenter: permIcon.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: permFace.perm?.label ?? ""
                    color: root.fg
                    font.pointSize: 11
                    font.weight: Font.Bold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: `${Agents.kindName(permFace.agent?.kind ?? "claude")} · ${permFace.perm?.project ?? ""}` + (Agents.perms.length > 1 ? I18n.tr(" · encore %1 en attente").arg(Agents.perms.length - 1) : "")
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            Row {
                id: permButtons

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: permIcon.verticalCenter
                spacing: 8

                ShotButton {
                    icon: "terminal"
                    tip: I18n.tr("Répondre dans le terminal")
                    onClicked: {
                        const p = permFace.perm;
                        Agents.answer(p.id, "terminal");
                        Agents.focusPid(p.agentPid);
                    }
                }
                PillButton {
                    icon: "block"
                    label: I18n.tr("Refuser")
                    tint: root.red
                    onClicked: Agents.answer(permFace.perm.id, "deny")
                }
                PillButton {
                    icon: "check"
                    label: I18n.tr("Autoriser")
                    tint: root.green
                    onClicked: Agents.answer(permFace.perm.id, "allow")
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                anchors.bottomMargin: 18
                height: 54
                radius: 14
                color: Qt.alpha(root.fg, 0.07)

                StyledText {
                    anchors.fill: parent
                    anchors.margins: 10
                    verticalAlignment: Text.AlignVCenter
                    text: permFace.perm?.detail ?? ""
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: root.fg
                    font.family: "monospace"
                    font.pointSize: 9
                }
            }
        }

        // ── un agent a terminé : projet + début de sa réponse ; clic = son terminal ──
        Face {
            active: root.mode === "agentDone"

            readonly property var agent: root.agentDone

            Rectangle {
                id: adIcon

                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                height: 42
                radius: 21
                color: Qt.alpha(root.green, 0.2)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "check_circle"
                    color: root.green
                    fontStyle: Tokens.font.icon.size(20).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: adIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: I18n.tr("%1 a terminé · %2").arg(Agents.kindName(parent.parent.agent?.kind ?? "")).arg(parent.parent.agent?.project ?? "")
                    color: root.fg
                    font.pointSize: 11
                    font.weight: Font.Bold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: parent.parent.agent?.reply || parent.parent.agent?.title || ""
                    color: root.fgDim
                    font.pointSize: 9
                }
            }
        }

        // ── minuteur / chronomètre / pomodoro (cadran horloger Liquid Glass) ──
        Face {
            id: clockFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property bool isStopwatch: root.clockKind === "stopwatch"
            readonly property bool isPaused: root.clockPaused > 0
            readonly property color clockTone: root.pomoOn && root.pomoPhase === "rest"
                ? root.green
                : isStopwatch
                    ? (Colours.light ? "#0284c7" : "#38bdf8")
                    : (Colours.light ? "#c77700" : "#ff9f0a")
            readonly property real clockRatio: root.clockTotal > 0 ? Math.max(0, Math.min(1, root.clockValue / root.clockTotal)) : ((root.clockValue % 60000) / 60000)

            active: root.mode === "clock"
            slide: root.pageSlide("clock")

            // Aura douce derrière le cadran horloger
            Rectangle {
                x: 12
                y: 10
                width: 240
                height: 66
                radius: 33
                opacity: Colours.light ? 0.34 : 0.6
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: Qt.alpha(clockFace.clockTone, 0.16) }
                    GradientStop { position: 0.72; color: Qt.alpha(clockFace.clockTone, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Caustique optique inférieure + point lumineux sous le curseur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.38 : 0.18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(clockFace.clockTone, 0.92) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                x: Math.max(32, Math.min(clockFace.width - width - 32, clockFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // ── Rangée haute : Cadran chronographe 56×56 + badges + grand temps + dock contrôles ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 14
                height: 60

                Rectangle {
                    id: clockDial

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56
                    height: 56
                    radius: 17
                    border.width: 0.5
                    border.color: Qt.alpha(clockFace.clockTone, 0.38)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(clockFace.clockTone, Colours.light ? 0.15 : 0.14) }
                        GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.035) }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 30
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.35 : 0.2
                    }

                    Shape {
                        anchors.centerIn: parent
                        width: 46
                        height: 46
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 2.6
                            strokeColor: Qt.alpha(root.fg, 0.12)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 23; centerY: 23
                                radiusX: 19; radiusY: 19
                                startAngle: 135; sweepAngle: 270
                            }
                        }
                        ShapePath {
                            strokeWidth: 6.4
                            strokeColor: Qt.alpha(clockFace.clockTone, 0.24)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 23; centerY: 23
                                radiusX: 19; radiusY: 19
                                startAngle: 135; sweepAngle: Math.max(4, 270 * clockFace.clockRatio)
                            }
                        }
                        ShapePath {
                            strokeWidth: 2.8
                            strokeColor: clockFace.clockTone
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: 23; centerY: 23
                                radiusX: 19; radiusY: 19
                                startAngle: 135; sweepAngle: Math.max(4, 270 * clockFace.clockRatio)
                            }
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.pomoOn ? "timelapse" : clockFace.isStopwatch ? "timer_play" : "timer"
                        color: clockFace.clockTone
                        fontStyle: Tokens.font.icon.size(19).build()
                        fill: 1
                        opacity: clockFace.isPaused ? 0.48 : 1
                    }
                }

                Column {
                    anchors.left: clockDial.right
                    anchors.leftMargin: 14
                    anchors.right: clockButtons.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: clockDial.verticalCenter
                    spacing: 1

                    Row {
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            id: clockModePill

                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(parent.width, clockModeRow.implicitWidth + 12)
                            height: 17
                            radius: 8.5
                            color: Qt.alpha(clockFace.clockTone, 0.15)
                            border.width: 0.5
                            border.color: Qt.alpha(clockFace.clockTone, 0.36)

                            Row {
                                id: clockModeRow

                                anchors.centerIn: parent
                                spacing: 4

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: clockFace.clockTone
                                    opacity: clockFace.isPaused ? 0.45 : 1
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        if (clockFace.isPaused)
                                            return I18n.tr("EN PAUSE");
                                        if (root.pomoOn)
                                            return I18n.tr("POMODORO · #%1").arg(root.pomoRound);
                                        if (clockFace.isStopwatch)
                                            return root.laps.length > 0 ? I18n.tr("CHRONOMÈTRE · %1").arg(root.laps.length) : I18n.tr("CHRONOMÈTRE");
                                        return I18n.tr("MINUTEUR");
                                    }
                                    color: clockFace.clockTone
                                    font.pointSize: 6.4
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.65
                                }
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - clockModePill.width - 6)
                            elide: Text.ElideRight
                            visible: text !== ""
                            text: {
                                if (root.clockLabel)
                                    return root.clockLabel;
                                if (!clockFace.isStopwatch && !clockFace.isPaused && root.clockEnd > 0)
                                    return I18n.tr("fin %1").arg(Qt.formatTime(new Date(root.clockEnd), "HH:mm"));
                                return "";
                            }
                            color: root.fgDim
                            font.pointSize: 7.5
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    StyledText {
                        text: root.fmtClock(root.clockValue)
                        color: root.fg
                        opacity: clockFace.isPaused ? 0.58 : 1
                        font.pointSize: 25
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }

                // Dock de commandes horlogères (Pause/Reprendre · Stop · App Horloge)
                Row {
                    id: clockButtons

                    anchors.right: parent.right
                    anchors.verticalCenter: clockDial.verticalCenter
                    spacing: 7

                    // Pilule héroïque Pause / Reprendre
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: clkPlayRow.implicitWidth + 20
                        height: 36
                        radius: 18
                        scale: clkPlayArea.pressed ? 0.94 : 1
                        color: clockFace.isPaused
                            ? (clkPlayArea.pressed ? Qt.darker(clockFace.clockTone, 1.15) : clockFace.clockTone)
                            : Qt.alpha(clockFace.clockTone, clkPlayArea.pressed ? 0.28 : clkPlayArea.containsMouse ? 0.22 : 0.14)
                        border.width: 0.5
                        border.color: clockFace.isPaused ? Qt.alpha("#ffffff", 0.3) : Qt.alpha(clockFace.clockTone, clkPlayArea.containsMouse ? 0.55 : 0.36)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(16, parent.width - 20)
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: clockFace.isPaused ? 0.35 : (Colours.light ? 0.34 : 0.2)
                        }

                        Row {
                            id: clkPlayRow

                            anchors.centerIn: parent
                            spacing: 4.5

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: clockFace.isPaused ? "play_arrow" : "pause"
                                color: clockFace.isPaused ? "#ffffff" : clockFace.clockTone
                                fontStyle: Tokens.font.icon.size(15.5).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: clockFace.isPaused ? I18n.tr("Reprendre") : I18n.tr("Pause")
                                color: clockFace.isPaused ? "#ffffff" : root.fg
                                font.pointSize: 8.2
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: clkPlayArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePause()
                        }
                    }

                    // Bouton Stop rouge translucide
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: 18
                        scale: clkStopArea.pressed ? 0.92 : 1
                        color: Qt.alpha(root.red, clkStopArea.pressed ? 0.28 : clkStopArea.containsMouse ? 0.22 : 0.14)
                        border.width: 0.5
                        border.color: Qt.alpha(root.red, clkStopArea.containsMouse ? 0.52 : 0.34)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 18
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.32 : 0.18
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "stop"
                            color: root.red
                            fontStyle: Tokens.font.icon.size(16).build()
                            fill: 1
                        }

                        MouseArea {
                            id: clkStopArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.stopClock()
                        }
                    }

                    // Ouvrir l'application Horloge
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: 17
                        scale: clkAppArea.pressed ? 0.92 : 1
                        color: Qt.alpha(root.fg, clkAppArea.pressed ? 0.18 : clkAppArea.containsMouse ? 0.13 : 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, clkAppArea.containsMouse ? 0.28 : 0.14)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "open_in_new"
                            color: root.fgDim
                            fontStyle: Tokens.font.icon.size(14.5).build()
                        }

                        MouseArea {
                            id: clkAppArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openClockApp()
                        }
                    }
                }
            }

            // Séparateur horizontal effilé
            Rectangle {
                x: 24
                y: 80
                width: parent.width - 48
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 0.8; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // ── Rangée basse : Piste horlogère liquide + actions rapides (+1 min / +5 min ou Tour + dernier tour) ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 88
                height: 24

                // Piste de progression liquide à gauche
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: clkQuickRow.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    color: Qt.alpha(root.fg, 0.08)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.14)
                    clip: true

                    Rectangle {
                        width: parent.width * clockFace.clockRatio
                        height: parent.height
                        radius: 3
                        color: clockFace.clockTone

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.width > 10
                            width: 10
                            height: parent.height
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.alpha("#ffffff", 0.55) }
                            }
                        }
                    }
                }

                // Droite : boutons rapides contextuels
                Row {
                    id: clkQuickRow

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Heure de fin quand un libellé occupe déjà la ligne haute (minuteur/pomodoro)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !clockFace.isStopwatch && !clockFace.isPaused && root.clockLabel !== "" && root.clockEnd > 0
                        width: clkEndTxt.implicitWidth + 12
                        height: 22
                        radius: 11
                        color: Qt.alpha(root.fg, 0.06)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.13)

                        StyledText {
                            id: clkEndTxt

                            anchors.centerIn: parent
                            text: I18n.tr("fin %1").arg(Qt.formatTime(new Date(root.clockEnd), "HH:mm"))
                            color: root.fgDim
                            font.pointSize: 7.4
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    // +1 min (Minuteur / Pomodoro)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !clockFace.isStopwatch
                        width: plus1Txt.implicitWidth + 16
                        height: 22
                        radius: 11
                        scale: plus1Area.pressed ? 0.94 : 1
                        color: Qt.alpha(clockFace.clockTone, plus1Area.pressed ? 0.26 : plus1Area.containsMouse ? 0.19 : 0.12)
                        border.width: 0.5
                        border.color: Qt.alpha(clockFace.clockTone, plus1Area.containsMouse ? 0.48 : 0.3)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        StyledText {
                            id: plus1Txt

                            anchors.centerIn: parent
                            text: I18n.tr("+1 min")
                            color: root.fg
                            font.pointSize: 7.6
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        MouseArea {
                            id: plus1Area

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addMinutes(1)
                        }
                    }

                    // +5 min (Minuteur / Pomodoro)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !clockFace.isStopwatch
                        width: plus5Txt.implicitWidth + 16
                        height: 22
                        radius: 11
                        scale: plus5Area.pressed ? 0.94 : 1
                        color: Qt.alpha(root.fg, plus5Area.pressed ? 0.16 : plus5Area.containsMouse ? 0.11 : 0.06)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, plus5Area.containsMouse ? 0.28 : 0.14)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        StyledText {
                            id: plus5Txt

                            anchors.centerIn: parent
                            text: I18n.tr("+5 min")
                            color: root.fg
                            font.pointSize: 7.6
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        MouseArea {
                            id: plus5Area

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addMinutes(5)
                        }
                    }

                    // Dernier tour enregistré (Chronomètre)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: clockFace.isStopwatch && root.laps.length > 0
                        width: lastLapTxt.implicitWidth + 12
                        height: 22
                        radius: 11
                        color: Qt.alpha(root.fg, 0.06)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.13)

                        StyledText {
                            id: lastLapTxt

                            anchors.centerIn: parent
                            text: root.laps.length > 0 ? `#${root.laps.length} · ${root.fmtClock(root.laps[root.laps.length - 1])}` : ""
                            color: root.fgDim
                            font.pointSize: 7.4
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    // Bouton Tour (Chronomètre)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: clockFace.isStopwatch
                        width: lapRow.implicitWidth + 16
                        height: 22
                        radius: 11
                        scale: lapArea.pressed ? 0.94 : 1
                        color: Qt.alpha(clockFace.clockTone, lapArea.pressed ? 0.26 : lapArea.containsMouse ? 0.19 : 0.12)
                        border.width: 0.5
                        border.color: Qt.alpha(clockFace.clockTone, lapArea.containsMouse ? 0.48 : 0.3)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        Row {
                            id: lapRow

                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "flag"
                                color: clockFace.clockTone
                                fontStyle: Tokens.font.icon.size(11).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Tour")
                                color: root.fg
                                font.pointSize: 7.6
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: lapArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addLap()
                        }
                    }
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
                    text: I18n.tr("Sonne depuis %1").arg(root.fmtTime(root.ringElapsed))
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
                    color: "transparent"
                    // Verre liquide (iOS 27) sous le contenu
                    GlassControl {
                        anchors.fill: parent
                        radius: parent.radius
                        bevel: parent.height > 60 ? 16 : 0
                        tintColour: Qt.alpha(root.fg, plusArea.pressed ? 0.26 : plusArea.containsMouse ? 0.2 : 0.12)
                        visible: tintColour.a > 0.01
                        pressed: plusArea.pressed
                        hovered: plusArea.containsMouse
                        pointer: plusArea.containsMouse ? Qt.point(plusArea.mouseX / Math.max(1, width), plusArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                    }
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
                    color: "transparent"
                    // Verre liquide (iOS 27) sous le contenu
                    GlassControl {
                        anchors.fill: parent
                        radius: parent.radius
                        bevel: parent.height > 60 ? 16 : 0
                        tintColour: Qt.alpha(root.fg, snoozeArea.pressed ? 0.26 : snoozeArea.containsMouse ? 0.2 : 0.12)
                        visible: tintColour.a > 0.01
                        pressed: snoozeArea.pressed
                        hovered: snoozeArea.containsMouse
                        pointer: snoozeArea.containsMouse ? Qt.point(snoozeArea.mouseX / Math.max(1, width), snoozeArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                    }
                    scale: snoozeArea.pressed ? 0.94 : 1

                    StyledText {
                        id: snoozeLbl

                        anchors.centerIn: parent
                        text: ringFace.isPomo ? I18n.tr("Terminer") : ringFace.isTimer ? I18n.tr("Relancer") : I18n.tr("Répéter")
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
                    color: "transparent"
                    // Verre liquide (iOS 27) sous le contenu
                    GlassControl {
                        anchors.fill: parent
                        radius: parent.radius
                        bevel: parent.height > 60 ? 16 : 0
                        tintColour: stopArea.containsMouse ? Qt.lighter(ringFace.tint, 1.12) : ringFace.tint
                        visible: tintColour.a > 0.01
                        pressed: stopArea.pressed
                        hovered: stopArea.containsMouse
                        pointer: stopArea.containsMouse ? Qt.point(stopArea.mouseX / Math.max(1, width), stopArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                    }
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
                            text: root.ringKind === "pomoWork" ? I18n.tr("Pause") : root.ringKind === "pomoRest" ? I18n.tr("Reprendre") : I18n.tr("Arrêter")
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

        // ── Centre de notifications (clic sur l'île, Super + N) : piles rétractables par appli/espèce & filtres ──
        Face {
            active: root.mode === "center"

            Item {
                id: centerHead

                x: 20
                y: 14
                width: parent.width - 40
                height: 36

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Row {
                        spacing: 6

                        StyledText {
                            text: I18n.tr("Notifications")
                            color: root.fg
                            font.pointSize: 12.5
                            font.weight: Font.Bold
                        }

                        // Badge de mode de regroupement actif
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: grpModeTxt.implicitWidth + 10
                            height: 17
                            radius: 8.5
                            color: Qt.alpha(root.accent, 0.16)
                            border.width: 1
                            border.color: Qt.alpha(root.accent, 0.35)

                            StyledText {
                                id: grpModeTxt

                                anchors.centerIn: parent
                                text: root.centerGroupBy === "app" ? I18n.tr("Par appli") : I18n.tr("Par espèce")
                                color: root.accent
                                font.pointSize: 7
                                font.weight: Font.Bold
                            }
                        }
                    }

                    StyledText {
                        text: {
                            const n = Notifs.notClosed.length;
                            const h = root.hiddenNotifCount;
                            const base = n === 0 ? I18n.tr("Tout est lu") : n === 1 ? I18n.tr("1 notification") : I18n.tr("%1 notifications").arg(n);
                            return h > 0 ? `${base} · ${I18n.tr("%1 masquée(s)").arg(h)}` : base;
                        }
                        color: root.fgDim
                        font.pointSize: 8
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Basculer le regroupement : Par appli ⇄ Par espèce (catégorie)
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: "transparent"

                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: 0
                            tintColour: root.centerGroupBy === "cat" ? Qt.alpha(root.accent, 0.28) : Qt.alpha(root.fg, grpByArea.containsMouse ? 0.16 : 0.1)
                            visible: tintColour.a > 0.01
                            pressed: grpByArea.pressed
                            hovered: grpByArea.containsMouse
                            pointer: grpByArea.containsMouse ? Qt.point(grpByArea.mouseX / Math.max(1, width), grpByArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: root.centerGroupBy === "app" ? "apps" : "category"
                            color: root.centerGroupBy === "cat" ? root.accent : root.fg
                            fontStyle: Tokens.font.icon.size(13).build()
                        }

                        MouseArea {
                            id: grpByArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.expandedGroups = ({});
                                root.expandedApp = "";
                                root.centerGroupBy = root.centerGroupBy === "app" ? "cat" : "app";
                            }
                        }
                    }

                    // Tout déplier / Tout replier
                    Rectangle {
                        visible: root.anyStackExpandable
                        width: 32
                        height: 32
                        radius: 16
                        color: "transparent"

                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: 0
                            tintColour: root.allStacksExpanded ? Qt.alpha(root.accent, 0.26) : Qt.alpha(root.fg, foldAllArea.containsMouse ? 0.16 : 0.1)
                            visible: tintColour.a > 0.01
                            pressed: foldAllArea.pressed
                            hovered: foldAllArea.containsMouse
                            pointer: foldAllArea.containsMouse ? Qt.point(foldAllArea.mouseX / Math.max(1, width), foldAllArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: root.allStacksExpanded ? "unfold_less" : "unfold_more"
                            color: root.allStacksExpanded ? root.accent : root.fg
                            fontStyle: Tokens.font.icon.size(14).build()
                        }

                        MouseArea {
                            id: foldAllArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleExpandAllStacks()
                        }
                    }

                    // Ne pas déranger
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: "transparent"

                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: 0
                            tintColour: Notifs.dnd ? root.accent : Qt.alpha(root.fg, dndArea.containsMouse ? 0.16 : 0.1)
                            visible: tintColour.a > 0.01
                            pressed: dndArea.pressed
                            hovered: dndArea.containsMouse
                            pointer: dndArea.containsMouse ? Qt.point(dndArea.mouseX / Math.max(1, width), dndArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }

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

                    // Tout effacer (dans la catégorie courante ou tout)
                    Rectangle {
                        visible: Notifs.notClosed.length > 0
                        width: clearLbl.implicitWidth + 22
                        height: 32
                        radius: 16
                        color: "transparent"

                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: 0
                            tintColour: Qt.alpha(root.fg, clearArea.containsMouse ? 0.16 : 0.1)
                            visible: tintColour.a > 0.01
                            pressed: clearArea.pressed
                            hovered: clearArea.containsMouse
                            pointer: clearArea.containsMouse ? Qt.point(clearArea.mouseX / Math.max(1, width), clearArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }

                        StyledText {
                            id: clearLbl

                            anchors.centerIn: parent
                            text: root.centerCat === "all" ? I18n.tr("Tout effacer") : I18n.tr("Effacer")
                            color: root.fg
                            font.pointSize: 8.5
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: clearArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                for (const n of [...Notifs.notClosed]) {
                                    if (root.centerCat === "all" || root.notifCat(n) === root.centerCat)
                                        n.close();
                                }
                            }
                        }
                    }
                }
            }

            // ── Barre de filtres par espèce / catégorie + bouton d'affichage des groupes masqués ──
            Item {
                id: centerFilterBar

                x: 16
                anchors.top: centerHead.bottom
                anchors.topMargin: 8
                width: parent.width - 32
                height: 26

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Repeater {
                        model: ["all", "messages", "system", "media", "apps"]

                        Rectangle {
                            id: catChip

                            required property string modelData
                            readonly property int count: root.catCount(modelData)
                            readonly property bool selected: root.centerCat === modelData
                            readonly property color catCol: root.notifCatColor(modelData)

                            visible: modelData === "all" || count > 0 || selected
                            width: catChipRow.implicitWidth + 14
                            height: 24
                            radius: 12
                            color: selected ? Qt.alpha(catCol, 0.24) : Qt.alpha(root.fg, catChipArea.containsMouse ? 0.11 : 0.06)
                            border.width: 1
                            border.color: selected ? Qt.alpha(catCol, 0.55) : Qt.alpha(root.fg, 0.08)

                            Row {
                                id: catChipRow

                                anchors.centerIn: parent
                                spacing: 4

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.notifCatIcon(catChip.modelData)
                                    color: catChip.selected ? catChip.catCol : root.fgDim
                                    fontStyle: Tokens.font.icon.size(11).build()
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.notifCatLabel(catChip.modelData)
                                    color: catChip.selected ? root.fg : root.fgDim
                                    font.pointSize: 7.5
                                    font.weight: catChip.selected ? Font.Bold : Font.Medium
                                }

                                Rectangle {
                                    visible: catChip.count > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(14, catCountTxt.implicitWidth + 6)
                                    height: 14
                                    radius: 7
                                    color: catChip.selected ? catChip.catCol : Qt.alpha(root.fg, 0.14)

                                    StyledText {
                                        id: catCountTxt

                                        anchors.centerIn: parent
                                        text: `${catChip.count}`
                                        color: catChip.selected ? "#081018" : root.fg
                                        font.pointSize: 6.5
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            MouseArea {
                                id: catChipArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.centerCat = catChip.modelData
                            }
                        }
                    }
                }

                // Pastille « Masquées (œil) » pour voir ou réafficher les espèces/applis masquées
                Rectangle {
                    visible: Object.keys(root.hiddenGroups).length > 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: maskRow.implicitWidth + 14
                    height: 24
                    radius: 12
                    color: root.showHiddenGroups ? Qt.alpha("#ff9f0a", 0.24) : Qt.alpha(root.fg, maskToggleArea.containsMouse ? 0.13 : 0.07)
                    border.width: 1
                    border.color: root.showHiddenGroups ? Qt.alpha("#ff9f0a", 0.55) : Qt.alpha(root.fg, 0.12)

                    Row {
                        id: maskRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.showHiddenGroups ? "visibility" : "visibility_off"
                            color: root.showHiddenGroups ? "#ff9f0a" : root.fgDim
                            fontStyle: Tokens.font.icon.size(11).build()
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.showHiddenGroups ? I18n.tr("Masquées visibles") : `${Object.keys(root.hiddenGroups).length}`
                            color: root.showHiddenGroups ? "#ff9f0a" : root.fgDim
                            font.pointSize: 7.5
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: maskToggleArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                root.hiddenGroups = ({});
                                root.showHiddenGroups = false;
                            } else {
                                root.showHiddenGroups = !root.showHiddenGroups;
                            }
                        }
                    }
                }
            }

            ListView {
                id: centerList

                x: 14
                anchors.top: centerFilterBar.bottom
                anchors.topMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                width: parent.width - 28
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: root.centerItems()

                add: Transition {
                    NumberAnimation {
                        properties: "opacity"
                        from: 0
                        to: 1
                        duration: 240
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            to: 0
                            duration: 190
                        }
                        NumberAnimation {
                            property: "x"
                            to: 80
                            duration: 210
                            easing.type: Easing.InCubic
                        }
                    }
                }
                displaced: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Item {
                    id: slot

                    required property var modelData
                    readonly property string grpKey: root.groupKey(modelData)
                    readonly property string grpName: root.groupTitle(modelData)
                    readonly property string catName: root.notifCat(modelData)
                    readonly property color catCol: root.notifCatColor(catName)
                    readonly property var members: root.groupMembers(modelData)
                    readonly property int repeats: members.length
                    readonly property bool isExpanded: root.isGroupExpanded(grpKey)
                    readonly property bool isHiddenGrp: root.isGroupHidden(grpKey)
                    readonly property bool stacked: repeats > 1 && !isExpanded
                    readonly property bool expandedMember: repeats > 1 && isExpanded
                    readonly property bool expandedHead: expandedMember && members[0] === modelData
                    readonly property real headBannerH: expandedHead ? 28 : 0

                    width: centerList.width
                    height: headBannerH + card.height + (stacked ? 13 : 0)

                    Behavior on height {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    // ── Bannière d'en-tête de pile dépliée : Réduire, Masquer l'espèce ou Tout fermer ──
                    Rectangle {
                        id: groupBanner

                        visible: slot.expandedHead
                        x: 0
                        y: 0
                        width: parent.width
                        height: 24
                        radius: 12
                        color: Qt.alpha(slot.catCol, 0.14)
                        border.width: 1
                        border.color: Qt.alpha(slot.catCol, 0.35)

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.notifCatIcon(slot.catName)
                                color: slot.catCol
                                fontStyle: Tokens.font.icon.size(11).build()
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${slot.grpName} · ${slot.repeats}`
                                color: root.fg
                                font.pointSize: 8
                                font.weight: Font.Bold
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            // Bouton Réduire la pile
                            Rectangle {
                                width: collapseRow.implicitWidth + 12
                                height: 18
                                radius: 9
                                color: collapseArea.containsMouse ? Qt.alpha(slot.catCol, 0.32) : Qt.alpha(slot.catCol, 0.2)

                                Row {
                                    id: collapseRow

                                    anchors.centerIn: parent
                                    spacing: 2

                                    MaterialIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "expand_less"
                                        color: slot.catCol
                                        fontStyle: Tokens.font.icon.size(11).build()
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr("Réduire")
                                        color: root.fg
                                        font.pointSize: 7
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: collapseArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleGroupExpand(slot.grpKey)
                                }
                            }

                            // Masquer / Afficher toute l'espèce ou l'application
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: bannerHideArea.containsMouse ? Qt.alpha(root.fg, 0.2) : Qt.alpha(root.fg, 0.1)

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: slot.isHiddenGrp ? "visibility" : "visibility_off"
                                    color: slot.isHiddenGrp ? "#ff9f0a" : root.fgDim
                                    fontStyle: Tokens.font.icon.size(10).build()
                                }

                                MouseArea {
                                    id: bannerHideArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleGroupHidden(slot.grpKey)
                                }
                            }

                            // Tout fermer du groupe
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: bannerClearArea.containsMouse ? Qt.alpha(root.red, 0.28) : Qt.alpha(root.fg, 0.1)

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "delete_sweep"
                                    color: bannerClearArea.containsMouse ? root.red : root.fgDim
                                    fontStyle: Tokens.font.icon.size(10).build()
                                }

                                MouseArea {
                                    id: bannerClearArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        for (const m of [...slot.members])
                                            m.close();
                                    }
                                }
                            }
                        }
                    }

                    // Cartes cachées derrière la première : effet d'éventail 3D quand la pile est rétractée
                    Rectangle {
                        visible: slot.stacked && slot.repeats >= 3
                        z: -2
                        x: 18
                        y: slot.headBannerH + 13
                        width: parent.width - 36
                        height: card.height
                        radius: 18
                        color: Qt.alpha(root.fg, 0.035)
                        border.width: 1
                        border.color: Qt.alpha(slot.catCol, 0.16)
                    }
                    Rectangle {
                        visible: slot.stacked
                        z: -1
                        x: 9
                        y: slot.headBannerH + 7
                        width: parent.width - 18
                        height: card.height
                        radius: 18
                        color: Qt.alpha(root.fg, 0.055)
                        border.width: 1
                        border.color: Qt.alpha(slot.catCol, 0.24)
                    }

                    Rectangle {
                        id: card

                        property var modelData: slot.modelData
                        readonly property string icon: modelData.appIcon ? Quickshell.iconPath(modelData.appIcon, true) : ""
                        readonly property int repeats: slot.repeats
                        readonly property bool stacked: slot.stacked

                        y: slot.headBannerH
                        width: centerList.width
                        height: cardBody.implicitHeight + 24
                        radius: 18
                        opacity: slot.isHiddenGrp ? 0.58 : 1
                        color: Qt.alpha(root.fg, cardArea.containsMouse ? 0.105 : 0.068)
                        border.width: 1
                        border.color: slot.stacked ? Qt.alpha(slot.catCol, 0.32) : Qt.alpha(root.fg, 0.08)

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }

                        // Fil conducteur vertical coloré quand la pile est dépliée
                        Rectangle {
                            visible: slot.expandedMember
                            x: 4
                            y: 10
                            width: 3
                            height: parent.height - 20
                            radius: 1.5
                            color: slot.catCol
                            opacity: 0.75
                        }

                        // Icône de l'app ou image de la notification
                        Rectangle {
                            id: cardIcon

                            x: slot.expandedMember ? 13 : 12
                            y: 12
                            width: 38
                            height: 38
                            radius: 11
                            color: Qt.alpha(slot.catCol, 0.14)
                            border.width: 1
                            border.color: Qt.alpha(slot.catCol, 0.28)
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
                                text: root.notifCatIcon(slot.catName)
                                color: slot.catCol
                                fontStyle: Tokens.font.icon.size(15).build()
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
                            spacing: 3

                            Item {
                                width: parent.width
                                height: Math.max(cardAppRow.implicitHeight, 16)

                                Row {
                                    id: cardAppRow

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: card.modelData.appName || root.notifCatLabel(slot.catName)
                                        color: root.fgDim
                                        font.pointSize: 8
                                        font.weight: Font.DemiBold
                                    }

                                    // Pastille d'espèce (Messages / Système / Média / Applis)
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: catTagTxt.implicitWidth + 8
                                        height: 14
                                        radius: 7
                                        color: Qt.alpha(slot.catCol, 0.15)

                                        StyledText {
                                            id: catTagTxt

                                            anchors.centerIn: parent
                                            text: root.notifCatLabel(slot.catName)
                                            color: slot.catCol
                                            font.pointSize: 6.5
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                StyledText {
                                    id: cardTime

                                    anchors.right: parent.right
                                    anchors.rightMargin: (card.stacked ? stackBadge.width + 6 : (slot.expandedMember ? foldChip.width + 6 : 0)) + (cardArea.containsMouse || hideBtnArea.containsMouse || xArea.containsMouse ? 48 : 0)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: card.modelData.timeStr
                                    color: root.fgDim
                                    font.pointSize: 7.5

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
                                text: root.plain(card.modelData.body)
                                color: Qt.alpha(root.fg, 0.78)
                                font.pointSize: 8.5
                            }

                            // Aperçu des autres notifications quand la pile est rétractée
                            StyledText {
                                visible: card.stacked && slot.repeats > 1
                                width: parent.width
                                elide: Text.ElideRight
                                text: {
                                    const others = slot.members.slice(1, 3).map(m => m.summary || root.plain(m.body)).filter(Boolean);
                                    return others.length > 0 ? `+ ${others.join("  ·  ")}` : "";
                                }
                                color: slot.catCol
                                font.pointSize: 7.5
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: cardArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const n = card.modelData;
                                // Pile rétractée : un clic la déplie
                                if (card.stacked) {
                                    root.toggleGroupExpand(slot.grpKey);
                                    return;
                                }
                                if (n.actions?.length > 0)
                                    n.actions[0].invoke();
                                n.close();
                            }
                        }

                        // ── Badge interactif de pile rétractée : « ×N · Déplier ▾ » ──
                        Rectangle {
                            id: stackBadge

                            visible: card.stacked
                            anchors.right: parent.right
                            anchors.rightMargin: (cardArea.containsMouse || hideBtnArea.containsMouse || xArea.containsMouse) ? 56 : 10
                            y: 9
                            width: stackBadgeRow.implicitWidth + 12
                            height: 20
                            radius: 10
                            color: stackBadgeArea.containsMouse ? Qt.alpha(slot.catCol, 0.34) : Qt.alpha(slot.catCol, 0.22)
                            border.width: 1
                            border.color: Qt.alpha(slot.catCol, 0.5)

                            Behavior on anchors.rightMargin {
                                NumberAnimation {
                                    duration: 150
                                }
                            }

                            Row {
                                id: stackBadgeRow

                                anchors.centerIn: parent
                                spacing: 3

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: `×${card.repeats} · ${I18n.tr("Déplier")}`
                                    color: root.fg
                                    font.pointSize: 7
                                    font.weight: Font.Bold
                                }

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "expand_more"
                                    color: slot.catCol
                                    fontStyle: Tokens.font.icon.size(11).build()
                                }
                            }

                            MouseArea {
                                id: stackBadgeArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleGroupExpand(slot.grpKey)
                            }
                        }

                        // ── Bouton rapide « Réduire ▴ » sur chaque carte d'une pile dépliée ──
                        Rectangle {
                            id: foldChip

                            visible: slot.expandedMember
                            anchors.right: parent.right
                            anchors.rightMargin: (cardArea.containsMouse || hideBtnArea.containsMouse || xArea.containsMouse) ? 56 : 10
                            y: 9
                            width: foldChipRow.implicitWidth + 10
                            height: 19
                            radius: 9.5
                            color: foldChipArea.containsMouse ? Qt.alpha(slot.catCol, 0.28) : Qt.alpha(root.fg, 0.09)

                            Behavior on anchors.rightMargin {
                                NumberAnimation {
                                    duration: 150
                                }
                            }

                            Row {
                                id: foldChipRow

                                anchors.centerIn: parent
                                spacing: 2

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "expand_less"
                                    color: slot.catCol
                                    fontStyle: Tokens.font.icon.size(10).build()
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Réduire")
                                    color: root.fgDim
                                    font.pointSize: 6.5
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                id: foldChipArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleGroupExpand(slot.grpKey)
                            }
                        }

                        // Masquer cette application / espèce (au survol)
                        Rectangle {
                            anchors.right: closeBtn.left
                            anchors.rightMargin: 4
                            y: 8
                            width: 22
                            height: 22
                            radius: 11
                            opacity: cardArea.containsMouse || hideBtnArea.containsMouse || xArea.containsMouse ? 1 : 0
                            color: "transparent"

                            GlassControl {
                                anchors.fill: parent
                                radius: parent.radius
                                bevel: 0
                                tintColour: Qt.alpha(slot.isHiddenGrp ? "#ff9f0a" : root.fg, hideBtnArea.containsMouse ? 0.24 : 0.13)
                                visible: tintColour.a > 0.01
                                pressed: hideBtnArea.pressed
                                hovered: hideBtnArea.containsMouse
                                pointer: hideBtnArea.containsMouse ? Qt.point(hideBtnArea.mouseX / Math.max(1, width), hideBtnArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 150
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: slot.isHiddenGrp ? "visibility" : "visibility_off"
                                color: slot.isHiddenGrp ? "#ff9f0a" : root.fg
                                fontStyle: Tokens.font.icon.size(10).build()
                            }

                            MouseArea {
                                id: hideBtnArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleGroupHidden(slot.grpKey)
                            }
                        }

                        // Fermer (au survol)
                        Rectangle {
                            id: closeBtn

                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            y: 8
                            width: 22
                            height: 22
                            radius: 11
                            opacity: cardArea.containsMouse || hideBtnArea.containsMouse || xArea.containsMouse ? 1 : 0
                            color: "transparent"

                            GlassControl {
                                anchors.fill: parent
                                radius: parent.radius
                                bevel: 0
                                tintColour: Qt.alpha(root.fg, xArea.containsMouse ? 0.22 : 0.13)
                                visible: tintColour.a > 0.01
                                pressed: xArea.pressed
                                hovered: xArea.containsMouse
                                pointer: xArea.containsMouse ? Qt.point(xArea.mouseX / Math.max(1, width), xArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                            }

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
                                onClicked: {
                                    // Pile repliée : ferme toute la pile ; sinon seulement cette carte
                                    for (const m of card.stacked ? slot.members : [card.modelData])
                                        m.close();
                                }
                            }
                        }
                    }
                }

                // Rien à lire (ou catégorie filtrée / masquée)
                Column {
                    anchors.centerIn: parent
                    visible: centerList.count === 0
                    spacing: 6

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.hiddenNotifCount > 0 && !root.showHiddenGroups ? "visibility_off" : "notifications_paused"
                        color: root.fgDim
                        fontStyle: Tokens.font.icon.size(22).build()
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.hiddenNotifCount > 0 && !root.showHiddenGroups ? I18n.tr("%1 notification(s) masquée(s)").arg(root.hiddenNotifCount) : I18n.tr("Aucune notification")
                        color: root.fgDim
                        font.pointSize: 9.5
                    }
                }
            }
        }

        // ── enregistrement d'écran (console studio Liquid Glass) : emblème REC, chrono, ondes, pause et arrêt ──
        Face {
            id: recordFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property color recTint: Recorder.paused ? "#ff9f0a" : root.red

            active: root.mode === "recordFull"
            slide: root.pageSlide("recordFull")

            // Aura studio rouge (ou ambre en pause) derrière l'emblème
            Rectangle {
                x: 12
                y: 12
                width: 240
                height: 68
                radius: 34
                opacity: Colours.light ? 0.35 : 0.62
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: Qt.alpha(recordFace.recTint, 0.16) }
                    GradientStop { position: 0.72; color: Qt.alpha(recordFace.recTint, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Caustique optique inférieure + point lumineux sous le curseur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.4 : 0.2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(recordFace.recTint, 0.92) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                x: Math.max(32, Math.min(recordFace.width - width - 32, recordFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // Emblème studio 56×56 avec double halo REC
            Rectangle {
                id: recBadge

                anchors.left: parent.left
                anchors.leftMargin: 22
                y: 20
                width: 56
                height: 56
                radius: 17
                border.width: 0.5
                border.color: Qt.alpha(recordFace.recTint, Recorder.paused ? 0.34 : 0.44)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(recordFace.recTint, Colours.light ? 0.16 : 0.16) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.035) }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 30
                    height: 1
                    radius: 0.5
                    color: "#ffffff"
                    opacity: Colours.light ? 0.35 : 0.22
                }

                // Anneau optique externe (respire doucement uniquement vue ouverte & active)
                Rectangle {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    radius: 17
                    color: "transparent"
                    border.width: 1.8
                    border.color: Qt.alpha(recordFace.recTint, Recorder.paused ? 0.35 : 0.58)

                    SequentialAnimation on opacity {
                        running: root.mode === "recordFull" && !Recorder.paused
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.38; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }

                // Point REC vif (ou icône pause ambre)
                Rectangle {
                    id: recFullDot

                    anchors.centerIn: parent
                    visible: !Recorder.paused
                    width: 13
                    height: 13
                    radius: 6.5
                    color: root.red

                    SequentialAnimation on opacity {
                        running: root.mode === "recordFull" && !Recorder.paused
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: Recorder.paused
                    text: "pause"
                    color: "#ff9f0a"
                    fontStyle: Tokens.font.icon.size(19).build()
                    fill: 1
                }
            }

            // Centre : Pastilles statut + raccourci Vidéos · Grand chronomètre + micro-barres studio
            Column {
                anchors.left: recBadge.right
                anchors.leftMargin: 14
                anchors.right: recButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: recBadge.verticalCenter
                spacing: 3

                Row {
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: recTagRow.implicitWidth + 12
                        height: 17
                        radius: 8.5
                        color: Qt.alpha(recordFace.recTint, 0.16)
                        border.width: 0.5
                        border.color: Qt.alpha(recordFace.recTint, 0.38)

                        Row {
                            id: recTagRow

                            anchors.centerIn: parent
                            spacing: 4

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 2.5
                                color: recordFace.recTint
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Recorder.paused ? I18n.tr("CAPTURE EN PAUSE") : I18n.tr("EN DIRECT")
                                color: recordFace.recTint
                                font.pointSize: 6.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.65
                            }
                        }
                    }

                    // Micro-pilule cliquable ouvrant le dossier d'enregistrements
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: recDirRow.implicitWidth + 12
                        height: 17
                        radius: 8.5
                        scale: recDirArea.pressed ? 0.94 : 1
                        color: Qt.alpha(root.fg, recDirArea.containsMouse ? 0.12 : 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, recDirArea.containsMouse ? 0.28 : 0.14)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                        Row {
                            id: recDirRow

                            anchors.centerIn: parent
                            spacing: 3.5

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "movie"
                                color: root.fgDim
                                fontStyle: Tokens.font.icon.size(9.5).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Vidéos")
                                color: root.fgDim
                                font.pointSize: 6.8
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: recDirArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["sh", "-c", "d=\"$(xdg-user-dir VIDEOS 2>/dev/null || echo \"$HOME/Videos\")\"; [ -d \"$d/ENREGISTREMENTS ECRAN\" ] && xdg-open \"$d/ENREGISTREMENTS ECRAN\" || xdg-open \"$d\""])
                        }
                    }
                }

                Row {
                    spacing: 10

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fmtTime(Recorder.elapsed)
                        color: root.fg
                        opacity: Recorder.paused ? 0.6 : 1
                        font.pointSize: 22
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }

                    // Micro-barres studio rythmées sur les secondes (zéro boucle 60 FPS)
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2.5
                        height: 12

                        Repeater {
                            model: 5

                            Rectangle {
                                required property int index
                                readonly property real baseH: [5, 10, 12, 8, 6][index]

                                anchors.verticalCenter: parent.verticalCenter
                                width: 2.2
                                height: Recorder.paused ? 3 : Math.max(3, baseH * (0.5 + 0.5 * Math.abs(Math.sin(Recorder.elapsed * 1.3 + index * 1.15))))
                                radius: 1.1
                                color: Recorder.paused ? Qt.alpha("#ff9f0a", 0.5) : recordFace.recTint

                                Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            // Droite : Dock studio (Pause/Reprendre · Pilule héroïque rouge Arrêter)
            Row {
                id: recButtons

                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: recBadge.verticalCenter
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: recPauseRow.implicitWidth + 18
                    height: 36
                    radius: 18
                    scale: recPauseArea.pressed ? 0.94 : 1
                    color: Recorder.paused
                        ? Qt.alpha("#ff9f0a", recPauseArea.pressed ? 0.28 : recPauseArea.containsMouse ? 0.22 : 0.15)
                        : Qt.alpha(root.fg, recPauseArea.pressed ? 0.18 : recPauseArea.containsMouse ? 0.13 : 0.07)
                    border.width: 0.5
                    border.color: Recorder.paused ? Qt.alpha("#ff9f0a", 0.48) : Qt.alpha(root.fg, recPauseArea.containsMouse ? 0.3 : 0.15)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(14, parent.width - 18)
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.18
                    }

                    Row {
                        id: recPauseRow

                        anchors.centerIn: parent
                        spacing: 4.5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Recorder.paused ? "play_arrow" : "pause"
                            color: Recorder.paused ? "#ff9f0a" : root.fg
                            fontStyle: Tokens.font.icon.size(15.5).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Recorder.paused ? I18n.tr("Reprendre") : I18n.tr("Pause")
                            color: root.fg
                            font.pointSize: 8.2
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: recPauseArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Recorder.togglePause()
                    }
                }

                // Pilule héroïque rouge Arrêter
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: stopRecRow.implicitWidth + 24
                    height: 38
                    radius: 19
                    scale: stopRecArea.pressed ? 0.93 : 1
                    color: stopRecArea.pressed ? Qt.darker("#ff453a", 1.15) : stopRecArea.containsMouse ? Qt.lighter("#ff453a", 1.08) : "#ff453a"
                    border.width: 0.5
                    border.color: Qt.alpha("#ffffff", 0.3)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 22
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: 0.34
                    }

                    Row {
                        id: stopRecRow

                        anchors.centerIn: parent
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10
                            height: 10
                            radius: 2.5
                            color: "#ffffff"
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Arrêter")
                            color: "#ffffff"
                            font.pointSize: 8.4
                            font.weight: Font.Bold
                        }
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

        // ── appel en cours (console Liquid Glass) : emblème lumineux, chrono, ondes, haut-parleur, micro et focus ──
        Face {
            id: callFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property color callTint: root.callMuted ? root.red : root.green

            active: root.mode === "callFull"
            slide: root.pageSlide("callFull")

            // Aura émeraude (ou rouge si micro coupé) derrière la console d'appel
            Rectangle {
                x: 12
                y: 12
                width: 240
                height: 68
                radius: 34
                opacity: Colours.light ? 0.35 : 0.62
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.3; color: Qt.alpha(callFace.callTint, 0.16) }
                    GradientStop { position: 0.72; color: Qt.alpha(callFace.callTint, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Caustique optique inférieure + point lumineux sous le curseur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.4 : 0.2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(callFace.callTint, 0.92) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                x: Math.max(32, Math.min(callFace.width - width - 32, callFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // Emblème appel Liquid Glass avec arc double passe
            Rectangle {
                id: callBadge

                anchors.left: parent.left
                anchors.leftMargin: 22
                y: 20
                width: 56
                height: 56
                radius: 17
                border.width: 0.5
                border.color: Qt.alpha(callFace.callTint, 0.38)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(callFace.callTint, Colours.light ? 0.16 : 0.15) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.035) }
                }

                Behavior on border.color { ColorAnimation { duration: 240 } }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 30
                    height: 1
                    radius: 0.5
                    color: "#ffffff"
                    opacity: Colours.light ? 0.35 : 0.2
                }

                Shape {
                    anchors.centerIn: parent
                    width: 46
                    height: 46
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(root.fg, 0.11)
                        strokeWidth: 2.8
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 23; centerY: 23
                            radiusX: 19; radiusY: 19
                            startAngle: 135; sweepAngle: 270
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(callFace.callTint, 0.24)
                        strokeWidth: 6.4
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 23; centerY: 23
                            radiusX: 19; radiusY: 19
                            startAngle: 135; sweepAngle: root.callMuted ? 68 : 270
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: callFace.callTint
                        strokeWidth: 2.8
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 23; centerY: 23
                            radiusX: 19; radiusY: 19
                            startAngle: 135; sweepAngle: root.callMuted ? 68 : 270
                        }
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.camInUse ? "videocam" : "call"
                    color: callFace.callTint
                    fontStyle: Tokens.font.icon.size(19).build()
                    fill: 1
                }
            }

            // Centre : Pastilles statut + chrono · Titre · Appli & micro-barres d'ondes
            Column {
                anchors.left: callBadge.right
                anchors.leftMargin: 14
                anchors.right: callButtons.left
                anchors.rightMargin: 12
                anchors.verticalCenter: callBadge.verticalCenter
                spacing: 3

                Row {
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: callTagRow.implicitWidth + 12
                        height: 17
                        radius: 8.5
                        color: Qt.alpha(callFace.callTint, 0.15)
                        border.width: 0.5
                        border.color: Qt.alpha(callFace.callTint, 0.36)

                        Row {
                            id: callTagRow

                            anchors.centerIn: parent
                            spacing: 4

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 2.5
                                color: callFace.callTint
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.callMuted ? I18n.tr("Micro coupé") : root.camInUse ? I18n.tr("Visioconférence") : I18n.tr("Liaison audio")).toUpperCase()
                                color: callFace.callTint
                                font.pointSize: 6.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.65
                            }
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: callDurTxt.implicitWidth + 12
                        height: 17
                        radius: 8.5
                        color: Qt.alpha(root.fg, 0.07)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.14)

                        StyledText {
                            id: callDurTxt

                            anchors.centerIn: parent
                            text: root.fmtLong(root.callElapsed)
                            color: root.fg
                            font.pointSize: 7.4
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.callTitle
                    color: root.fg
                    font.pointSize: 12
                    font.weight: Font.Bold
                }

                Row {
                    spacing: 8

                    // Micro-barres vocales (actives uniquement appel ouvert & micro ouvert)
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        height: 10

                        Repeater {
                            model: 5

                            Rectangle {
                                required property int index
                                readonly property real baseH: [4, 8, 10, 7, 5][index]

                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: root.callMuted ? 3 : Math.max(3, baseH * (0.55 + 0.45 * Math.abs(Math.sin(root.callElapsed * 1.4 + index * 1.1))))
                                radius: 1
                                color: root.callMuted ? Qt.alpha(root.red, 0.5) : callFace.callTint

                                Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.callAppName !== ""
                        text: root.callAppName
                        color: root.fgDim
                        font.pointSize: 8.2
                        font.weight: Font.Medium
                    }
                }
            }

            // Droite : Dock d'actions d'appel vitré (Aller à l'appel · Haut-parleur · Pilule Micro)
            Row {
                id: callButtons

                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: callBadge.verticalCenter
                spacing: 8

                // Retour à la fenêtre d'appel
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.callWindow !== null
                    width: 36
                    height: 36
                    radius: 18
                    scale: callOpenArea.pressed ? 0.92 : 1
                    color: Qt.alpha(root.fg, callOpenArea.pressed ? 0.18 : callOpenArea.containsMouse ? 0.13 : 0.07)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, callOpenArea.containsMouse ? 0.3 : 0.15)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 18
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.18
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "open_in_new"
                        color: root.fg
                        fontStyle: Tokens.font.icon.size(15).build()
                    }

                    MouseArea {
                        id: callOpenArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusCall()
                    }
                }

                // Sourdine haut-parleur rapide
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 18
                    scale: callSpkArea.pressed ? 0.92 : 1
                    color: Audio.muted
                        ? Qt.alpha(root.red, callSpkArea.containsMouse ? 0.24 : 0.16)
                        : Qt.alpha(root.fg, callSpkArea.pressed ? 0.18 : callSpkArea.containsMouse ? 0.13 : 0.07)
                    border.width: 0.5
                    border.color: Audio.muted ? Qt.alpha(root.red, 0.45) : Qt.alpha(root.fg, callSpkArea.containsMouse ? 0.3 : 0.15)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 18
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.18
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: Audio.muted ? "volume_off" : "volume_up"
                        color: Audio.muted ? root.red : root.fg
                        fontStyle: Tokens.font.icon.size(15.5).build()
                        fill: 1
                    }

                    MouseArea {
                        id: callSpkArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Audio.sink?.ready && Audio.sink?.audio)
                                Audio.sink.audio.muted = !Audio.sink.audio.muted;
                        }
                    }
                }

                // Pilule héroïque Micro (rouge vif si coupé, verre émeraude si actif)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: callMicRow.implicitWidth + 24
                    height: 38
                    radius: 19
                    scale: callMicArea.pressed ? 0.93 : 1
                    color: root.callMuted
                        ? (callMicArea.pressed ? Qt.darker(root.red, 1.15) : root.red)
                        : Qt.alpha(root.green, callMicArea.pressed ? 0.26 : callMicArea.containsMouse ? 0.2 : 0.14)
                    border.width: 0.5
                    border.color: root.callMuted ? Qt.alpha("#ffffff", 0.3) : Qt.alpha(root.green, callMicArea.containsMouse ? 0.55 : 0.36)

                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 22
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: root.callMuted ? 0.32 : (Colours.light ? 0.34 : 0.2)
                    }

                    Row {
                        id: callMicRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.callMuted ? "mic_off" : "mic"
                            color: root.callMuted ? "#ffffff" : root.green
                            fontStyle: Tokens.font.icon.size(15.5).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.callMuted ? I18n.tr("Coupé") : I18n.tr("Micro")
                            color: root.callMuted ? "#ffffff" : root.fg
                            font.pointSize: 8.4
                            font.weight: Font.Bold
                        }
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
                text: I18n.tr("clic : annuler")
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
                        text: I18n.tr("Déposer sur l'étagère")
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
                        text: root.queue.length > 0 ? `+${root.queue.length}` : I18n.tr("maintenant")
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
                    text: root.plain(root.notif?.body).replace(/\n/g, " ")
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

                        width: Math.min(150, Math.max(90, actLbl.implicitWidth + 28))
                        height: 30
                        radius: 15
                        color: "transparent"
                        // Verre liquide (iOS 27) sous le contenu
                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: parent.height > 60 ? 16 : 0
                            tintColour: actArea.containsMouse ? Qt.alpha(root.fg, 0.2) : Qt.alpha(root.fg, 0.1)
                            visible: tintColour.a > 0.01
                            pressed: actArea.pressed
                            hovered: actArea.containsMouse
                            pointer: actArea.containsMouse ? Qt.point(actArea.mouseX / Math.max(1, width), actArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }

                        StyledText {
                            id: actLbl

                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, act.width - 24)
                            elide: Text.ElideRight
                            // kitty envoie une action « default » sans libellé
                            text: act.modelData.text || I18n.tr("Voir")
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

        // ── page Infos : cadran Liquid Glass horloger (heure roulante + secondes chronographe, météo atmosphérique, énergie, pastilles interactives) ──
        Face {
            id: infoFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property color battTint: root.battCharging ? root.green : root.battery < 0.2 ? root.red : root.fg

            active: root.mode === "info"
            slide: root.pageSlide("info")

            // Halo céleste discret derrière le cadran horloger
            Rectangle {
                x: 12
                y: 12
                width: 204
                height: 68
                radius: 34
                opacity: Colours.light ? 0.35 : 0.58
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.35; color: Qt.alpha(root.idleAccent, 0.13) }
                    GradientStop { position: 0.72; color: Qt.alpha(root.idleAccent, 0.05) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Caustique optique sur la lèvre inférieure de la page Infos + point lumineux sous le pointeur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.36 : 0.18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(root.idleAccent, 0.9) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                x: Math.max(32, Math.min(infoFace.width - width - 32, infoFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // ── Colonne gauche : Horloge roulante + secondes chronographe · Date éditoriale · Piste bureaux & raccourcis ──
            Item {
                id: infoClockCol

                x: 24
                y: 16
                width: 182
                height: 78

                // Horloge roulante 25.5 pt + rubis battant (uniquement page Infos active) + pilule secondes chronographe
                Row {
                    id: infoClockRow

                    anchors.left: parent.left
                    anchors.top: parent.top
                    spacing: 0

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: -0.5

                        ClockDigit { digit: root.idleHourStr.charAt(0) || "0"; ptSize: 25.5 }
                        ClockDigit { digit: root.idleHourStr.charAt(1) || "0"; ptSize: 25.5 }
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13
                        height: 26

                        Column {
                            anchors.centerIn: parent
                            spacing: 5.5
                            opacity: root.mode === "info" ? (Time.seconds % 2 === 0 ? 1.0 : 0.42) : 0.9

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 360
                                    easing.type: Easing.InOutSine
                                }
                            }

                            Repeater {
                                model: 2

                                Rectangle {
                                    required property int index

                                    width: 4.4
                                    height: 4.4
                                    radius: 2.2
                                    color: root.idleAccent

                                    Behavior on color { ColorAnimation { duration: 420 } }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 1.6
                                        height: 1.6
                                        radius: 0.8
                                        color: "#ffffff"
                                        opacity: 0.58
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: -0.5

                        ClockDigit { digit: root.idleMinStr.charAt(0) || "0"; ptSize: 25.5 }
                        ClockDigit { digit: root.idleMinStr.charAt(1) || "0"; ptSize: 25.5 }
                    }

                    // Pilule concentrique des secondes avec micro-barre chronographe (0 → 59 s)
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 2
                        width: 33
                        height: 21

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 20
                            radius: 10
                            color: Qt.alpha(root.fg, 0.07)
                            border.width: 0.5
                            border.color: Qt.alpha(root.fg, 0.16)
                            clip: true

                            // Reflet spéculaire supérieur
                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 13
                                height: 1
                                radius: 0.5
                                color: "#ffffff"
                                opacity: Colours.light ? 0.35 : 0.22
                            }

                            StyledText {
                                id: infoSecTxt

                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -0.5
                                text: Time.format("ss")
                                color: root.fgDim
                                font.pointSize: 8
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }

                            // Piste et barre de progression fine de la minute en cours
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 5
                                anchors.rightMargin: 5
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 1.5
                                height: 1.5
                                radius: 0.75
                                color: Qt.alpha(root.fg, 0.12)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.max(2, parent.width * (Time.seconds / 59))
                                    radius: 0.75
                                    color: root.idleAccent
                                    opacity: 0.92

                                    Behavior on width {
                                        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color { ColorAnimation { duration: 420 } }
                                }
                            }
                        }
                    }
                }

                // Date éditoriale complète
                StyledText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: 41
                    elide: Text.ElideRight
                    text: I18n.locale.toString(Time.date, I18n.isFr ? "dddd d MMMM" : "dddd, MMMM d").toUpperCase()
                    color: root.fgDim
                    font.pointSize: 7.8
                    font.weight: Font.Bold
                    font.letterSpacing: 0.7
                }

                // Barre inférieure gauche : piste vitrée des bureaux + raccourcis Horloge & Centre de contrôle
                Row {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 6

                    // Piste de bureaux en continuité visuelle directe avec l'île au repos
                    Rectangle {
                        id: infoWsTrack

                        readonly property bool compactNum: root.wsLast > 5 || root.wsId > 5

                        anchors.verticalCenter: parent.verticalCenter
                        visible: Island.workspaces
                        width: compactNum ? Math.max(22, infoWsNum.implicitWidth + 10) : infoWsBeads.implicitWidth + 12
                        height: 18
                        radius: 9
                        color: Qt.alpha(root.fg, 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.14)

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.55
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.35 : 0.2
                        }

                        Row {
                            id: infoWsBeads

                            anchors.centerIn: parent
                            visible: !infoWsTrack.compactNum
                            spacing: 3.5

                            Repeater {
                                model: infoWsTrack.compactNum ? 0 : Math.min(root.wsLast, 5)

                                Item {
                                    id: iWsBead

                                    required property int index
                                    readonly property int wsNum: index + 1
                                    readonly property bool isCurrent: wsNum === root.wsId
                                    readonly property bool isOccupied: !!root.wsOccupied[wsNum]

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: isCurrent ? 13 : (isOccupied ? 4.5 : 3.5)
                                    height: 16

                                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width
                                        height: iWsBead.isCurrent ? 4.5 : (iWsBead.isOccupied ? 4.5 : 3.5)
                                        radius: height / 2
                                        color: iWsBead.isCurrent ? root.idleAccent : Qt.alpha(root.fg, iWsBead.isOccupied ? 0.58 : 0.24)

                                        Behavior on color { ColorAnimation { duration: 220 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (iWsBead.wsNum !== root.wsId)
                                                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${iWsBead.wsNum} })` : `workspace ${iWsBead.wsNum}`);
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            id: infoWsNum

                            anchors.centerIn: parent
                            visible: infoWsTrack.compactNum
                            text: `${root.wsId}`
                            color: root.idleAccent
                            font.pointSize: 7.8
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }

                    // Bouton rapide Horloge / Minuteur
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 18
                        radius: 9
                        scale: infoClockBtn.pressed ? 0.9 : 1
                        color: Qt.alpha(root.fg, infoClockBtn.containsMouse ? 0.14 : 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, infoClockBtn.containsMouse ? 0.26 : 0.14)

                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "schedule"
                            color: infoClockBtn.containsMouse ? root.fg : root.fgDim
                            fontStyle: Tokens.font.icon.size(10.5).build()
                            fill: 1
                        }

                        MouseArea {
                            id: infoClockBtn

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openInfoDrop("clock")
                        }
                    }

                    // Bouton rapide Centre de contrôle
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 18
                        radius: 9
                        scale: infoCcBtn.pressed ? 0.9 : 1
                        color: Qt.alpha(root.fg, infoCcBtn.containsMouse ? 0.14 : 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, infoCcBtn.containsMouse ? 0.26 : 0.14)

                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "tune"
                            color: infoCcBtn.containsMouse ? root.fg : root.fgDim
                            fontStyle: Tokens.font.icon.size(10.5).build()
                            fill: 1
                        }

                        MouseArea {
                            id: infoCcBtn

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openInfoDrop("controlCenter")
                        }
                    }
                }
            }

            // ── Zone droite : Deux puits de verre distincts (Météo atmosphérique + Énergie) ──
            Item {
                id: infoCardsZone

                anchors.left: infoClockCol.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 24
                y: 16
                height: 78

                // Puits 1 : Météo atmosphérique (cliquable pour rafraîchir)
                Rectangle {
                    id: infoWeatherCard

                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width - (UPower.displayDevice.isLaptopBattery ? 124 : 0)
                    radius: 16
                    scale: infoWeatherArea.pressed ? 0.985 : 1
                    border.width: 0.5
                    border.color: Weather.cc ? Qt.alpha(root.idleWeatherTint, infoWeatherArea.containsMouse ? 0.42 : 0.24) : Qt.alpha(root.fg, 0.14)
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Weather.cc ? Qt.alpha(root.idleWeatherTint, Colours.light ? 0.12 : 0.1) : Qt.alpha(root.fg, 0.06)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.alpha(root.fg, 0.04)
                        }
                    }

                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    // Reflet spéculaire supérieur sur le puits météo
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.16
                    }

                    // Haut de la carte : emblème solaire/lunaire + température + ville & condition
                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 11
                        height: 36

                        // Emblème météo lumineux avec halo
                        Item {
                            id: infoWeatherGlyph

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34

                            Rectangle {
                                anchors.centerIn: parent
                                width: 34
                                height: 34
                                radius: 17
                                color: Weather.cc ? root.idleWeatherTint : root.fgDim
                                opacity: Weather.cc ? (Colours.light ? 0.15 : 0.18) : 0.08
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: Weather.cc ? Qt.alpha(root.idleWeatherTint, 0.14) : Qt.alpha(root.fg, 0.06)
                                border.width: 0.5
                                border.color: Weather.cc ? Qt.alpha(root.idleWeatherTint, 0.34) : Qt.alpha(root.fg, 0.14)
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: Weather.cc ? root.idleWeatherIcon : "cloud_off"
                                color: Weather.cc ? root.idleWeatherTint : root.fgDim
                                fontStyle: Tokens.font.icon.size(16).build()
                                fill: 1
                            }
                        }

                        StyledText {
                            id: infoTempBig

                            anchors.left: infoWeatherGlyph.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: Weather.cc ? root.idleTempShort : "—"
                            color: root.fg
                            font.pointSize: 17
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        Column {
                            anchors.left: infoTempBig.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            StyledText {
                                width: parent.width
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                                visible: !!Weather.city
                                text: (Weather.city || "").toUpperCase()
                                color: Weather.cc ? root.idleWeatherTint : root.fgDim
                                font.pointSize: 6.8
                                font.weight: Font.Bold
                                font.letterSpacing: 0.65
                            }

                            StyledText {
                                width: parent.width
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                                text: Weather.cc ? (Weather.description || "") : I18n.tr("Météo indisponible")
                                color: root.fgDim
                                font.pointSize: 7.8
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    // Filet interne discret
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottom: infoWeatherFoot.top
                        anchors.bottomMargin: 6
                        height: 1
                        visible: !!Weather.cc
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Qt.alpha(root.fg, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    // Bas de la carte : ressenti · humidité · min/max du jour (ou vent)
                    Row {
                        id: infoWeatherFoot

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        visible: !!Weather.cc
                        spacing: 10

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Ress. %1").arg(Weather.feelsLike.replace(/[CF]$/, ""))
                            color: root.fgDim
                            font.pointSize: 7.5
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "water_drop"
                                color: Colours.light ? "#0284c7" : "#38bdf8"
                                fontStyle: Tokens.font.icon.size(9.5).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${Weather.humidity}%`
                                color: root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.infoWeatherRange !== ""
                            spacing: 2

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Weather.forecast && Weather.forecast.length > 0 ? "thermostat" : "air"
                                color: root.fgDim
                                fontStyle: Tokens.font.icon.size(9.5).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.infoWeatherRange
                                color: root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    MouseArea {
                        id: infoWeatherArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Weather.reload()
                    }
                }

                // Puits 2 : Énergie & batterie de précision (cliquable → Centre de contrôle)
                Rectangle {
                    id: infoBattCard

                    visible: UPower.displayDevice.isLaptopBattery
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 116
                    radius: 16
                    scale: infoBattArea.pressed ? 0.98 : 1
                    border.width: 0.5
                    border.color: Qt.alpha(infoFace.battTint, root.battCharging || root.battery < 0.2 ? (infoBattArea.containsMouse ? 0.5 : 0.34) : (infoBattArea.containsMouse ? 0.28 : 0.14))
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.alpha(infoFace.battTint, root.battCharging || root.battery < 0.2 ? (Colours.light ? 0.14 : 0.13) : 0.065)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.alpha(root.fg, 0.035)
                        }
                    }

                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    // Reflet spéculaire supérieur sur le puits batterie
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.16
                    }

                    // Haut : Pourcentage tabulaire + glyphe batterie
                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: 11
                        anchors.topMargin: 12
                        height: 22

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: `${Math.round(root.battery * 100)}%`
                            color: root.battCharging ? root.green : root.battery < 0.2 ? root.red : root.fg
                            font.pointSize: 13.5
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }

                        BatteryGlyph {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            pct: root.battery
                            charging: root.battCharging
                        }
                    }

                    // Milieu : Jauge énergétique liquide horizontale
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        y: 44
                        height: 4
                        radius: 2
                        color: Qt.alpha(root.fg, 0.1)

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(4, parent.width * Math.max(0, Math.min(1, root.battery)))
                            radius: 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0.0
                                    color: root.battCharging ? "#22c55e" : root.battery < 0.2 ? "#ff453a" : root.accent
                                }
                                GradientStop {
                                    position: 1.0
                                    color: root.battCharging ? "#34d399" : root.battery < 0.2 ? "#ff6b6b" : root.fg
                                }
                            }

                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                        }
                    }

                    // Bas : Autonomie / puissance en Watts / état de charge
                    StyledText {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 9
                        elide: Text.ElideRight
                        text: root.infoBattSub
                        color: root.battCharging ? root.green : root.battery < 0.2 ? root.red : root.fgDim
                        font.pointSize: 7.4
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }

                    MouseArea {
                        id: infoBattArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openInfoDrop("controlCenter")
                    }
                }
            }

            // Séparateur horizontal discret avant les pastilles d'action
            Rectangle {
                x: 26
                y: 100
                width: parent.width - 52
                height: 1
                visible: root.infoChips.length > 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: Qt.alpha(root.fg, 0.12) }
                    GradientStop { position: 0.8; color: Qt.alpha(root.fg, 0.12) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // ── Pastilles d'état concentriques & interactives (alarme, Bluetooth, caféine, nuit, tâches, notifs, son, VPN) ──
            Flow {
                id: infoFlow

                x: 24
                y: 108
                width: parent.width - 48
                spacing: 6

                add: Transition {
                    NumberAnimation {
                        property: "scale"
                        from: 0.65
                        to: 1
                        duration: 300
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 200
                    }
                }
                move: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: 260
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
                        scale: chipArea.pressed ? 0.96 : 1
                        color: Qt.alpha(chip.modelData.tint, chipArea.pressed ? 0.26 : chipArea.containsMouse ? 0.2 : 0.12)
                        border.width: 0.5
                        border.color: Qt.alpha(chip.modelData.tint, chipArea.containsMouse ? 0.52 : 0.3)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        // Reflet spéculaire supérieur sur la pastille
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(12, parent.width - 18)
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.32 : 0.2
                        }

                        Row {
                            id: chipRow

                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
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
                                width: Math.min(implicitWidth, infoFlow.width - 52)
                                elide: Text.ElideRight
                                text: chip.modelData.text
                                color: root.fg
                                font.pointSize: 8.2
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                            }
                        }

                        MouseArea {
                            id: chipArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runInfoChip(chip.modelData.action ?? "")
                        }
                    }
                }
            }
        }

        // ── performances & processus en direct : 4 cadrans Liquid Glass, oscilloscope réseau, top 3 processus + Pulsar ──
        Face {
            id: perfFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))

            active: root.mode === "perf"
            slide: root.pageSlide("perf")

            // Caustique optique sur la lèvre inférieure + point lumineux sous le pointeur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.36 : 0.18
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(root.idleAccent, 0.9) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                x: Math.max(32, Math.min(perfFace.width - width - 32, perfFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // ── Rangée supérieure : 4 cadrans chronographes en verre + oscilloscope réseau double canal ──
            Item {
                id: perfTopRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 16
                height: 98

                Row {
                    id: perfRingsRow

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    PerfRing {
                        icon: "memory"
                        label: "CPU"
                        value: Cpu.percentage
                        sub: root.cpuGhz > 0 ? `${root.cpuGhz.toFixed(1).replace(".", ",")} GHz` : ""
                    }
                    // Température en direct : cyan au calme, accent tempéré, orange 70 °C, rouge 85 °C
                    PerfRing {
                        icon: Cpu.temperature >= 85 ? "local_fire_department" : "device_thermostat"
                        label: I18n.tr("Temp.")
                        thermal: true
                        rawTemp: Cpu.temperature
                        value: Math.max(0, Math.min(1, (Cpu.temperature - 35) / 60))
                        centerText: Cpu.temperature > 0 ? `${Math.round(Cpu.temperature)}°` : "—"
                        sub: root.fanRpm > 0 ? `${root.fanRpm} tr` : root.fanRpm === 0 ? I18n.tr("Ventilo arrêté") : root.tempPeak > 0 ? I18n.tr("Max %1°").arg(Math.round(root.tempPeak)) : ""
                    }
                    PerfRing {
                        icon: "memory_alt"
                        label: "RAM"
                        value: Memory.percentage
                        sub: root.kibText(Memory.used, Memory.total).replace(".", ",")
                    }
                    PerfRing {
                        icon: "hard_drive"
                        label: I18n.tr("Disque")
                        value: Storage.primaryDisk?.perc ?? 0
                        sub: Storage.primaryDisk ? root.freeText(Storage.primaryDisk.total - Storage.primaryDisk.used).replace(" libres", "").replace(" free", "") : ""
                    }
                }

                // Puits oscilloscope réseau double canal (cyan ↓ / violet ↑)
                Rectangle {
                    id: perfNetCard

                    readonly property color dlColor: Colours.light ? "#0284c7" : "#38bdf8"
                    readonly property color ulColor: Colours.light ? "#7c3aed" : "#a78bfa"

                    anchors.left: perfRingsRow.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: 16
                    scale: perfNetArea.pressed ? 0.985 : 1
                    border.width: 0.5
                    border.color: Qt.alpha(dlColor, perfNetArea.containsMouse ? 0.44 : 0.22)
                    clip: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(perfNetCard.dlColor, Colours.light ? 0.1 : 0.085) }
                        GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.035) }
                    }

                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    // Reflet spéculaire supérieur
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.34 : 0.18
                    }

                    // En-tête réseau + témoin d'activité
                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        anchors.topMargin: 8
                        height: 12

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Réseau").toUpperCase()
                            color: root.fgDim
                            font.pointSize: 6.5
                            font.weight: Font.Bold
                            font.letterSpacing: 0.7
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 5.5
                            height: 5.5
                            radius: 2.75
                            color: (NetworkUsage.downloadSpeed > 128 || NetworkUsage.uploadSpeed > 128) ? perfNetCard.dlColor : root.green
                            opacity: (Nmcli.wifiEnabled || Nmcli.hasAvailableEthernet) ? 0.9 : 0.3
                        }
                    }

                    // Débits descendant / montant
                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 21
                        spacing: 0

                        NetLine {
                            icon: "south"
                            tint: perfNetCard.dlColor
                            speed: NetworkUsage.downloadSpeed
                            big: true
                        }
                        NetLine {
                            icon: "north"
                            tint: perfNetCard.ulColor
                            speed: NetworkUsage.uploadSpeed
                        }
                    }

                    // Ligne de référence discrète dans la zone oscilloscope
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 22
                        height: 1
                        color: Qt.alpha(root.fg, 0.07)
                    }

                    SparklineItem {
                        id: netSpark

                        property real targetMax: 1024
                        property real smoothMax: targetMax

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        anchors.bottomMargin: 5
                        height: 36
                        line1: NetworkUsage.uploadBuffer // qmllint disable missing-type
                        line1Color: perfNetCard.ulColor
                        line1FillAlpha: 0.16
                        line2: NetworkUsage.downloadBuffer // qmllint disable missing-type
                        line2Color: perfNetCard.dlColor
                        line2FillAlpha: 0.26
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

                    MouseArea {
                        id: perfNetArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openMonitorApp()
                    }
                }
            }

            // Séparateur horizontal effilé entre capteurs et processus
            Rectangle {
                x: 24
                y: 121
                width: parent.width - 48
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.2; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 0.8; color: Qt.alpha(root.fg, 0.13) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // ── Barre d'en-tête Processus : compteur + charge, sélecteur CPU|RAM, lanceur Pulsar ──
            Item {
                id: perfProcHead

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 128
                height: 22

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "speed"
                        color: root.idleAccent
                        fontStyle: Tokens.font.icon.size(12).build()
                        fill: 1
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Processus").toUpperCase()
                        color: root.fg
                        font.pointSize: 7.3
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.perfProcCount > 0
                        width: procMetaTxt.implicitWidth + 12
                        height: 17
                        radius: 8.5
                        color: Qt.alpha(root.fg, 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.13)

                        StyledText {
                            id: procMetaTxt

                            anchors.centerIn: parent
                            text: `${root.perfProcCount} · ` + I18n.tr("charge %1").arg(root.perfLoad.toFixed(2).replace(".", ","))
                            color: root.fgDim
                            font.pointSize: 6.9
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Contrôle segmenté vitré : tri CPU | RAM en direct
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 74
                        height: 20
                        radius: 10
                        color: Qt.alpha(root.fg, 0.065)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.14)

                        // Pastille glissante active
                        Rectangle {
                            x: root.perfSort === "cpu" ? 2 : 37
                            y: 2
                            width: 35
                            height: 16
                            radius: 8
                            color: Qt.alpha(root.accent, Colours.light ? 0.22 : 0.24)
                            border.width: 0.5
                            border.color: Qt.alpha(root.accent, 0.45)

                            Behavior on x {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                        }

                        Row {
                            anchors.fill: parent

                            Item {
                                width: 37
                                height: parent.height

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "CPU"
                                    color: root.perfSort === "cpu" ? root.fg : root.fgDim
                                    font.pointSize: 6.8
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.perfSort = "cpu"
                                }
                            }

                            Item {
                                width: 37
                                height: parent.height

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "RAM"
                                    color: root.perfSort === "ram" ? root.fg : root.fgDim
                                    font.pointSize: 6.8
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.perfSort = "ram"
                                }
                            }
                        }
                    }

                    // Bouton vitré vers Pulsar / Moniteur système complet
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: pulsarBtnRow.implicitWidth + 14
                        height: 20
                        radius: 10
                        scale: pulsarArea.pressed ? 0.94 : 1
                        color: Qt.alpha(root.accent, pulsarArea.pressed ? 0.26 : pulsarArea.containsMouse ? 0.2 : 0.12)
                        border.width: 0.5
                        border.color: Qt.alpha(root.accent, pulsarArea.containsMouse ? 0.52 : 0.3)

                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 14
                            height: 1
                            radius: 0.5
                            color: "#ffffff"
                            opacity: Colours.light ? 0.34 : 0.2
                        }

                        Row {
                            id: pulsarBtnRow

                            anchors.centerIn: parent
                            spacing: 3.5

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Pulsar"
                                color: root.fg
                                font.pointSize: 7.2
                                font.weight: Font.Bold
                            }
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "open_in_new"
                                color: root.accent
                                fontStyle: Tokens.font.icon.size(9.5).build()
                            }
                        }

                        MouseArea {
                            id: pulsarArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openMonitorApp()
                        }
                    }
                }
            }

            // ── Top 3 des applications actives (cartes vitrées cliquables avec jauge de charge en direct) ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 155
                height: 45

                StyledText {
                    anchors.centerIn: parent
                    visible: root.topProcs.length === 0
                    text: I18n.tr("Analyse…")
                    color: root.fgDim
                    font.pointSize: 8
                    font.weight: Font.Medium
                }

                Row {
                    anchors.fill: parent
                    spacing: 7
                    visible: root.topProcs.length > 0

                    Repeater {
                        model: root.topProcs

                        Rectangle {
                            id: procCard

                            required property var modelData
                            readonly property real ramShare: Memory.total > 0 ? Math.min(1, modelData.rss / Memory.total) : 0
                            readonly property real cpuShare: Math.min(1, (modelData.cpu || 0) / 100)
                            readonly property real ratio: root.perfSort === "ram" ? ramShare : (cpuShare > 0.005 ? cpuShare : ramShare)
                            readonly property color loadTint: {
                                if (root.perfSort === "ram")
                                    return ramShare >= 0.35 ? root.red : ramShare >= 0.18 ? (Colours.light ? "#c77700" : "#ff9f0a") : root.accent;
                                return modelData.cpu >= 50 ? root.red : modelData.cpu >= 20 ? (Colours.light ? "#c77700" : "#ff9f0a") : root.accent;
                            }

                            width: Math.floor((parent.width - 14) / 3)
                            height: parent.height
                            radius: 12
                            scale: procArea.pressed ? 0.97 : 1
                            border.width: 0.5
                            border.color: Qt.alpha(loadTint, procArea.containsMouse ? 0.45 : 0.2)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.alpha(procCard.loadTint, procArea.containsMouse ? 0.14 : 0.08) }
                                GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.03) }
                            }

                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            // Reflet spéculaire supérieur sur la carte processus
                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                height: 1
                                radius: 0.5
                                color: "#ffffff"
                                opacity: Colours.light ? 0.32 : 0.16
                            }

                            // Ligne haute : pastille de charge + nom d'appli + métrique principale
                            Item {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.topMargin: 6
                                height: 15

                                Rectangle {
                                    id: procDot

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5.5
                                    height: 5.5
                                    radius: 2.75
                                    color: procCard.loadTint
                                }

                                StyledText {
                                    anchors.left: procDot.right
                                    anchors.leftMargin: 5.5
                                    anchors.right: procPrimary.left
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: procCard.modelData.name
                                    color: root.fg
                                    font.pointSize: 8.2
                                    font.weight: Font.DemiBold
                                }

                                StyledText {
                                    id: procPrimary

                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.perfSort === "ram"
                                        ? root.fmtRamKb(procCard.modelData.rss)
                                        : `${procCard.modelData.cpu >= 10 ? Math.round(procCard.modelData.cpu) : procCard.modelData.cpu.toFixed(1).replace(".", ",")}%`
                                    color: procCard.loadTint
                                    font.pointSize: 8.4
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                }
                            }

                            // Ligne médiane : nombre de tâches/PID + métrique secondaire
                            Item {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                y: 21
                                height: 12

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: procCard.modelData.count > 1 ? `×${procCard.modelData.count}` : `#${procCard.modelData.pid}`
                                    color: Qt.alpha(root.fg, 0.46)
                                    font.pointSize: 6.7
                                    font.weight: Font.Medium
                                    font.features: { "tnum": 1 }
                                }

                                StyledText {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.perfSort === "ram"
                                        ? `${procCard.modelData.cpu >= 10 ? Math.round(procCard.modelData.cpu) : procCard.modelData.cpu.toFixed(1).replace(".", ",")}% CPU`
                                        : root.fmtRamKb(procCard.modelData.rss)
                                    color: root.fgDim
                                    font.pointSize: 6.9
                                    font.weight: Font.Medium
                                    font.features: { "tnum": 1 }
                                }
                            }

                            // Barre de charge liquide en bas de carte
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                anchors.bottomMargin: 5.5
                                height: 3
                                radius: 1.5
                                color: Qt.alpha(root.fg, 0.09)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.max(4, parent.width * Math.max(0.03, procCard.ratio))
                                    radius: 1.5
                                    color: procCard.loadTint

                                    Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 280 } }
                                }
                            }

                            MouseArea {
                                id: procArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.focusProcessApp(procCard.modelData.key)
                            }
                        }
                    }
                }
            }
        }

        // Dock de pagination : capsule optique abritant les pastilles de page
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            width: pageDotsRow.implicitWidth + 12
            height: 11
            radius: 5.5
            color: Qt.alpha(root.fg, 0.05)
            border.width: 0.5
            border.color: Qt.alpha(root.fg, 0.12)
            opacity: root.paged && root.shelf.length === 0 ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: 250
                }
            }

            Row {
                id: pageDotsRow

                anchors.centerIn: parent
                spacing: 4.5

                Repeater {
                    model: root.pages.length

                    Rectangle {
                        required property int index
                        readonly property bool current: root.pageIndex === index

                        anchors.verticalCenter: parent.verticalCenter
                        width: current ? 15 : 4.5
                        height: 4.5
                        radius: 2.25
                        color: current ? root.accent : Qt.alpha(root.fg, 0.28)

                        Behavior on width {
                            NumberAnimation {
                                duration: 380
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.4
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 260
                            }
                        }

                        TapHandler {
                            margin: 6
                            onTapped: root.flipPage(parent.index - root.pageIndex)
                        }
                    }
                }
            }
        }

        // ── lecteur média Liquid Glass : pochette réactive, sélecteur source, puits spectre Cava, paroles vitrées, waveform + dock audio complet ──
        Face {
            id: playerFace

            readonly property real hoverX: Math.max(0, Math.min(width, islandHover.point.position.x - (root.width - width) / 2))
            readonly property real rawBass: {
                if (!root.playing || Audio.cava.values.length === 0)
                    return 0;
                const n = Math.min(4, Audio.cava.values.length);
                let s = 0;
                for (let i = 0; i < n; i++)
                    s += Audio.cava.values[i] ?? 0;
                return Math.min(1, s / n);
            }
            property real bassLevel: rawBass

            active: root.mode === "player"
            slide: root.pageSlide("player")

            Behavior on bassLevel {
                NumberAnimation {
                    duration: 85
                    easing.type: Easing.OutQuad
                }
            }

            // Horizon atmosphérique réactif aux basses derrière la tête du lecteur
            Rectangle {
                x: 14
                y: 10
                width: 280
                height: 78
                radius: 39
                opacity: root.playing ? (0.14 + playerFace.bassLevel * 0.24) : 0.08
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.28; color: Qt.alpha(root.accent, 0.36) }
                    GradientStop { position: 0.65; color: Qt.alpha("#38bdf8", 0.18) }
                    GradientStop { position: 1.0; color: "transparent" }
                }

                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            // Caustique optique inférieure + point lumineux sous le curseur
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(120, parent.width - 72)
                height: 1
                opacity: root.hovered ? 0.38 : 0.2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 0.5; color: Qt.alpha(root.accent, 0.92) }
                    GradientStop { position: 0.75; color: Qt.alpha("#ffffff", Colours.light ? 0.45 : 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                x: Math.max(32, Math.min(playerFace.width - width - 32, playerFace.hoverX - width / 2))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1.5
                width: 84
                height: 1.5
                radius: 0.75
                opacity: root.hovered ? 0.65 : 0
                visible: opacity > 0.01
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                Behavior on x { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // Halo liquide réactif aux basses derrière la pochette
            Rectangle {
                anchors.centerIn: bigCover
                width: bigCover.width + 12
                height: bigCover.height + 12
                radius: bigCover.radius + 5
                scale: 1 + playerFace.bassLevel * 0.14
                opacity: root.playing ? 0.2 + playerFace.bassLevel * 0.48 : 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(root.accent, 0.7) }
                    GradientStop { position: 0.5; color: Qt.alpha("#38bdf8", 0.58) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.green, 0.48) }
                }
                border.width: 1
                border.color: Qt.alpha("#ffffff", 0.22 + playerFace.bassLevel * 0.35)
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // Pochette sculptée avec reflet biseauté et micro-pastille de pause
            Cover {
                id: bigCover

                x: 22
                y: 18
                size: 66
                radius: 16
                scale: 1 + playerFace.bassLevel * 0.035

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha("#ffffff", 0.2 + playerFace.bassLevel * 0.24)
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 34
                    height: 1
                    radius: 0.5
                    color: "#ffffff"
                    opacity: 0.32
                }

                // Micro pastille pause si en pause
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    visible: !root.playing
                    width: 18
                    height: 18
                    radius: 9
                    color: Qt.alpha("#000000", 0.58)
                    border.width: 0.5
                    border.color: Qt.alpha("#ffffff", 0.28)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "pause"
                        color: "#ffffff"
                        fontStyle: Tokens.font.icon.size(10.5).build()
                        fill: 1
                    }
                }
            }

            // Centre : Pilule source cliquable (bascule entre lecteurs si > 1) · Titre · Artiste
            Column {
                anchors.left: bigCover.right
                anchors.leftMargin: 14
                anchors.right: bigBarsWell.left
                anchors.rightMargin: 12
                anchors.verticalCenter: bigCover.verticalCenter
                spacing: 2

                Rectangle {
                    width: Math.min(parent.width, srcPillRow.implicitWidth + 14)
                    height: 17
                    radius: 8.5
                    scale: srcArea.pressed ? 0.94 : 1
                    color: Qt.alpha(root.accent, srcArea.containsMouse && root.playerCount > 1 ? 0.22 : 0.13)
                    border.width: 0.5
                    border.color: Qt.alpha(root.accent, srcArea.containsMouse && root.playerCount > 1 ? 0.48 : 0.3)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: srcPillRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "music_note"
                            color: root.accent
                            fontStyle: Tokens.font.icon.size(9.5).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (Players.getIdentity(root.player) || I18n.tr("Audio")).toUpperCase()
                            color: root.accent
                            font.pointSize: 6.6
                            font.weight: Font.Bold
                            font.letterSpacing: 0.65
                        }
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.playerCount > 1
                            text: "swap_horiz"
                            color: root.fgDim
                            fontStyle: Tokens.font.icon.size(10).build()
                        }
                    }

                    MouseArea {
                        id: srcArea

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.playerCount > 1
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.cyclePlayer()
                    }
                }

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackTitle ?? ""
                    color: root.fg
                    font.pointSize: 12
                    font.weight: Font.Bold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackArtist || Players.getIdentity(root.player)
                    color: root.fgDim
                    font.pointSize: 8.8
                    font.weight: Font.Medium
                }
            }

            // Puits vitré du spectre audio Cava (6 bandes)
            Rectangle {
                id: bigBarsWell

                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: bigCover.verticalCenter
                width: 56
                height: 44
                radius: 14
                border.width: 0.5
                border.color: Qt.alpha(root.accent, root.playing ? 0.3 : 0.14)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(root.accent, root.playing ? 0.11 : 0.05) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.03) }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28
                    height: 1
                    radius: 0.5
                    color: "#ffffff"
                    opacity: Colours.light ? 0.34 : 0.18
                }

                Bars {
                    id: bigBars

                    anchors.centerIn: parent
                    count: 6
                    barWidth: 3.2
                    maxHeight: 24
                }
            }

            // Ruban vitré des paroles synchronisées en direct
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: 92
                height: 28
                radius: 11
                visible: root.hasLyrics
                border.width: 0.5
                border.color: Qt.alpha(root.accent, 0.24)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(root.accent, Colours.light ? 0.1 : 0.09) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.03) }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    height: 1
                    radius: 0.5
                    color: "#ffffff"
                    opacity: Colours.light ? 0.3 : 0.16
                }

                LyricLine {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    line: root.lyricLine
                    lineColor: root.accent
                    size: 10
                    bold: true
                }
            }

            // Barre de progression waveform Cava 28 bandes avec aperçu temps au survol
            Item {
                id: progress

                readonly property real len: root.player?.length ?? 0
                readonly property real pos: root.player?.position ?? 0
                readonly property bool known: len > 0 && len < 2147483
                readonly property real playRatio: known ? Math.max(0, Math.min(1, pos / len)) : 0

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: root.hasLyrics ? 127 : 96
                height: 20

                StyledText {
                    id: posText

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    text: seekTrack.hoverRatio >= 0 && progress.known
                        ? root.fmtTime(seekTrack.hoverRatio * progress.len)
                        : root.fmtTime(progress.pos)
                    color: seekTrack.hoverRatio >= 0 && progress.known ? root.accent : root.fgDim
                    font.pointSize: 7.6
                    font.weight: seekTrack.hoverRatio >= 0 ? Font.Bold : Font.Medium
                    font.features: { "tnum": 1 }
                }

                Item {
                    id: seekTrack

                    readonly property int barCount: 28
                    readonly property real hoverRatio: seekArea.containsMouse ? Math.max(0, Math.min(1, (seekArea.mouseX - 6) / Math.max(1, width))) : -1

                    anchors.left: posText.right
                    anchors.right: lenText.left
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18

                    Row {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        spacing: 2

                        Repeater {
                            model: seekTrack.barCount

                            Rectangle {
                                required property int index
                                readonly property real barRatio: (index + 0.5) / seekTrack.barCount
                                readonly property bool played: progress.known && barRatio <= progress.playRatio
                                readonly property bool hoveredBar: seekTrack.hoverRatio >= 0 && Math.abs(barRatio - seekTrack.hoverRatio) < 0.08
                                readonly property real baseWave: 0.28 + 0.34 * Math.abs(Math.sin((index + 1) * 0.72 + Math.cos(index * 0.35)))
                                readonly property real liveSpec: {
                                    if (!root.playing || Audio.cava.values.length === 0)
                                        return 0;
                                    const ci = Math.floor(barRatio * Audio.cava.values.length);
                                    return Math.min(1, Audio.cava.values[ci] ?? 0);
                                }
                                readonly property real amp: Math.min(1, baseWave * (root.playing ? 0.55 : 0.75) + liveSpec * 0.65 + (hoveredBar ? 0.22 : 0))

                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(2, (seekTrack.width - (seekTrack.barCount - 1) * 2) / seekTrack.barCount)
                                height: Math.max(3, Math.round((seekArea.containsMouse ? 16 : 13) * amp))
                                radius: width / 2
                                color: played ? root.accent : (seekTrack.hoverRatio >= 0 && barRatio <= seekTrack.hoverRatio ? Qt.alpha(root.fg, 0.35) : root.fgFaint)

                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: played ? "#38bdf8" : (seekTrack.hoverRatio >= 0 && barRatio <= seekTrack.hoverRatio ? Qt.alpha(root.fg, 0.38) : root.fgFaint)
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: played ? root.accent : (seekTrack.hoverRatio >= 0 && barRatio <= seekTrack.hoverRatio ? Qt.alpha(root.fg, 0.28) : root.fgFaint)
                                    }
                                }

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 85
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }
                        }
                    }

                    // Curseur goutte de verre lumineuse
                    Rectangle {
                        visible: progress.known
                        x: Math.max(0, Math.min(seekTrack.width - width, progress.playRatio * seekTrack.width - width / 2))
                        anchors.verticalCenter: parent.verticalCenter
                        width: seekArea.containsMouse ? 5 : 3.5
                        height: seekArea.containsMouse ? 17 : 13
                        radius: width / 2
                        color: "#ffffff"
                        border.width: 1
                        border.color: Qt.alpha(root.accent, 0.7)

                        Behavior on width { NumberAnimation { duration: 120 } }
                        Behavior on height { NumberAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: seekArea

                        function seekAt(mx: real): void {
                            const ratio = Math.max(0, Math.min(1, (mx - 6) / Math.max(1, seekTrack.width)));
                            root.player.position = ratio * progress.len;
                        }

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        enabled: progress.known && (root.player?.canSeek ?? false)
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: e => seekAt(e.x)
                        onPositionChanged: e => {
                            if (pressed)
                                seekAt(e.x);
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
                    font.pointSize: 7.6
                    font.features: { "tnum": 1 }
                }
            }

            // ── Dock de transport & audio : Sortie audio à gauche · Transport sculpté au centre · Volume à droite ──
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                y: root.hasLyrics ? 154 : 124
                height: 40

                // Gauche : Pilule sortie audio (clic = basculer de sortie)
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(144, outPillRow.implicitWidth + 18)
                    height: 28
                    radius: 14
                    scale: outArea.pressed ? 0.94 : 1
                    color: Qt.alpha(root.btConnected.length > 0 && !Audio.muted ? root.green : root.fg, outArea.pressed ? 0.18 : outArea.containsMouse ? 0.13 : 0.065)
                    border.width: 0.5
                    border.color: Qt.alpha(root.btConnected.length > 0 && !Audio.muted ? root.green : root.fg, outArea.containsMouse ? 0.36 : 0.15)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(14, parent.width - 20)
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.16
                    }

                    Row {
                        id: outPillRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.playerOutputIcon
                            color: Audio.muted ? root.red : (root.btConnected.length > 0 ? root.green : root.fgDim)
                            fontStyle: Tokens.font.icon.size(12.5).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 102)
                            elide: Text.ElideRight
                            text: root.playerOutputLabel
                            color: root.fg
                            font.pointSize: 7.6
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: outArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.cycleNextAudioOutput()
                    }
                }

                // Centre : Capsule de transport vitrée avec bouton Lecture/Pause lumineux
                Rectangle {
                    anchors.centerIn: parent
                    width: 144
                    height: 40
                    radius: 20
                    color: Qt.alpha(root.fg, 0.055)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.13)

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 96
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.16
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 14

                        IslandButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "skip_previous"
                            enabled: root.player?.canGoPrevious ?? false
                            onClicked: root.player?.previous()
                        }

                        // Bouton central Lecture / Pause en lentille accentuée
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34
                            radius: 17
                            opacity: (root.player?.canTogglePlaying ?? false) ? 1 : 0.35
                            scale: playBtnArea.pressed ? 0.9 : (playBtnArea.containsMouse ? 1.05 : 1)
                            border.width: 0.5
                            border.color: Qt.alpha(root.accent, 0.6)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.alpha(root.accent, playBtnArea.pressed ? 0.42 : 0.3) }
                                GradientStop { position: 1.0; color: Qt.alpha(root.accent, 0.16) }
                            }

                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                            Rectangle {
                                anchors.top: parent.top
                                anchors.topMargin: 1.5
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 16
                                height: 1
                                radius: 0.5
                                color: "#ffffff"
                                opacity: 0.42
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: root.playing ? "pause" : "play_arrow"
                                color: root.fg
                                fontStyle: Tokens.font.icon.size(19).build()
                                fill: 1
                            }

                            MouseArea {
                                id: playBtnArea

                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.player?.canTogglePlaying ?? false
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.player?.togglePlaying()
                            }
                        }

                        IslandButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "skip_next"
                            enabled: root.player?.canGoNext ?? false
                            onClicked: root.player?.next()
                        }
                    }
                }

                // Droite : Capsule volume en direct (clic = muet, molette = volume via Island)
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: volPillRow.implicitWidth + 18
                    height: 28
                    radius: 14
                    scale: volPillArea.pressed ? 0.94 : 1
                    color: Audio.muted
                        ? Qt.alpha(root.red, volPillArea.containsMouse ? 0.24 : 0.15)
                        : Qt.alpha(root.fg, volPillArea.pressed ? 0.18 : volPillArea.containsMouse ? 0.13 : 0.065)
                    border.width: 0.5
                    border.color: Audio.muted ? Qt.alpha(root.red, 0.45) : Qt.alpha(root.fg, volPillArea.containsMouse ? 0.3 : 0.15)

                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(14, parent.width - 20)
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.32 : 0.16
                    }

                    Row {
                        id: volPillRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Audio.muted || Audio.volume <= 0 ? "volume_off" : Audio.volume < 0.5 ? "volume_down" : "volume_up"
                            color: Audio.muted ? root.red : root.accent
                            fontStyle: Tokens.font.icon.size(12.5).build()
                            fill: 1
                        }

                        // Mini barre de volume intégrée
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 3.5
                            radius: 1.75
                            color: Qt.alpha(root.fg, 0.12)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: Audio.muted ? 0 : Math.max(2, parent.width * Math.min(1, Audio.volume))
                                radius: 1.75
                                color: root.accent

                                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Audio.muted ? "0%" : `${Math.round(Audio.volume * 100)}%`
                            color: Audio.muted ? root.red : root.fg
                            font.pointSize: 7.5
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                        }
                    }

                    MouseArea {
                        id: volPillArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Audio.sink?.ready && Audio.sink?.audio)
                                Audio.sink.audio.muted = !Audio.sink.audio.muted;
                        }
                    }
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
        const gibTot = total / 1048576;
        if (gibTot >= 1024)
            return `${+(used / 1073741824).toFixed(1)}/${Math.round(gibTot / 1024)} To`;
        if (gibTot >= 1)
            return `${+(used / 1048576).toFixed(1)}/${Math.round(gibTot)} Go`;
        return `${Math.round(used / 1024)}/${Math.round(total / 1024)} Mo`;
    }

    // Espace libre lisible : « 46,9 Go libres »
    function freeText(kib: real): string {
        if (!(kib > 0))
            return "plein";
        const gib = kib / 1048576;
        const v = gib >= 1024 ? `${(gib / 1024).toFixed(1)} To` : gib >= 100 ? `${Math.round(gib)} Go` : `${gib.toFixed(1)} Go`;
        return `${v.replace(".", ",")} libres`;
    }

    // Cadran chronographe Liquid Glass 270° (puits vitré biseauté, arc lumineux double passe et teinte dynamique)
    component PerfRing: Rectangle {
        id: ring

        property string icon
        property string label
        property string sub
        property string centerText
        property real value
        property real shown: value
        property bool thermal: false
        property real rawTemp: 0
        readonly property color tint: {
            if (thermal) {
                if (rawTemp >= 85)
                    return root.red;
                if (rawTemp >= 70)
                    return Colours.light ? "#c77700" : "#ff9f0a";
                if (rawTemp > 0 && rawTemp < 55)
                    return Colours.light ? "#0284c7" : "#38bdf8";
                return root.accent;
            }
            return shown > 0.85 ? root.red : shown > 0.6 ? (Colours.light ? "#c77700" : "#ff9f0a") : root.accent;
        }

        width: 84
        height: 98
        radius: 16
        scale: ringArea.pressed ? 0.97 : 1
        border.width: 0.5
        border.color: Qt.alpha(tint, ringArea.containsMouse ? 0.46 : 0.22)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(ring.tint, Colours.light ? 0.11 : 0.095) }
            GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.03) }
        }

        Behavior on shown {
            NumberAnimation {
                duration: 700
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 220 } }

        // Reflet spéculaire supérieur sur la carte jauge
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 24
            height: 1
            radius: 0.5
            color: "#ffffff"
            opacity: Colours.light ? 0.34 : 0.18
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1
            spacing: 1

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56
                height: 54

                // Disque cristallin interne
                Rectangle {
                    anchors.centerIn: parent
                    width: 39
                    height: 39
                    radius: 19.5
                    color: Qt.alpha(ring.tint, Colours.light ? 0.11 : 0.09)
                    border.width: 0.5
                    border.color: Qt.alpha(ring.tint, 0.26)

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1.5
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 16
                        height: 1
                        radius: 0.5
                        color: "#ffffff"
                        opacity: Colours.light ? 0.35 : 0.22
                    }
                }

                Shape {
                    anchors.centerIn: parent
                    width: 56
                    height: 56
                    preferredRendererType: Shape.CurveRenderer

                    // Piste de fond 270°
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(root.fg, 0.11)
                        strokeWidth: 4.2
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: 28
                            centerY: 28
                            radiusX: 24
                            radiusY: 24
                            startAngle: 135
                            sweepAngle: 270
                        }
                    }
                    // Halo lumineux doux sous l'arc actif
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.alpha(ring.tint, 0.22)
                        strokeWidth: 8.2
                        capStyle: ShapePath.RoundCap

                        Behavior on strokeColor { ColorAnimation { duration: 420 } }

                        PathAngleArc {
                            centerX: 28
                            centerY: 28
                            radiusX: 24
                            radiusY: 24
                            startAngle: 135
                            sweepAngle: Math.max(0.01, Math.min(1, ring.shown)) * 270
                        }
                    }
                    // Arc actif net au premier plan
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: ring.tint
                        strokeWidth: 4.2
                        capStyle: ShapePath.RoundCap

                        Behavior on strokeColor { ColorAnimation { duration: 420 } }

                        PathAngleArc {
                            centerX: 28
                            centerY: 28
                            radiusX: 24
                            radiusY: 24
                            startAngle: 135
                            sweepAngle: Math.max(0.01, Math.min(1, ring.shown)) * 270
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: -2

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ring.icon
                        color: ring.tint
                        fontStyle: Tokens.font.icon.size(10).build()
                        fill: 1
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ring.centerText || Math.round(ring.shown * 100) + "%"
                        color: root.fg
                        font.pointSize: 9.8
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ring.label.toUpperCase()
                color: root.fg
                font.pointSize: 6.9
                font.weight: Font.Bold
                font.letterSpacing: 0.65
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: -2
                width: Math.min(implicitWidth, ring.width - 8)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: ring.sub
                visible: text !== ""
                color: root.fgDim
                font.pointSize: 6.8
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }

        MouseArea {
            id: ringArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openMonitorApp()
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

        spacing: 3.5

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
            fontStyle: Tokens.font.icon.size(nl.big ? 11.5 : 9.5).build()
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const b = Math.max(0, Number(nl.shown) || 0);
                let v = b;
                let unit = "o/s";
                if (b >= 1073741824) {
                    v = b / 1073741824;
                    unit = "Go/s";
                } else if (b >= 1048576) {
                    v = b / 1048576;
                    unit = "Mo/s";
                } else if (b >= 1024) {
                    v = b / 1024;
                    unit = "Ko/s";
                }
                return `${v.toFixed(v < 10 && unit !== "o/s" ? 1 : 0).replace(".", ",")} ${unit}`;
            }
            color: nl.big ? root.fg : root.fgDim
            font.pointSize: nl.big ? 10.6 : 8.4
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
        property real phase: 0

        NumberAnimation on phase {
            running: Players.active?.isPlaying ?? false
            from: 0
            to: Math.PI * 2
            duration: 1400
            loops: Animation.Infinite
        }

        spacing: 2.5
        height: maxHeight

        Repeater {
            model: bars.count

            Rectangle {
                required property int index
                readonly property int total: Audio.cava.values.length
                readonly property real v: {
                    if (!(Players.active?.isPlaying ?? false))
                        return 0.16;
                    const wave = 0.22 + 0.14 * Math.sin(bars.phase + index * 1.15);
                    if (total === 0)
                        return wave;
                    const i = Math.floor((index + 0.5) / bars.count * total);
                    const cv = Audio.cava.values[i] ?? 0;
                    return Math.max(wave, Math.min(1, cv * 0.88 + wave * 0.25));
                }

                anchors.verticalCenter: parent.verticalCenter
                width: bars.barWidth
                height: Math.max(bars.barWidth, bars.maxHeight * v)
                radius: bars.barWidth / 2
                color: Colours.palette.m3primary
                border.width: 0.5
                border.color: Qt.alpha("#ffffff", 0.22 + v * 0.25)

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: "#38bdf8"
                    }
                    GradientStop {
                        position: 0.55
                        color: Colours.palette.m3primary
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.tint(Colours.palette.m3primary, Qt.alpha("#34d399", 0.35))
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 75
                        easing.type: Easing.OutQuad
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
        readonly property color fillTop: charging ? "#34d399" : pct < 0.2 ? "#ff6b6b" : fg
        readonly property color fillBot: charging ? (Colours.light ? "#16a34a" : "#22c55e") : pct < 0.2 ? "#ff453a" : Qt.alpha(fg, 0.86)

        width: 26
        height: 12.5

        // Halo doux discret autour de la batterie en charge ou faible (< 20 %)
        Rectangle {
            anchors.centerIn: glyphShell
            width: glyphShell.width + 6
            height: glyphShell.height + 6
            radius: height / 2
            color: glyph.charging ? "#34d399" : "#ff453a"
            opacity: glyph.charging ? 0.2 : (glyph.pct < 0.2 ? 0.18 : 0)
            visible: opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: 280 } }
        }

        Rectangle {
            id: glyphShell

            anchors.verticalCenter: parent.verticalCenter
            width: 23
            height: 12.5
            radius: 3.8
            color: Qt.alpha(glyph.fg, 0.08)
            border.width: 1
            border.color: glyph.charging ? Qt.alpha("#34d399", 0.55) : Qt.alpha(glyph.fg, 0.42)

            // Jauge au sous-pixel près (largeur fractionnaire, lissée)
            Rectangle {
                x: 1.8
                y: 1.8
                height: parent.height - 3.6
                width: Math.max(2, (parent.width - 3.6) * Math.max(0, Math.min(1, glyph.pct)))
                radius: 2.2
                antialiasing: true

                gradient: Gradient {
                    GradientStop { position: 0.0; color: glyph.fillTop }
                    GradientStop { position: 1.0; color: glyph.fillBot }
                }

                // Reflet spéculaire supérieur sur la jauge
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 0.5
                    height: 1
                    radius: 0.5
                    color: Qt.alpha("#ffffff", 0.32)
                }

                Behavior on width {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Éclair vectoriel net au centre pendant la charge
            Shape {
                anchors.centerIn: parent
                width: 8
                height: 10
                visible: glyph.charging
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 0.7
                    strokeColor: Qt.alpha("#000000", 0.45)
                    fillColor: "#ffffff"
                    joinStyle: ShapePath.MiterJoin

                    startX: 4.8
                    startY: 0.4
                    PathLine { x: 1.2; y: 5.4 }
                    PathLine { x: 3.9; y: 5.4 }
                    PathLine { x: 3.1; y: 9.6 }
                    PathLine { x: 6.8; y: 4.5 }
                    PathLine { x: 4.1; y: 4.5 }
                    PathLine { x: 4.8; y: 0.4 }
                }
            }
        }

        // Borne positive usinée
        Rectangle {
            x: 23.8
            anchors.verticalCenter: parent.verticalCenter
            width: 1.8
            height: 4.5
            radius: 0.9
            color: glyph.charging ? Qt.alpha("#34d399", 0.6) : Qt.alpha(glyph.fg, 0.42)
        }
    }

    // Chiffre d'horloge horloger à roulement vertical fluide (0 % CPU entre deux minutes)
    component ClockDigit: Item {
        id: cd

        property string digit: "0"
        property color textColor: root.fg
        property real ptSize: 13.8
        property string shown: ""
        property string prev: ""
        property real roll: 1

        readonly property string activeChar: shown !== "" ? shown : digit

        implicitWidth: Math.ceil(curTxt.implicitWidth)
        implicitHeight: Math.ceil(curTxt.implicitHeight) + 2
        clip: true

        Component.onCompleted: shown = digit

        onDigitChanged: {
            if (shown === "") {
                shown = digit;
                return;
            }
            if (digit === shown)
                return;
            prev = shown;
            shown = digit;
            rollAnim.restart();
        }

        NumberAnimation {
            id: rollAnim

            target: cd
            property: "roll"
            from: 0
            to: 1
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 0.7
        }

        // Ancien chiffre qui glisse vers le haut et s'efface
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 1 - cd.roll * (cd.height * 0.62)
            opacity: cd.roll < 0.75 ? Math.max(0, 1 - cd.roll * 1.45) : 0
            scale: 1 - cd.roll * 0.16
            visible: cd.roll < 0.99 && cd.prev !== ""
            text: cd.prev
            color: cd.textColor
            font.pointSize: cd.ptSize
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }

        // Légère ombre optique pour une lisibilité parfaite sur fond clair comme sombre
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 1.8 + (1 - cd.roll) * (cd.height * 0.62)
            opacity: (Colours.light ? 0.06 : 0.34) * Math.min(1, cd.roll * 1.35)
            scale: 0.86 + 0.14 * Math.min(1, cd.roll)
            text: cd.activeChar
            color: "#000000"
            font.pointSize: cd.ptSize
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }

        // Nouveau chiffre au premier plan
        StyledText {
            id: curTxt

            anchors.horizontalCenter: parent.horizontalCenter
            y: 1 + (1 - cd.roll) * (cd.height * 0.62)
            opacity: Math.min(1, cd.roll * 1.35)
            scale: 0.86 + 0.14 * Math.min(1, cd.roll)
            text: cd.activeChar
            color: cd.textColor
            font.pointSize: cd.ptSize
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
    }

    // Icône d'état de l'île au repos dans sa lentille circulaire concentrique (zéro saut de largeur)
    component IdleIcon: Item {
        id: ii

        property bool shown
        property string icon
        property color tint
        property int count: 0
        property real leadGap: 6

        readonly property real pillW: count > 1 ? Math.max(32, iiRow.implicitWidth + 10) : 20

        anchors.verticalCenter: parent?.verticalCenter
        width: shown ? pillW + leadGap : 0
        height: 20
        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        clip: true

        Behavior on width {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 220
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: ii.pillW
            height: 20
            radius: 10
            scale: ii.shown ? 1 : 0.72
            color: Qt.alpha(ii.tint, Colours.light ? 0.16 : 0.14)
            border.width: 0.5
            border.color: Qt.alpha(ii.tint, Colours.light ? 0.34 : 0.32)

            Behavior on scale {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutBack
                }
            }
            Behavior on color { ColorAnimation { duration: 240 } }
            Behavior on border.color { ColorAnimation { duration: 240 } }

            // Reflet spéculaire supérieur sur la lentille circulaire
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.5
                height: 1
                radius: 0.5
                color: "#ffffff"
                opacity: Colours.light ? 0.35 : 0.24
            }

            Row {
                id: iiRow

                anchors.centerIn: parent
                spacing: 2.5

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ii.icon
                    color: ii.tint
                    fontStyle: Tokens.font.icon.size(11.5).build()
                    fill: 1
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ii.count > 1
                    text: `${ii.count}`
                    color: root.fg
                    font.pointSize: 7.4
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    component PrivacyDot: Rectangle {
        property color dotColor

        anchors.verticalCenter: parent?.verticalCenter
        width: 6.5
        height: 6.5
        radius: 3.25
        color: dotColor
        border.width: 0.5
        border.color: Qt.alpha("#ffffff", 0.45)

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 2.3
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(parent.dotColor, 0.38)
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
        color: "transparent"
        // Verre liquide (iOS 27) sous le contenu
        GlassControl {
            anchors.fill: parent
            radius: parent.radius
            bevel: parent.height > 60 ? 16 : 0
            tintColour: Qt.alpha(Colours.palette.m3onSurface, sbArea.pressed ? 0.24 : sbArea.containsMouse ? 0.17 : 0.1)
            visible: tintColour.a > 0.01
            pressed: sbArea.pressed
            hovered: sbArea.containsMouse
            pointer: sbArea.containsMouse ? Qt.point(sbArea.mouseX / Math.max(1, width), sbArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
        }
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

    // Pastille d'action avec libellé (Autoriser, Refuser…)
    component PillButton: Rectangle {
        id: pill

        property string icon
        property string label
        property color tint
        signal clicked

        width: pillRow.implicitWidth + 26
        height: 40
        radius: 20
        color: "transparent"
        // Verre liquide (iOS 27) sous le contenu
        GlassControl {
            anchors.fill: parent
            radius: parent.radius
            bevel: parent.height > 60 ? 16 : 0
            tintColour: pillArea.containsMouse ? Qt.lighter(tint, 1.1) : tint
            visible: tintColour.a > 0.01
            pressed: pillArea.pressed
            hovered: pillArea.containsMouse
            pointer: pillArea.containsMouse ? Qt.point(pillArea.mouseX / Math.max(1, width), pillArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
        }
        scale: pillArea.pressed ? 0.93 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 120
            }
        }

        Row {
            id: pillRow

            anchors.centerIn: parent
            spacing: 5

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                color: "white"
                fontStyle: Tokens.font.icon.size(15).build()
                fill: 1
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: "white"
                font.pointSize: 10
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: pillArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    // Pastille d'agent : anneau qui tourne pendant le travail, coche quand c'est fini
    component AgentSpinner: Item {
        id: spin

        property color tint
        property bool spinning
        property bool done
        property string letter
        property real size: 24

        width: size
        height: size

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(spin.tint, 0.16)
            border.width: 0.5
            border.color: Qt.alpha(spin.tint, 0.34)

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.45
                height: 1
                radius: 0.5
                color: "#ffffff"
                opacity: Colours.light ? 0.35 : 0.24
            }
        }

        Shape {
            anchors.fill: parent
            visible: !spin.done
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 5.2
                strokeColor: Qt.alpha(spin.tint, 0.24)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: spin.size / 2
                    centerY: spin.size / 2
                    radiusX: spin.size / 2 - 2
                    radiusY: spin.size / 2 - 2
                    startAngle: -90
                    sweepAngle: spin.spinning ? 120 : 360
                }
            }
            ShapePath {
                strokeWidth: 2.5
                strokeColor: spin.tint
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: spin.size / 2
                    centerY: spin.size / 2
                    radiusX: spin.size / 2 - 2
                    radiusY: spin.size / 2 - 2
                    startAngle: -90
                    sweepAngle: spin.spinning ? 120 : 360
                }
            }

            RotationAnimation on rotation {
                running: spin.spinning
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1100
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: !spin.done
            text: spin.letter || "✦"
            color: spin.tint
            font.pointSize: spin.letter ? (spin.size >= 28 ? 9.6 : 8.5) : 9
            font.weight: Font.Black
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: spin.done
            text: "check"
            color: spin.tint
            fontStyle: Tokens.font.icon.size(spin.size >= 28 ? 16 : 14).build()
            fill: 1
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

        // Verre liquide (iOS 27) : la lentille apparaît au survol et gonfle à l'appui
        GlassControl {
            anchors.fill: parent
            tintColour: Qt.alpha(Colours.palette.m3onSurface, area.pressed ? 0.16 : 0.08)
            pressed: area.pressed
            hovered: area.containsMouse
            pointer: area.containsMouse ? Qt.point(area.mouseX / Math.max(1, width), area.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
            opacity: area.pressed || area.containsMouse ? 1 : 0
            scale: area.pressed ? 1.1 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }
            Behavior on scale {
                SpringAnimation {
                    spring: 5
                    damping: 0.26
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

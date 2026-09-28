pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Batterie détaillée (Centre de contrôle → batterie) :
// niveau, autonomie, consommation en watts, santé, historique sur 24 h,
// apps qui consomment le plus (processeur, regroupé par app), économie d'énergie automatique.
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev?.isLaptopBattery ?? false
    readonly property real pct: (dev?.percentage ?? 0)
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging || dev?.state === UPowerDeviceState.PendingCharge
    readonly property bool full: dev?.state === UPowerDeviceState.FullyCharged || (!UPower.onBattery && pct >= 0.995)
    readonly property real timeToEmpty: dev?.timeToEmpty ?? 0
    readonly property real timeToFull: dev?.timeToFull ?? 0

    // Lu dans /sys (plus précis que UPower pour les watts et la santé)
    property real watts
    property real health: -1 // capacité actuelle / capacité d'origine
    property int cycles

    // Historique : un point toutes les 5 min, 24 h gardées
    property list<var> history: []
    // Apps qui consomment : [{ key, cpu }] (part du processeur sur les dernières secondes)
    property list<var> consumers: []
    property int consumersRefs // pages ouvertes qui veulent la liste

    // Économie d'énergie automatique sous 20 % (sur batterie), retour au profil d'avant en charge
    property bool autoSaver: true
    property bool saverOn // c'est nous qui l'avons mis
    property int profileBefore: PowerProfile.Balanced

    readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/caelestia/battery.json`

    function fmtDuration(sec: real): string {
        if (!(sec > 0))
            return "";
        const h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60);
        return h > 0 ? `${h} h ${m.toString().padStart(2, "0")}` : `${m} min`;
    }

    readonly property string statusText: {
        if (!present)
            return qsTr("Sur secteur");
        if (full)
            return qsTr("Chargée");
        if (charging)
            return timeToFull > 0 ? qsTr("En charge · pleine dans %1").arg(fmtDuration(timeToFull)) : qsTr("En charge");
        if (!UPower.onBattery)
            return qsTr("Branchée, pas en charge");
        return timeToEmpty > 0 ? qsTr("Environ %1 restantes").arg(fmtDuration(timeToEmpty)) : qsTr("Sur batterie");
    }

    function save(): void {
        stateView.setText(JSON.stringify({
            autoSaver: autoSaver,
            saverOn: saverOn,
            profileBefore: profileBefore,
            history: history
        }));
    }

    function setAutoSaver(on: bool): void {
        autoSaver = on;
        checkSaver();
        save();
    }

    function record(): void {
        if (!present)
            return;
        const now = Date.now();
        const h = history.filter(p => now - p.t < 24 * 3600 * 1000);
        const last = h[h.length - 1];
        // Pas deux points en moins de 4 min (redémarrages du shell)
        if (last && now - last.t < 4 * 60 * 1000)
            h[h.length - 1] = { t: last.t, p: Math.round(pct * 100), c: charging || !UPower.onBattery };
        else
            h.push({ t: now, p: Math.round(pct * 100), c: charging || !UPower.onBattery });
        history = h;
        save();
    }

    function checkSaver(): void {
        if (!present || !PowerProfiles)
            return;
        const low = UPower.onBattery && pct < 0.2;
        if (autoSaver && low && !saverOn && PowerProfiles.profile !== PowerProfile.PowerSaver) {
            profileBefore = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
            saverOn = true;
            save();
        } else if (saverOn && (!UPower.onBattery || pct >= 0.25 || !autoSaver)) {
            if (PowerProfiles.profile === PowerProfile.PowerSaver)
                PowerProfiles.profile = profileBefore;
            saverOn = false;
            save();
        }
    }

    onPctChanged: checkSaver()
    Connections {
        target: UPower

        function onOnBatteryChanged(): void {
            root.checkSaver();
            root.record();
        }
    }

    Timer {
        running: root.present
        interval: 5 * 60 * 1000
        repeat: true
        onTriggered: root.record()
    }

    // Watts, santé, cycles
    Process {
        id: sysProc

        command: ["sh", "-c", 'b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1); [ -n "$b" ] || exit 1; r() { cat "$b/$1" 2>/dev/null || echo 0; }; echo "$(r power_now) $(r current_now) $(r voltage_now) $(r energy_full) $(r energy_full_design) $(r charge_full) $(r charge_full_design) $(r cycle_count)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number);
                if (v.length < 8)
                    return;
                const [pw, cur, volt, ef, efd, cf, cfd, cyc] = v;
                root.watts = pw > 0 ? pw / 1e6 : cur * volt / 1e12;
                root.health = efd > 0 ? ef / efd : cfd > 0 ? cf / cfd : -1;
                root.cycles = cyc;
            }
        }
    }
    Timer {
        running: root.present
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: sysProc.running = true
    }

    // Apps qui consomment : temps processeur sur 2 s, regroupé par app (unité systemd app-*)
    Process {
        id: topProc

        command: ["python3", "-c", `
import os, time, json, re
def snap():
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            st = open(f"/proc/{pid}/stat").read()
            comm = st[st.index("(") + 1:st.rindex(")")]
            f = st[st.rindex(")") + 2:].split()
            ticks = int(f[11]) + int(f[12])
            cg = open(f"/proc/{pid}/cgroup").read()
        except Exception:
            continue
        if int(pid) == os.getpid():
            continue  # la mesure elle-même
        if comm.startswith("python"):
            # Scripts : on regarde lequel (les outils Caelestia comptent pour Caelestia)
            try:
                args = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\\0")
                script = next((os.path.basename(a.decode()) for a in args[1:] if a and not a.startswith(b"-")), comm)
            except Exception:
                script = comm
            comm = "quickshell" if script.startswith("caelestia") or script.startswith("island-") else script
        m = re.search(r"/(app-[^/]*?)\\.(scope|service)$", cg.strip())
        if m:
            key = re.sub(r"^app-(?:[Hh]yprland-)?", "", m.group(1))
            key = re.sub(r"(@[^.]*)?$", "", key)
            key = re.sub(r"-\\d+$", "", key)
        elif "session" in cg or "user@" in cg:
            key = comm
        else:
            continue
        out[pid] = (key, ticks)
    return out
a = snap(); t0 = time.time(); time.sleep(2); b = snap(); dt = time.time() - t0
hz = os.sysconf("SC_CLK_TCK"); ncpu = os.cpu_count() or 1
use = {}
for pid, (key, ticks) in b.items():
    prev = a.get(pid, (key, ticks))[1]
    use[key] = use.get(key, 0) + max(0, ticks - prev) / hz / dt / ncpu * 100
top = sorted(((k, round(v, 1)) for k, v in use.items() if v >= 0.3), key=lambda x: -x[1])[:8]
print(json.dumps([{"key": k, "cpu": v} for k, v in top]))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.consumers = JSON.parse(text);
                } catch (e) {}
            }
        }
    }
    Timer {
        running: root.consumersRefs > 0
        interval: 4000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!topProc.running) topProc.running = true
    }

    FileView {
        id: stateView

        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.autoSaver = d.autoSaver ?? true;
                root.saverOn = !!d.saverOn;
                root.profileBefore = d.profileBefore ?? PowerProfile.Balanced;
                root.history = d.history ?? [];
            } catch (e) {}
            root.record();
            root.checkSaver();
        }
        onLoadFailed: {
            root.record();
            root.checkSaver();
        }
    }
}

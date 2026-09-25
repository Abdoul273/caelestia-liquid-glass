pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

Singleton {
    id: root

    property bool ignoreClosed
    property bool lidClosed
    property bool hasLid
    property bool ready

    readonly property bool shouldBlockSleep: ignoreClosed && lidClosed

    function save(): void {
        storage.setText(JSON.stringify({
            ignoreLidSwitch: root.ignoreClosed
        }, null, 2) + "\n");
    }

    function isSleepAction(action: var): bool {
        const parts = [];
        if (typeof action === "string") {
            parts.push(action);
        } else if (action && typeof action === "object") {
            const len = action.length;
            if (typeof len === "number") {
                for (let i = 0; i < len; i++)
                    parts.push(String(action[i]));
            } else {
                parts.push(String(action));
            }
        } else {
            return false;
        }

        const joined = parts.join(" ").toLowerCase();
        if (joined.includes("dpms"))
            return false;

        return ["suspend", "hibernate", "hybrid-sleep", "suspendthenhibernate", "poweroff", "shutdown"].some(token => joined.includes(token));
    }

    onIgnoreClosedChanged: {
        if (!ready)
            return;

        save();

        if (ignoreClosed)
            Toaster.toast(qsTr("Capot ignoré"), qsTr("Le PC reste allumé si vous fermez le capot"), "laptop");
        else
            Toaster.toast(qsTr("Veille au capot rétablie"), qsTr("Fermer le capot peut mettre le PC en veille"), "bedtime");
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.config}/power.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (typeof data.ignoreLidSwitch === "boolean")
                    root.ignoreClosed = data.ignoreLidSwitch;
            } catch (error) {
                console.warn("Unable to parse power.json:", error);
            }
            Qt.callLater(() => root.ready = true);
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("{}\n"));
            Qt.callLater(() => root.ready = true);
        }
    }

    Process {
        running: root.ignoreClosed
        command: ["systemd-inhibit", "--what=handle-lid-switch", "--who=Caelestia", "--why=Rester allume capot ferme", "--mode=block", "sleep", "infinity"]
    }

    Process {
        id: lidProc

        command: ["sh", "-c", "cat /proc/acpi/button/lid/*/state 2>/dev/null; echo; busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text;
                root.hasLid = t.includes("state:") || t.includes("b true") || t.includes("b false");
                if (t.includes("closed") || t.includes("b true"))
                    root.lidClosed = true;
                else if (t.includes("open") || t.includes("b false"))
                    root.lidClosed = false;
            }
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: lidProc.running = true
    }

    IpcHandler {
        function isEnabled(): bool {
            return root.ignoreClosed;
        }

        function toggle(): void {
            root.ignoreClosed = !root.ignoreClosed;
        }

        function enable(): void {
            root.ignoreClosed = true;
        }

        function disable(): void {
            root.ignoreClosed = false;
        }

        target: "lidSwitch"
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property alias enabled: props.enabled
    readonly property alias enabledSince: props.enabledSince
    // Fin prévue en ms (0 = sans limite)
    readonly property alias until: props.until
    property real now: Date.now()
    readonly property real remaining: enabled && until > 0 ? Math.max(0, until - now) : 0

    onEnabledChanged: {
        if (enabled && !restoring)
            props.enabledSince = new Date();
        else if (!enabled)
            props.until = 0;
        save();
    }

    // L'état survit aux redémarrages du shell (Super+Maj+R, nouvelle session…) :
    // ~/.local/state/caelestia/caffeine.json, relu au démarrage (une durée écoulée entre-temps est terminée)
    property bool restoring
    property bool restored

    function save(): void {
        if (!restored)
            return;
        stateFile.setText(JSON.stringify({
            enabled: props.enabled,
            until: props.until,
            since: props.enabledSince.getTime()
        }));
    }

    FileView {
        id: stateFile

        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/caelestia/caffeine.json`
        printErrors: false
        onLoaded: {
            try {
                const st = JSON.parse(text());
                if (st.enabled && !(st.until > 0 && st.until <= Date.now())) {
                    root.restoring = true;
                    props.until = st.until || 0;
                    props.enabledSince = new Date(st.since || Date.now());
                    props.enabled = true;
                    root.restoring = false;
                }
            } catch (e) {}
            root.restored = true;
        }
        onLoadFailed: root.restored = true
    }

    // Active pour une durée (minutes ; 0 = sans limite)
    function enableFor(minutes: int): void {
        props.until = minutes > 0 ? Date.now() + minutes * 60000 : 0;
        now = Date.now();
        props.enabled = true;
        save();
    }

    // Prolonge la durée en cours (ou l'active pour cette durée)
    function extend(minutes: int): void {
        if (!enabled || until <= 0) {
            enableFor(minutes);
            return;
        }
        props.until = Math.max(until, Date.now()) + minutes * 60000;
        now = Date.now();
        save();
    }

    function remainingText(): string {
        if (!enabled)
            return "";
        if (until <= 0)
            return qsTr("Sans limite");
        const min = Math.ceil(remaining / 60000);
        return min >= 60 ? qsTr("%1 h %2").arg(Math.floor(min / 60)).arg((min % 60).toString().padStart(2, "0")) : qsTr("%1 min").arg(min);
    }

    Timer {
        running: props.enabled && props.until > 0
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now();
            if (root.now >= props.until)
                props.enabled = false;
        }
    }

    PersistentProperties {
        id: props

        property bool enabled
        property date enabledSince
        property real until

        reloadableId: "idleInhibitor"
    }

    IdleInhibitor {
        enabled: props.enabled
        window: PanelWindow {
            // 1 px transparent : une surface 0×0 n'est jamais affichée, et Hyprland ignore alors l'inhibiteur
            implicitWidth: 1
            implicitHeight: 1
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "caelestia-idleinhibitor"
            anchors.top: true
            anchors.left: true
            color: "transparent"
            mask: Region {}
        }
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        target: "idleInhibitor"
    }
}

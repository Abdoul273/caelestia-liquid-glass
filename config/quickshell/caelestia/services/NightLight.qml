pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Éclairage de nuit : réchauffe l'écran (Centre de contrôle → Écran).
// Sans rien installer : filtre d'écran de Hyprland (decoration:screen_shader).
// Si hyprsunset est installé, c'est lui qui est utilisé (réglage matériel, captures non teintées).
// Transition douce à l'allumage / l'extinction, programmation horaire facultative.
Singleton {
    id: root

    property bool enabled
    property int temperature: 4000 // 2500 (très chaud) … 6000 (léger)
    property bool scheduled // allumage / extinction automatiques
    property string from: "20:00"
    property string to: "07:00"
    property bool loaded

    readonly property int minTemp: 2500
    readonly property int maxTemp: 6000
    readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/caelestia/nightlight.json`
    readonly property string shaderDir: `${Quickshell.env("HOME")}/.config/caelestia/shaders`
    property bool hasHyprsunset

    // Température affichée à l'écran, animée vers la cible (6500 K = neutre)
    readonly property real target: enabled ? temperature : 6500
    property real shown: 6500
    property real applied: -1 // -1 : premier passage, remet l'écran dans le bon état
    property int flip // alterne deux fichiers : Hyprland recharge le filtre à chaque changement

    Behavior on shown {
        enabled: root.loaded
        NumberAnimation {
            duration: 1600
            easing.type: Easing.InOutSine
        }
    }
    onTargetChanged: shown = target

    function toggle(): void {
        enabled = !enabled;
        save();
    }

    function setTemperature(k: int): void {
        temperature = Math.round(Math.max(minTemp, Math.min(maxTemp, k)) / 50) * 50;
        save();
    }

    function setSchedule(on: bool): void {
        scheduled = on;
        if (on)
            enabled = inWindow();
        save();
    }

    function inWindow(): bool {
        const d = new Date();
        const now = d.getHours() * 60 + d.getMinutes();
        const [fh, fm] = from.split(":").map(Number);
        const [th, tm] = to.split(":").map(Number);
        const a = fh * 60 + fm, b = th * 60 + tm;
        return a <= b ? now >= a && now < b : now >= a || now < b;
    }

    // Couleur d'une température (approximation de Tanner Helland), relative au blanc 6500 K
    function rgbOf(k: real): list<real> {
        const t = k / 100;
        const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
        const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
        const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
        return [r, g, b].map(v => Math.max(0, Math.min(255, v)) / 255);
    }

    function tintOf(k: real): list<real> {
        const c = rgbOf(k), w = rgbOf(6500);
        return c.map((v, i) => Math.min(1, v / w[i]));
    }

    function save(): void {
        if (!loaded)
            return;
        stateView.setText(JSON.stringify({
            enabled: enabled,
            temperature: temperature,
            scheduled: scheduled,
            from: from,
            to: to
        }));
    }

    function apply(k: real): void {
        applied = k;
        if (hasHyprsunset)
            return; // géré par le processus hyprsunset
        if (k >= 6450) {
            applyProc.command = ["hyprctl", "eval", "hl.config({ decoration = { screen_shader = '' } })"];
        } else {
            const c = tintOf(k).map(v => v.toFixed(4));
            flip = 1 - flip;
            const file = `${shaderDir}/nightlight-${flip ? "b" : "a"}.frag`;
            const src = `#version 300 es
// Éclairage de nuit (Caelestia) — généré par services/NightLight.qml, ne pas modifier
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() {
    vec4 c = texture(tex, v_texcoord);
    fragColor = vec4(c.rgb * vec3(${c[0]}, ${c[1]}, ${c[2]}), c.a);
}
`;
            applyProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && printf "%s" "$1" > "$2" && exec hyprctl eval "hl.config({ decoration = { screen_shader = \'$2\' } })"', "sh", src, file];
        }
        applyProc.running = true;
    }

    Process {
        id: applyProc
    }

    // Pendant la transition, on met à jour le filtre ~10 fois par seconde (pas à chaque image)
    Timer {
        running: root.loaded && !root.hasHyprsunset && Math.abs(root.applied - root.shown) > 3
        interval: 100
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!applyProc.running)
                root.apply(Math.abs(root.shown - root.target) < 20 ? root.target : root.shown);
        }
    }

    // hyprsunset (si installé)
    Process {
        running: root.loaded && root.hasHyprsunset && root.enabled
        command: ["hyprsunset", "-t", String(root.temperature)]
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: code => {
            root.hasHyprsunset = code === 0;
            // Le filtre de secours ne doit pas rester par-dessus hyprsunset
            if (root.hasHyprsunset)
                Quickshell.execDetached(["hyprctl", "eval", "hl.config({ decoration = { screen_shader = '' } })"]);
        }
    }

    // Programmation : bascule au passage des heures choisies (on peut toujours forcer entre-temps)
    property bool lastWindow
    Timer {
        running: root.loaded && root.scheduled
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const w = root.inWindow();
            if (w !== root.lastWindow) {
                root.lastWindow = w;
                root.enabled = w;
                root.save();
            }
        }
    }

    FileView {
        id: stateView

        path: root.stateFile
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.temperature = d.temperature ?? 4000;
                root.scheduled = !!d.scheduled;
                root.from = d.from ?? "20:00";
                root.to = d.to ?? "07:00";
                root.enabled = root.scheduled ? root.inWindow() : !!d.enabled;
            } catch (e) {}
            root.lastWindow = root.inWindow();
            root.loaded = true;
            root.shown = root.target;
        }
        onLoadFailed: {
            root.lastWindow = root.inWindow();
            root.loaded = true;
            root.shown = root.target;
        }
    }
}

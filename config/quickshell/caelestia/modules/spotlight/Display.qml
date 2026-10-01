pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.components.effects
import qs.services

// Projection (Super + P) dans le même verre que l'île : une goutte tombe de l'île et
// montre les 4 modes d'affichage en une rangée (Écran du PC, Dupliquer, Étendre,
// Deuxième écran). En mode Étendre, le verre grandit pour choisir la position.
// Les réglages passent par `caelestia-display-pro --status / --mode / --position` ;
// « Plus d'options » ouvre l'ancienne fenêtre (résolution, échelle).
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.display ?? false

    // ── Ouverture : le verre part de l'île et tombe jusqu'à sa place ──
    property real morph: shown ? 1 : 0
    readonly property real offsetScale: 1 - morph
    property real fromX
    property real fromW: 200
    property real fromBottom: 38
    property real fromR: 19
    readonly property real fromTop: -70
    readonly property real hMorph: Math.min(1, morph)
    readonly property real curX: fromX + (x - fromX) * hMorph
    readonly property real curW: fromW + (width - fromW) * hMorph
    readonly property real curTop: fromTop + (y - fromTop) * morph
    readonly property real curBottom: fromBottom + (y + height - fromBottom) * morph
    readonly property real curR: fromR + (30 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Couleurs ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.55)
    readonly property color fgFaint: Qt.alpha(fg, 0.1)
    readonly property color accent: Colours.palette.m3primary
    readonly property string glyphFont: "JetBrainsMono Nerd Font"
    readonly property string tool: `${Quickshell.env("HOME")}/.local/bin/caelestia-display-pro`

    // ── État ──
    readonly property var modes: [
        {
            key: "internal",
            title: qsTr("Écran du PC"),
            sub: qsTr("Le portable seul")
        },
        {
            key: "duplicate",
            title: qsTr("Dupliquer"),
            sub: qsTr("La même image")
        },
        {
            key: "extend",
            title: qsTr("Étendre"),
            sub: qsTr("Un bureau plus large")
        },
        {
            key: "external",
            title: qsTr("Deuxième écran"),
            sub: qsTr("L'externe seul")
        }
    ]
    readonly property var positions: [
        {
            key: "left",
            glyph: "󰁍",
            title: qsTr("À gauche")
        },
        {
            key: "up",
            glyph: "󰁝",
            title: qsTr("Au-dessus")
        },
        {
            key: "down",
            glyph: "󰁅",
            title: qsTr("En dessous")
        },
        {
            key: "right",
            glyph: "󰁔",
            title: qsTr("À droite")
        }
    ]
    property string mode: "internal"
    property string position: "right"
    property var externals: []
    property int sel: 0
    property bool busy: false
    property string hint: ""
    readonly property bool connected: externals.length > 0

    function close(): void {
        screenState.display = false;
    }

    function refresh(): void {
        status.running = true;
    }

    function apply(key: string): void {
        if (busy || (key !== "internal" && !connected)) {
            if (!connected && key !== "internal")
                showHint(qsTr("Branche un écran HDMI ou DisplayPort d'abord"));
            return;
        }
        busy = true;
        mode = key;
        applier.command = [tool, "--mode", key];
        applier.running = true;
    }

    function place(key: string): void {
        if (busy || !connected)
            return;
        busy = true;
        position = key;
        applier.command = [tool, "--position", key];
        applier.running = true;
    }

    function showHint(text: string): void {
        hint = text;
        hintTimer.restart();
    }

    visible: morph > 0.001
    implicitWidth: 660
    implicitHeight: 64 + 136 + (mode === "extend" && connected ? 56 : 0) + 38

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 360
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }
    }

    Behavior on morph {
        NumberAnimation {
            duration: root.shown ? 620 : 380
            easing.type: root.shown ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 0.8
        }
    }

    onShownChanged: {
        if (shown) {
            if (island && island.h > 1) {
                fromX = island.x;
                fromW = island.w;
                fromBottom = island.y + island.h;
                fromR = island.radius;
            } else {
                fromX = island ? island.x + island.width / 2 - 100 : x;
                fromW = 200;
                fromBottom = island ? island.y + 38 : 38;
                fromR = 19;
            }
            hint = "";
            refresh();
            content.forceActiveFocus();
        }
    }

    Timer {
        id: hintTimer

        interval: 3000
        onTriggered: root.hint = ""
    }

    // Écran branché ou débranché pendant que le panneau est ouvert
    Timer {
        interval: 2500
        repeat: true
        running: root.shown && !root.busy
        onTriggered: root.refresh()
    }

    Process {
        id: status

        command: [root.tool, "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.externals = s.externals ?? [];
                    if (!root.busy) {
                        root.mode = s.mode ?? "internal";
                        root.position = s.position ?? "right";
                        root.sel = Math.max(0, root.modes.findIndex(m => m.key === root.mode));
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: applier

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.showHint(r.ok ? "✓ " + r.message : r.message);
                } catch (e) {}
                root.busy = false;
                root.refresh();
            }
        }
    }

    // Le contenu suit la forme du verre qui tombe de l'île
    Item {
        id: clipper

        x: root.curX - root.x
        y: root.curTop - root.y
        width: Math.max(0, root.curW)
        height: Math.max(0, root.curBottom - root.curTop)
        clip: true

        FocusScope {
            id: content

            x: -clipper.x
            y: -clipper.y
            width: root.width
            height: root.height
            focus: root.shown
            opacity: root.reveal
            scale: 0.94 + 0.06 * root.reveal
            transformOrigin: Item.Top

            Keys.onPressed: event => {
                const k = event.key;
                if (k === Qt.Key_Escape)
                    root.close();
                else if (k >= Qt.Key_1 && k <= Qt.Key_4)
                    root.apply(root.modes[k - Qt.Key_1].key);
                else if (k === Qt.Key_Right || k === Qt.Key_Tab)
                    root.sel = (root.sel + 1) % 4;
                else if (k === Qt.Key_Left || k === Qt.Key_Backtab)
                    root.sel = (root.sel + 3) % 4;
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
                    root.apply(root.modes[root.sel].key);
                else
                    return;
                event.accepted = true;
            }

            // ── En-tête ──
            Item {
                id: head

                x: 22
                width: parent.width - 44
                height: 64

                Rectangle {
                    id: logo

                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: 10
                    color: Qt.alpha(root.accent, 0.18)

                    Text {
                        anchors.centerIn: parent
                        text: "󰍹"
                        font.family: root.glyphFont
                        font.pixelSize: 19
                        color: root.accent
                    }
                }

                Column {
                    anchors.left: logo.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        text: qsTr("Projection")
                        color: root.fg
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.connected ? qsTr("Écran externe : ") + root.externals.map(e => e.title).join(", ") : qsTr("Aucun écran externe branché")
                        color: root.connected ? root.accent : root.fgDim
                        font.pixelSize: 12
                    }
                }

                GlassButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: moreLbl.implicitWidth + 24
                    height: 30
                    tint: Qt.alpha(root.fg, 0.08)
                    onClicked: {
                        Quickshell.execDetached([root.tool]);
                        root.close();
                    }

                    Text {
                        id: moreLbl

                        anchors.centerIn: parent
                        text: qsTr("Plus d'options")
                        color: root.fgDim
                        font.pixelSize: 12
                    }

                }
            }

            // ── Les 4 modes ──
            Row {
                id: tiles

                anchors.top: head.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Repeater {
                    model: root.modes

                    GlassButton {
                        id: tile

                        required property var modelData
                        required property int index
                        readonly property bool active: root.mode === modelData.key
                        readonly property bool focused: root.sel === index
                        readonly property bool usable: modelData.key === "internal" || root.connected

                        width: 147
                        height: 128
                        radius: 22
                        tint: active ? Qt.alpha(root.accent, Colours.light ? 0.28 : 0.32) : Qt.alpha(root.fg, focused ? 0.11 : 0.06)
                        enabled: usable
                        cursorShape: usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: root.sel = tile.index
                        onClicked: root.apply(tile.modelData.key)

                        // Liseré de focus clavier
                        Rectangle {
                            anchors.fill: parent
                            radius: 22
                            color: "transparent"
                            border.width: 2
                            border.color: tile.active ? Qt.alpha(root.accent, 0.75) : Qt.alpha(root.fg, 0.3)
                            visible: tile.focused || tile.active
                        }

                        // Petite illustration : portable à gauche, écran externe à droite
                        Item {
                            id: art

                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 18
                            width: 96
                            height: 44

                            readonly property bool pcOn: tile.modelData.key !== "external"
                            readonly property bool extOn: tile.modelData.key !== "internal"
                            readonly property color onCol: tile.active ? root.accent : Qt.alpha(root.fg, 0.75)
                            readonly property real gapX: tile.modelData.key === "extend" ? 0 : 8

                            // Portable
                            Rectangle {
                                id: pc

                                x: (art.width - (pc.width + art.gapX + ext.width)) / 2
                                y: 12
                                width: 38
                                height: 26
                                radius: 4
                                color: art.pcOn ? Qt.alpha(art.onCol, 0.35) : "transparent"
                                border.width: 2
                                border.color: art.pcOn ? art.onCol : Qt.alpha(root.fg, 0.25)

                                Text {
                                    anchors.centerIn: parent
                                    visible: tile.modelData.key === "duplicate"
                                    text: "1"
                                    color: art.onCol
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }
                            Rectangle {
                                anchors.horizontalCenter: pc.horizontalCenter
                                anchors.top: pc.bottom
                                anchors.topMargin: 1
                                width: pc.width + 8
                                height: 3
                                radius: 1.5
                                color: art.pcOn ? art.onCol : Qt.alpha(root.fg, 0.25)
                            }

                            // Écran externe
                            Rectangle {
                                id: ext

                                x: pc.x + pc.width + art.gapX
                                y: 4
                                width: 46
                                height: 32
                                radius: 4
                                color: art.extOn ? Qt.alpha(art.onCol, 0.35) : "transparent"
                                border.width: 2
                                border.color: art.extOn ? art.onCol : Qt.alpha(root.fg, 0.25)

                                Text {
                                    anchors.centerIn: parent
                                    visible: tile.modelData.key === "duplicate"
                                    text: "1"
                                    color: art.onCol
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }
                            Rectangle {
                                anchors.horizontalCenter: ext.horizontalCenter
                                anchors.top: ext.bottom
                                width: 4
                                height: 4
                                color: art.extOn ? art.onCol : Qt.alpha(root.fg, 0.25)
                            }
                        }

                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 14
                            spacing: 1

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.title
                                color: tile.active ? root.accent : root.fg
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (tile.index + 1) + "  ·  " + tile.modelData.sub
                                color: root.fgDim
                                font.pixelSize: 11
                            }
                        }

                    }
                }
            }

            // ── Position de l'écran externe (mode Étendre) ──
            Row {
                anchors.top: tiles.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                opacity: root.mode === "extend" && root.connected ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Repeater {
                    model: root.positions

                    GlassButton {
                        id: pos

                        required property var modelData
                        readonly property bool active: root.position === modelData.key

                        width: 147
                        height: 40
                        tint: active ? Qt.alpha(root.accent, 0.32) : Qt.alpha(root.fg, 0.06)
                        onClicked: root.place(pos.modelData.key)

                        Text {
                            anchors.centerIn: parent
                            text: pos.modelData.glyph + "  " + pos.modelData.title
                            color: pos.active ? root.accent : root.fg
                            font.family: root.glyphFont
                            font.pixelSize: 13
                        }

                    }
                }
            }

            // ── Ligne d'aide / résultat ──
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.busy ? qsTr("Application…") : root.hint || qsTr("1–4 ou ←/→ puis Entrée  ·  Échap : fermer")
                color: root.hint.startsWith("✓") ? root.accent : Qt.alpha(root.fg, 0.45)
                font.pixelSize: 12
            }
        }
    }
}

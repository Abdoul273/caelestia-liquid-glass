pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Dictée façon macOS (Super + Maj + D) : on se place dans un champ, la goutte tombe
// de l'île, on parle et le texte s'affiche en direct ; à la fermeture (Entrée, même
// raccourci, clic ailleurs) il est tapé dans le champ d'origine. Échap annule.
// Micro + reconnaissance (Gemini Transcribe) + insertion : `caelestia-dictate`.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.dictation ?? false

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
    readonly property real curR: fromR + (barH / 2 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Couleurs ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.55)
    readonly property color red: "#ff453a"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── État de la dictée ──
    readonly property real barH: 64
    property string phase: "connexion"
    property string detail: ""
    property string transcript: ""
    property real level: 0
    property var levels: [0, 0, 0, 0, 0, 0, 0]
    property bool cancelled
    property bool closedByBackend
    property bool pendingStart

    function close(): void {
        screenState.dictation = false;
    }

    function cancel(): void {
        cancelled = true;
        close();
    }

    function begin(): void {
        phase = "connexion";
        detail = "";
        transcript = "";
        level = 0;
        cancelled = false;
        closedByBackend = false;
        if (backend.running)
            pendingStart = true; // la dictée précédente finit son insertion
        else
            backend.running = true;
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!shown || pendingStart)
            return;
        if (msg.stage === "level") {
            level = msg.v;
            levels = levels.slice(1).concat([msg.v]);
        } else if (msg.stage === "text") {
            transcript = msg.text;
        } else if (msg.stage === "state") {
            phase = msg.state;
            detail = msg.detail ?? "";
        } else if (msg.stage === "done") {
            // Erreur sans texte : la goutte reste ouverte pour l'afficher
            if (phase !== "erreur" || msg.text) {
                closedByBackend = true;
                close();
            }
        }
    }

    visible: morph > 0.001
    implicitWidth: 640
    implicitHeight: Math.max(barH, textBox.contentHeight + 40)

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 300
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
            begin();
            content.forceActiveFocus();
        } else if (!closedByBackend && backend.running && !pendingStart) {
            // Fermée par Entrée, le raccourci ou un clic ailleurs : on insère (ou on annule)
            backend.send(cancelled ? {
                cancel: true
            } : {
                stop: true
            });
        }
    }

    Process {
        id: backend

        function send(msg: var): void {
            if (running)
                write(JSON.stringify(msg) + "\n");
        }

        command: [`${Quickshell.env("HOME")}/.local/bin/caelestia-dictate`]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        onExited: {
            if (root.pendingStart) {
                root.pendingStart = false;
                if (root.shown)
                    running = true;
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
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.cancel();
                    event.accepted = true;
                }
            }

            // ── Micro qui pulse avec la voix ──
            Item {
                id: mic

                x: 14
                y: (root.barH - height) / 2
                width: 40
                height: 40

                Rectangle {
                    anchors.centerIn: parent
                    width: 40 * (1 + root.level * 0.5)
                    height: width
                    radius: width / 2
                    color: Qt.alpha(root.red, 0.22)
                    visible: root.phase === "parole" || root.phase === "ecoute"

                    Behavior on width {
                        NumberAnimation {
                            duration: 90
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    radius: 17
                    color: root.phase === "erreur" ? Qt.alpha(root.fg, 0.15) : root.phase === "connexion" || root.phase === "fin" ? Qt.alpha(root.fg, 0.25) : root.red

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.phase === "erreur" ? "󰍭" : "󰍬"
                        font.family: root.glyphFont
                        font.pixelSize: 19
                        color: "white"
                    }
                }
            }

            // ── Texte dicté, en direct ──
            Text {
                id: textBox

                anchors.left: mic.right
                anchors.leftMargin: 14
                anchors.right: wave.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "erreur" ? qsTr("Dictée indisponible : %1").arg(root.detail || qsTr("erreur inconnue")) : root.transcript || (root.phase === "connexion" ? qsTr("Connexion…") : qsTr("Parlez, je vous écoute…"))
                color: root.phase === "erreur" ? root.red : root.transcript ? root.fg : Qt.alpha(root.fg, 0.4)
                wrapMode: Text.Wrap
                maximumLineCount: 5
                elide: Text.ElideLeft
                font.pixelSize: 19
                font.weight: Font.Light
            }

            // ── Onde du micro ──
            Row {
                id: wave

                anchors.right: parent.right
                anchors.rightMargin: 22
                y: (root.barH - height) / 2
                height: 28
                spacing: 3

                Repeater {
                    model: root.levels

                    Rectangle {
                        required property real modelData

                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: Math.max(4, 28 * Math.min(1, modelData * 1.6))
                        radius: 1.5
                        color: root.phase === "parole" ? root.red : Qt.alpha(root.fg, 0.35)

                        Behavior on height {
                            NumberAnimation {
                                duration: 90
                            }
                        }
                    }
                }
            }
        }
    }
}

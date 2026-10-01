pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Calculatrice façon Spotlight de macOS (Super + O), dans le même verre que l'île :
// au départ une seule ligne de saisie ; dès qu'un calcul donne un résultat, le verre
// grandit vers le bas et affiche le résultat en grand, comme la carte Calculatrice de macOS.
// Entrée copie le résultat ; ↑ reprend les calculs précédents.
// Les calculs passent par `caelestia-spotlight serve` (format français, % façon macOS,
// trigo en degrés, conversions d'unités).
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.calculator ?? false

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
    readonly property color fgFaint: Qt.alpha(fg, 0.1)
    readonly property color orange: "#ff9f0a"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── État du calcul ──
    readonly property real barH: 60
    readonly property real cardH: 132
    property string result: ""
    property string shownExpr: ""
    property int seq: 0
    property var history: []
    property int histIndex: -1
    property string hint: ""
    readonly property bool hasResult: result !== "" && input.text.trim() !== ""

    function close(): void {
        screenState.calculator = false;
    }

    function evaluate(): void {
        seq += 1;
        if (!input.text.trim()) {
            result = "";
            return;
        }
        backend.send({
            calc: input.text,
            seq: seq
        });
    }

    function commit(): void {
        const expr = input.text.trim();
        if (!hasResult) {
            showHint(qsTr("Calcul incomplet"));
            return;
        }
        backend.send({
            commit: expr,
            result: result
        });
        showHint(qsTr("Copié dans le presse-papiers ✓"));
        bump.restart();
        histIndex = -1;
    }

    function showHint(text: string): void {
        hint = text;
        hintTimer.restart();
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.stage === "calc") {
            // Un calcul incomplet garde le dernier résultat affiché
            if (msg.seq === seq && msg.result !== null) {
                result = msg.result;
                shownExpr = input.text.trim();
            }
        } else if (msg.stage === "history") {
            history = msg.items;
        }
    }

    function recall(step: int): void {
        if (history.length === 0)
            return;
        histIndex = Math.max(-1, Math.min(history.length - 1, histIndex + step));
        input.text = histIndex < 0 ? "" : history[histIndex][0];
        input.cursorPosition = input.text.length;
    }

    visible: morph > 0.001
    implicitWidth: 700
    implicitHeight: barH + (hasResult ? cardH : 0)

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
            backend.running = true;
            backend.send({
                history: true
            });
            histIndex = -1;
            input.text = "";
            result = "";
            input.forceActiveFocus();
        }
    }

    Timer {
        id: hintTimer

        interval: 1600
        onTriggered: root.hint = ""
    }

    Process {
        id: backend

        function send(msg: var): void {
            if (running)
                write(JSON.stringify(msg) + "\n");
        }

        command: [`${Quickshell.env("HOME")}/.local/bin/caelestia-spotlight`, "serve"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        onStarted: send({
            history: true
        })
        onExited: if (root.shown)
            running = true
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

            // ── Ligne de saisie ──
            Item {
                id: bar

                width: parent.width
                height: root.barH

                Text {
                    id: icon

                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰃬"
                    font.family: root.glyphFont
                    font.pixelSize: 24
                    color: root.fgDim
                }

                TextInput {
                    id: input

                    anchors.left: icon.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    color: root.fg
                    selectionColor: Qt.alpha(root.orange, 0.35)
                    selectedTextColor: root.fg
                    font.pixelSize: 23
                    font.weight: Font.Light
                    clip: true
                    onTextChanged: root.evaluate()

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.commit();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            root.recall(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            root.recall(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (text)
                                text = "";
                            else
                                root.close();
                            event.accepted = true;
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: qsTr("Calcul ou conversion…  (↑ pour l'historique)")
                        color: Qt.alpha(root.fg, 0.38)
                        font: input.font
                    }
                }
            }

            Rectangle {
                anchors.top: bar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                height: 1
                color: root.fgFaint
                opacity: root.hasResult ? 1 : 0
            }

            // ── Carte du résultat, façon Spotlight de macOS ──
            Item {
                id: card

                anchors.top: bar.bottom
                width: parent.width
                height: root.cardH
                opacity: root.hasResult ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                    }
                }

                // Icône de l'app Calculatrice
                Rectangle {
                    id: appIcon

                    x: 26
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    height: 64
                    radius: 16
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: "#ffb340"
                        }
                        GradientStop {
                            position: 1
                            color: "#ff8a00"
                        }
                    }
                    border.width: 1
                    border.color: Qt.alpha("white", 0.3)

                    Text {
                        anchors.centerIn: parent
                        text: "󰃬"
                        font.family: root.glyphFont
                        font.pixelSize: 34
                        color: "white"
                    }
                }

                Column {
                    anchors.left: appIcon.right
                    anchors.leftMargin: 20
                    anchors.right: parent.right
                    anchors.rightMargin: 28
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.shownExpr + " ="
                        color: root.fgDim
                        elide: Text.ElideLeft
                        font.pixelSize: 15
                    }

                    Text {
                        id: big

                        width: parent.width
                        height: 54
                        text: root.result
                        color: root.fg
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 44
                        font.weight: Font.DemiBold
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 20
                        elide: Text.ElideRight

                        transform: Scale {
                            id: bumpScale

                            origin.y: big.height / 2
                        }

                        SequentialAnimation {
                            id: bump

                            NumberAnimation {
                                target: bumpScale
                                properties: "xScale,yScale"
                                to: 1.07
                                duration: 110
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: bumpScale
                                properties: "xScale,yScale"
                                to: 1
                                duration: 260
                                easing.type: Easing.OutBack
                            }
                        }
                    }

                    Text {
                        text: root.hint || qsTr("Calculatrice  ·  Entrée pour copier")
                        color: root.hint.startsWith("Calcul i") ? "#ff453a" : root.hint ? root.orange : Qt.alpha(root.fg, 0.4)
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}

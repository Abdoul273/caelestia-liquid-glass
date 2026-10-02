pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Traduction rapide (Super + Alt + T) : une ligne comme Spotlight ; la traduction
// apparaît en dessous pendant qu'on tape. Le texte sélectionné est repris à l'ouverture.
// Langue cible : Tab / Maj + Tab (Auto = français ↔ anglais). Entrée tape la traduction
// dans le champ d'origine, Ctrl + C la copie. Gemini via `caelestia-write serve`.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.translate ?? false

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
    readonly property color blue: "#0a84ff"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    readonly property var targets: [
        {
            id: "auto",
            label: qsTr("Auto")
        },
        {
            id: "anglais",
            label: qsTr("Anglais")
        },
        {
            id: "français",
            label: qsTr("Français")
        },
        {
            id: "arabe",
            label: qsTr("Arabe")
        },
        {
            id: "espagnol",
            label: qsTr("Espagnol")
        },
        {
            id: "allemand",
            label: qsTr("Allemand")
        },
        {
            id: "italien",
            label: qsTr("Italien")
        },
        {
            id: "portugais",
            label: qsTr("Portugais")
        },
        {
            id: "chinois simplifié",
            label: qsTr("Chinois")
        }
    ]

    // ── État ──
    readonly property real barH: 60
    property int target: 0
    property int seq: 0
    property string result: ""
    property string sourceLang: ""
    property bool busy
    property string error: ""
    property string winAddr: ""
    property string hint: ""
    readonly property bool hasResult: result !== "" && input.text.trim() !== ""

    function close(): void {
        screenState.translate = false;
    }

    function translate(): void {
        seq += 1;
        error = "";
        if (!input.text.trim()) {
            result = "";
            sourceLang = "";
            busy = false;
            return;
        }
        busy = true;
        backend.send({
            seq: seq,
            op: "translate",
            text: input.text,
            target: targets[target].id
        });
    }

    function setTarget(i: int): void {
        target = (i + targets.length) % targets.length;
        translate();
    }

    function apply(): void {
        if (!hasResult || busy)
            return;
        backend.send({
            insert: result,
            window: winAddr
        });
        close();
    }

    function copy(): void {
        if (!hasResult)
            return;
        backend.send({
            copy: result
        });
        hint = qsTr("Copié dans le presse-papiers ✓");
        hintTimer.restart();
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.stage === "selection") {
            winAddr = msg.window;
            // Reprendre une sélection courte, toute sélectionnée : taper la remplace
            const sel = msg.text.trim();
            if (sel && sel.length < 3000 && !input.text) {
                input.text = sel;
                input.selectAll();
            }
            return;
        }
        if (msg.seq !== seq)
            return;
        if (msg.stage === "chunk" || msg.stage === "end") {
            if (msg.text || msg.stage === "end")
                result = msg.text;
            if (msg.source)
                sourceLang = msg.source;
            if (msg.stage === "end")
                busy = false;
        } else if (msg.stage === "error") {
            error = msg.text;
            busy = false;
        }
    }

    visible: morph > 0.001
    implicitWidth: 720
    implicitHeight: barH + (input.text.trim() ? card.implicitHeight + 30 : 0)

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutBack
            easing.overshoot: 0.7
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
            input.text = "";
            result = "";
            sourceLang = "";
            error = "";
            winAddr = "";
            backend.running = true;
            backend.send({
                selection: true
            });
            input.forceActiveFocus();
        }
    }

    Timer {
        id: debounce

        interval: 450
        onTriggered: root.translate()
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

        command: [`${Quickshell.env("HOME")}/.local/bin/caelestia-write`, "serve"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        onStarted: if (root.shown)
            send({
                selection: true
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
                    text: "󰗊"
                    font.family: root.glyphFont
                    font.pixelSize: 24
                    color: root.blue
                }

                TextInput {
                    id: input

                    anchors.left: icon.right
                    anchors.leftMargin: 14
                    anchors.right: targetPill.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    color: root.fg
                    selectionColor: Qt.alpha(root.blue, 0.35)
                    selectedTextColor: root.fg
                    font.pixelSize: 21
                    font.weight: Font.Light
                    clip: true
                    onTextChanged: {
                        if (!text.trim())
                            root.translate();
                        else
                            debounce.restart();
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.apply();
                        } else if (event.key === Qt.Key_Tab) {
                            root.setTarget(root.target + 1);
                        } else if (event.key === Qt.Key_Backtab) {
                            root.setTarget(root.target - 1);
                        } else if (ctrl && event.key === Qt.Key_C && !selectedText) {
                            root.copy();
                        } else if (event.key === Qt.Key_Escape) {
                            if (text)
                                text = "";
                            else
                                root.close();
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: qsTr("Texte à traduire…")
                        color: Qt.alpha(root.fg, 0.38)
                        font: input.font
                    }
                }

                // Langue cible (Tab pour changer, clic aussi)
                Rectangle {
                    id: targetPill

                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: pillRow.implicitWidth + 22
                    height: 32
                    radius: 16
                    color: Qt.alpha(root.blue, pillMouse.containsMouse ? 0.3 : 0.18)

                    Row {
                        id: pillRow

                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "→ " + root.targets[root.target].label
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.fg
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⇥"
                            font.pixelSize: 12
                            color: root.fgDim
                        }
                    }

                    MouseArea {
                        id: pillMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: event => root.setTarget(root.target + (event.button === Qt.RightButton ? -1 : 1))
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
                opacity: input.text.trim() ? 1 : 0
            }

            // ── Traduction ──
            Column {
                id: card

                anchors.top: bar.bottom
                anchors.topMargin: 14
                x: 26
                width: parent.width - 52
                spacing: 8
                opacity: input.text.trim() ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Text {
                    text: (root.sourceLang || "…") + "  →  " + (root.targets[root.target].id === "auto" ? (root.sourceLang === "Français" ? qsTr("Anglais") : root.sourceLang ? qsTr("Français") : "…") : root.targets[root.target].label)
                    color: root.blue
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                TextEdit {
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    activeFocusOnPress: false
                    text: root.error ? qsTr("Erreur : %1").arg(root.error) : root.result || qsTr("Traduction…")
                    color: root.error ? "#ff453a" : root.result ? (root.busy ? root.fgDim : root.fg) : Qt.alpha(root.fg, 0.35)
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: root.result.length > 220 ? 17 : 24
                    font.weight: Font.Normal
                    selectionColor: Qt.alpha(root.blue, 0.35)

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                Text {
                    text: root.hint || qsTr("Entrée insérer dans le champ  ·  Ctrl + C copier  ·  Tab langue  ·  Échap effacer / fermer")
                    color: root.hint ? root.blue : Qt.alpha(root.fg, 0.4)
                    font.pixelSize: 12
                }
            }
        }
    }
}

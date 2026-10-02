pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Outils d'écriture façon Apple Intelligence (Super + Maj + W) : on sélectionne du
// texte n'importe où, la goutte tombe de l'île avec la sélection, on choisit une action
// (corriger, reformuler, ton pro…) ou on décrit la modification ; le résultat arrive en
// direct et Entrée remplace la sélection dans l'appli d'origine.
// Gemini via `caelestia-write serve` (sélection = presse-papiers primaire).
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.writing ?? false

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
    readonly property color accent: "#bf5af2"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    readonly property var actions: [
        {
            id: "corriger",
            label: qsTr("Corriger"),
            icon: "󰓆"
        },
        {
            id: "reformuler",
            label: qsTr("Reformuler"),
            icon: "󰑐"
        },
        {
            id: "pro",
            label: qsTr("Professionnel"),
            icon: "󰃖"
        },
        {
            id: "amical",
            label: qsTr("Amical"),
            icon: "󰱱"
        },
        {
            id: "concis",
            label: qsTr("Concis"),
            icon: "󰘕"
        },
        {
            id: "resumer",
            label: qsTr("Résumer"),
            icon: "󰦨"
        },
        {
            id: "points",
            label: qsTr("Points clés"),
            icon: "󰉹"
        },
        {
            id: "traduire",
            label: qsTr("En anglais"),
            icon: "󰗊"
        }
    ]

    // ── État ──
    property string source: ""
    property string winAddr: ""
    property bool manual // pas de sélection : le texte est tapé/collé dans la goutte
    property int selected: 0
    property int seq: 0
    property string result: ""
    property bool busy
    property string error: ""
    property string lastAsk: "" // dernière demande envoyée (action ou consigne)
    property string hint: ""
    readonly property bool hasResult: result !== "" && !busy && !error
    readonly property string text: manual ? editor.text : source

    function close(): void {
        screenState.writing = false;
    }

    function run(action: string, instruction: string): void {
        if (!text.trim()) {
            showHint(qsTr("Sélectionne d'abord du texte (ou tape-le ici)"));
            return;
        }
        seq += 1;
        busy = true;
        error = "";
        result = "";
        lastAsk = instruction || action;
        backend.send({
            seq: seq,
            op: "rewrite",
            action: action,
            text: text,
            instruction: instruction,
            target: "anglais"
        });
    }

    function runSelected(): void {
        run(actions[selected].id, "");
    }

    function apply(): void {
        if (!hasResult)
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
        showHint(qsTr("Copié dans le presse-papiers ✓"));
    }

    function showHint(t: string): void {
        hint = t;
        hintTimer.restart();
    }

    function onEnter(): void {
        const ask = input.text.trim();
        if (ask && ask !== lastAsk)
            run("libre", ask);
        else if (hasResult)
            apply();
        else if (!busy)
            runSelected();
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.stage === "selection") {
            source = msg.text.trim() ? msg.text : "";
            winAddr = msg.window;
            manual = !source;
            if (manual)
                editor.forceActiveFocus();
        } else if (msg.seq !== seq) {
            return;
        } else if (msg.stage === "chunk") {
            result = msg.text;
        } else if (msg.stage === "end") {
            result = msg.text;
            busy = false;
        } else if (msg.stage === "error") {
            error = msg.text;
            busy = false;
        }
    }

    visible: morph > 0.001
    implicitWidth: 720
    implicitHeight: column.implicitHeight + 28

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutBack
            easing.overshoot: 0.6
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
            source = "";
            winAddr = "";
            manual = false;
            editor.text = "";
            input.text = "";
            result = "";
            error = "";
            busy = false;
            lastAsk = "";
            selected = 0;
            seq += 1;
            backend.running = true;
            backend.send({
                selection: true
            });
            input.forceActiveFocus();
        }
    }

    Timer {
        id: hintTimer

        interval: 1800
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

    component Chip: Rectangle {
        id: chip

        required property var modelData
        required property int index
        readonly property bool active: root.selected === index

        width: chipRow.implicitWidth + 24
        height: 32
        radius: 16
        color: active ? Qt.alpha(root.accent, 0.28) : chipMouse.containsMouse ? Qt.alpha(root.fg, 0.1) : Qt.alpha(root.fg, 0.05)
        border.width: 1
        border.color: active ? Qt.alpha(root.accent, 0.7) : Qt.alpha(root.fg, 0.08)

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: 7

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.modelData.icon
                font.family: root.glyphFont
                font.pixelSize: 15
                color: chip.active ? root.accent : root.fgDim
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.modelData.label
                font.pixelSize: 14
                color: root.fg
            }
        }

        MouseArea {
            id: chipMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.selected = chip.index;
                root.runSelected();
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
                const ctrl = event.modifiers & Qt.ControlModifier;
                if (event.key === Qt.Key_Escape) {
                    root.close();
                } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_8) {
                    root.selected = event.key - Qt.Key_1;
                    root.runSelected();
                } else if (ctrl && event.key === Qt.Key_R) {
                    if (root.lastAsk)
                        root.run(root.actions.some(a => a.id === root.lastAsk) ? root.lastAsk : "libre", root.actions.some(a => a.id === root.lastAsk) ? "" : root.lastAsk);
                } else if (ctrl && event.key === Qt.Key_C && !input.selectedText) {
                    root.copy();
                } else if (event.key === Qt.Key_Tab) {
                    root.selected = (root.selected + 1) % root.actions.length;
                } else if (event.key === Qt.Key_Backtab) {
                    root.selected = (root.selected + root.actions.length - 1) % root.actions.length;
                } else {
                    return;
                }
                event.accepted = true;
            }

            Column {
                id: column

                x: 18
                y: 14
                width: parent.width - 36
                spacing: 12

                // ── Consigne libre ──
                Item {
                    width: parent.width
                    height: 36

                    Text {
                        id: icon

                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰲶"
                        font.family: root.glyphFont
                        font.pixelSize: 22
                        color: root.accent
                    }

                    TextInput {
                        id: input

                        anchors.left: icon.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        focus: true
                        color: root.fg
                        selectionColor: Qt.alpha(root.accent, 0.35)
                        selectedTextColor: root.fg
                        font.pixelSize: 20
                        font.weight: Font.Light
                        clip: true

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.onEnter();
                                event.accepted = true;
                            } else if (!text && event.key === Qt.Key_Right) {
                                root.selected = (root.selected + 1) % root.actions.length;
                                event.accepted = true;
                            } else if (!text && event.key === Qt.Key_Left) {
                                root.selected = (root.selected + root.actions.length - 1) % root.actions.length;
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !input.text
                            text: qsTr("Décris la modification, ou choisis une action…")
                            color: Qt.alpha(root.fg, 0.38)
                            font: input.font
                        }
                    }
                }

                // ── Texte d'origine ──
                Rectangle {
                    width: parent.width
                    height: root.manual ? Math.min(140, Math.max(44, editor.contentHeight + 20)) : sourceText.implicitHeight + 20
                    radius: 14
                    color: Qt.alpha(root.fg, 0.05)

                    Text {
                        id: sourceText

                        visible: !root.manual
                        x: 14
                        y: 10
                        width: parent.width - 28
                        text: root.source || qsTr("Lecture de la sélection…")
                        color: root.fgDim
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Flickable {
                        visible: root.manual
                        x: 14
                        y: 10
                        width: parent.width - 28
                        height: parent.height - 20
                        contentHeight: editor.contentHeight
                        clip: true

                        TextEdit {
                            id: editor

                            width: parent.width
                            color: root.fg
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: 15
                            selectionColor: Qt.alpha(root.accent, 0.35)
                            KeyNavigation.tab: input

                            Keys.onPressed: event => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                    root.onEnter();
                                    event.accepted = true;
                                }
                            }

                            Text {
                                visible: !editor.text
                                text: qsTr("Aucune sélection : colle ou tape le texte ici (Maj + Entrée = nouvelle ligne)")
                                color: Qt.alpha(root.fg, 0.38)
                                font: editor.font
                            }
                        }
                    }
                }

                // ── Actions ──
                Flow {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.actions

                        Chip {}
                    }
                }

                // ── Résultat, en direct ──
                Rectangle {
                    visible: root.busy || root.result !== "" || root.error !== ""
                    width: parent.width
                    height: visible ? Math.min(320, resultText.implicitHeight + 28) : 0
                    radius: 16
                    color: Qt.alpha(root.accent, 0.08)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, root.busy ? 0.5 : 0.25)

                    SequentialAnimation on border.color {
                        running: root.busy
                        loops: Animation.Infinite

                        ColorAnimation {
                            to: Qt.alpha(root.accent, 0.8)
                            duration: 600
                        }
                        ColorAnimation {
                            to: Qt.alpha(root.accent, 0.2)
                            duration: 600
                        }
                    }

                    Flickable {
                        id: resultFlick

                        anchors.fill: parent
                        anchors.margins: 14
                        contentHeight: resultText.implicitHeight
                        clip: true

                        TextEdit {
                            id: resultText

                            width: resultFlick.width
                            readOnly: true
                            selectByMouse: true
                            text: root.error ? qsTr("Erreur : %1").arg(root.error) : root.result || qsTr("Écriture…")
                            color: root.error ? "#ff453a" : root.result ? root.fg : root.fgDim
                            wrapMode: TextEdit.Wrap
                            font.pixelSize: 16
                            selectionColor: Qt.alpha(root.accent, 0.35)
                            activeFocusOnPress: false
                        }
                    }
                }

                // ── Aide ──
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.hint || (root.hasResult ? qsTr("Entrée remplacer  ·  Ctrl + C copier  ·  Ctrl + R réessayer  ·  Échap fermer") : qsTr("Entrée lancer  ·  ← → ou Tab choisir  ·  Ctrl + 1…8 action directe  ·  Échap fermer"))
                    color: root.hint ? root.accent : Qt.alpha(root.fg, 0.4)
                    font.pixelSize: 12
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Calculatrice façon macOS 27 (Super + O), dans le même verre que l'île :
// une goutte se détache de l'île et devient la calculatrice. Touches rondes,
// grand résultat en direct, historique, Entrée = résultat copié.
// Les calculs passent par `caelestia-spotlight serve` (même moteur que Spotlight :
// format français, % façon macOS, trigo en degrés, conversions d'unités).
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
    readonly property real curR: fromR + (34 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Couleurs ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.55)
    readonly property color orange: "#ff9f0a"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── État du calcul ──
    property string result: ""
    property bool incomplete: false
    property int seq: 0
    property var history: []
    property bool showHistory: false
    property string hint: ""
    property string flashKey: ""

    readonly property real keySize: 58
    readonly property real gap: 11
    readonly property var keypad: [
        [["√", "√(", "fn"], ["x²", "^2", "fn"], ["π", "π", "fn"], ["%", "%", "fn"]],
        [["AC", "clear", "fn"], ["(", "(", "fn"], [")", ")", "fn"], ["÷", "÷", "op"]],
        [["7", "7", "num"], ["8", "8", "num"], ["9", "9", "num"], ["×", "×", "op"]],
        [["4", "4", "num"], ["5", "5", "num"], ["6", "6", "num"], ["−", "−", "op"]],
        [["1", "1", "num"], ["2", "2", "num"], ["3", "3", "num"], ["+", "+", "op"]],
        [["⌫", "back", "fn"], ["0", "0", "num"], [",", ",", "num"], ["=", "equals", "eq"]]
    ]
    // Caractère tapé → symbole affiché (et touche éclairée)
    readonly property var charMap: ({
            "*": "×",
            "x": "×",
            "X": "×",
            "/": "÷",
            "-": "−",
            ".": ",",
            "p": "π",
            "P": "π"
        })
    readonly property string allowed: "0123456789+−×÷^%(),π√! "

    function close(): void {
        screenState.calculator = false;
    }

    function clean(text: string): string {
        let out = "";
        for (const ch of text) {
            const c = charMap[ch] ?? ch;
            if (allowed.includes(c))
                out += c;
        }
        return out;
    }

    function evaluate(): void {
        seq += 1;
        if (!input.text.trim()) {
            result = "";
            incomplete = false;
            return;
        }
        backend.send({
            calc: input.text,
            seq: seq
        });
    }

    function insert(text: string): void {
        const pos = input.cursorPosition;
        input.insert(pos, text);
        input.forceActiveFocus();
    }

    function press(action: string, label: string): void {
        flash(label);
        if (action === "clear")
            input.text = "";
        else if (action === "back") {
            const pos = input.cursorPosition;
            if (pos > 0)
                input.remove(pos - 1, pos);
        } else if (action === "equals")
            commit();
        else
            insert(action);
        input.forceActiveFocus();
    }

    function flash(label: string): void {
        flashKey = "";
        flashKey = label;
        flashTimer.restart();
    }

    function commit(): void {
        const expr = input.text.trim();
        if (!expr || !result || incomplete) {
            showHint(qsTr("Calcul incomplet"));
            return;
        }
        backend.send({
            commit: expr,
            result: result
        });
        showHint(qsTr("Copié dans le presse-papiers ✓"));
        bump.restart();
        // Le résultat devient le nouveau calcul, pour enchaîner
        if (/^[-−]?[\d\s ]+(,\d+)?$/.test(result)) {
            input.text = result.replace(/[\s ]/g, "").replace("-", "−");
            input.cursorPosition = input.text.length;
        }
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
            if (msg.seq !== seq)
                return;
            if (msg.result === null) {
                incomplete = true; // on garde le dernier résultat, estompé
            } else {
                incomplete = false;
                result = msg.result;
            }
        } else if (msg.stage === "history") {
            history = msg.items;
        }
    }

    visible: morph > 0.001
    implicitWidth: keySize * 4 + gap * 3 + 36
    implicitHeight: 52 + 112 + keySize * 6 + gap * 5 + 22

    Behavior on morph {
        NumberAnimation {
            duration: root.shown ? 640 : 380
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
            showHistory = false;
            input.forceActiveFocus();
            input.selectAll();
        }
    }

    Timer {
        id: flashTimer

        interval: 150
        onTriggered: root.flashKey = ""
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
        clip: root.morph < 0.999

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
                if (event.key === Qt.Key_Escape) {
                    if (root.showHistory)
                        root.showHistory = false;
                    else if (input.text) {
                        input.text = "";
                        root.flash("AC");
                    } else
                        root.close();
                    event.accepted = true;
                }
            }

            // ── En-tête : titre discret + historique ──
            Item {
                id: head

                x: 18
                y: 12
                width: parent.width - 36
                height: 32

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Calculatrice")
                    color: root.fgDim
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 16
                    color: root.showHistory ? Qt.alpha(root.orange, 0.25) : histArea.containsMouse ? Qt.alpha(root.fg, 0.1) : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰋚"
                        font.family: root.glyphFont
                        font.pixelSize: 17
                        color: root.showHistory ? root.orange : root.fgDim
                    }

                    MouseArea {
                        id: histArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showHistory = !root.showHistory
                    }
                }
            }

            // ── Écran : calcul en haut, grand résultat dessous ──
            Item {
                id: display

                x: 18
                anchors.top: head.bottom
                anchors.topMargin: 6
                width: parent.width - 36
                height: 104

                TextInput {
                    id: input

                    anchors.top: parent.top
                    width: parent.width
                    horizontalAlignment: TextInput.AlignRight
                    focus: true
                    color: root.fgDim
                    selectionColor: Qt.alpha(root.orange, 0.35)
                    selectedTextColor: root.fg
                    font.pixelSize: 20
                    clip: true

                    onTextChanged: {
                        const c = root.clean(text);
                        if (c !== text) {
                            const pos = cursorPosition;
                            const before = root.clean(text.slice(0, pos)).length;
                            text = c;
                            cursorPosition = before;
                            return;
                        }
                        root.evaluate();
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "=") {
                            root.flash("=");
                            root.commit();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier) && !selectedText) {
                            if (root.result) {
                                root.copyResult();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace) {
                            root.flash("⌫");
                        } else if (event.text) {
                            const c = root.charMap[event.text] ?? event.text;
                            root.flash(c === "^" ? "x²" : c);
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        visible: !input.text
                        text: "0"
                        color: Qt.alpha(root.fg, 0.3)
                        font: input.font
                    }
                }

                Text {
                    id: big

                    anchors.bottom: hintText.top
                    anchors.bottomMargin: -2
                    width: parent.width
                    height: 64
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignBottom
                    text: root.result || "0"
                    color: !input.text.trim() || root.incomplete ? Qt.alpha(root.fg, 0.4) : root.fg
                    font.pixelSize: 58
                    font.weight: Font.Light
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 22
                    elide: Text.ElideLeft

                    Behavior on color {
                        ColorAnimation {
                            duration: 160
                        }
                    }

                    transform: Scale {
                        id: bumpScale

                        origin.x: big.width
                        origin.y: big.height
                    }

                    SequentialAnimation {
                        id: bump

                        NumberAnimation {
                            target: bumpScale
                            properties: "xScale,yScale"
                            to: 1.08
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
                    id: hintText

                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    text: root.hint || qsTr("Entrée : résultat copié  ·  Échap : effacer")
                    color: root.hint.startsWith("Calcul") ? "#ff453a" : Qt.alpha(root.fg, 0.4)
                    font.pixelSize: 11
                }
            }

            // ── Pavé de touches ──
            Grid {
                id: pad

                x: 18
                anchors.top: display.bottom
                anchors.topMargin: 14
                columns: 4
                spacing: root.gap
                opacity: root.showHistory ? 0 : 1
                scale: root.showHistory ? 0.96 : 1
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                Repeater {
                    model: root.keypad.flat()

                    Rectangle {
                        id: key

                        required property var modelData
                        readonly property string label: modelData[0]
                        readonly property string action: modelData[1]
                        readonly property string kind: modelData[2]
                        readonly property bool lit: keyArea.pressed || root.flashKey === label
                        readonly property bool orangeKey: kind === "op" || kind === "eq"

                        width: root.keySize
                        height: root.keySize
                        radius: width / 2
                        color: orangeKey ? (lit ? Qt.lighter(root.orange, 1.35) : root.orange) : Qt.alpha(root.fg, (kind === "fn" ? 0.2 : 0.1) + (lit ? 0.18 : keyArea.containsMouse ? 0.06 : 0))
                        border.width: 1
                        border.color: orangeKey ? Qt.alpha("white", 0.25) : Qt.alpha(root.fg, 0.08)
                        scale: lit ? 0.9 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutBack
                                easing.overshoot: 2
                            }
                        }

                        // Reflet du verre en haut de la touche
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 3
                            width: parent.width - 14
                            height: parent.height * 0.42
                            radius: height / 2
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: Qt.alpha("white", key.orangeKey ? 0.28 : 0.1)
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.alpha("white", 0)
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: key.label
                            color: key.orangeKey ? "white" : root.fg
                            font.pixelSize: key.kind === "num" ? 25 : key.label.length > 1 ? 18 : 24
                            font.weight: key.kind === "num" ? Font.Normal : Font.Medium
                        }

                        MouseArea {
                            id: keyArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.press(key.action, key.label)
                        }
                    }
                }
            }

            // ── Historique (remplace le pavé) ──
            Item {
                x: 12
                anchors.top: display.bottom
                anchors.topMargin: 14
                width: parent.width - 24
                height: pad.height
                opacity: root.showHistory ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.history.length === 0
                    text: qsTr("Aucun calcul pour l'instant")
                    color: root.fgDim
                    font.pixelSize: 13
                }

                ListView {
                    anchors.fill: parent
                    anchors.bottomMargin: 40
                    clip: true
                    spacing: 4
                    model: root.history
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: hrow

                        required property var modelData

                        width: ListView.view.width
                        height: 54
                        radius: 14
                        color: hArea.containsMouse ? Qt.alpha(root.fg, 0.1) : Qt.alpha(root.fg, 0.04)

                        Column {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignRight
                                text: hrow.modelData[0]
                                color: root.fgDim
                                elide: Text.ElideLeft
                                font.pixelSize: 12
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignRight
                                text: "= " + hrow.modelData[1]
                                color: root.fg
                                elide: Text.ElideLeft
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: hArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Seulement le nombre (sans l'unité d'une conversion)
                                root.insert(hrow.modelData[1].split(" ")[0].replace(/ /g, ""));
                                root.showHistory = false;
                            }
                        }
                    }
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.history.length > 0
                    text: qsTr("Effacer l'historique")
                    color: clearArea.containsMouse ? "#ff453a" : root.fgDim
                    font.pixelSize: 12

                    MouseArea {
                        id: clearArea

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: backend.send({
                            history: "clear"
                        })
                    }
                }
            }
        }
    }

    function copyResult(): void {
        backend.send({
            run: "copy:" + result.replace(/[\s ]/g, "")
        });
        showHint(qsTr("Copié dans le presse-papiers ✓"));
    }
}

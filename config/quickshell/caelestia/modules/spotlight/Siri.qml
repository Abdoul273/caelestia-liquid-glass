pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Assistant vocal façon Siri (Super + Maj + Espace) : la goutte tombe de l'île, une orbe
// réagit à la voix ; on parle, l'assistant répond à voix haute (Gemini Live, même chaîne
// qu'ANO-GPT) et agit (apps, minuteur, musique, volume, recherche web, écrire dans le
// champ…). Sans nouvelle demande après la réponse, la goutte se referme seule.
// On peut aussi écrire sa demande. Moteur persistant : `caelestia-siri serve`.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.siri ?? false

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
    readonly property real curR: fromR + (32 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Couleurs ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.55)
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── État ──
    property string phase: "connexion"
    property string detail: ""
    property string userText: ""
    property string replyText: ""
    property string toolLabel: ""
    property real level: 0
    property bool typing: typed.text !== "" || typed.activeFocus

    function close(): void {
        screenState.siri = false;
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!shown)
            return;
        if (msg.stage === "level") {
            level = msg.v;
            decay.restart();
        } else if (msg.stage === "user") {
            if (replyText && phase === "ecoute") {
                replyText = "";
                toolLabel = "";
            }
            userText = msg.text;
        } else if (msg.stage === "reply") {
            replyText = msg.text;
            toolLabel = "";
        } else if (msg.stage === "tool") {
            toolLabel = msg.label;
        } else if (msg.stage === "state") {
            phase = msg.state;
            detail = msg.detail ?? "";
        } else if (msg.stage === "idle") {
            if (!typed.text)
                close();
        }
    }

    function statusText(): string {
        if (phase === "erreur")
            return qsTr("Indisponible : %1").arg(detail || qsTr("erreur inconnue"));
        if (toolLabel && (phase === "outil" || phase === "reflexion"))
            return toolLabel;
        if (phase === "connexion")
            return qsTr("Un instant…");
        if (phase === "reflexion")
            return "…";
        return qsTr("Je vous écoute…");
    }

    visible: morph > 0.001
    implicitWidth: 640
    implicitHeight: Math.max(84, column.implicitHeight + 36)

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
            phase = "connexion";
            userText = "";
            replyText = "";
            toolLabel = "";
            typed.text = "";
            if (backend.running)
                backend.send({
                    open: true
                });
            else
                backend.running = true;
            content.forceActiveFocus();
        } else {
            backend.send({
                close: true
            });
        }
    }

    Timer {
        id: decay

        interval: 160
        onTriggered: root.level = 0
    }

    // Moteur persistant : il garde la conversation (reprise Gemini) entre deux ouvertures
    Process {
        id: backend

        function send(msg: var): void {
            if (running)
                write(JSON.stringify(msg) + "\n");
        }

        command: [`${Quickshell.env("HOME")}/.local/bin/caelestia-siri`, "serve"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        onStarted: if (root.shown)
            send({
                open: true
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

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Space && root.phase === "parle") {
                    backend.send({
                        interrupt: true
                    });
                    event.accepted = true;
                } else if (event.text && event.text.trim() && !(event.modifiers & Qt.ControlModifier)) {
                    // Taper une lettre ouvre la saisie écrite
                    typed.forceActiveFocus();
                    typed.text += event.text;
                    event.accepted = true;
                }
            }

            // ── Orbe ──
            Item {
                id: orb

                x: 18
                y: 20
                width: 48
                height: 48

                property real pulse: 1 + root.level * 0.35

                Behavior on pulse {
                    NumberAnimation {
                        duration: 110
                    }
                }

                Repeater {
                    model: [
                        {
                            c: "#ff375f",
                            dx: -5,
                            dy: -3,
                            k: 1.0
                        },
                        {
                            c: "#5e5ce6",
                            dx: 5,
                            dy: -2,
                            k: 0.8
                        },
                        {
                            c: "#64d2ff",
                            dx: 0,
                            dy: 5,
                            k: 1.2
                        }
                    ]

                    Rectangle {
                        id: blob

                        required property var modelData
                        required property int index

                        readonly property real breathe: root.phase === "erreur" ? 0 : root.phase === "connexion" || root.phase === "reflexion" || root.phase === "outil" ? 0.18 : 0.08

                        width: 30 * orb.pulse * (1 + Math.sin(spin.angle * modelData.k * Math.PI / 90) * breathe)
                        height: width
                        radius: width / 2
                        x: orb.width / 2 - width / 2 + modelData.dx * Math.cos(spin.angle * Math.PI / 180 + index * 2.1) * orb.pulse
                        y: orb.height / 2 - height / 2 + modelData.dy * Math.sin(spin.angle * Math.PI / 180 + index * 2.1) * orb.pulse
                        color: root.phase === "erreur" ? Qt.alpha(root.fg, 0.25) : modelData.c
                        opacity: 0.72
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 14 * orb.pulse
                    height: width
                    radius: width / 2
                    color: Qt.alpha("white", 0.55)
                }

                Item {
                    id: spin

                    property real angle: 0

                    NumberAnimation on angle {
                        from: 0
                        to: 360
                        duration: root.phase === "parle" ? 2400 : root.phase === "ecoute" ? 7000 : 3600
                        loops: Animation.Infinite
                        running: root.shown
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.send({
                        interrupt: true
                    })
                }
            }

            // ── Conversation ──
            Column {
                id: column

                anchors.left: orb.right
                anchors.leftMargin: 18
                anchors.right: parent.right
                anchors.rightMargin: 24
                y: 18
                spacing: 6

                // Ce que l'utilisateur a dit
                Text {
                    width: parent.width
                    visible: root.userText !== ""
                    text: root.userText
                    color: root.fgDim
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideLeft
                }

                // Réponse (ou état)
                Text {
                    width: parent.width
                    text: root.replyText || root.statusText()
                    color: root.phase === "erreur" ? "#ff453a" : root.replyText ? root.fg : Qt.alpha(root.fg, 0.45)
                    font.pixelSize: root.replyText.length > 160 ? 17 : 20
                    font.weight: root.replyText ? Font.Normal : Font.Light
                    wrapMode: Text.Wrap
                    maximumLineCount: 7
                    elide: Text.ElideRight
                    lineHeight: 1.08
                }

                // Saisie écrite (apparaît dès qu'on tape)
                Item {
                    width: parent.width
                    height: root.typing ? 34 : 0
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: 180
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 17
                        color: Qt.alpha(root.fg, 0.07)
                    }

                    TextInput {
                        id: typed

                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.fg
                        font.pixelSize: 15
                        clip: true
                        selectionColor: Qt.alpha("#5e5ce6", 0.4)

                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && text.trim()) {
                                root.userText = text.trim();
                                root.replyText = "";
                                backend.send({
                                    text: text.trim()
                                });
                                text = "";
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.close();
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !typed.text
                            text: qsTr("Écrire à l'assistant…")
                            color: Qt.alpha(root.fg, 0.38)
                            font: typed.font
                        }
                    }
                }
            }
        }
    }
}

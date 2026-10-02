pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Assistant vocal façon Siri (Super + Maj + Espace) : la goutte tombe de l'île, une orbe
// réagit à la voix ; on parle, l'assistant répond à voix haute (Gemini Live, même chaîne
// qu'ANO-GPT) et agit (apps, minuteur, musique, volume, recherche web, écrire dans le
// champ…). Micro coupé par défaut, comme « Écrire à Siri » : on écrit sa demande, ou
// on active le micro (bouton ou Tab) pour une demande vocale ; il se recoupe ensuite.
// Moteur persistant : `caelestia-siri serve`.
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
    property bool micOn
    // Fil de conversation (comme Siri sur macOS) : on garde tout l'échange, la bulle grandit
    property int replyIndex: -1
    property real lastActivity: 0
    readonly property bool hasThread: messages.count > 0
    readonly property real maxHeight: (screen?.height ?? 1080) * 0.66

    ListModel {
        id: messages
    }

    function addUser(text: string, typedIn: bool): void {
        messages.append({
            role: "user",
            text: text,
            typedIn: typedIn
        });
        replyIndex = -1;
    }

    function clearThread(): void {
        messages.clear();
        replyIndex = -1;
        userText = "";
        replyText = "";
        toolLabel = "";
    }

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
            // Transcription de la voix : arrive par morceaux, on met à jour la même bulle
            const last = messages.count ? messages.get(messages.count - 1) : null;
            if (last && last.role === "user" && !last.typedIn && replyIndex < 0)
                messages.setProperty(messages.count - 1, "text", msg.text);
            else
                addUser(msg.text, false);
            userText = msg.text;
            lastActivity = Date.now();
        } else if (msg.stage === "reply") {
            if (replyIndex >= 0 && replyIndex < messages.count)
                messages.setProperty(replyIndex, "text", msg.text);
            else {
                messages.append({
                    role: "assistant",
                    text: msg.text,
                    typedIn: false
                });
                replyIndex = messages.count - 1;
            }
            replyText = msg.text;
            toolLabel = "";
            lastActivity = Date.now();
        } else if (msg.stage === "mic") {
            micOn = msg.on;
            if (!micOn)
                level = 0;
        } else if (msg.stage === "tool") {
            toolLabel = msg.label;
            const prev = messages.count ? messages.get(messages.count - 1) : null;
            if (msg.label && !(prev && prev.role === "tool" && prev.text === msg.label))
                messages.append({
                    role: "tool",
                    text: msg.label,
                    typedIn: false
                });
        } else if (msg.stage === "state") {
            phase = msg.state;
            detail = msg.detail ?? "";
        } else if (msg.stage === "idle") {
            if (!typed.text)
                close();
        }
    }

    // Nouvelle conversation : on vide le fil et le moteur oublie la session Gemini
    function newConversation(): void {
        clearThread();
        backend.send({
            reset: true
        });
    }

    function toggleMic(): void {
        backend.send({
            mic: "toggle"
        });
    }

    // Échap : coupe d'abord la parole (ou le micro), puis ferme
    function handleEscape(): void {
        if (phase === "parle")
            backend.send({
                interrupt: true
            });
        else if (micOn)
            backend.send({
                mic: false
            });
        else
            close();
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
        if (micOn)
            return qsTr("Je vous écoute…");
        return qsTr("Que puis-je faire pour vous ?");
    }

    visible: morph > 0.001
    implicitWidth: hasThread ? 680 : 640
    implicitHeight: Math.min(maxHeight, 18 + header.height + (hasThread ? 10 + thread.contentHeight + 14 : 8) + 38 + 18)

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 360
            easing.type: Easing.OutCubic
        }
    }

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
            // Même mémoire que le moteur (reprise Gemini 15 min) : le fil reste affiché
            if (Date.now() - lastActivity > 15 * 60 * 1000)
                clearThread();
            toolLabel = "";
            typed.text = "";
            micOn = false;
            if (backend.running)
                backend.send({
                    open: true
                });
            else
                backend.running = true;
            typed.forceActiveFocus();
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
                    root.handleEscape();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.toggleMic();
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

            // ── En-tête : état (ou accueil quand le fil est vide) ──
            Item {
                id: header

                anchors.left: orb.right
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 24
                y: 18
                height: 48

                Text {
                    anchors.left: parent.left
                    anchors.right: newChat.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusText()
                    color: root.phase === "erreur" ? "#ff453a" : root.hasThread ? root.fgDim : Qt.alpha(root.fg, 0.6)
                    font.pixelSize: root.hasThread ? 14 : 20
                    font.weight: root.hasThread ? Font.Medium : Font.Light
                    elide: Text.ElideRight
                }

                // Nouvelle conversation (Ctrl + L)
                Rectangle {
                    id: newChat

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 15
                    visible: root.hasThread
                    color: newMouse.containsMouse ? Qt.alpha(root.fg, 0.14) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰑓"
                        font.family: root.glyphFont
                        font.pixelSize: 16
                        color: root.fgDim
                    }

                    MouseArea {
                        id: newMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.newConversation()
                    }
                }
            }

            // ── Fil de la conversation ──
            ListView {
                id: thread

                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.right: parent.right
                anchors.rightMargin: 24
                y: header.y + header.height + 10
                height: Math.max(0, inputRow.y - y - 14)
                visible: root.hasThread
                clip: true
                spacing: 10
                model: messages
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                // Toujours sur le dernier message, sauf si on remonte le fil soi-même
                property bool follow: true
                onMovementStarted: follow = false
                onMovementEnded: follow = atYEnd
                onContentHeightChanged: if (follow)
                    Qt.callLater(positionViewAtEnd)
                onCountChanged: {
                    follow = true;
                    Qt.callLater(positionViewAtEnd);
                }

                // Molette : le shell freine fort les Flickable (QT_QUICK_FLICKABLE_WHEEL_DECELERATION),
                // le fil gère donc lui-même un défilement ample et doux
                property real wheelTarget: 0

                function scrollBy(dy: real): void {
                    const top = originY;
                    const bottom = Math.max(top, originY + contentHeight - height);
                    const from = scrollAnim.running ? wheelTarget : contentY;
                    wheelTarget = Math.max(top, Math.min(bottom, from - dy));
                    follow = wheelTarget >= bottom - 2;
                    scrollAnim.restart();
                }

                function scrollToTop(): void {
                    follow = false;
                    wheelTarget = originY;
                    scrollAnim.duration = 420;
                    scrollAnim.restart();
                }

                function scrollToBottom(): void {
                    wheelTarget = Math.max(originY, originY + contentHeight - height);
                    follow = true;
                    scrollAnim.duration = 420;
                    scrollAnim.restart();
                }

                NumberAnimation {
                    id: scrollAnim

                    target: thread
                    property: "contentY"
                    to: thread.wheelTarget
                    duration: 220
                    easing.type: Easing.OutCubic
                    onStopped: duration = 220
                }

                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        // Pavé tactile : pixels réels ; molette : ~3 lignes par cran
                        const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y * 1.6 : event.angleDelta.y / 120 * 110;
                        thread.scrollBy(dy);
                        event.accepted = true;
                    }
                }

                add: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 260
                    }
                    NumberAnimation {
                        property: "scale"
                        from: 0.92
                        to: 1
                        duration: 320
                        easing.type: Easing.OutBack
                    }
                }

                // « … » pendant que l'assistant réfléchit ou agit
                footer: Item {
                    readonly property bool on: root.hasThread && root.replyIndex < 0 && (root.phase === "reflexion" || root.phase === "outil" || root.phase === "connexion")

                    width: ListView.view.width
                    height: on ? 36 : 0
                    visible: on

                    Rectangle {
                        y: 10
                        width: 58
                        height: 26
                        radius: 13
                        color: Qt.alpha(root.fg, 0.08)

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Repeater {
                                model: 3

                                Rectangle {
                                    id: dot

                                    required property int index

                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: root.fgDim

                                    SequentialAnimation on opacity {
                                        running: root.shown
                                        loops: Animation.Infinite

                                        PauseAnimation {
                                            duration: dot.index * 160
                                        }
                                        NumberAnimation {
                                            from: 0.25
                                            to: 1
                                            duration: 320
                                        }
                                        NumberAnimation {
                                            from: 1
                                            to: 0.25
                                            duration: 320
                                        }
                                        PauseAnimation {
                                            duration: (2 - dot.index) * 160
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                delegate: Item {
                    id: msg

                    required property string role
                    required property string text
                    required property int index

                    width: ListView.view.width
                    height: role === "user" ? bubble.height : role === "tool" ? chip.height : answer.implicitHeight
                    transformOrigin: role === "user" ? Item.Right : Item.Left

                    // Demande : bulle à droite
                    Rectangle {
                        id: bubble

                        visible: msg.role === "user"
                        anchors.right: parent.right
                        width: Math.min(msg.width * 0.78, userLabel.implicitWidth + 28)
                        height: userLabel.implicitHeight + 16
                        radius: Math.min(19, height / 2)
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Qt.alpha("#5e5ce6", 0.78)
                            }
                            GradientStop {
                                position: 1
                                color: Qt.alpha("#3a7bfd", 0.72)
                            }
                        }

                        Text {
                            id: userLabel

                            x: 14
                            y: 8
                            width: Math.min(implicitWidth, msg.width * 0.78 - 28)
                            text: msg.text
                            color: "white"
                            font.pixelSize: 15
                            wrapMode: Text.Wrap
                        }
                    }

                    // Action en cours : pastille discrète
                    Rectangle {
                        id: chip

                        visible: msg.role === "tool"
                        width: chipRow.implicitWidth + 20
                        height: 26
                        radius: 13
                        color: Qt.alpha(root.fg, 0.07)
                        border.width: 1
                        border.color: Qt.alpha(root.fg, 0.08)

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰄬"
                                font.family: root.glyphFont
                                font.pixelSize: 13
                                color: "#64d2ff"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: msg.text
                                color: root.fgDim
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, msg.width - 60)
                            }
                        }
                    }

                    // Réponse : texte libre à gauche, sélectionnable
                    TextEdit {
                        id: answer

                        visible: msg.role === "assistant"
                        width: msg.width * 0.94
                        text: msg.text
                        readOnly: true
                        selectByMouse: true
                        activeFocusOnPress: false
                        color: root.fg
                        selectionColor: Qt.alpha("#5e5ce6", 0.4)
                        font.pixelSize: 17
                        wrapMode: TextEdit.Wrap
                    }
                }
            }

            // ── Flèches : tout en haut / tout en bas du fil ──
            Column {
                anchors.right: thread.right
                anchors.rightMargin: -6
                anchors.bottom: thread.bottom
                anchors.bottomMargin: 4
                spacing: 6
                z: 2

                Repeater {
                    model: [
                        {
                            glyph: "󰁝",
                            up: true
                        },
                        {
                            glyph: "󰁅",
                            up: false
                        }
                    ]

                    Rectangle {
                        id: arrow

                        required property var modelData

                        readonly property bool needed: thread.contentHeight > thread.height + 4 && (modelData.up ? thread.contentY > thread.originY + 4 : !thread.follow)

                        width: 32
                        height: 32
                        radius: 16
                        color: arrowMouse.containsMouse ? Qt.alpha(root.fg, 0.26) : Qt.alpha(Colours.palette.m3surface, 0.82)
                        border.width: 1
                        border.color: Qt.alpha(root.fg, 0.14)
                        opacity: needed ? 1 : 0
                        scale: needed ? 1 : 0.6
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 180
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutBack
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: arrow.modelData.glyph
                            font.family: root.glyphFont
                            font.pixelSize: 18
                            color: root.fg
                        }

                        MouseArea {
                            id: arrowMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: arrow.modelData.up ? thread.scrollToTop() : thread.scrollToBottom()
                        }
                    }
                }
            }

            // ── Saisie écrite (toujours là) + bouton micro ──
            Item {
                id: inputRow

                anchors.left: parent.left
                anchors.leftMargin: root.hasThread ? 24 : orb.width + 34
                anchors.right: parent.right
                anchors.rightMargin: 24
                y: root.height - height - 18

                height: 38

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 46
                        radius: 19
                        color: Qt.alpha(root.fg, 0.07)
                    }

                    // Micro : coupé par défaut, une demande vocale par appui (Tab)
                    Rectangle {
                        id: micBtn

                        anchors.right: parent.right
                        width: 38
                        height: 38
                        radius: 19
                        color: root.micOn ? "#ff375f" : micMouse.containsMouse ? Qt.alpha(root.fg, 0.16) : Qt.alpha(root.fg, 0.08)
                        scale: root.micOn ? 1 + root.level * 0.25 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.micOn ? "󰍬" : "󰍭"
                            font.family: root.glyphFont
                            font.pixelSize: 19
                            color: root.micOn ? "white" : root.fgDim
                        }

                        MouseArea {
                            id: micMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleMic()
                        }
                    }

                    TextInput {
                        id: typed

                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 60
                        verticalAlignment: TextInput.AlignVCenter
                        focus: true
                        color: root.fg
                        font.pixelSize: 15
                        clip: true
                        selectionColor: Qt.alpha("#5e5ce6", 0.4)

                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && text.trim()) {
                                root.userText = text.trim();
                                root.replyText = "";
                                root.addUser(text.trim(), true);
                                root.lastActivity = Date.now();
                                backend.send({
                                    text: text.trim()
                                });
                                text = "";
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.handleEscape();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                root.toggleMic();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                                root.newConversation();
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !typed.text
                            text: root.micOn ? qsTr("Parlez… (Tab pour couper le micro)") : qsTr("Écrire à l'assistant…  (Tab pour parler)")
                            color: Qt.alpha(root.fg, 0.38)
                            font: typed.font
                        }
                    }
                }
        }
    }
}

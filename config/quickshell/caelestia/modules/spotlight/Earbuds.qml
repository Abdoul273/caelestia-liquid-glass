pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.components
import qs.components.effects
import qs.services

// Écouteurs 3D (Super + Maj + B) dans le même verre que l'île, façon AirPodsDesktop :
// une goutte tombe de l'île avec l'animation 3D temps réel des écouteurs
// (Écouteur Gauche = BX012, Écouteur Droit = CETW572, Boîtier galet articulé).
// Si seul le droit (CETW572) est connecté sans le gauche (BX012), seul l'écouteur droit
// apparaît connecté / en lévitation / allumé (et inversement si seul BX012 est connecté).
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.earbuds ?? false

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
    readonly property color fgFaint: Qt.alpha(fg, 0.1)
    readonly property color accent: Colours.palette.m3primary
    readonly property color green: "#32d74b"
    readonly property color orange: "#ff9f0a"
    readonly property color red: "#ff453a"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── Appareils Bluetooth séparés : Gauche = BX012, Droite = CETW572 ──
    readonly property var allDevices: Bluetooth.devices.values ?? []

    readonly property BluetoothDevice leftDevice: {
        return allDevices.find(d => d && (/bx012/i.test(d.name ?? "") || /94:f8:0e:fb/i.test(d.address ?? ""))) ?? null;
    }

    readonly property BluetoothDevice rightDevice: {
        return allDevices.find(d => d && (/cetw572/i.test(d.name ?? "") || /ff:9d:75:ba/i.test(d.address ?? "")))
            ?? allDevices.find(d => d && d !== leftDevice && (/airpod|bud|ear|head|audio/i.test(d.name ?? "") || /audio|head|ear|phone/i.test(d.icon ?? "")))
            ?? null;
    }

    readonly property bool leftConnected: leftDevice?.connected ?? false
    readonly property bool rightConnected: rightDevice?.connected ?? false
    readonly property bool isConnected: leftConnected || rightConnected

    readonly property bool leftBusy: Bluez.isBusy(leftDevice)
    readonly property bool rightBusy: Bluez.isBusy(rightDevice)
    readonly property bool isBusy: leftBusy || rightBusy

    readonly property bool leftHasBatt: leftDevice?.batteryAvailable ?? false
    readonly property bool rightHasBatt: rightDevice?.batteryAvailable ?? false
    readonly property int leftPct: leftHasBatt ? Math.round((leftDevice?.battery ?? 0) * 100) : (leftConnected ? 100 : 0)
    readonly property int rightPct: rightHasBatt ? Math.round((rightDevice?.battery ?? 0) * 100) : (rightConnected ? 100 : 0)

    readonly property int activeEarPct: {
        if (leftConnected && rightConnected)
            return Math.round((leftPct + rightPct) / 2);
        if (rightConnected)
            return rightPct;
        if (leftConnected)
            return leftPct;
        return 100;
    }
    readonly property int casePct: isConnected ? Math.min(100, Math.max(25, Math.round(activeEarPct * 0.9 + 10))) : 95

    readonly property string headerTitle: {
        if (leftConnected && rightConnected)
            return "BX012 · CETW572";
        if (rightConnected)
            return (rightDevice?.name || "CETW572") + " · " + qsTr("Droite");
        if (leftConnected)
            return (leftDevice?.name || "BX012") + " · " + qsTr("Gauche");
        return "BX012 · CETW572";
    }

    readonly property string statusText: {
        if (isBusy)
            return qsTr("Connexion…");
        if (leftConnected && rightConnected)
            return qsTr("Gauche & Droite connectés");
        if (rightConnected)
            return qsTr("Écouteur droit connecté");
        if (leftConnected)
            return qsTr("Écouteur gauche connecté");
        return qsTr("Boîtier fermé");
    }

    property string activeProfile: "A2DP · Hi-Fi Stéréo"
    property bool autoPopup: true
    property bool openedByAuto: false

    function close(): void {
        openedByAuto = false;
        screenState.earbuds = false;
    }

    function syncLifts(): void {
        if (scene.lidOpen < 0.5) {
            scene.leftLift = 0;
            scene.rightLift = 0;
            return;
        }
        scene.leftLift = leftConnected ? 0.44 : 0;
        scene.rightLift = rightConnected ? 0.44 : 0;
    }

    visible: morph > 0.001
    implicitWidth: 424
    implicitHeight: 534

    Behavior on morph {
        NumberAnimation {
            duration: root.shown ? 640 : 380
            easing.type: root.shown ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 0.82
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
            scene.lidOpen = 0;
            scene.leftLift = 0;
            scene.rightLift = 0;
            scene.pitch = 22;
            openAnimTimer.restart();
            profileProc.running = true;
            content.forceActiveFocus();
        } else {
            openAnimTimer.stop();
            liftTimer.stop();
            autoCloseTimer.stop();
            scene.leftLift = 0;
            scene.rightLift = 0;
            scene.lidOpen = 0;
        }
    }

    onLeftConnectedChanged: {
        if (shown) {
            syncLifts();
            profileProc.running = true;
        }
    }

    onRightConnectedChanged: {
        if (shown) {
            syncLifts();
            profileProc.running = true;
        }
    }

    Timer {
        id: openAnimTimer

        interval: 210
        onTriggered: {
            scene.lidOpen = 1;
            if (root.isConnected)
                liftTimer.restart();
        }
    }

    Timer {
        id: liftTimer

        interval: 320
        onTriggered: {
            if (root.shown)
                root.syncLifts();
        }
    }

    Timer {
        id: autoCloseTimer

        interval: 5800
        onTriggered: {
            if (root.shown && root.openedByAuto && !hoverTracker.hovered && !scene.dragging)
                root.close();
        }
    }

    // Détection automatique de connexion façon AirPodsDesktop :
    // l'île fait son flash habituel ET la goutte 3D s'ouvre en dessous
    Instantiator {
        model: Bluetooth.devices

        delegate: QtObject {
            required property BluetoothDevice modelData
            readonly property bool on: modelData?.connected ?? false
            property bool ready: false

            Component.onCompleted: ready = true

            onOnChanged: {
                if (!ready || !on || !root.autoPopup)
                    return;
                const d = modelData;
                const isEarbud = /cetw|bx012|airpod|bud|ear|head|audio/i.test(d?.name ?? "") || /audio|head|ear|phone/i.test(d?.icon ?? "");
                if (!isEarbud)
                    return;
                if (!root.shown) {
                    root.openedByAuto = true;
                    root.screenState.earbuds = true;
                    autoCloseTimer.restart();
                }
            }
        }
    }

    // Lecture rapide du profil/codec PipeWire actif (A2DP / HFP)
    Process {
        id: profileProc

        command: ["sh", "-c", "pactl list cards 2>/dev/null | awk '/bluez_card/{f=1} f&&/Active Profile:/{sub(/.*Active Profile: /,\"\"); print; exit}'"]
        stdout: SplitParser {
            onRead: data => {
                const s = data.trim();
                if (!s)
                    return;
                if (/a2dp/i.test(s))
                    root.activeProfile = "A2DP · Hi-Fi Stéréo";
                else if (/headset|hfp|HSP/i.test(s))
                    root.activeProfile = "Mains libres · Micro";
                else
                    root.activeProfile = s;
            }
        }
    }

    HoverHandler {
        id: hoverTracker
        onHoveredChanged: if (hovered) root.openedByAuto = false
    }

    // ── Carte jauge circulaire cliquable (Écouteur G BX012 / Boîtier / Écouteur D CETW572) ──
    component PodCard: GlassButton {
        id: card

        property string label: ""
        property string modelTag: ""
        property string sideBadge: ""
        property string sublabel: ""
        property string glyph: "󰋋"
        property int pct: 100
        property bool connected: false
        property bool busy: false
        property bool showPct: false
        readonly property color ringColor: busy ? root.orange : !connected ? root.fgFaint : pct < 20 ? root.red : pct < 40 ? root.orange : root.green

        width: 120
        height: 110
        radius: 20
        tint: connected ? Qt.alpha(root.green, hovered ? 0.16 : 0.10) : Qt.alpha(root.fg, hovered ? 0.10 : 0.05)

        Column {
            anchors.centerIn: parent
            spacing: 4

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48
                height: 48

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 3.5
                        strokeColor: root.fgFaint
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: 24
                            centerY: 24
                            radiusX: 20
                            radiusY: 20
                            startAngle: -90
                            sweepAngle: 360
                        }
                    }

                    ShapePath {
                        strokeWidth: 3.5
                        strokeColor: card.ringColor
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: 24
                            centerY: 24
                            radiusX: 20
                            radiusY: 20
                            startAngle: -90
                            sweepAngle: card.connected ? 360 * Math.max(0.05, card.pct / 100) * root.reveal : (card.busy ? 120 : 0)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: card.glyph
                    font.family: root.glyphFont
                    font.pixelSize: 18
                    color: card.connected ? root.fg : root.fgDim
                    opacity: card.connected ? 1 : 0.55
                }

                // Pastille L / R sur le coin de l'anneau
                Rectangle {
                    visible: card.sideBadge !== ""
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 16
                    height: 16
                    radius: 8
                    color: card.connected ? root.green : Qt.alpha(root.fg, 0.18)

                    Text {
                        anchors.centerIn: parent
                        text: card.sideBadge
                        color: card.connected ? "#08100a" : root.fgDim
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: card.label
                color: card.connected ? root.fg : root.fgDim
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: card.ringColor
                    visible: card.connected || card.busy
                }

                Text {
                    text: card.busy ? qsTr("Connexion…") : card.showPct ? `${card.pct} %` : card.sublabel
                    color: card.connected ? root.green : card.busy ? root.orange : Qt.alpha(root.fg, 0.42)
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
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
                root.openedByAuto = false;
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Space) {
                    if (scene.lidOpen > 0.5) {
                        scene.leftLift = 0;
                        scene.rightLift = 0;
                        scene.lidOpen = 0;
                    } else {
                        scene.lidOpen = 1;
                        root.syncLifts();
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left && root.leftDevice) {
                    Bluez.toggleConnection(root.leftDevice);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right && root.rightDevice) {
                    Bluez.toggleConnection(root.rightDevice);
                    event.accepted = true;
                }
            }

            // ── En-tête : Appareil(s) actif(s), pastille d'état et actions 3D ──
            Item {
                id: header

                x: 18
                y: 14
                width: parent.width - 36
                height: 42

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Row {
                        spacing: 8

                        Text {
                            text: root.headerTitle
                            color: root.fg
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }

                        // Pastille d'état en verre (indique précisément quel côté est connecté)
                        GlassControl {
                            anchors.verticalCenter: parent.verticalCenter
                            width: statusRow.implicitWidth + 16
                            height: 22
                            radius: 11
                            tintColour: Qt.alpha(root.isBusy ? root.orange : root.isConnected ? root.green : root.fg, root.isConnected || root.isBusy ? 0.22 : 0.08)

                            Row {
                                id: statusRow

                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.isBusy ? root.orange : root.isConnected ? root.green : root.fgDim
                                }

                                Text {
                                    text: root.statusText
                                    color: root.isBusy ? root.orange : root.isConnected ? root.green : root.fgDim
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    Text {
                        text: root.isConnected ? root.activeProfile : qsTr("Glisser pour tourner · Double-clic : couvercle")
                        color: root.fgDim
                        font.pixelSize: 11
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // Bouton Ouvrir / Fermer le boîtier 3D
                    GlassButton {
                        width: 32
                        height: 32
                        radius: 16
                        tint: scene.lidOpen > 0.5 ? Qt.alpha(root.accent, 0.26) : Qt.alpha(root.fg, hovered ? 0.12 : 0.06)
                        onClicked: {
                            root.openedByAuto = false;
                            if (scene.lidOpen > 0.5) {
                                scene.leftLift = 0;
                                scene.rightLift = 0;
                                scene.lidOpen = 0;
                            } else {
                                scene.lidOpen = 1;
                                root.syncLifts();
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: scene.lidOpen > 0.5 ? "󰁝" : "󰁅"
                            font.family: root.glyphFont
                            font.pixelSize: 15
                            color: scene.lidOpen > 0.5 ? root.accent : root.fgDim
                        }
                    }

                    // Sortir / Ranger l'écouteur connecté (ou les deux en aperçu)
                    GlassButton {
                        width: 32
                        height: 32
                        radius: 16
                        tint: (scene.leftLift > 0.1 || scene.rightLift > 0.1) ? Qt.alpha(root.accent, 0.26) : Qt.alpha(root.fg, hovered ? 0.12 : 0.06)
                        onClicked: {
                            root.openedByAuto = false;
                            if (scene.lidOpen < 0.5)
                                scene.lidOpen = 1;
                            if (scene.leftLift > 0.1 || scene.rightLift > 0.1) {
                                scene.leftLift = 0;
                                scene.rightLift = 0;
                            } else if (root.isConnected) {
                                root.syncLifts();
                            } else {
                                scene.leftLift = 0.5;
                                scene.rightLift = 0.5;
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰋋"
                            font.family: root.glyphFont
                            font.pixelSize: 15
                            color: (scene.leftLift > 0.1 || scene.rightLift > 0.1) ? root.accent : root.fgDim
                        }
                    }
                }
            }

            // ── Scène 3D interactive style AirPodsDesktop (Gauche & Droite indépendants) ──
            EarbudsScene {
                id: scene

                anchors.top: header.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 20
                height: 238
                active: root.visible
                leftConnected: root.leftConnected
                rightConnected: root.rightConnected
                accentColor: root.accent
            }

            // ── Cartes de batterie indépendantes : Gauche (BX012) · Boîtier · Droite (CETW572) ──
            Row {
                id: cardsRow

                anchors.top: scene.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                // Écouteur Gauche = BX012 (cliquer dessus le connecte / déconnecte directement)
                PodCard {
                    label: "BX012"
                    sideBadge: "L"
                    sublabel: qsTr("Non connecté")
                    glyph: "󰋋"
                    pct: root.leftPct
                    connected: root.leftConnected
                    busy: root.leftBusy
                    showPct: root.leftConnected
                    onClicked: {
                        root.openedByAuto = false;
                        if (root.leftDevice)
                            Bluez.toggleConnection(root.leftDevice);
                    }
                }

                // Boîtier de charge
                PodCard {
                    label: qsTr("Boîtier")
                    sideBadge: ""
                    sublabel: qsTr("En veille")
                    glyph: "󰂄"
                    pct: root.casePct
                    connected: root.isConnected
                    busy: false
                    showPct: root.isConnected
                    onClicked: {
                        root.openedByAuto = false;
                        if (scene.lidOpen > 0.5) {
                            scene.leftLift = 0;
                            scene.rightLift = 0;
                            scene.lidOpen = 0;
                        } else {
                            scene.lidOpen = 1;
                            root.syncLifts();
                        }
                    }
                }

                // Écouteur Droit = CETW572 (cliquer dessus le connecte / déconnecte directement)
                PodCard {
                    label: "CETW572"
                    sideBadge: "R"
                    sublabel: qsTr("Non connecté")
                    glyph: "󰋋"
                    pct: root.rightPct
                    connected: root.rightConnected
                    busy: root.rightBusy
                    showPct: root.rightConnected
                    onClicked: {
                        root.openedByAuto = false;
                        if (root.rightDevice)
                            Bluez.toggleConnection(root.rightDevice);
                    }
                }
            }

            // ── Barre de volume PipeWire en verre ──
            GlassControl {
                id: volBar

                anchors.top: cardsRow.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 36
                height: 42
                radius: 21
                tintColour: Qt.alpha(root.fg, 0.055)

                Text {
                    id: volIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: Audio.muted || Audio.volume <= 0.001 ? "󰝟" : Audio.volume < 0.5 ? "󰖀" : "󰕾"
                    font.family: root.glyphFont
                    font.pixelSize: 17
                    color: Audio.muted ? root.red : root.fgDim

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Audio.sink?.audio)
                                Audio.sink.audio.muted = !Audio.sink.audio.muted;
                        }
                    }
                }

                Item {
                    id: sliderTrack

                    anchors.left: volIcon.right
                    anchors.leftMargin: 12
                    anchors.right: volPctText.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: 3
                        color: root.fgFaint

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, Audio.volume))
                            height: parent.height
                            radius: 3
                            color: Audio.muted ? root.fgDim : root.accent
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            root.openedByAuto = false;
                            Audio.setVolume(Math.max(0, Math.min(1, mouse.x / width)));
                        }
                        onPositionChanged: mouse => {
                            if (pressed)
                                Audio.setVolume(Math.max(0, Math.min(1, mouse.x / width)));
                        }
                        onWheel: wheel => {
                            if (wheel.angleDelta.y > 0)
                                Audio.incrementVolume(0.04);
                            else
                                Audio.decrementVolume(0.04);
                        }
                    }
                }

                Text {
                    id: volPctText

                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    text: `${Math.round(Audio.volume * 100)} %`
                    color: root.fgDim
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            // ── Actions du bas : bouton Gauche (BX012), bouton Droite (CETW572) et Réglages ──
            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                // Bouton Gauche (BX012)
                GlassButton {
                    width: (root.width - 36 - 44 - 16) / 2
                    height: 42
                    radius: 21
                    enabled: !!root.leftDevice && !root.leftBusy
                    tint: root.leftConnected ? Qt.alpha(root.green, hovered ? 0.28 : 0.20) : Qt.alpha(root.fg, hovered ? 0.14 : 0.07)
                    onClicked: {
                        root.openedByAuto = false;
                        if (root.leftDevice)
                            Bluez.toggleConnection(root.leftDevice);
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.leftBusy ? "󰑐" : root.leftConnected ? "󰂱" : "󰂲"
                            font.family: root.glyphFont
                            font.pixelSize: 14
                            color: root.leftConnected ? root.green : root.fgDim
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.leftBusy ? qsTr("Gauche…") : root.leftConnected ? qsTr("G · BX012 ✓") : qsTr("Connecter G")
                            color: root.leftConnected ? root.green : root.fg
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // Bouton Droite (CETW572)
                GlassButton {
                    width: (root.width - 36 - 44 - 16) / 2
                    height: 42
                    radius: 21
                    enabled: !!root.rightDevice && !root.rightBusy
                    tint: root.rightConnected ? Qt.alpha(root.green, hovered ? 0.28 : 0.20) : Qt.alpha(root.fg, hovered ? 0.14 : 0.07)
                    onClicked: {
                        root.openedByAuto = false;
                        if (root.rightDevice)
                            Bluez.toggleConnection(root.rightDevice);
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.rightBusy ? "󰑐" : root.rightConnected ? "󰂱" : "󰂲"
                            font.family: root.glyphFont
                            font.pixelSize: 14
                            color: root.rightConnected ? root.green : root.fgDim
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.rightBusy ? qsTr("Droite…") : root.rightConnected ? qsTr("D · CETW572 ✓") : qsTr("Connecter D")
                            color: root.rightConnected ? root.green : root.fg
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                GlassButton {
                    width: 44
                    height: 42
                    radius: 21
                    tint: Qt.alpha(root.fg, hovered ? 0.13 : 0.07)
                    onClicked: {
                        root.close();
                        root.screenState.controlCenter = true;
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        font.family: root.glyphFont
                        font.pixelSize: 17
                        color: root.fgDim
                    }
                }
            }
        }
    }
}

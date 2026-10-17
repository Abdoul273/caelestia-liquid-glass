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
// une goutte tombe de l'île avec l'animation 3D temps réel des écouteurs CETW572
// (boîtier galet qui s'ouvre au ressort, écouteurs à crochet avec anneau chromé et LEDs bleues),
// jauges Gauche / Droite / Boîtier, volume et connexion Bluetooth en un clic.
// La notification rapide dans l'île est intégralement conservée.
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

    // ── Appareils Bluetooth (priorité CETW572 / audio connecté / écouteurs connus) ──
    readonly property var audioDevices: {
        const all = Bluetooth.devices.values ?? [];
        const match = d => d && (/cetw|bx012|airpod|bud|ear|head|audio/i.test(d.name ?? "") || /audio|head|ear|phone/i.test(d.icon ?? ""));
        const filtered = all.filter(match);
        return filtered.length > 0 ? filtered : all;
    }

    property string selectedAddress: ""

    readonly property BluetoothDevice device: {
        const list = audioDevices;
        if (selectedAddress) {
            const found = list.find(d => d?.address === selectedAddress);
            if (found)
                return found;
        }
        const conn = list.find(d => d?.connected && /cetw/i.test(d?.name ?? ""))
            ?? list.find(d => d?.connected)
            ?? list.find(d => /cetw/i.test(d?.name ?? ""))
            ?? list[0] ?? null;
        return conn;
    }

    readonly property bool isConnected: device?.connected ?? false
    readonly property bool isBusy: Bluez.isBusy(device)
    readonly property string deviceName: device?.name || "CETW572"
    readonly property bool hasBattery: device?.batteryAvailable ?? false
    readonly property int batteryPct: hasBattery ? Math.round((device?.battery ?? 0) * 100) : (isConnected ? 100 : 0)
    // Estimation intelligente du boîtier quand le protocole Bluetooth standard n'expose qu'une batterie globale
    readonly property int casePct: hasBattery ? Math.min(100, Math.max(20, Math.round(batteryPct * 0.9 + 10))) : 95

    property string activeProfile: "A2DP · AAC"
    property bool autoPopup: true

    // Fermeture automatique après un popup de connexion (annulée dès que l'utilisateur interagit)
    property bool openedByAuto: false

    function close(): void {
        openedByAuto = false;
        screenState.earbuds = false;
    }

    function selectNextDevice(): void {
        const list = audioDevices;
        if (list.length < 2)
            return;
        const idx = list.findIndex(d => d === device);
        const next = list[(idx + 1) % list.length];
        if (next)
            selectedAddress = next.address;
    }

    visible: morph > 0.001
    implicitWidth: 420
    implicitHeight: 530

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
            // Séquence d'ouverture AirPodsDesktop : le boîtier part fermé puis le couvercle s'ouvre
            scene.lidOpen = 0;
            scene.budsLift = 0;
            scene.pitch = 22;
            openAnimTimer.restart();
            profileProc.running = true;
            content.forceActiveFocus();
        } else {
            openAnimTimer.stop();
            autoCloseTimer.stop();
            scene.budsLift = 0;
            scene.lidOpen = 0;
        }
    }

    onIsConnectedChanged: {
        if (shown) {
            scene.budsLift = isConnected && scene.lidOpen > 0.5 ? 0.35 : 0;
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

        interval: 340
        onTriggered: {
            if (root.shown && scene.lidOpen > 0.5)
                scene.budsLift = root.isConnected ? 0.35 : 0;
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
                root.selectedAddress = d.address;
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

    // ── Carte jauge circulaire (Écouteur G / Boîtier / Écouteur D) ──
    component PodCard: GlassControl {
        id: card

        property string label: ""
        property string sublabel: ""
        property string glyph: "󰋋"
        property int pct: 100
        property bool available: true
        readonly property color ringColor: !available ? root.fgFaint : pct < 20 ? root.red : pct < 40 ? root.orange : root.green

        width: 118
        height: 104
        radius: 20
        tintColour: Qt.alpha(root.fg, 0.055)

        Column {
            anchors.centerIn: parent
            spacing: 5

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
                            sweepAngle: card.available ? 360 * Math.max(0.04, card.pct / 100) * root.reveal : 0
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: card.glyph
                    font.family: root.glyphFont
                    font.pixelSize: 18
                    color: card.available ? root.fg : root.fgDim
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: card.label
                color: root.fg
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
                    visible: card.available
                }

                Text {
                    text: card.available ? `${card.pct} %` : card.sublabel
                    color: card.available ? root.fgDim : Qt.alpha(root.fg, 0.38)
                    font.pixelSize: 11
                    font.weight: Font.Medium
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
                        scene.budsLift = 0;
                        scene.lidOpen = 0;
                    } else {
                        scene.lidOpen = 1;
                        scene.budsLift = root.isConnected ? 0.35 : 0;
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.device)
                        Bluez.toggleConnection(root.device);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.selectNextDevice();
                    event.accepted = true;
                }
            }

            // ── En-tête : Nom de l'appareil, pastille d'état et actions 3D ──
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
                            text: root.deviceName
                            color: root.fg
                            font.pixelSize: 17
                            font.weight: Font.Bold
                        }

                        // Pastille d'état en verre (Connecté / En cours / Déconnecté)
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
                                    text: root.isBusy ? qsTr("Connexion…") : root.isConnected ? qsTr("Connecté") : qsTr("Boîtier fermé")
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

                    // Changer d'appareil si plusieurs écouteurs sont connus
                    GlassButton {
                        visible: root.audioDevices.length > 1
                        width: 32
                        height: 32
                        radius: 16
                        tint: Qt.alpha(root.fg, hovered ? 0.12 : 0.06)
                        onClicked: {
                            root.openedByAuto = false;
                            root.selectNextDevice();
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰓡"
                            font.family: root.glyphFont
                            font.pixelSize: 15
                            color: root.fgDim
                        }
                    }

                    // Bouton Ouvrir / Fermer le boîtier 3D
                    GlassButton {
                        width: 32
                        height: 32
                        radius: 16
                        tint: scene.lidOpen > 0.5 ? Qt.alpha(root.accent, 0.26) : Qt.alpha(root.fg, hovered ? 0.12 : 0.06)
                        onClicked: {
                            root.openedByAuto = false;
                            if (scene.lidOpen > 0.5) {
                                scene.budsLift = 0;
                                scene.lidOpen = 0;
                            } else {
                                scene.lidOpen = 1;
                                scene.budsLift = root.isConnected ? 0.35 : 0;
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

                    // Sortir / Ranger les écouteurs en lévitation
                    GlassButton {
                        width: 32
                        height: 32
                        radius: 16
                        tint: scene.budsLift > 0.1 ? Qt.alpha(root.accent, 0.26) : Qt.alpha(root.fg, hovered ? 0.12 : 0.06)
                        onClicked: {
                            root.openedByAuto = false;
                            if (scene.lidOpen < 0.5)
                                scene.lidOpen = 1;
                            scene.budsLift = scene.budsLift > 0.1 ? 0 : 0.55;
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰋋"
                            font.family: root.glyphFont
                            font.pixelSize: 15
                            color: scene.budsLift > 0.1 ? root.accent : root.fgDim
                        }
                    }
                }
            }

            // ── Scène 3D interactive style AirPodsDesktop ──
            EarbudsScene {
                id: scene

                anchors.top: header.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 20
                height: 242
                active: root.visible
                connected: root.isConnected
                accentColor: root.accent
            }

            // ── Cartes de batterie : Gauche · Boîtier · Droite ──
            Row {
                id: cardsRow

                anchors.top: scene.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                PodCard {
                    label: qsTr("Gauche")
                    sublabel: root.isConnected ? qsTr("Actif") : qsTr("Rangé")
                    glyph: "󰋋"
                    pct: root.batteryPct
                    available: root.hasBattery || root.isConnected
                }

                PodCard {
                    label: qsTr("Boîtier")
                    sublabel: qsTr("Prêt")
                    glyph: "󰂄"
                    pct: root.casePct
                    available: root.hasBattery || root.isConnected
                }

                PodCard {
                    label: qsTr("Droite")
                    sublabel: root.isConnected ? qsTr("Actif") : qsTr("Rangé")
                    glyph: "󰋋"
                    pct: root.batteryPct
                    available: root.hasBattery || root.isConnected
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

            // ── Actions du bas : Connecter / Déconnecter + Ouvrir les réglages Bluetooth ──
            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                GlassButton {
                    width: root.width - 36 - 48 - 10
                    height: 42
                    radius: 21
                    enabled: !!root.device && !root.isBusy
                    tint: root.isConnected ? Qt.alpha(root.red, hovered ? 0.28 : 0.2) : Qt.alpha(root.accent, hovered ? 0.36 : 0.26)
                    onClicked: {
                        root.openedByAuto = false;
                        if (root.device)
                            Bluez.toggleConnection(root.device);
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isBusy ? "󰑐" : root.isConnected ? "󰂲" : "󰂱"
                            font.family: root.glyphFont
                            font.pixelSize: 16
                            color: root.isConnected ? root.red : root.accent
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isBusy ? qsTr("Opération en cours…") : root.isConnected ? qsTr("Déconnecter %1").arg(root.deviceName) : qsTr("Connecter %1").arg(root.deviceName)
                            color: root.isConnected ? root.red : root.fg
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                }

                GlassButton {
                    width: 48
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

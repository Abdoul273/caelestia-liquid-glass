pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.services

// Dynamic Island façon macOS : une pastille noire qui sort du bord haut du cadre et se
// transforme selon ce qui se passe (musique, volume, luminosité, notifications, charge,
// enregistrement). Survol = vue étendue (lecteur complet ou date/météo/batterie).
// Molette = volume, clic = lecture/pause quand un lecteur est actif.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            // ── Plein écran : l'île se cache comme le cadre ──
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            readonly property bool hasFullscreen: {
                const special = monitor?.lastIpcObject?.specialWorkspace?.name ?? "";
                if (special.length > 0) {
                    const ws = Hypr.workspaces.values.find(w => w.name === special);
                    return ws?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
                }
                return monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
            }

            // ── Sources ──
            readonly property MprisPlayer player: Players.active
            readonly property bool playing: player?.isPlaying ?? false
            readonly property bool hasMedia: !!player && (player.trackTitle ?? "").length > 0
            readonly property var brightMon: Brightness.getMonitorForScreen(modelData)
            readonly property real brightness: brightMon?.brightness ?? 0
            readonly property real battery: UPower.displayDevice.percentage ?? 0
            readonly property bool charging: !UPower.onBattery

            // Le dashboard (Super+A / clic droit) s'ouvre au même endroit : l'île s'efface
            readonly property ScreenState screenState: ShellState.forScreen(modelData)
            readonly property bool hidden: screenState?.dashboard ?? false

            // ── État éphémère ──
            property string pulse: ""   // "volume", "brightness", "notif", "charge"
            property var notif: null
            property bool ready
            property bool hovered
            property bool expanded

            // ── Mode affiché (par priorité) ──
            readonly property string mode: {
                if (pulse === "volume" || pulse === "brightness")
                    return "level";
                if (pulse === "notif" && notif)
                    return "notif";
                if (pulse === "charge")
                    return "charge";
                if (expanded)
                    return hasMedia ? "player" : "info";
                if (Recorder.running)
                    return "record";
                if (hasMedia && playing)
                    return "media";
                return "idle";
            }

            // Taille du corps de l'île pour chaque mode
            readonly property size target: {
                switch (mode) {
                case "level":
                    return Qt.size(330, 44);
                case "notif":
                    return Qt.size(420, 84);
                case "charge":
                    return Qt.size(300, 44);
                case "player":
                    return Qt.size(440, 168);
                case "info":
                    return Qt.size(380, 112);
                case "record":
                    return Qt.size(200, 36);
                case "media":
                    return Qt.size(270, 36);
                default:
                    return Qt.size(hovered ? 150 : 132, hovered ? 34 : 30);
                }
            }

            function flash(kind: string, ms: int): void {
                if (!ready)
                    return;
                pulse = kind;
                transientTimer.interval = ms;
                transientTimer.restart();
            }

            function fmtTime(s: real): string {
                if (!isFinite(s) || s < 0 || s > 2147483)
                    return "--:--";
                const m = Math.floor(s / 60);
                return `${m}:${Math.floor(s % 60).toString().padStart(2, "0")}`;
            }

            screen: modelData
            name: "island"
            visible: !hasFullscreen
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {
                item: body
            }

            anchors.top: true
            implicitWidth: 560
            implicitHeight: 230

            Component.onCompleted: readyTimer.start()

            Timer {
                id: readyTimer

                interval: 1500
                onTriggered: win.ready = true
            }

            Timer {
                id: transientTimer

                onTriggered: win.pulse = ""
            }

            // Survol : petite attente avant d'ouvrir, fermeture douce
            Timer {
                id: hoverTimer

                interval: win.hovered ? 260 : 380
                onTriggered: win.expanded = win.hovered
            }

            onHoveredChanged: hoverTimer.restart()

            // ── Déclencheurs ──
            Connections {
                target: Audio

                function onVolumeChanged(): void {
                    win.levelIcon = Audio.muted || Audio.volume <= 0 ? "volume_off" : Audio.volume < 0.5 ? "volume_down" : "volume_up";
                    win.levelValue = Audio.volume;
                    win.levelLabel = qsTr("Volume");
                    win.flash("volume", 1600);
                }

                function onMutedChanged(): void {
                    onVolumeChanged();
                }
            }

            property string levelIcon: "volume_up"
            property string levelLabel: ""
            property real levelValue: 0

            onBrightnessChanged: {
                levelIcon = `brightness_${Math.round(brightness * 6) + 1}`;
                levelValue = brightness;
                levelLabel = qsTr("Luminosité");
                flash("brightness", 1600);
            }

            onChargingChanged: {
                if (UPower.displayDevice.ready && charging)
                    flash("charge", 2600);
            }

            property int notifCount: Notifs.list.length

            onNotifCountChanged: {
                const n = Notifs.list[0];
                if (!n || Notifs.dnd || n.closed)
                    return;
                if (Date.now() - n.time.getTime() > 3000)
                    return;
                notif = n;
                flash("notif", 4200);
            }

            // Position du lecteur (Mpris ne la pousse pas tout seul)
            Timer {
                running: win.mode === "player" && win.playing
                interval: 500
                repeat: true
                onTriggered: win.player?.positionChanged()
            }

            ServiceRef {
                service: win.playing ? Audio.cava : null
            }

            // ════════════════════ L'île ════════════════════
            Item {
                id: body

                readonly property real shoulder: 14

                anchors.horizontalCenter: parent.horizontalCenter
                y: win.hidden ? -h - 6 : 0
                width: w + shoulder * 2

                Behavior on y {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutCubic
                    }
                }
                height: h

                property real w: win.target.width
                property real h: win.target.height
                readonly property real r: Math.min(h / 2, win.mode === "player" || win.mode === "info" || win.mode === "notif" ? 30 : h / 2)

                Behavior on w {
                    SpringAnimation {
                        spring: 4.2
                        damping: 0.32
                        epsilon: 0.3
                    }
                }
                Behavior on h {
                    SpringAnimation {
                        spring: 4.2
                        damping: 0.36
                        epsilon: 0.3
                    }
                }

                // Pulsation au moment où un évènement arrive
                scale: 1
                transformOrigin: Item.Top

                SequentialAnimation {
                    id: bump

                    NumberAnimation {
                        target: body
                        property: "scale"
                        to: 1.045
                        duration: 110
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: body
                        property: "scale"
                        to: 1
                        duration: 420
                        easing.type: Easing.OutBack
                        easing.overshoot: 2
                    }
                }

                Connections {
                    target: win

                    function onPulseChanged(): void {
                        if (win.pulse === "notif" || win.pulse === "charge")
                            bump.restart();
                    }
                }

                // Forme : épaules concaves en haut (fusion avec le cadre), coins arrondis en bas
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        id: path

                        readonly property real s: body.shoulder
                        readonly property real w: body.width
                        readonly property real h: body.height
                        readonly property real r: Math.min(body.r, (h) / 2)

                        strokeWidth: 1
                        strokeColor: Qt.rgba(1, 1, 1, 0.07)
                        fillGradient: LinearGradient {
                            y1: 0
                            y2: path.h
                            GradientStop {
                                position: 0
                                color: "#000000"
                            }
                            GradientStop {
                                position: 1
                                color: "#0d0d12"
                            }
                        }

                        startX: 0
                        startY: 0
                        PathArc {
                            x: path.s
                            y: path.s
                            radiusX: path.s
                            radiusY: path.s
                        }
                        PathLine {
                            x: path.s
                            y: path.h - path.r
                        }
                        PathArc {
                            x: path.s + path.r
                            y: path.h
                            radiusX: path.r
                            radiusY: path.r
                            direction: PathArc.Counterclockwise
                        }
                        PathLine {
                            x: path.w - path.s - path.r
                            y: path.h
                        }
                        PathArc {
                            x: path.w - path.s
                            y: path.h - path.r
                            radiusX: path.r
                            radiusY: path.r
                            direction: PathArc.Counterclockwise
                        }
                        PathLine {
                            x: path.w - path.s
                            y: path.s
                        }
                        PathArc {
                            x: path.w
                            y: 0
                            radiusX: path.s
                            radiusY: path.s
                        }
                        PathLine {
                            x: 0
                            y: 0
                        }
                    }
                }

                // Reflet discret sur le bord bas
                Rectangle {
                    x: body.shoulder + body.r * 0.6
                    width: body.w - body.r * 1.2
                    y: body.h - 1.5
                    height: 1
                    opacity: win.mode === "idle" ? 0.12 : 0.22
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: "transparent"
                        }
                        GradientStop {
                            position: 0.5
                            color: Colours.palette.m3primary
                        }
                        GradientStop {
                            position: 1
                            color: "transparent"
                        }
                    }
                }

                HoverHandler {
                    onHoveredChanged: win.hovered = hovered
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: e => {
                        if (e.angleDelta.y > 0)
                            Audio.incrementVolume();
                        else if (e.angleDelta.y < 0)
                            Audio.decrementVolume();
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onTapped: (_, button) => {
                        if (button === Qt.RightButton) {
                            win.expanded = false;
                            win.screenState.dashboard = true;
                        } else if (button === Qt.MiddleButton || win.mode === "media")
                            win.player?.togglePlaying();
                        else if (win.mode === "idle")
                            win.expanded = true;
                    }
                }

                // Zone de contenu (sans les épaules)
                Item {
                    id: content

                    x: body.shoulder
                    width: body.w
                    height: body.h
                    clip: true

                    // ── idle : trois petits points discrets au survol ──
                    Face {
                        active: win.mode === "idle"

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            opacity: win.hovered ? 0.6 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                }
                            }

                            Repeater {
                                model: 3

                                Rectangle {
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: "white"
                                }
                            }
                        }
                    }

                    // ── media compact : pochette + visualiseur ──
                    Face {
                        active: win.mode === "media"

                        Cover {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            size: 22
                            radius: 6
                        }

                        StyledText {
                            anchors.centerIn: parent
                            width: parent.width - 130
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: win.player?.trackTitle ?? ""
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.pointSize: 9
                            font.weight: Font.Medium
                        }

                        Bars {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            count: 5
                            barWidth: 3
                            maxHeight: 16
                        }
                    }

                    // ── enregistrement ──
                    Face {
                        active: win.mode === "record"

                        Rectangle {
                            id: recDot

                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10
                            height: 10
                            radius: 5
                            color: "#ff453a"

                            SequentialAnimation on opacity {
                                running: win.mode === "record" && !Recorder.paused
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 0.3
                                    duration: 700
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 700
                                }
                            }
                        }

                        StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.fmtTime(Recorder.elapsed)
                            color: "#ff453a"
                            font.pointSize: 10
                            font.weight: Font.DemiBold
                            font.features: {
                                "tnum": 1
                            }
                        }
                    }

                    // ── volume / luminosité ──
                    Face {
                        active: win.mode === "level"

                        MaterialIcon {
                            id: lvlIcon

                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.levelIcon
                            color: "white"
                            fontStyle: Tokens.font.icon.size(14).build()
                            fill: 1
                        }

                        Rectangle {
                            id: track

                            anchors.left: lvlIcon.right
                            anchors.leftMargin: 12
                            anchors.right: levelPct.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.16)

                            Rectangle {
                                height: parent.height
                                radius: 3
                                width: parent.width * Math.max(0, Math.min(1, win.levelValue))
                                color: win.pulse === "volume" && Audio.muted ? Qt.rgba(1, 1, 1, 0.35) : "white"

                                Behavior on width {
                                    SpringAnimation {
                                        spring: 5
                                        damping: 0.45
                                    }
                                }
                            }
                        }

                        StyledText {
                            id: levelPct

                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(win.levelValue * 100)
                            color: Qt.rgba(1, 1, 1, 0.8)
                            font.pointSize: 10
                            font.weight: Font.DemiBold
                            font.features: {
                                "tnum": 1
                            }
                        }
                    }

                    // ── charge ──
                    Face {
                        active: win.mode === "charge"

                        StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("En charge")
                            color: "white"
                            font.pointSize: 10
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${Math.round(win.battery * 100)} %`
                                color: "#32d74b"
                                font.pointSize: 10
                                font.weight: Font.DemiBold
                            }

                            BatteryGlyph {
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // ── notification ──
                    Face {
                        active: win.mode === "notif"

                        Rectangle {
                            id: notifIconBox

                            anchors.left: parent.left
                            anchors.leftMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            width: 46
                            height: 46
                            radius: 13
                            color: Qt.rgba(1, 1, 1, 0.08)
                            clip: true

                            Image {
                                id: notifImg

                                anchors.fill: parent
                                anchors.margins: win.notif?.image ? 0 : 8
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(92, 92)
                                source: win.notif?.image || (win.notif?.appIcon ? Quickshell.iconPath(win.notif.appIcon, true) : "")
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: notifImg.status !== Image.Ready
                                text: "notifications"
                                color: "white"
                                fontStyle: Tokens.font.icon.size(16).build()
                                fill: 1
                            }
                        }

                        Column {
                            anchors.left: notifIconBox.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: win.notif?.appName ?? ""
                                color: Qt.rgba(1, 1, 1, 0.5)
                                font.pointSize: 8
                                font.weight: Font.Medium
                            }
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: win.notif?.summary ?? ""
                                color: "white"
                                font.pointSize: 10
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                                text: (win.notif?.body ?? "").replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                                color: Qt.rgba(1, 1, 1, 0.72)
                                font.pointSize: 9
                            }
                        }
                    }

                    // ── vue étendue sans musique : heure, date, météo, batterie ──
                    Face {
                        active: win.mode === "info"

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 26
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            StyledText {
                                text: Time.format("HH:mm")
                                color: "white"
                                font.pointSize: 26
                                font.weight: Font.Bold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                            StyledText {
                                text: {
                                    const s = Time.format("dddd d MMMM");
                                    return s.charAt(0).toUpperCase() + s.slice(1);
                                }
                                color: Qt.rgba(1, 1, 1, 0.6)
                                font.pointSize: 9
                                font.weight: Font.Medium
                            }
                        }

                        Column {
                            anchors.right: parent.right
                            anchors.rightMargin: 26
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Row {
                                anchors.right: parent.right
                                spacing: 6

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Weather.icon
                                    color: Colours.palette.m3primary
                                    fontStyle: Tokens.font.icon.size(14).build()
                                    fill: 1
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Weather.cc ? Weather.temp : "—"
                                    color: "white"
                                    font.pointSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                spacing: 8
                                visible: UPower.displayDevice.isLaptopBattery

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: `${Math.round(win.battery * 100)} %`
                                    color: win.charging ? "#32d74b" : Qt.rgba(1, 1, 1, 0.8)
                                    font.pointSize: 10
                                    font.weight: Font.DemiBold
                                }
                                BatteryGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    // ── lecteur complet ──
                    Face {
                        active: win.mode === "player"

                        Cover {
                            id: bigCover

                            anchors.left: parent.left
                            anchors.leftMargin: 22
                            y: 22
                            size: 64
                            radius: 14
                        }

                        Column {
                            anchors.left: bigCover.right
                            anchors.leftMargin: 14
                            anchors.right: bigBars.left
                            anchors.rightMargin: 12
                            y: 30
                            spacing: 2

                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: win.player?.trackTitle ?? ""
                                color: "white"
                                font.pointSize: 11
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: win.player?.trackArtist || Players.getIdentity(win.player)
                                color: Qt.rgba(1, 1, 1, 0.6)
                                font.pointSize: 9
                            }
                        }

                        Bars {
                            id: bigBars

                            anchors.right: parent.right
                            anchors.rightMargin: 24
                            y: 40
                            count: 6
                            barWidth: 3
                            maxHeight: 22
                        }

                        // Progression
                        Item {
                            id: progress

                            readonly property real len: win.player?.length ?? 0
                            readonly property real pos: win.player?.position ?? 0
                            readonly property bool known: len > 0 && len < 2147483

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 22
                            anchors.rightMargin: 22
                            y: 98
                            height: 16

                            StyledText {
                                id: posText

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                text: win.fmtTime(progress.pos)
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.pointSize: 7.5
                                font.features: {
                                    "tnum": 1
                                }
                            }

                            Rectangle {
                                id: seekTrack

                                anchors.left: posText.right
                                anchors.right: lenText.left
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                height: seekArea.containsMouse ? 7 : 5
                                radius: height / 2
                                color: Qt.rgba(1, 1, 1, 0.18)

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 150
                                    }
                                }

                                Rectangle {
                                    height: parent.height
                                    radius: parent.radius
                                    width: progress.known ? parent.width * Math.min(1, progress.pos / progress.len) : 0
                                    color: "white"
                                }

                                MouseArea {
                                    id: seekArea

                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    enabled: progress.known && (win.player?.canSeek ?? false)
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: e => {
                                        const ratio = Math.max(0, Math.min(1, (e.x - 6) / seekTrack.width));
                                        win.player.position = ratio * progress.len;
                                    }
                                }
                            }

                            StyledText {
                                id: lenText

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                horizontalAlignment: Text.AlignRight
                                text: progress.known ? win.fmtTime(progress.len) : ""
                                color: Qt.rgba(1, 1, 1, 0.55)
                                font.pointSize: 7.5
                                font.features: {
                                    "tnum": 1
                                }
                            }
                        }

                        // Commandes
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 122
                            spacing: 26

                            IslandButton {
                                icon: "skip_previous"
                                enabled: win.player?.canGoPrevious ?? false
                                onClicked: win.player?.previous()
                            }
                            IslandButton {
                                icon: win.playing ? "pause" : "play_arrow"
                                big: true
                                enabled: win.player?.canTogglePlaying ?? false
                                onClicked: win.player?.togglePlaying()
                            }
                            IslandButton {
                                icon: "skip_next"
                                enabled: win.player?.canGoNext ?? false
                                onClicked: win.player?.next()
                            }
                        }
                    }
                }
            }

            // ════════════════════ Composants ════════════════════

            // Une « face » de l'île : fondu + léger zoom + flou de mouvement simulé
            component Face: Item {
                property bool active

                anchors.fill: parent
                opacity: active ? 1 : 0
                scale: active ? 1 : 0.9
                visible: opacity > 0.01
                enabled: active

                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }
            }

            component Cover: Rectangle {
                property real size: 22

                width: size
                height: size
                color: Qt.rgba(1, 1, 1, 0.1)
                clip: true

                Image {
                    id: coverImg

                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(parent.size * 2, parent.size * 2)
                    source: Players.getArtUrl(Players.active)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: coverImg.status !== Image.Ready
                    text: "music_note"
                    color: "white"
                    fontStyle: Tokens.font.icon.size(parent.size / 2.6).build()
                    fill: 1
                }
            }

            // Barres du visualiseur (cava), couleur de l'accent du thème
            component Bars: Row {
                id: bars

                property int count: 5
                property real barWidth: 3
                property real maxHeight: 16

                spacing: 2.5
                height: maxHeight

                Repeater {
                    model: bars.count

                    Rectangle {
                        required property int index
                        readonly property int total: Audio.cava.values.length
                        readonly property real v: {
                            if (!(Players.active?.isPlaying ?? false) || total === 0)
                                return 0.12;
                            // On prend des bandes réparties sur le spectre utile (basses → médiums)
                            const i = Math.floor((index + 0.5) / bars.count * total);
                            return Math.max(0.12, Math.min(1, Audio.cava.values[i] ?? 0));
                        }

                        anchors.verticalCenter: parent.verticalCenter
                        width: bars.barWidth
                        height: Math.max(bars.barWidth, bars.maxHeight * v)
                        radius: bars.barWidth / 2
                        color: Colours.palette.m3primary

                        Behavior on height {
                            NumberAnimation {
                                duration: 90
                            }
                        }
                    }
                }
            }

            component BatteryGlyph: Item {
                width: 26
                height: 12

                Rectangle {
                    width: 23
                    height: 12
                    radius: 3.5
                    color: "transparent"
                    border.width: 1.2
                    border.color: Qt.rgba(1, 1, 1, 0.5)

                    Rectangle {
                        x: 2
                        y: 2
                        height: parent.height - 4
                        width: Math.max(2, (parent.width - 4) * (UPower.displayDevice.percentage ?? 0))
                        radius: 2
                        color: !UPower.onBattery ? "#32d74b" : (UPower.displayDevice.percentage ?? 0) < 0.2 ? "#ff453a" : "white"
                    }
                }

                Rectangle {
                    x: 24
                    y: 4
                    width: 2
                    height: 4
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.5)
                }
            }

            component IslandButton: Item {
                id: btn

                property string icon
                property bool big
                signal clicked

                width: big ? 34 : 28
                height: width
                opacity: enabled ? 1 : 0.35

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "white"
                    opacity: area.pressed ? 0.18 : area.containsMouse ? 0.1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                        }
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: btn.icon
                    color: "white"
                    fontStyle: Tokens.font.icon.size(btn.big ? 18 : 14).build()
                    fill: 1
                    scale: area.pressed ? 0.85 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutBack
                        }
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: btn.clicked()
                }
            }
        }
    }
}

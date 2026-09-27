pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

// Dynamic Island façon macOS, dessinée dans le même verre que le cadre (PanelBg dans
// ContentWindow) : elle sort du haut de l'écran et se fond dans la forme fluide.
// Musique, lecteur complet au survol, volume/luminosité, notifications, charge,
// enregistrement. Molette = volume, clic = lecture/pause.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property bool fullscreen

    // ── Sources ──
    readonly property MprisPlayer player: Players.active
    readonly property bool playing: player?.isPlaying ?? false
    readonly property bool hasMedia: !!player && (player.trackTitle ?? "").length > 0
    readonly property var brightMon: Brightness.getMonitorForScreen(screen)
    readonly property real brightness: brightMon?.brightness ?? 0
    readonly property real battery: UPower.displayDevice.percentage ?? 0
    readonly property bool charging: !UPower.onBattery

    // ── Couleurs du thème (le verre suit le thème clair/sombre) ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.62)
    readonly property color fgFaint: Qt.alpha(fg, 0.16)
    readonly property color accent: Colours.palette.m3primary
    readonly property color green: Colours.light ? "#1f9d3a" : "#32d74b"
    readonly property color red: Colours.light ? "#d70015" : "#ff453a"

    // ── État ──
    property string pulse: "" // "level", "notif", "charge"
    property var notif: null
    property list<var> queue: []
    property bool ready
    property bool hovered
    property bool expanded
    property bool levelHeld // doigt/souris sur la jauge : l'île reste ouverte
    property string levelKind: "volume"
    property string levelIcon: "volume_up"
    // Valeur en direct selon le type : chaque jauge garde la sienne, pas de glissement de l'une à l'autre
    readonly property real levelValue: levelKind === "volume" ? Audio.volume : brightness

    readonly property bool hidden: !Island.enabled || fullscreen || (screenState?.dashboard ?? false)

    readonly property string mode: {
        if (hidden)
            return "hidden";
        if (pulse === "level")
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

    readonly property bool notifHasActions: (notif?.actions?.length ?? 0) > 0

    // Taille visible (depuis le haut de l'écran) pour chaque mode
    readonly property size target: {
        switch (mode) {
        case "hidden":
            return Qt.size(180, 0);
        case "level":
            return Qt.size(340, 52);
        case "notif":
            return Qt.size(430, hovered && notifHasActions ? 132 : 92);
        case "charge":
            return Qt.size(310, 48);
        case "player":
            return Qt.size(450, 178);
        case "info":
            return Qt.size(390, 118);
        case "record":
            return Qt.size(210, 40);
        case "media":
            return Qt.size(290, 40);
        default:
            // Au repos : juste l'heure (ou rien si Island.clock est coupé)
            return Island.clock ? Qt.size(hovered ? 124 : 112, 32) : Qt.size(150, 0);
        }
    }

    property real w: target.width
    property real h: target.height
    readonly property real radius: Math.min(h / 2, mode === "player" || mode === "info" || mode === "notif" ? 32 : h / 2)

    function flash(kind: string, ms: int): void {
        if (!ready)
            return;
        pulse = kind;
        pulseTimer.interval = ms;
        pulseTimer.restart();
    }

    function showNext(): void {
        while (queue.length > 0) {
            const n = queue[0];
            queue = queue.slice(1);
            if (n && !n.closed) {
                notif = n;
                flash("notif", n.urgency === 2 ? 9000 : 5000);
                return;
            }
        }
        notif = null;
    }

    function fmtTime(s: real): string {
        if (!isFinite(s) || s < 0 || s > 2147483)
            return "--:--";
        const m = Math.floor(s / 60);
        return `${m}:${Math.floor(s % 60).toString().padStart(2, "0")}`;
    }

    function setLevel(v: real): void {
        v = Math.max(0, Math.min(1, v));
        if (levelKind === "volume")
            Audio.setVolume(v);
        else
            brightMon?.setBrightness(v);
    }

    implicitWidth: w
    // Au repos, une bande invisible de 4 px en haut de l'écran garde le survol actif
    implicitHeight: Math.max(h, 4)
    clip: true

    Behavior on w {
        SpringAnimation {
            spring: 4
            damping: 0.3
            epsilon: 0.25
        }
    }
    Behavior on h {
        SpringAnimation {
            spring: 4
            damping: 0.34
            epsilon: 0.25
        }
    }

    Component.onCompleted: readyTimer.start()

    Timer {
        id: readyTimer

        interval: 1500
        onTriggered: root.ready = true
    }

    Timer {
        id: pulseTimer

        onTriggered: {
            // Survolée ou jauge tenue : on attend que la souris parte
            if (root.hovered || root.levelHeld) {
                restart();
                return;
            }
            if (root.pulse === "notif" && root.queue.length > 0) {
                root.showNext();
                return;
            }
            root.pulse = "";
            root.notif = null;
        }
    }

    Timer {
        id: hoverTimer

        interval: root.hovered ? 280 : 420
        onTriggered: root.expanded = root.hovered && root.pulse === ""
    }

    onHoveredChanged: hoverTimer.restart()

    // ── Déclencheurs ──
    Connections {
        target: Audio

        function onVolumeChanged(): void {
            root.levelKind = "volume";
            root.levelIcon = Audio.muted || Audio.volume <= 0 ? "volume_off" : Audio.volume < 0.34 ? "volume_mute" : Audio.volume < 0.67 ? "volume_down" : "volume_up";
            root.flash("level", 1700);
        }

        function onMutedChanged(): void {
            onVolumeChanged();
        }
    }

    onBrightnessChanged: {
        levelKind = "brightness";
        levelIcon = brightness < 0.34 ? "brightness_low" : brightness < 0.67 ? "brightness_medium" : "brightness_high";
        flash("level", 1700);
    }

    onChargingChanged: {
        if (UPower.displayDevice.ready && charging)
            flash("charge", 2800);
    }

    Connections {
        target: Island

        function onNotify(n: var): void {
            if (!root.ready)
                return;
            if (root.pulse === "notif" && root.notif) {
                root.queue = [...root.queue, n];
                return;
            }
            root.queue = [n];
            root.showNext();
        }
    }

    // Petit rebond quand un évènement arrive
    onPulseChanged: if (pulse === "notif" || pulse === "charge") bump.restart()

    SequentialAnimation {
        id: bump

        NumberAnimation {
            target: content
            property: "scale"
            to: 1.05
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: content
            property: "scale"
            to: 1
            duration: 460
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }
    }

    Timer {
        running: root.mode === "player" && root.playing
        interval: 500
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    ServiceRef {
        service: root.playing ? Audio.cava : null
    }

    // ── Interactions ──
    HoverHandler {
        onHoveredChanged: root.hovered = hovered
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
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onTapped: (_, button) => {
            if (root.mode === "notif") {
                const n = root.notif;
                if (n?.actions?.length > 0)
                    n.actions[0].invoke();
                pulseTimer.stop();
                root.pulse = "";
                root.showNext();
            } else if (button === Qt.MiddleButton || root.mode === "media") {
                root.player?.togglePlaying();
            } else if (root.mode === "idle") {
                root.expanded = true;
            }
        }
    }

    // ════════════════════ Contenu ════════════════════
    Item {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        width: root.w
        height: root.h
        transformOrigin: Item.Top

        // ── repos : l'heure ──
        Face {
            active: root.mode === "idle"

            StyledText {
                anchors.centerIn: parent
                text: Time.format("HH:mm")
                color: root.fg
                font.pointSize: 10.5
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── musique compacte ──
        Face {
            active: root.mode === "media"

            Cover {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                size: 24
                radius: 7
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - 140
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.player?.trackTitle ?? ""
                color: root.fg
                font.pointSize: 9
                font.weight: Font.Medium
            }

            Bars {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                count: 5
                barWidth: 3
                maxHeight: 16
            }
        }

        // ── enregistrement ──
        Face {
            active: root.mode === "record"

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: root.red

                SequentialAnimation on opacity {
                    running: root.mode === "record" && !Recorder.paused
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
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtTime(Recorder.elapsed)
                color: root.red
                font.pointSize: 10
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── volume / luminosité, façon macOS : jauge épaisse, icône dedans, glissable ──
        Face {
            active: root.mode === "level"

            Rectangle {
                id: gauge

                anchors.left: parent.left
                anchors.right: pct.left
                anchors.leftMargin: 18
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: gaugeArea.pressed ? 26 : 22
                radius: height / 2
                color: root.fgFaint
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                // Une jauge par type (volume, luminosité), chacune liée à sa propre valeur
                Repeater {
                    model: ["volume", "brightness"]

                    Rectangle {
                        required property string modelData
                        readonly property real value: modelData === "volume" ? Audio.volume : root.brightness

                        visible: root.levelKind === modelData
                        height: parent.height
                        radius: parent.radius
                        width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, value)))
                        color: modelData === "volume" && Audio.muted ? Qt.alpha(root.fg, 0.35) : root.fg

                        Behavior on width {
                            enabled: !gaugeArea.pressed

                            SpringAnimation {
                                spring: 5
                                damping: 0.42
                            }
                        }
                    }
                }

                // L'icône change de couleur selon la partie remplie qu'elle recouvre
                MaterialIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.levelIcon
                    color: root.levelValue > 0.08 ? Colours.palette.m3surface : root.fg
                    fontStyle: Tokens.font.icon.size(11).build()
                    fill: 1
                }

                MouseArea {
                    id: gaugeArea

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: e => {
                        root.levelHeld = true;
                        root.setLevel(e.x / width);
                    }
                    onPositionChanged: e => {
                        if (pressed)
                            root.setLevel(e.x / width);
                    }
                    onReleased: root.levelHeld = false
                    onCanceled: root.levelHeld = false
                }
            }

            StyledText {
                id: pct

                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                horizontalAlignment: Text.AlignRight
                text: Math.round(root.levelValue * 100)
                color: root.fgDim
                font.pointSize: 10
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }
        }

        // ── charge ──
        Face {
            active: root.mode === "charge"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "bolt"
                    color: root.green
                    fontStyle: Tokens.font.icon.size(13).build()
                    fill: 1
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("En charge")
                    color: root.fg
                    font.pointSize: 10
                    font.weight: Font.DemiBold
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Math.round(root.battery * 100)} %`
                    color: root.green
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
            active: root.mode === "notif"

            Rectangle {
                id: notifIconBox

                x: 22
                y: 22
                width: 48
                height: 48
                radius: 14
                color: root.fgFaint
                clip: true

                Image {
                    id: notifImg

                    anchors.fill: parent
                    anchors.margins: root.notif?.image ? 0 : 8
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(96, 96)
                    source: root.notif?.image || (root.notif?.appIcon ? Quickshell.iconPath(root.notif.appIcon, true) : "")
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: notifImg.status !== Image.Ready
                    text: "notifications"
                    color: root.fg
                    fontStyle: Tokens.font.icon.size(16).build()
                    fill: 1
                }
            }

            Column {
                anchors.left: notifIconBox.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: notifIconBox.verticalCenter
                spacing: 1

                Item {
                    width: parent.width
                    height: appLbl.height

                    StyledText {
                        id: appLbl

                        anchors.left: parent.left
                        anchors.right: moreLbl.left
                        elide: Text.ElideRight
                        text: root.notif?.appName ?? ""
                        color: root.fgDim
                        font.pointSize: 8
                        font.weight: Font.Medium
                    }
                    StyledText {
                        id: moreLbl

                        anchors.right: parent.right
                        text: root.queue.length > 0 ? `+${root.queue.length}` : qsTr("maintenant")
                        color: root.queue.length > 0 ? root.accent : root.fgDim
                        font.pointSize: 8
                        font.weight: Font.Medium
                    }
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.notif?.summary ?? ""
                    color: root.fg
                    font.pointSize: 10
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    text: (root.notif?.body ?? "").replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                    color: Qt.alpha(root.fg, 0.78)
                    font.pointSize: 9
                }
            }

            // Actions au survol
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 88
                spacing: 8
                opacity: root.hovered && root.notifHasActions ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Repeater {
                    model: (root.notif?.actions ?? []).slice(0, 3)

                    Rectangle {
                        id: act

                        required property var modelData

                        width: Math.max(90, actLbl.implicitWidth + 28)
                        height: 30
                        radius: 15
                        color: actArea.containsMouse ? Qt.alpha(root.fg, 0.2) : Qt.alpha(root.fg, 0.1)

                        StyledText {
                            id: actLbl

                            anchors.centerIn: parent
                            text: act.modelData.text
                            color: root.fg
                            font.pointSize: 9
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: actArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                act.modelData.invoke();
                                pulseTimer.stop();
                                root.pulse = "";
                                root.showNext();
                            }
                        }
                    }
                }
            }
        }

        // ── survol sans musique : heure, date, météo, batterie ──
        Face {
            active: root.mode === "info"

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 4

                StyledText {
                    text: Time.format("HH:mm")
                    color: root.fg
                    font.pointSize: 26
                    font.weight: Font.Bold
                    font.features: {
                        "tnum": 1
                    }
                }
                StyledText {
                    text: {
                        const s = Qt.locale("fr_FR").toString(Time.date, "dddd d MMMM");
                        return s.charAt(0).toUpperCase() + s.slice(1);
                    }
                    color: root.fgDim
                    font.pointSize: 9
                    font.weight: Font.Medium
                }
            }

            Column {
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 4
                spacing: 8

                Row {
                    anchors.right: parent.right
                    spacing: 6

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.icon
                        color: root.accent
                        fontStyle: Tokens.font.icon.size(14).build()
                        fill: 1
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.cc ? Weather.temp : "—"
                        color: root.fg
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
                        text: `${Math.round(root.battery * 100)} %`
                        color: root.charging ? root.green : root.fgDim
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
            active: root.mode === "player"

            Cover {
                id: bigCover

                x: 26
                y: 26
                size: 66
                radius: 15
            }

            Column {
                anchors.left: bigCover.right
                anchors.leftMargin: 14
                anchors.right: bigBars.left
                anchors.rightMargin: 12
                anchors.verticalCenter: bigCover.verticalCenter
                spacing: 2

                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackTitle ?? ""
                    color: root.fg
                    font.pointSize: 11
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackArtist || Players.getIdentity(root.player)
                    color: root.fgDim
                    font.pointSize: 9
                }
            }

            Bars {
                id: bigBars

                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: bigCover.verticalCenter
                count: 6
                barWidth: 3
                maxHeight: 22
            }

            Item {
                id: progress

                readonly property real len: root.player?.length ?? 0
                readonly property real pos: root.player?.position ?? 0
                readonly property bool known: len > 0 && len < 2147483

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                y: 104
                height: 16

                StyledText {
                    id: posText

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    text: root.fmtTime(progress.pos)
                    color: root.fgDim
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
                    height: seekArea.containsMouse ? 8 : 5
                    radius: height / 2
                    color: root.fgFaint

                    Behavior on height {
                        NumberAnimation {
                            duration: 150
                        }
                    }

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width: progress.known ? parent.width * Math.min(1, progress.pos / progress.len) : 0
                        color: root.fg
                    }

                    MouseArea {
                        id: seekArea

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        enabled: progress.known && (root.player?.canSeek ?? false)
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: e => {
                            const ratio = Math.max(0, Math.min(1, (e.x - 6) / seekTrack.width));
                            root.player.position = ratio * progress.len;
                        }
                    }
                }

                StyledText {
                    id: lenText

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    horizontalAlignment: Text.AlignRight
                    text: progress.known ? root.fmtTime(progress.len) : ""
                    color: root.fgDim
                    font.pointSize: 7.5
                    font.features: {
                        "tnum": 1
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 128
                spacing: 28

                IslandButton {
                    icon: "skip_previous"
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.player?.previous()
                }
                IslandButton {
                    icon: root.playing ? "pause" : "play_arrow"
                    big: true
                    enabled: root.player?.canTogglePlaying ?? false
                    onClicked: root.player?.togglePlaying()
                }
                IslandButton {
                    icon: "skip_next"
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player?.next()
                }
            }
        }
    }

    // ════════════════════ Composants ════════════════════

    component Face: Item {
        property bool active

        anchors.fill: parent
        opacity: active ? 1 : 0
        scale: active ? 1 : 0.88
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
                duration: 400
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }
    }

    component Cover: Rectangle {
        property real size: 22

        width: size
        height: size
        color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
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
            color: Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.size(parent.size / 2.6).build()
            fill: 1
        }
    }

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
                        return 0.15;
                    const i = Math.floor((index + 0.5) / bars.count * total);
                    return Math.max(0.15, Math.min(1, Audio.cava.values[i] ?? 0));
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
        readonly property real pct: UPower.displayDevice.percentage ?? 0
        readonly property color fg: Colours.palette.m3onSurface

        width: 26
        height: 12

        Rectangle {
            width: 23
            height: 12
            radius: 3.5
            color: "transparent"
            border.width: 1.2
            border.color: Qt.alpha(parent.fg, 0.5)

            Rectangle {
                x: 2
                y: 2
                height: parent.height - 4
                width: Math.max(2, (parent.width - 4) * parent.parent.pct)
                radius: 2
                color: !UPower.onBattery ? (Colours.light ? "#1f9d3a" : "#32d74b") : parent.parent.pct < 0.2 ? "#ff453a" : parent.parent.fg
            }
        }

        Rectangle {
            x: 24
            y: 4
            width: 2
            height: 4
            radius: 1
            color: Qt.alpha(parent.fg, 0.5)
        }
    }

    component IslandButton: Item {
        id: btn

        property string icon
        property bool big
        signal clicked

        width: big ? 36 : 30
        height: width
        opacity: enabled ? 1 : 0.35

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colours.palette.m3onSurface
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
            color: Colours.palette.m3onSurface
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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// Centre de contrôle façon macOS 27 (Super + A), dessiné dans le verre du cadre en haut à droite :
// connexions (Wi-Fi, Bluetooth, VPN) avec leurs listes, Ne pas déranger, lecteur, luminosité,
// son et sortie audio, raccourcis rapides, énergie, icônes système et session.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState

    readonly property bool shown: screenState?.controlCenter ?? false
    // ── Ouverture façon Dynamic Island : le verre jaillit de l'île et file vers le coin haut droit ──
    property Item island
    property real morph: shown ? 1 : 0
    readonly property real offsetScale: 1 - morph
    property real fromX // position de l'île à l'ouverture (repère du parent)
    property real fromW: 240
    property real fromBottom: 40
    // Pas de rebond sur l'horizontale (il sortirait de l'écran) : seulement vers le bas
    readonly property real hMorph: Math.min(1, morph)
    readonly property real curX: fromX + (x - fromX) * hMorph
    readonly property real curW: fromW + (width - fromW) * hMorph
    readonly property real curBottom: fromBottom + (y + height - fromBottom) * morph
    property string page: "main" // main, wifi, bt, audio, record

    // Choix d'enregistrement, retenus d'une fois sur l'autre
    property bool recRegion: false
    property bool recSound: true
    property bool recMic: false
    property bool recCountdown: true
    property bool recCopy: false

    function saveRecPrefs(): void {
        recPrefs.setText(JSON.stringify({
            region: recRegion,
            sound: recSound,
            mic: recMic,
            countdown: recCountdown,
            copy: recCopy
        }));
    }

    function startRecording(): void {
        saveRecPrefs();
        const args = [];
        if (recSound)
            args.push("-s");
        if (recMic)
            args.push("-m");
        if (recCopy)
            args.push("-c");
        if (recRegion)
            args.push("-r");
        close();
        // Compte à rebours dans l'île (plein écran seulement : la zone se choisit au lancement)
        Island.recordRequest(args, recCountdown && !recRegion ? 3 : 0);
    }

    FileView {
        id: recPrefs

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/record-prefs.json`
        printErrors: false
        onLoaded: {
            try {
                const p = JSON.parse(text());
                root.recRegion = !!p.region;
                root.recSound = p.sound ?? true;
                root.recMic = !!p.mic;
                root.recCountdown = p.countdown ?? true;
                root.recCopy = !!p.copy;
            } catch (e) {}
        }
    }

    // ── Couleurs matérielles & horlogères (cohérentes avec la Dynamic Island) ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.62)
    readonly property color fgFaint: Qt.alpha(fg, 0.12)
    readonly property color tileColour: Qt.alpha(fg, Colours.light ? 0.055 : 0.065)
    readonly property color tileBorder: Qt.alpha(fg, Colours.light ? 0.12 : 0.14)
    readonly property color accent: Colours.palette.m3primary
    readonly property color onAccent: Colours.palette.m3onPrimary
    readonly property color green: Colours.light ? "#1f8f3a" : "#32d74b"
    readonly property color red: Colours.light ? "#d70015" : "#ff453a"
    readonly property color amber: Colours.light ? "#c77700" : "#ff9f0a"

    readonly property MprisPlayer player: Players.active
    readonly property bool playing: player?.isPlaying ?? false
    readonly property real rawBass: {
        if (!shown || !playing || Audio.cava.values.length === 0)
            return 0;
        const n = Math.min(4, Audio.cava.values.length);
        let s = 0;
        for (let i = 0; i < n; i++)
            s += Audio.cava.values[i] ?? 0;
        return Math.min(1, s / n);
    }
    property real bassLevel: rawBass
    Behavior on bassLevel {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutQuad
        }
    }

    function fmtTime(sec: real): string {
        if (!(sec > 0))
            return "0:00";
        const s = Math.floor(sec);
        const m = Math.floor(s / 60);
        const r = s % 60;
        return `${m}:${r.toString().padStart(2, "0")}`;
    }

    readonly property var brightMon: Brightness.getMonitorForScreen(screen)
    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property list<BluetoothDevice> btConnected: Bluetooth.devices.values.filter(d => d.connected)

    // Caféine : dernière durée choisie (minutes, 0 = sans limite)
    property int caffMinutes: 0

    function idleName(action: var): string {
        const a = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        if (a === "lock")
            return qsTr("Verrouiller");
        if (a.includes("dpms"))
            return qsTr("Éteindre l'écran");
        if (a.includes("hibernate") && !a.includes("suspend"))
            return qsTr("Hiberner");
        if (a.includes("suspend") || a.includes("sleep"))
            return qsTr("Mettre en veille");
        return a;
    }

    function idleIcon(action: var): string {
        const a = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        return a === "lock" ? "lock" : a.includes("dpms") ? "desktop_access_disabled" : "bedtime";
    }

    function setIdle(index: int, key: string, value: var): void {
        const list = GlobalConfig.general.idle.timeouts.map(t => Object.assign({}, t));
        list[index][key] = value;
        GlobalConfig.general.idle.timeouts = list;
    }

    function close(): void {
        screenState.controlCenter = false;
    }

    // ── Concentration : choix préparés avant d'activer ──
    property string focusSel: FocusMode.lastMode
    property int focusMinutes: FocusMode.lastMinutes
    property var focusOpts: Object.assign({}, FocusMode.modes[FocusMode.lastMode] ?? FocusMode.modes.dnd)

    function focusPick(m: string): void {
        focusSel = m;
        focusOpts = Object.assign({}, FocusMode.modes[m]);
        if (FocusMode.active && FocusMode.mode !== m)
            FocusMode.start(m, focusMinutes, focusOpts);
    }

    function focusOpt(key: string): bool {
        return FocusMode.active ? FocusMode[key] : !!focusOpts[key];
    }

    function focusSetOpt(key: string, value: bool): void {
        if (FocusMode.active) {
            FocusMode.setOption(key, value);
        } else {
            const o = Object.assign({}, focusOpts);
            o[key] = value;
            focusOpts = o;
        }
    }

    function focusToggle(): void {
        if (FocusMode.active)
            FocusMode.stop(false);
        else
            FocusMode.start(focusSel, focusMinutes, focusOpts);
    }

    // La page Batterie demande la liste des apps gourmandes seulement quand elle est affichée
    readonly property bool batteryShown: shown && page === "battery"
    onBatteryShownChanged: BatteryInfo.consumersRefs += batteryShown ? 1 : -1

    function appName(key: string): string {
        const special = ({ quickshell: "Caelestia", qs: "Caelestia", Hyprland: "Hyprland", kitty: "Terminal (kitty)", claude: "Claude Code", node: "Node.js", pipewire: "Son (PipeWire)", wireplumber: "Son (PipeWire)" })[key];
        if (special)
            return special;
        const e = DesktopEntries.byId(key) ?? DesktopEntries.heuristicLookup(key);
        return e?.name || (key.charAt(0).toUpperCase() + key.slice(1));
    }

    function appIcon(key: string): string {
        if (key === "quickshell" || key === "qs")
            return Quickshell.iconPath("preferences-desktop", "application-x-executable");
        if (key === "claude")
            return Quickshell.iconPath("claude-desktop", "utilities-terminal");
        const e = DesktopEntries.byId(key) ?? DesktopEntries.heuristicLookup(key);
        const icon = e?.icon ?? key;
        return icon.startsWith("/") ? `file://${icon}` : Quickshell.iconPath(icon, "application-x-executable");
    }

    // ── Projection (outil caelestia-display-pro, piloté sans fenêtre) ──
    readonly property string displayTool: `${Quickshell.env("HOME")}/.local/bin/caelestia-display-pro`
    property string projMode: "internal"
    property list<var> projExternals: []
    property string projMessage: ""
    property string projPending: ""

    Process {
        id: projStatus

        command: [root.displayTool, "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.projMode = d.mode ?? "internal";
                    root.projExternals = d.externals ?? [];
                } catch (e) {}
            }
        }
    }
    Process {
        id: projApply

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.projMessage = d.ok ? "" : (d.message ?? "");
                } catch (e) {}
                root.projPending = "";
                projStatus.running = true;
            }
        }
    }
    Timer {
        running: root.shown && root.page === "display"
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!projStatus.running) projStatus.running = true
    }

    function setProjection(mode: string): void {
        if (projApply.running)
            return;
        projPending = mode;
        projMessage = "";
        projApply.command = [displayTool, "--mode", mode];
        projApply.running = true;
    }

    // ── Fermeture quand la souris s'en va (comme le menu du Dock) ──
    // Le centre capture la souris : le survol n'est pas fiable, on lit la vraie position du curseur.
    property bool cursorAway
    property real trayMenuUntil: 0 // menu d'une icône système ouvert (il déborde du panneau)

    Process {
        id: cursorProc

        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text);
                    const mon = Hyprland.monitorFor(root.screen);
                    const o = root.mapToItem(QsWindow.window.contentItem, 0, 0);
                    const x = c.x - (mon?.x ?? 0) - o.x;
                    const y = c.y - (mon?.y ?? 0) - o.y;
                    const m = 24; // marge tolérée autour du panneau
                    const inside = x >= -m && x <= root.width + m && y <= root.height + m;
                    if (inside)
                        root.trayMenuUntil = 0;
                    root.cursorAway = !inside && Date.now() > root.trayMenuUntil;
                } catch (e) {}
            }
        }
    }
    Timer {
        running: root.shown
        repeat: true
        interval: 250
        onTriggered: cursorProc.running = true
        onRunningChanged: root.cursorAway = false
    }
    Timer {
        running: root.shown && root.cursorAway
        interval: 700
        onTriggered: {
            // On n'interrompt pas une saisie (mot de passe Wi-Fi)
            const f = root.Window.activeFocusItem;
            if (!(f && f.cursorPosition !== undefined && f.text?.length > 0))
                root.close();
        }
    }

    function run(cmd: list<string>): void {
        Quickshell.execDetached(cmd);
    }

    visible: morph > 0.001
    implicitWidth: 400
    implicitHeight: pages.height + 28

    onShownChanged: {
        if (shown) {
            if (island && island.h > 1) {
                fromX = island.x;
                fromW = island.w;
                fromBottom = island.y + island.h;
            } else {
                fromX = island ? island.x + island.width / 2 - 120 : x;
                fromW = 240;
                fromBottom = island ? island.y + 40 : y + 40;
            }
            page = "main";
            focusScope.forceActiveFocus();
        }
    }

    Behavior on morph {
        NumberAnimation {
            duration: root.shown ? 600 : 380
            easing.type: root.shown ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 0.6
        }
    }

    // Le contenu est découpé à la forme du verre qui grandit, puis se pose en fondu + léger zoom
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.45) / 0.55))

    Item {
        id: ccClipper

        x: root.curX - root.x
        y: -400
        width: Math.max(0, root.curW)
        height: Math.max(0, root.curBottom - root.y + 400)
        clip: root.morph < 0.999

    FocusScope {
        id: focusScope

        // Accroché au bord droit du verre : il voyage avec lui
        x: ccClipper.width - root.width
        y: -ccClipper.y
        width: root.width
        height: root.height
        focus: root.shown
        opacity: root.reveal
        scale: 0.92 + 0.08 * root.reveal
        transformOrigin: Item.Top
        Keys.onEscapePressed: {
            if (root.page !== "main")
                root.page = "main";
            else
                root.close();
        }

        // Pages : la principale glisse à gauche quand une liste s'ouvre
        Item {
            id: pages

            x: 14
            y: 14
            width: parent.width - 28
            height: root.page === "main" ? mainPage.implicitHeight : root.page === "record" ? recordPage.implicitHeight + 50 : root.page === "caffeine" ? caffPage.implicitHeight + 50 : root.page === "display" ? displayPage.implicitHeight + 50 : root.page === "battery" ? batteryPage.implicitHeight + 50 : root.page === "focus" ? focusPage.implicitHeight + 50 : 470
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }

            // ════════════════════ Page principale ════════════════════
            ColumnLayout {
                id: mainPage

                width: pages.width
                x: root.page === "main" ? 0 : -pages.width * 0.3
                opacity: root.page === "main" ? 1 : 0
                visible: opacity > 0.01
                spacing: 10

                Behavior on x {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 240
                    }
                }

                // ── Connexions + Concentration / Apparence ──
                Row {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 176
                    spacing: 10

                    Tile {
                        width: mainPage.width - 160
                        height: 176

                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            ConnRow {
                                icon: Nmcli.wifiEnabled ? "wifi" : "wifi_off"
                                title: qsTr("Wi-Fi")
                                subtitle: !Nmcli.wifiEnabled ? qsTr("Désactivé") : Nmcli.active?.ssid ?? (Nmcli.activeEthernet ? qsTr("Ethernet") : qsTr("Non connecté"))
                                badgeText: Nmcli.wifiEnabled && Nmcli.active ? `${Nmcli.active.strength} %` : ""
                                hasSubpage: true
                                on: Nmcli.wifiEnabled
                                onToggle: Nmcli.toggleWifi()
                                onOpen: {
                                    Nmcli.rescanWifi();
                                    root.page = "wifi";
                                }
                            }
                            ConnRow {
                                icon: root.adapter?.enabled ? "bluetooth" : "bluetooth_disabled"
                                title: qsTr("Bluetooth")
                                subtitle: !root.adapter?.enabled ? qsTr("Désactivé") : root.btConnected.length > 0 ? root.btConnected.map(d => d.name).join(", ") : qsTr("Activé")
                                badgeText: root.btConnected.length > 0 && root.btConnected[0].batteryAvailable ? `${Math.round(root.btConnected[0].battery * 100)} %` : root.btConnected.length > 1 ? `${root.btConnected.length}` : ""
                                hasSubpage: true
                                on: root.adapter?.enabled ?? false
                                onToggle: {
                                    if (root.adapter)
                                        root.adapter.enabled = !root.adapter.enabled;
                                }
                                onOpen: root.page = "bt"
                            }
                            ConnRow {
                                icon: "vpn_key"
                                title: qsTr("VPN")
                                subtitle: VPN.connecting ? qsTr("Connexion…") : VPN.connected ? qsTr("Tunnel chiffré actif") : qsTr("Déconnecté")
                                badgeText: VPN.connected ? qsTr("ACTIF") : ""
                                activeTint: root.green
                                on: VPN.connected
                                onToggle: VPN.toggle()
                                onOpen: VPN.toggle()
                            }
                        }
                    }

                    Column {
                        width: 150
                        spacing: 10

                        WideToggle {
                            width: parent.width
                            icon: FocusMode.active ? FocusMode.info.icon : Notifs.dnd ? "do_not_disturb_on" : "do_not_disturb_off"
                            title: qsTr("Concentration")
                            subtitle: FocusMode.active ? FocusMode.info.name : Notifs.dnd ? qsTr("Ne pas déranger") : qsTr("Désactivée")
                            activeTint: FocusMode.active ? (FocusMode.info.tint ?? root.accent) : root.accent
                            hasSubpage: true
                            on: FocusMode.active || Notifs.dnd
                            onClicked: root.page = "focus"
                        }
                        WideToggle {
                            width: parent.width
                            icon: Colours.light ? "light_mode" : "dark_mode"
                            title: qsTr("Apparence")
                            subtitle: Colours.light ? qsTr("Mode clair") : qsTr("Mode sombre")
                            on: !Colours.light
                            onClicked: Colours.setMode(Colours.light ? "dark" : "light")
                        }
                    }
                }

                // ── Lecteur Studio (halo basse, spectre Cava, barre de progression tactile) ──
                Tile {
                    id: ccPlayerTile

                    readonly property real len: root.player?.length ?? 0
                    readonly property real pos: root.player?.position ?? 0
                    readonly property bool known: len > 0 && len < 2147483
                    readonly property real playRatio: known ? Math.max(0, Math.min(1, pos / len)) : 0

                    Layout.fillWidth: true
                    Layout.preferredHeight: known ? 96 : 78
                    visible: !!root.player

                    // Halo réactif aux basses sous la pochette
                    Rectangle {
                        anchors.centerIn: ccCover
                        width: ccCover.width + 8
                        height: ccCover.height + 8
                        radius: ccCover.radius + 3
                        scale: 1 + root.bassLevel * 0.12
                        opacity: root.playing ? 0.16 + root.bassLevel * 0.42 : 0
                        color: Qt.alpha(root.accent, 0.5)
                        border.width: 0.5
                        border.color: Qt.alpha("#ffffff", 0.22 + root.bassLevel * 0.3)
                    }

                    Rectangle {
                        id: ccCover

                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        y: 12
                        width: 52
                        height: 52
                        radius: 13
                        color: root.fgFaint
                        clip: true

                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(104, 104)
                            source: Players.getArtUrl(root.player)
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 0.5
                            border.color: Qt.alpha("#ffffff", 0.22)
                        }
                    }

                    Column {
                        anchors.left: ccCover.right
                        anchors.leftMargin: 12
                        anchors.right: ccControls.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: ccCover.verticalCenter
                        spacing: 1

                        Row {
                            spacing: 6

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (Players.getIdentity(root.player) || qsTr("Audio")).toUpperCase()
                                color: root.accent
                                font.pointSize: 6.8
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }

                            // Mini spectre 4 bandes Cava en direct
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1.5
                                height: 9
                                visible: root.playing

                                Repeater {
                                    model: 4

                                    Rectangle {
                                        required property int index
                                        readonly property real v: root.shown && root.playing && Audio.cava.values.length > 0 ? (Audio.cava.values[index * 2] ?? 0.2) : 0.2

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 2
                                        height: Math.max(2.5, Math.min(9, 2.5 + v * 7))
                                        radius: 1
                                        color: index % 2 === 0 ? root.accent : "#38bdf8"

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 85
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.player?.trackTitle || qsTr("Rien en lecture")
                            color: root.fg
                            font.pointSize: 10.2
                            font.weight: Font.Bold
                        }
                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.player?.trackArtist || Players.getIdentity(root.player)
                            color: root.fgDim
                            font.pointSize: 8.5
                        }
                    }

                    Row {
                        id: ccControls

                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: ccCover.verticalCenter
                        spacing: 4

                        IconBtn {
                            icon: "skip_previous"
                            onClicked: root.player?.previous()
                        }
                        IconBtn {
                            icon: root.player?.isPlaying ? "pause" : "play_arrow"
                            big: true
                            onClicked: root.player?.togglePlaying()
                        }
                        IconBtn {
                            icon: "skip_next"
                            onClicked: root.player?.next()
                        }
                    }

                    // Piste de progression et scrubbing direct
                    Item {
                        visible: ccPlayerTile.known
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 8
                        height: 14

                        StyledText {
                            id: ccPosLbl

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            text: root.fmtTime(ccPlayerTile.pos)
                            color: root.fgDim
                            font.pointSize: 7.2
                            font.features: {
                                "tnum": 1
                            }
                        }

                        Rectangle {
                            id: ccSeekBar

                            anchors.left: ccPosLbl.right
                            anchors.right: ccLenLbl.left
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            height: ccSeekArea.containsMouse ? 5 : 3.5
                            radius: height / 2
                            color: Qt.alpha(root.fg, 0.12)

                            Behavior on height {
                                NumberAnimation {
                                    duration: 120
                                }
                            }

                            Rectangle {
                                width: parent.width * ccPlayerTile.playRatio
                                height: parent.height
                                radius: parent.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: root.accent }
                                    GradientStop { position: 1.0; color: "#38bdf8" }
                                }
                            }

                            MouseArea {
                                id: ccSeekArea

                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                enabled: ccPlayerTile.known && (root.player?.canSeek ?? false)
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: e => {
                                    const r = Math.max(0, Math.min(1, (e.x - 5) / Math.max(1, ccSeekBar.width)));
                                    root.player.position = r * ccPlayerTile.len;
                                }
                            }
                        }

                        StyledText {
                            id: ccLenLbl

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            horizontalAlignment: Text.AlignRight
                            text: root.fmtTime(ccPlayerTile.len)
                            color: root.fgDim
                            font.pointSize: 7.2
                            font.features: {
                                "tnum": 1
                            }
                        }
                    }
                }

                // ── Luminosité & Écran ──
                Tile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 74

                    Row {
                        x: 14
                        y: 9
                        spacing: 7

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("ÉCRAN")
                            color: root.fgDim
                            font.pointSize: 7.2
                            font.weight: Font.Bold
                            font.letterSpacing: 0.7
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: brightPctTxt.implicitWidth + 10
                            height: 16
                            radius: 5
                            color: Qt.alpha(root.fg, 0.06)
                            border.width: 0.5
                            border.color: Qt.alpha(root.fg, 0.12)

                            StyledText {
                                id: brightPctTxt

                                anchors.centerIn: parent
                                text: `${Math.round((root.brightMon?.brightness ?? 0) * 100)} %`
                                color: root.fg
                                font.pointSize: 7.8
                                font.weight: Font.Bold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                        }
                    }

                    // Éclairage de nuit / projection → page Écran
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        y: 6
                        width: scrRow.implicitWidth + 16
                        height: 22
                        radius: 11
                        color: scrArea.containsMouse ? Qt.alpha(root.fg, 0.1) : Qt.alpha(root.fg, 0.04)
                        border.width: 0.5
                        border.color: NightLight.enabled ? Qt.alpha(root.amber, 0.4) : Qt.alpha(root.fg, 0.12)

                        Row {
                            id: scrRow

                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: NightLight.enabled
                                text: "nightlight"
                                color: root.amber
                                fontStyle: Tokens.font.icon.size(11).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: NightLight.enabled ? qsTr("Nuit · %1 K").arg(NightLight.temperature) : root.projMode === "duplicate" ? qsTr("Dupliqué") : root.projMode === "extend" ? qsTr("Étendu") : root.projMode === "external" ? qsTr("Second écran") : qsTr("Nuit, projection")
                                color: NightLight.enabled ? root.amber : root.fgDim
                                font.pointSize: 7.8
                                font.weight: Font.DemiBold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "chevron_right"
                                color: root.fgDim
                                fontStyle: Tokens.font.icon.size(11).build()
                            }
                        }

                        MouseArea {
                            id: scrArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = "display"
                        }
                    }

                    GlassSlider {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        icon: "light_mode"
                        value: root.brightMon?.brightness ?? 0
                        onMoved: v => root.brightMon?.setBrightness(v)
                    }
                }

                // ── Audio & Sortie ──
                Tile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 74

                    Row {
                        x: 14
                        y: 9
                        spacing: 7

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("AUDIO")
                            color: root.fgDim
                            font.pointSize: 7.2
                            font.weight: Font.Bold
                            font.letterSpacing: 0.7
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: volPctTxt.implicitWidth + 10
                            height: 16
                            radius: 5
                            color: Audio.muted ? Qt.alpha(root.red, 0.14) : Qt.alpha(root.fg, 0.06)
                            border.width: 0.5
                            border.color: Audio.muted ? Qt.alpha(root.red, 0.35) : Qt.alpha(root.fg, 0.12)

                            StyledText {
                                id: volPctTxt

                                anchors.centerIn: parent
                                text: Audio.muted ? qsTr("MUET") : `${Math.round(Audio.volume * 100)} %`
                                color: Audio.muted ? root.red : root.fg
                                font.pointSize: 7.8
                                font.weight: Font.Bold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                        }
                    }

                    // Sortie audio actuelle → console audio complète
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        y: 6
                        width: outRow.implicitWidth + 16
                        height: 22
                        radius: 11
                        color: outArea.containsMouse ? Qt.alpha(root.fg, 0.1) : Qt.alpha(root.fg, 0.04)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.12)

                        Row {
                            id: outRow

                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (Audio.sink?.name ?? "").startsWith("bluez") ? "headphones" : (Audio.sink?.name ?? "").includes("hdmi") ? "tv" : "speaker"
                                color: root.accent
                                fontStyle: Tokens.font.icon.size(11).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 175)
                                elide: Text.ElideRight
                                text: Audio.sink?.description || Audio.sink?.nickname || Audio.sink?.name || ""
                                color: root.fgDim
                                font.pointSize: 7.8
                                font.weight: Font.DemiBold
                            }
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "chevron_right"
                                color: root.fgDim
                                fontStyle: Tokens.font.icon.size(11).build()
                            }
                        }

                        MouseArea {
                            id: outArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = "audio"
                        }
                    }

                    GlassSlider {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        icon: Audio.muted ? "volume_off" : "volume_up"
                        value: Audio.volume
                        dim: Audio.muted
                        onMoved: v => Audio.setVolume(v)
                        onIconClicked: {
                            if (Audio.sink?.audio)
                                Audio.sink.audio.muted = !Audio.sink.audio.muted;
                        }
                    }
                }

                // ── Raccourcis rapides (grille matérielle 4×2 biseautée) ──
                Tile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: grid.implicitHeight + 20

                    Grid {
                        id: grid

                        anchors.centerIn: parent
                        columns: 4
                        columnSpacing: 8
                        rowSpacing: 8

                        RoundToggle {
                            icon: "coffee"
                            label: IdleInhibitor.enabled ? IdleInhibitor.remainingText() : qsTr("Caféine")
                            on: IdleInhibitor.enabled
                            onClicked: root.page = "caffeine"
                        }
                        RoundToggle {
                            icon: "sports_esports"
                            label: qsTr("Mode jeu")
                            on: GameMode.enabled
                            onClicked: GameMode.enabled = !GameMode.enabled
                        }
                        RoundToggle {
                            icon: Audio.sourceMuted ? "mic_off" : "mic"
                            label: Audio.sourceMuted ? qsTr("Muet") : qsTr("Micro")
                            activeTint: Audio.sourceMuted ? root.red : root.accent
                            on: !Audio.sourceMuted
                            onClicked: {
                                if (Audio.source?.audio)
                                    Audio.source.audio.muted = !Audio.source.audio.muted;
                            }
                        }
                        RoundToggle {
                            icon: Recorder.running ? "radio_button_checked" : "screen_record"
                            label: Recorder.running ? qsTr("En cours") : qsTr("Capturer")
                            activeTint: Recorder.running ? root.red : root.accent
                            on: Recorder.running
                            onClicked: root.page = "record"
                        }
                        RoundToggle {
                            icon: "screenshot_region"
                            label: qsTr("Photo")
                            onClicked: {
                                root.close();
                                captureDelay.start();
                            }
                        }
                        RoundToggle {
                            icon: "timer"
                            label: qsTr("Horloge")
                            onClicked: {
                                root.close();
                                root.run([`${Quickshell.env("HOME")}/.local/bin/caelestia-clock`]);
                            }
                        }
                        RoundToggle {
                            icon: "nightlight"
                            label: NightLight.enabled ? qsTr("%1 K").arg(NightLight.temperature) : qsTr("Nuit")
                            activeTint: root.amber
                            on: NightLight.enabled
                            onClicked: NightLight.toggle()
                        }
                        RoundToggle {
                            icon: "calculate"
                            label: qsTr("Calcul")
                            onClicked: {
                                root.close();
                                root.run([`${Quickshell.env("HOME")}/.local/bin/caelestia-spotlight`, "calc"]);
                            }
                        }
                    }
                }

                // ── Télémétrie Énergie & Profils de puissance ──
                Tile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    visible: UPower.displayDevice.isLaptopBattery || PowerProfiles.hasPerformanceProfile !== undefined

                    readonly property real battPct: UPower.displayDevice.percentage ?? 0
                    readonly property color battColor: !UPower.onBattery ? root.green : battPct < 0.2 ? root.red : battPct < 0.4 ? root.amber : root.accent

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9

                        // Mini cadran 270° de batterie
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            height: 38
                            radius: 11
                            color: Qt.alpha(parent.parent.battColor, 0.11)
                            border.width: 0.5
                            border.color: Qt.alpha(parent.parent.battColor, 0.32)

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Qt.alpha(root.fg, 0.12)
                                    strokeWidth: 2.4
                                    capStyle: ShapePath.RoundCap

                                    PathAngleArc {
                                        centerX: 19
                                        centerY: 19
                                        radiusX: 13
                                        radiusY: 13
                                        startAngle: 135
                                        sweepAngle: 270
                                    }
                                }
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: parent.parent.parent.parent.battColor
                                    strokeWidth: 2.4
                                    capStyle: ShapePath.RoundCap

                                    PathAngleArc {
                                        centerX: 19
                                        centerY: 19
                                        radiusX: 13
                                        radiusY: 13
                                        startAngle: 135
                                        sweepAngle: Math.max(0.02, Math.min(1, parent.parent.parent.parent.battPct)) * 270
                                    }
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: !UPower.onBattery ? "bolt" : "battery_full"
                                color: parent.parent.parent.battColor
                                fontStyle: Tokens.font.icon.size(13).build()
                                fill: 1
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            Row {
                                spacing: 4

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: `${Math.round((UPower.displayDevice.percentage ?? 0) * 100)} %`
                                    color: root.fg
                                    font.pointSize: 10
                                    font.weight: Font.Bold
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: BatteryInfo.watts > 0.2
                                    text: `· ${BatteryInfo.watts.toFixed(1).replace(".", ",")} W`
                                    color: !UPower.onBattery ? root.green : root.fgDim
                                    font.pointSize: 7.8
                                    font.weight: Font.DemiBold
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "chevron_right"
                                    color: root.fgDim
                                    fontStyle: Tokens.font.icon.size(11).build()
                                }
                            }
                            StyledText {
                                width: 128
                                elide: Text.ElideRight
                                text: BatteryInfo.statusText
                                color: root.fgDim
                                font.pointSize: 7.5
                            }
                        }
                    }

                    // Clic sur l'état de la batterie → page détaillée
                    MouseArea {
                        x: 4
                        width: 175
                        height: parent.height
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.page = "battery"
                    }

                    // Profils d'énergie : contrôle segmenté biseauté
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 174
                        height: 36
                        radius: 12
                        color: Qt.alpha(root.fg, 0.06)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.14)

                        Rectangle {
                            readonly property int idx: PowerProfiles.profile === PowerProfile.PowerSaver ? 0 : PowerProfiles.profile === PowerProfile.Performance ? 2 : 1
                            readonly property color modeTint: idx === 0 ? root.green : idx === 2 ? root.amber : root.accent

                            x: 3 + idx * (parent.width - 6) / 3
                            y: 3
                            width: (parent.width - 6) / 3
                            height: parent.height - 6
                            radius: 9
                            color: Qt.alpha(modeTint, 0.2)
                            border.width: 0.5
                            border.color: Qt.alpha(modeTint, 0.45)

                            Behavior on x {
                                NumberAnimation {
                                    duration: 320
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.15
                                }
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 3

                            Repeater {
                                model: [
                                    {
                                        icon: "energy_savings_leaf",
                                        lbl: qsTr("ÉCO"),
                                        tint: root.green,
                                        p: PowerProfile.PowerSaver
                                    },
                                    {
                                        icon: "balance",
                                        lbl: qsTr("ÉQUIL."),
                                        tint: root.accent,
                                        p: PowerProfile.Balanced
                                    },
                                    {
                                        icon: "speed",
                                        lbl: qsTr("PERF."),
                                        tint: root.amber,
                                        p: PowerProfile.Performance
                                    }
                                ]

                                Item {
                                    id: prof

                                    required property var modelData
                                    readonly property bool active: PowerProfiles.profile === modelData.p

                                    width: parent.width / 3
                                    height: parent.height

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 3

                                        MaterialIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: prof.modelData.icon
                                            color: prof.active ? prof.modelData.tint : root.fgDim
                                            fontStyle: Tokens.font.icon.size(12).build()
                                            fill: prof.active ? 1 : 0
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: prof.modelData.lbl
                                            color: prof.active ? root.fg : root.fgDim
                                            font.pointSize: 6.8
                                            font.weight: Font.Bold
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: PowerProfiles.profile = prof.modelData.p
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Icônes système (SystemTray en puits optiques biseautés) ──
                Tile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    visible: SystemTray.items.values.length > 0

                    StyledText {
                        id: trayTitleLbl

                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("ACTIFS")
                        color: root.fgDim
                        font.pointSize: 6.8
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }

                    Row {
                        anchors.left: trayTitleLbl.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Repeater {
                            model: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))

                            Rectangle {
                                id: trayBtn

                                required property SystemTrayItem modelData

                                width: 30
                                height: 30
                                radius: 9
                                color: trayArea.containsMouse ? Qt.alpha(root.fg, 0.12) : Qt.alpha(root.fg, 0.05)
                                border.width: 0.5
                                border.color: trayArea.containsMouse ? Qt.alpha(root.fg, 0.25) : Qt.alpha(root.fg, 0.11)

                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 16
                                    source: {
                                        let icon = trayBtn.modelData.icon;
                                        if (icon.includes("?path=")) {
                                            const [name, path] = icon.split("?path=");
                                            icon = `file://${path}/${name.slice(name.lastIndexOf("/") + 1)}`;
                                        }
                                        return icon;
                                    }
                                }

                                MouseArea {
                                    id: trayArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: e => {
                                        const item = trayBtn.modelData;
                                        if (e.button === Qt.LeftButton && !item.onlyMenu) {
                                            item.activate();
                                            root.close();
                                        } else if (item.hasMenu) {
                                            const win = QsWindow.window;
                                            const p = trayBtn.mapToItem(win.contentItem, 0, trayBtn.height);
                                            root.trayMenuUntil = Date.now() + 15000;
                                            item.display(win, p.x, p.y);
                                        }
                                    }
                                }

                                // Croix au survol : quitter complètement l'app (même sans fenêtre)
                                Rectangle {
                                    visible: trayArea.containsMouse || quitArea.containsMouse
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: -3
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: quitArea.containsMouse ? Colours.palette.m3error : Qt.alpha(Colours.palette.m3surface, 0.95)
                                    border.width: 0.5
                                    border.color: Qt.alpha(Colours.palette.m3onSurface, 0.25)

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: "close"
                                        color: quitArea.containsMouse ? Colours.palette.m3onError : Colours.palette.m3onSurface
                                        fontStyle: Tokens.font.icon.size(9).build()
                                    }

                                    MouseArea {
                                        id: quitArea

                                        anchors.fill: parent
                                        anchors.margins: -2
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/caelestia-quit-app`, "--tray", trayBtn.modelData.id, trayBtn.modelData.title])
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Barre de Session encadrée ──
                Tile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 7

                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: root.fgFaint
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize: Qt.size(64, 64)
                                    source: `file://${Quickshell.env("HOME")}/.face`
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.width: 0.5
                                    border.color: Qt.alpha("#ffffff", 0.25)
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: -1
                                width: 8
                                height: 8
                                radius: 4
                                color: root.green
                                border.width: 1.5
                                border.color: Colours.palette.m3surface
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: -1

                            StyledText {
                                text: qsTr("SESSION ACTIVE")
                                color: root.fgDim
                                font.pointSize: 6.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: {
                                    const u = Quickshell.env("USER") ?? "";
                                    return u.charAt(0).toUpperCase() + u.slice(1);
                                }
                                color: root.fg
                                font.pointSize: 9.8
                                font.weight: Font.Bold
                            }
                        }

                        IconBtn {
                            icon: "settings"
                            onClicked: {
                                root.close();
                                root.run(["qs", "-c", "caelestia", "ipc", "call", "nexus", "open"]);
                            }
                        }
                        IconBtn {
                            icon: "lock"
                            onClicked: {
                                root.close();
                                root.run(["qs", "-c", "caelestia", "ipc", "call", "lock", "lock"]);
                            }
                        }
                        IconBtn {
                            icon: "bedtime"
                            onClicked: {
                                root.close();
                                root.run(["systemctl", "suspend"]);
                            }
                        }
                        IconBtn {
                            icon: "restart_alt"
                            onClicked: root.run(Config.session.commands.reboot)
                        }
                        IconBtn {
                            icon: "power_settings_new"
                            danger: true
                            onClicked: root.run(Config.session.commands.shutdown)
                        }
                    }
                }
            }

            // ════════════════════ Sous-pages ════════════════════
            Item {
                id: subPage

                width: pages.width
                height: 470
                x: root.page === "main" ? pages.width : 0
                opacity: root.page === "main" ? 0 : 1
                visible: opacity > 0.01

                Behavior on x {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 240
                    }
                }

                // En-tête : retour biseauté + catégorie technique + titre + contrôles
                Item {
                    id: subHead

                    width: parent.width
                    height: 46

                    IconBtn {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "arrow_back_ios_new"
                        onClicked: root.page = "main"
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 42
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            text: root.page === "wifi" || root.page === "bt" ? qsTr("CONNECTIVITÉ SANS FIL") : root.page === "audio" ? qsTr("CONSOLE AUDIO PIPEWIRE") : root.page === "battery" ? qsTr("GESTION ÉNERGÉTIQUE") : root.page === "display" ? qsTr("AFFICHAGE & COLORIMÉTRIE") : root.page === "focus" ? qsTr("PROFIL DE CONCENTRATION") : root.page === "caffeine" ? qsTr("INHIBITION DE VEILLE") : qsTr("CAPTURE STUDIO")
                            color: root.accent
                            font.pointSize: 6.5
                            font.weight: Font.Bold
                            font.letterSpacing: 0.7
                        }
                        StyledText {
                            text: root.page === "wifi" ? qsTr("Wi-Fi") : root.page === "bt" ? qsTr("Bluetooth") : root.page === "record" ? qsTr("Enregistrement") : root.page === "caffeine" ? qsTr("Caféine") : root.page === "display" ? qsTr("Écran") : root.page === "battery" ? qsTr("Batterie") : root.page === "focus" ? qsTr("Concentration") : qsTr("Studio Audio")
                            color: root.fg
                            font.pointSize: 12.5
                            font.weight: Font.Bold
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        // Bouton Écouteurs 3D sur la page Bluetooth
                        IconBtn {
                            visible: root.page === "bt"
                            icon: "Spatial_audio_off"
                            onClicked: {
                                root.close();
                                root.screenState.earbuds = true;
                            }
                        }
                        IconBtn {
                            visible: root.page === "wifi" || root.page === "bt"
                            icon: "refresh"
                            spinning: root.page === "wifi" ? Nmcli.scanning : (root.adapter?.discovering ?? false)
                            onClicked: {
                                if (root.page === "wifi")
                                    Nmcli.rescanWifi();
                                else if (root.adapter)
                                    root.adapter.discovering = !root.adapter.discovering;
                            }
                        }
                        Switch {
                            visible: root.page === "focus"
                            on: FocusMode.active
                            onToggled: root.focusToggle()
                        }
                        Switch {
                            visible: root.page === "display"
                            on: NightLight.enabled
                            onToggled: NightLight.toggle()
                        }
                        Switch {
                            visible: root.page === "caffeine"
                            on: IdleInhibitor.enabled
                            onToggled: {
                                if (IdleInhibitor.enabled)
                                    IdleInhibitor.enabled = false;
                                else
                                    IdleInhibitor.enableFor(root.caffMinutes);
                            }
                        }
                        Switch {
                            visible: root.page === "wifi" || root.page === "bt"
                            on: root.page === "wifi" ? Nmcli.wifiEnabled : (root.adapter?.enabled ?? false)
                            onToggled: {
                                if (root.page === "wifi")
                                    Nmcli.toggleWifi();
                                else if (root.adapter)
                                    root.adapter.enabled = !root.adapter.enabled;
                            }
                        }
                    }
                }

                // ── Wi-Fi ──
                ListView {
                    id: wifiList

                    property string passwordFor: ""
                    property string connecting: ""

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    anchors.bottom: parent.bottom
                    width: parent.width
                    visible: root.page === "wifi"
                    clip: true
                    spacing: 5
                    model: [...Nmcli.networks].sort((a, b) => (b.active - a.active) || (b.strength - a.strength))

                    delegate: Rectangle {
                        id: net

                        required property var modelData
                        readonly property bool askPwd: wifiList.passwordFor === modelData.ssid

                        width: wifiList.width
                        height: askPwd ? 104 : 50
                        radius: 15
                        color: "transparent"
                        border.width: 0.5
                        border.color: modelData.active ? Qt.alpha(root.accent, 0.45) : netArea.containsMouse ? Qt.alpha("white", 0.14) : Qt.alpha(root.fg, 0.06)

                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: parent.height > 60 ? 16 : 0
                            tintColour: modelData.active ? Qt.alpha(root.accent, 0.16) : netArea.containsMouse ? root.tileColour : Qt.alpha(root.fg, 0.03)
                            visible: tintColour.a > 0.01
                            pressed: netArea.pressed
                            hovered: netArea.containsMouse
                            pointer: netArea.containsMouse ? Qt.point(netArea.mouseX / Math.max(1, width), netArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 240
                                easing.type: Easing.OutCubic
                            }
                        }

                        Rectangle {
                            x: 10
                            y: 9
                            width: 32
                            height: 32
                            radius: 10
                            color: net.modelData.active ? root.accent : Qt.alpha(root.fg, 0.08)
                            border.width: 0.5
                            border.color: net.modelData.active ? Qt.alpha("white", 0.28) : Qt.alpha(root.fg, 0.1)

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: net.modelData.strength > 66 ? "network_wifi" : net.modelData.strength > 33 ? "network_wifi_2_bar" : "network_wifi_1_bar"
                                color: net.modelData.active ? root.onAccent : root.fg
                                fontStyle: Tokens.font.icon.size(14).build()
                                fill: 1
                            }
                        }

                        Column {
                            x: 50
                            y: 9
                            width: parent.width - 140
                            spacing: 1

                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: net.modelData.ssid
                                color: root.fg
                                font.pointSize: 9.8
                                font.weight: net.modelData.active ? Font.Bold : Font.DemiBold
                            }
                            StyledText {
                                text: wifiList.connecting === net.modelData.ssid && !net.modelData.active ? qsTr("Connexion en cours…") : net.modelData.active ? qsTr("Connecté · %1 %").arg(net.modelData.strength) : (net.modelData.isSecure ? qsTr("Sécurisé WPA") : qsTr("Réseau ouvert"))
                                color: net.modelData.active ? root.accent : root.fgDim
                                font.pointSize: 7.8
                                font.features: { "tnum": 1 }
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            y: 15
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: sigTxt.implicitWidth + 10
                                height: 19
                                radius: 9.5
                                color: net.modelData.active ? Qt.alpha(root.accent, 0.18) : Qt.alpha(root.fg, 0.07)
                                border.width: 0.5
                                border.color: net.modelData.active ? Qt.alpha(root.accent, 0.4) : Qt.alpha(root.fg, 0.1)

                                StyledText {
                                    id: sigTxt

                                    anchors.centerIn: parent
                                    text: `${net.modelData.strength} %`
                                    color: net.modelData.active ? root.accent : root.fgDim
                                    font.pointSize: 7.5
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                }
                            }
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: net.modelData.isSecure
                                text: "lock"
                                color: root.fgDim
                                fontStyle: Tokens.font.icon.size(11).build()
                            }
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: net.modelData.active
                                text: "check_circle"
                                color: root.accent
                                fontStyle: Tokens.font.icon.size(13).build()
                                fill: 1
                            }
                        }

                        MouseArea {
                            id: netArea

                            width: parent.width
                            height: 50
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (net.modelData.active) {
                                    Nmcli.disconnectFromNetwork();
                                    return;
                                }
                                wifiList.connecting = net.modelData.ssid;
                                NetworkConnection.handleConnect(net.modelData, null, () => {
                                    wifiList.passwordFor = net.modelData.ssid;
                                    pwd.forceActiveFocus();
                                });
                            }
                        }

                        // Mot de passe, directement dans la liste
                        Rectangle {
                            x: 12
                            y: 54
                            width: parent.width - 24
                            height: 38
                            radius: 12
                            visible: net.askPwd
                            color: root.tileColour
                            border.width: 0.5
                            border.color: pwd.activeFocus ? Qt.alpha(root.accent, 0.7) : root.tileBorder

                            TextInput {
                                id: pwd

                                anchors.left: parent.left
                                anchors.right: pwdGo.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                echoMode: TextInput.Password
                                color: root.fg
                                font.pointSize: 10
                                clip: true
                                Keys.onReturnPressed: pwdGo.go()
                                Keys.onEscapePressed: wifiList.passwordFor = ""

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !pwd.text
                                    text: qsTr("Mot de passe")
                                    color: root.fgDim
                                    font.pointSize: 10
                                }
                            }

                            IconBtn {
                                id: pwdGo

                                function go(): void {
                                    if (!pwd.text)
                                        return;
                                    NetworkConnection.connectWithPassword(net.modelData, pwd.text, () => {});
                                    wifiList.passwordFor = "";
                                    pwd.text = "";
                                }

                                anchors.right: parent.right
                                anchors.rightMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "arrow_forward"
                                onClicked: go()
                            }
                        }
                    }
                }

                // ── Bluetooth ──
                ListView {
                    id: btList

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    anchors.bottom: parent.bottom
                    width: parent.width
                    visible: root.page === "bt"
                    clip: true
                    spacing: 5
                    model: [...Bluetooth.devices.values].filter(d => d.bonded || d.trusted || d.paired || d.connected || (root.adapter?.discovering && d.name)).sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

                    delegate: Rectangle {
                        id: dev

                        required property BluetoothDevice modelData
                        readonly property bool busy: Bluez.isBusy(modelData)

                        width: btList.width
                        height: 54
                        radius: 15
                        color: "transparent"
                        border.width: 0.5
                        border.color: modelData.connected ? Qt.alpha(root.accent, 0.45) : devArea.containsMouse ? Qt.alpha("white", 0.14) : Qt.alpha(root.fg, 0.06)

                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: parent.height > 60 ? 16 : 0
                            tintColour: modelData.connected ? Qt.alpha(root.accent, 0.16) : devArea.containsMouse ? root.tileColour : Qt.alpha(root.fg, 0.03)
                            visible: tintColour.a > 0.01
                            pressed: devArea.pressed
                            hovered: devArea.containsMouse
                            pointer: devArea.containsMouse ? Qt.point(devArea.mouseX / Math.max(1, width), devArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }

                        Rectangle {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34
                            radius: 11
                            color: dev.modelData.connected ? root.accent : root.fgFaint
                            border.width: 0.5
                            border.color: dev.modelData.connected ? Qt.alpha("white", 0.28) : Qt.alpha(root.fg, 0.1)

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: Icons.getBluetoothIcon(dev.modelData.icon)
                                color: dev.modelData.connected ? root.onAccent : root.fg
                                fontStyle: Tokens.font.icon.size(14).build()
                                fill: 1
                            }
                        }
                        Column {
                            x: 52
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 140
                            spacing: 1

                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: dev.modelData.name || dev.modelData.address
                                color: root.fg
                                font.pointSize: 9.8
                                font.weight: dev.modelData.connected ? Font.Bold : Font.DemiBold
                            }
                            StyledText {
                                text: dev.busy ? qsTr("Synchronisation…") : dev.modelData.connected ? qsTr("Connecté · Audio actif") : (dev.modelData.paired || dev.modelData.bonded || dev.modelData.trusted) ? qsTr("Associé") : qsTr("Disponible")
                                color: dev.modelData.connected ? root.accent : root.fgDim
                                font.pointSize: 7.8
                            }
                        }

                        // Badge de batterie biseauté
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: dev.modelData.connected && dev.modelData.batteryAvailable
                            width: btBattRow.implicitWidth + 12
                            height: 22
                            radius: 11
                            color: Qt.alpha(dev.modelData.battery < 0.2 ? root.red : root.green, 0.15)
                            border.width: 0.5
                            border.color: Qt.alpha(dev.modelData.battery < 0.2 ? root.red : root.green, 0.4)

                            Row {
                                id: btBattRow

                                anchors.centerIn: parent
                                spacing: 4

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: dev.modelData.battery < 0.2 ? "battery_alert" : "battery_full"
                                    color: dev.modelData.battery < 0.2 ? root.red : root.green
                                    fontStyle: Tokens.font.icon.size(10).build()
                                    fill: 1
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: `${Math.round(dev.modelData.battery * 100)} %`
                                    color: dev.modelData.battery < 0.2 ? root.red : root.green
                                    font.pointSize: 8
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }

                        MouseArea {
                            id: devArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !dev.busy
                            onClicked: Bluez.toggleConnection(dev.modelData)
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: btList.count === 0
                        text: root.adapter?.enabled ? qsTr("Aucun appareil — actualise pour chercher") : qsTr("Bluetooth désactivé")
                        color: root.fgDim
                        font.pointSize: 9.5
                    }
                }

                // ── Concentration : modes, durée, ce qui est coupé ──
                Column {
                    id: focusPage

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    visible: root.page === "focus"
                    spacing: 10

                    readonly property string shownMode: FocusMode.active ? FocusMode.mode : root.focusSel
                    readonly property color tint: FocusMode.modes[shownMode]?.tint ?? root.accent

                    // Modes
                    Row {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: FocusMode.order

                            Rectangle {
                                id: fm

                                required property string modelData
                                readonly property var def: FocusMode.modes[modelData]
                                readonly property bool sel: focusPage.shownMode === modelData
                                readonly property bool live: FocusMode.active && FocusMode.mode === modelData

                                width: (parent.width - 16) / 3
                                height: 92
                                radius: 22
                                color: "transparent"
                                // Verre liquide (iOS 27) sous le contenu
                                GlassControl {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    bevel: parent.height > 60 ? 16 : 0
                                    tintColour: fm.sel ? Qt.alpha(fm.def.tint, fm.live ? 0.3 : 0.18) : Qt.alpha(root.fg, fmArea.containsMouse ? 0.1 : 0.07)
                                    visible: tintColour.a > 0.01
                                    pressed: fmArea.pressed
                                    hovered: fmArea.containsMouse
                                    pointer: fmArea.containsMouse ? Qt.point(fmArea.mouseX / Math.max(1, width), fmArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                }
                                border.width: fm.sel ? 2 : 1
                                border.color: fm.sel ? Qt.alpha(fm.def.tint, 0.75) : Qt.alpha(root.fg, 0.08)
                                scale: fmArea.pressed ? 0.96 : 1

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 220
                                    }
                                }
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutBack
                                    }
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 38
                                        height: 38
                                        radius: 19
                                        color: fm.live ? fm.def.tint : Qt.alpha(fm.def.tint, 0.2)

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 220
                                            }
                                        }

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: fm.def.icon
                                            color: fm.live ? "white" : fm.def.tint
                                            fontStyle: Tokens.font.icon.size(18).build()
                                            fill: 1
                                        }
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: fm.def.name
                                        color: root.fg
                                        font.pointSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: fmArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.focusPick(fm.modelData)
                                }
                            }
                        }
                    }

                    // Durée
                    Tile {
                        width: parent.width
                        height: 82

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 9

                            StyledText {
                                text: FocusMode.active ? qsTr("ACTIVÉ %1").arg(FocusMode.untilText().toUpperCase()) : qsTr("DURÉE")
                                color: FocusMode.active ? focusPage.tint : root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            Row {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: [[30, "30 min"], [60, "1 h"], [120, "2 h"], [-1, qsTr("Ce soir")], [0, "∞"]]

                                    Rectangle {
                                        id: fdur

                                        required property var modelData
                                        readonly property bool on: root.focusMinutes === modelData[0]

                                        width: (parent.width - 24) / 5
                                        height: 32
                                        radius: 16
                                        color: "transparent"
                                        // Verre liquide (iOS 27) sous le contenu
                                        GlassControl {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            bevel: parent.height > 60 ? 16 : 0
                                            tintColour: on ? focusPage.tint : fdurArea.containsMouse ? Qt.alpha(root.fg, 0.14) : root.fgFaint
                                            visible: tintColour.a > 0.01
                                            pressed: fdurArea.pressed
                                            hovered: fdurArea.containsMouse
                                            pointer: fdurArea.containsMouse ? Qt.point(fdurArea.mouseX / Math.max(1, width), fdurArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 180
                                            }
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: fdur.modelData[1]
                                            color: fdur.on ? "white" : root.fg
                                            font.pointSize: fdur.modelData[0] === 0 ? 13 : 9
                                            font.weight: Font.DemiBold
                                        }
                                        MouseArea {
                                            id: fdurArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.focusMinutes = fdur.modelData[0];
                                                // Déjà actif : on prolonge / raccourcit avec la nouvelle durée
                                                if (FocusMode.active)
                                                    FocusMode.start(FocusMode.mode, root.focusMinutes, { hideDock: FocusMode.hideDock, muteApps: FocusMode.muteApps, pomodoro: FocusMode.pomodoro, night: FocusMode.night });
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Ce que la concentration fait
                    Tile {
                        width: parent.width
                        height: focusOptCol.implicitHeight + 16

                        Column {
                            id: focusOptCol

                            x: 14
                            y: 8
                            width: parent.width - 28

                            Item {
                                width: parent.width
                                height: 40

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "notifications_off"
                                    color: focusPage.tint
                                    fontStyle: Tokens.font.icon.size(14).build()
                                    fill: 1
                                }
                                Column {
                                    x: 30
                                    anchors.verticalCenter: parent.verticalCenter

                                    StyledText {
                                        text: qsTr("Notifications coupées")
                                        color: root.fg
                                        font.pointSize: 9.5
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        text: qsTr("Toujours : elles t'attendent dans le centre de notifications")
                                        color: root.fgDim
                                        font.pointSize: 8
                                    }
                                }
                            }
                            OptionRow {
                                icon: "volume_off"
                                title: qsTr("Messageries en sourdine")
                                subtitle: qsTr("Telegram, Discord, WhatsApp, Slack…")
                                on: root.focusOpt("muteApps")
                                onToggled: root.focusSetOpt("muteApps", !root.focusOpt("muteApps"))
                            }
                            OptionRow {
                                icon: "dock_to_bottom"
                                title: qsTr("Masquer le Dock")
                                subtitle: qsTr("Plus rien ne dépasse en bas de l'écran")
                                on: root.focusOpt("hideDock")
                                onToggled: root.focusSetOpt("hideDock", !root.focusOpt("hideDock"))
                            }
                            OptionRow {
                                icon: "timer"
                                title: qsTr("Lancer un Pomodoro")
                                subtitle: qsTr("25 min de travail, 5 min de pause, dans l'île")
                                on: root.focusOpt("pomodoro")
                                onToggled: root.focusSetOpt("pomodoro", !root.focusOpt("pomodoro"))
                            }
                            OptionRow {
                                icon: "nightlight"
                                title: qsTr("Éclairage de nuit")
                                subtitle: qsTr("Écran plus chaud, pour le soir")
                                on: root.focusOpt("night")
                                onToggled: root.focusSetOpt("night", !root.focusOpt("night"))
                            }
                        }
                    }

                    // Grand bouton
                    Rectangle {
                        width: parent.width
                        height: 46
                        radius: 23
                        color: "transparent"
                        // Verre liquide (iOS 27) sous le contenu
                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: parent.height > 60 ? 16 : 0
                            tintColour: FocusMode.active ? (fgoArea.containsMouse ? Qt.lighter("#ff453a", 1.08) : "#ff453a") : (fgoArea.containsMouse ? Qt.lighter(focusPage.tint, 1.1) : focusPage.tint)
                            visible: tintColour.a > 0.01
                            pressed: fgoArea.pressed
                            hovered: fgoArea.containsMouse
                            pointer: fgoArea.containsMouse ? Qt.point(fgoArea.mouseX / Math.max(1, width), fgoArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }
                        scale: fgoArea.pressed ? 0.97 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 220
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 140
                            }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 7

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: FocusMode.active ? "stop_circle" : (FocusMode.modes[focusPage.shownMode]?.icon ?? "do_not_disturb_on")
                                color: "white"
                                fontStyle: Tokens.font.icon.size(17).build()
                                fill: 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: FocusMode.active ? qsTr("Arrêter la concentration") : qsTr("Activer « %1 »").arg(FocusMode.modes[focusPage.shownMode]?.name ?? "")
                                color: "white"
                                font.pointSize: 10.5
                                font.weight: Font.Bold
                            }
                        }
                        MouseArea {
                            id: fgoArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.focusToggle()
                        }
                    }
                }

                // ── Batterie détaillée ──
                Column {
                    id: batteryPage

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    visible: root.page === "battery"
                    spacing: 10

                    readonly property color level: BatteryInfo.charging || BatteryInfo.full ? "#32d74b" : BatteryInfo.pct < 0.2 ? "#ff453a" : BatteryInfo.pct < 0.4 ? "#ff9f0a" : root.fg

                    // État (cadran radial 270° + télémétrie électrique)
                    Tile {
                        width: parent.width
                        height: 96

                        Rectangle {
                            id: bigBatt

                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 64
                            radius: 18
                            color: Qt.alpha(batteryPage.level, 0.1)
                            border.width: 0.5
                            border.color: Qt.alpha(batteryPage.level, 0.35)

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Qt.alpha(root.fg, 0.14)
                                    strokeWidth: 4
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 32
                                        centerY: 32
                                        radiusX: 23
                                        radiusY: 23
                                        startAngle: 135
                                        sweepAngle: 270
                                    }
                                }
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: batteryPage.level
                                    strokeWidth: 4
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 32
                                        centerY: 32
                                        radiusX: 23
                                        radiusY: 23
                                        startAngle: 135
                                        sweepAngle: 270 * Math.max(0.03, BatteryInfo.pct)
                                    }
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: BatteryInfo.charging ? "bolt" : BatteryInfo.pct < 0.2 ? "battery_alert" : "battery_full"
                                color: batteryPage.level
                                fontStyle: Tokens.font.icon.size(20).build()
                                fill: 1
                            }
                        }

                        Column {
                            anchors.left: bigBatt.right
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: qsTr("CAPACITÉ ÉLECTRIQUE")
                                color: batteryPage.level
                                font.pointSize: 6.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }
                            Row {
                                spacing: 8

                                StyledText {
                                    anchors.baseline: battUnitSub.baseline
                                    text: `${Math.round(BatteryInfo.pct * 100)} %`
                                    color: root.fg
                                    font.pointSize: 20
                                    font.weight: Font.Bold
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                StyledText {
                                    id: battUnitSub

                                    visible: BatteryInfo.watts > 0.2
                                    text: (BatteryInfo.charging ? `+${BatteryInfo.watts.toFixed(1).replace(".", ",")} W` : `-${BatteryInfo.watts.toFixed(1).replace(".", ",")} W`)
                                    color: BatteryInfo.charging ? root.green : root.fgDim
                                    font.pointSize: 9.5
                                    font.weight: Font.Bold
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                            }
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: BatteryInfo.statusText
                                color: BatteryInfo.charging ? "#32d74b" : root.fgDim
                                font.pointSize: 9
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    // Historique 24 h
                    Tile {
                        width: parent.width
                        height: 128

                        StyledText {
                            x: 14
                            y: 10
                            text: qsTr("DERNIÈRES 24 H")
                            color: root.fgDim
                            font.pointSize: 7.5
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }

                        Canvas {
                            id: histCanvas

                            x: 14
                            y: 30
                            width: parent.width - 28
                            height: 74

                            readonly property var pts: BatteryInfo.history
                            onPtsChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            Connections {
                                target: root

                                function onBatteryShownChanged(): void {
                                    histCanvas.requestPaint();
                                }
                            }

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const w = width, h = height, now = Date.now(), span = 24 * 3600 * 1000;
                                // Lignes 0 / 50 / 100 %
                                ctx.strokeStyle = Qt.alpha(root.fg, 0.1);
                                ctx.lineWidth = 1;
                                for (const f of [0, 0.5, 1]) {
                                    ctx.beginPath();
                                    ctx.moveTo(0, 2 + (h - 4) * f);
                                    ctx.lineTo(w, 2 + (h - 4) * f);
                                    ctx.stroke();
                                }
                                const p = pts.filter(q => now - q.t <= span);
                                if (p.length === 0)
                                    return;
                                const X = t => w * (1 - (now - t) / span);
                                const Y = v => 2 + (h - 4) * (1 - v / 100);
                                const all = [...p, { t: now, p: Math.round(BatteryInfo.pct * 100), c: BatteryInfo.charging }];
                                // Aire sous la courbe
                                const grad = ctx.createLinearGradient(0, 0, 0, h);
                                grad.addColorStop(0, Qt.alpha(root.accent, 0.45));
                                grad.addColorStop(1, Qt.alpha(root.accent, 0.02));
                                ctx.beginPath();
                                ctx.moveTo(X(all[0].t), h);
                                for (const q of all)
                                    ctx.lineTo(X(q.t), Y(q.p));
                                ctx.lineTo(X(now), h);
                                ctx.closePath();
                                ctx.fillStyle = grad;
                                ctx.fill();
                                // Courbe : verte quand ça charge
                                ctx.lineWidth = 2.2;
                                ctx.lineJoin = "round";
                                for (let i = 1; i < all.length; i++) {
                                    ctx.beginPath();
                                    ctx.strokeStyle = all[i - 1].c ? "#32d74b" : root.accent;
                                    ctx.moveTo(X(all[i - 1].t), Y(all[i - 1].p));
                                    ctx.lineTo(X(all[i].t), Y(all[i].p));
                                    ctx.stroke();
                                }
                                ctx.beginPath();
                                ctx.fillStyle = root.fg;
                                ctx.arc(X(now), Y(all[all.length - 1].p), 3, 0, Math.PI * 2);
                                ctx.fill();
                            }
                        }

                        // Les premières heures, l'historique se remplit
                        StyledText {
                            anchors.horizontalCenter: histCanvas.horizontalCenter
                            y: histCanvas.y + histCanvas.height / 2 - height / 2
                            visible: BatteryInfo.history.length < 6
                            text: qsTr("L'historique se remplit (un point toutes les 5 min)")
                            color: root.fgDim
                            font.pointSize: 8.5
                        }

                        Item {
                            x: 14
                            y: 106
                            width: parent.width - 28
                            height: 14

                            StyledText {
                                text: qsTr("il y a 24 h")
                                color: root.fgDim
                                font.pointSize: 7.5
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("12 h")
                                color: root.fgDim
                                font.pointSize: 7.5
                            }
                            StyledText {
                                anchors.right: parent.right
                                text: qsTr("maintenant")
                                color: root.fgDim
                                font.pointSize: 7.5
                            }
                        }
                    }

                    // Apps qui consomment le plus
                    Tile {
                        width: parent.width
                        height: appsCol.implicitHeight + 24

                        Column {
                            id: appsCol

                            x: 14
                            y: 12
                            width: parent.width - 28
                            spacing: 8

                            StyledText {
                                text: qsTr("PROCESSUS LES PLUS ÉNERGIVORES")
                                color: root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            StyledText {
                                visible: BatteryInfo.consumers.length === 0
                                text: qsTr("Rien de gourmand en ce moment")
                                color: root.fgDim
                                font.pointSize: 9
                            }

                            Repeater {
                                model: BatteryInfo.consumers.slice(0, 5)

                                Item {
                                    id: consumer

                                    required property var modelData
                                    readonly property real maxCpu: Math.max(1, BatteryInfo.consumers[0]?.cpu ?? 1)

                                    width: appsCol.width
                                    height: 30

                                    IconImage {
                                        id: consIcon

                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitSize: 22
                                        source: root.appIcon(consumer.modelData.key)
                                    }
                                    StyledText {
                                        anchors.left: consIcon.right
                                        anchors.leftMargin: 10
                                        anchors.top: parent.top
                                        width: parent.width - 130
                                        elide: Text.ElideRight
                                        text: root.appName(consumer.modelData.key)
                                        color: root.fg
                                        font.pointSize: 9.5
                                        font.weight: Font.DemiBold
                                    }
                                    // Barre relative à la plus gourmande
                                    Rectangle {
                                        anchors.left: consIcon.right
                                        anchors.leftMargin: 10
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 2
                                        width: parent.width - 130
                                        height: 4
                                        radius: 2
                                        color: root.fgFaint

                                        Rectangle {
                                            width: parent.width * Math.min(1, consumer.modelData.cpu / consumer.maxCpu)
                                            height: parent.height
                                            radius: 2
                                            color: consumer.modelData.cpu >= 15 ? "#ff9f0a" : root.accent

                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 500
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: consBadgeTxt.implicitWidth + 12
                                        height: 20
                                        radius: 10
                                        color: Qt.alpha(consumer.modelData.cpu >= 15 ? root.amber : root.fg, 0.1)
                                        border.width: 0.5
                                        border.color: Qt.alpha(consumer.modelData.cpu >= 15 ? root.amber : root.fg, 0.25)

                                        StyledText {
                                            id: consBadgeTxt

                                            anchors.centerIn: parent
                                            text: `${Math.round(consumer.modelData.cpu)} % · ` + (consumer.modelData.cpu >= 15 ? qsTr("Élevé") : consumer.modelData.cpu >= 4 ? qsTr("Moyen") : qsTr("Faible"))
                                            color: consumer.modelData.cpu >= 15 ? root.amber : root.fgDim
                                            font.pointSize: 7.5
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Santé et économie d'énergie
                    Tile {
                        width: parent.width
                        height: careCol.implicitHeight + 16

                        Column {
                            id: careCol

                            x: 14
                            y: 8
                            width: parent.width - 28

                            OptionRow {
                                icon: "energy_savings_leaf"
                                title: qsTr("Économie auto sous 20 %")
                                subtitle: BatteryInfo.saverOn ? qsTr("Active en ce moment") : qsTr("Passe en économie d'énergie, revient en charge")
                                on: BatteryInfo.autoSaver
                                onToggled: BatteryInfo.setAutoSaver(!BatteryInfo.autoSaver)
                            }
                            Item {
                                width: parent.width
                                height: 40
                                visible: BatteryInfo.health > 0

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "health_and_safety"
                                    color: BatteryInfo.health < 0.8 ? "#ff9f0a" : root.fg
                                    fontStyle: Tokens.font.icon.size(14).build()
                                    fill: 1
                                }
                                Column {
                                    x: 30
                                    anchors.verticalCenter: parent.verticalCenter

                                    StyledText {
                                        text: qsTr("Santé de la batterie : %1 %").arg(Math.round(BatteryInfo.health * 100))
                                        color: root.fg
                                        font.pointSize: 9.5
                                        font.weight: Font.DemiBold
                                    }
                                    StyledText {
                                        text: (BatteryInfo.health < 0.8 ? qsTr("Capacité réduite par rapport à l'origine") : qsTr("Capacité proche de l'origine")) + (BatteryInfo.cycles > 0 ? qsTr(" · %1 cycles").arg(BatteryInfo.cycles) : "")
                                        color: root.fgDim
                                        font.pointSize: 8
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Écran : éclairage de nuit + projection ──
                Column {
                    id: displayPage

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    visible: root.page === "display"
                    spacing: 10

                    readonly property color warm: Qt.rgba(1, 0.62 + 0.3 * (NightLight.temperature - 2500) / 3500, 0.2 + 0.55 * (NightLight.temperature - 2500) / 3500, 1)

                    // État + chaleur
                    Tile {
                        width: parent.width
                        height: nlCol.implicitHeight + 24

                        Column {
                            id: nlCol

                            x: 14
                            y: 12
                            width: parent.width - 28
                            spacing: 12

                            Item {
                                width: parent.width
                                height: 52

                                Rectangle {
                                    id: moon

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 52
                                    height: 52
                                    radius: 26
                                    color: NightLight.enabled ? displayPage.warm : root.fgFaint

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 300
                                        }
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: "nightlight"
                                        fill: NightLight.enabled ? 1 : 0
                                        color: NightLight.enabled ? "#2a1605" : root.fg
                                        fontStyle: Tokens.font.icon.size(22).build()
                                    }
                                }
                                Column {
                                    anchors.left: moon.right
                                    anchors.leftMargin: 14
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    StyledText {
                                        text: qsTr("Éclairage de nuit")
                                        color: root.fg
                                        font.pointSize: 12
                                        font.weight: Font.Bold
                                    }
                                    StyledText {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: (NightLight.enabled ? qsTr("Activé · %1 K").arg(NightLight.temperature) : qsTr("Désactivé")) + (NightLight.scheduled ? qsTr(" · auto %1 → %2").arg(NightLight.from).arg(NightLight.to) : "")
                                        color: root.fgDim
                                        font.pointSize: 9
                                    }
                                }
                            }

                            StyledText {
                                text: qsTr("CHALEUR")
                                color: root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            GlassSlider {
                                width: parent.width
                                icon: "wb_sunny"
                                tint: displayPage.warm
                                value: (NightLight.maxTemp - NightLight.temperature) / (NightLight.maxTemp - NightLight.minTemp)
                                onMoved: v => {
                                    NightLight.setTemperature(NightLight.maxTemp - v * (NightLight.maxTemp - NightLight.minTemp));
                                    if (!NightLight.enabled)
                                        NightLight.toggle();
                                }
                            }
                            Row {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: [[5200, qsTr("Léger")], [4200, qsTr("Doux")], [3400, qsTr("Chaud")], [2700, qsTr("Bougie")]]

                                    Rectangle {
                                        id: preset

                                        required property var modelData
                                        readonly property bool on: NightLight.enabled && Math.abs(NightLight.temperature - modelData[0]) < 100

                                        width: (parent.width - 18) / 4
                                        height: 32
                                        radius: 16
                                        color: "transparent"
                                        // Verre liquide (iOS 27) sous le contenu
                                        GlassControl {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            bevel: parent.height > 60 ? 16 : 0
                                            tintColour: on ? displayPage.warm : presetArea.containsMouse ? Qt.alpha(root.fg, 0.14) : root.fgFaint
                                            visible: tintColour.a > 0.01
                                            pressed: presetArea.pressed
                                            hovered: presetArea.containsMouse
                                            pointer: presetArea.containsMouse ? Qt.point(presetArea.mouseX / Math.max(1, width), presetArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 180
                                            }
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: preset.modelData[1]
                                            color: preset.on ? "#2a1605" : root.fg
                                            font.pointSize: 9
                                            font.weight: Font.DemiBold
                                        }
                                        MouseArea {
                                            id: presetArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                NightLight.setTemperature(preset.modelData[0]);
                                                if (!NightLight.enabled)
                                                    NightLight.toggle();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Programmation
                    Tile {
                        width: parent.width
                        height: schedCol.implicitHeight + 16

                        Column {
                            id: schedCol

                            x: 14
                            y: 8
                            width: parent.width - 28
                            spacing: 8

                            OptionRow {
                                icon: "schedule"
                                title: qsTr("Programmer")
                                subtitle: NightLight.scheduled ? qsTr("S'allume à %1, s'éteint à %2").arg(NightLight.from).arg(NightLight.to) : qsTr("Allumer et éteindre tout seul")
                                on: NightLight.scheduled
                                onToggled: NightLight.setSchedule(!NightLight.scheduled)
                            }

                            Repeater {
                                model: NightLight.scheduled ? [["from", qsTr("Allumer"), ["19:00", "20:00", "21:00", "22:00"]], ["to", qsTr("Éteindre"), ["06:00", "07:00", "08:00", "09:00"]]] : []

                                Row {
                                    id: schedRow

                                    required property var modelData

                                    width: parent.width
                                    spacing: 6

                                    StyledText {
                                        width: 60
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: schedRow.modelData[1]
                                        color: root.fgDim
                                        font.pointSize: 8.5
                                    }
                                    Repeater {
                                        model: schedRow.modelData[2]

                                        Rectangle {
                                            id: hourChip

                                            required property string modelData
                                            readonly property bool on: NightLight[schedRow.modelData[0]] === modelData

                                            width: (schedRow.width - 60 - 24) / 4
                                            height: 28
                                            radius: 14
                                            color: "transparent"
                                            // Verre liquide (iOS 27) sous le contenu
                                            GlassControl {
                                                anchors.fill: parent
                                                radius: parent.radius
                                                bevel: parent.height > 60 ? 16 : 0
                                                tintColour: on ? root.accent : hourArea.containsMouse ? Qt.alpha(root.fg, 0.14) : root.fgFaint
                                                visible: tintColour.a > 0.01
                                                pressed: hourArea.pressed
                                                hovered: hourArea.containsMouse
                                                pointer: hourArea.containsMouse ? Qt.point(hourArea.mouseX / Math.max(1, width), hourArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                            }

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: hourChip.modelData.replace(":00", " h")
                                                color: hourChip.on ? root.onAccent : root.fg
                                                font.pointSize: 8.5
                                                font.weight: Font.DemiBold
                                            }
                                            MouseArea {
                                                id: hourArea

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    NightLight[schedRow.modelData[0]] = hourChip.modelData;
                                                    NightLight.setSchedule(true);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Projection (façon Windows + P)
                    Tile {
                        width: parent.width
                        height: projCol.implicitHeight + 24

                        Column {
                            id: projCol

                            x: 12
                            y: 12
                            width: parent.width - 24
                            spacing: 10

                            Item {
                                width: parent.width
                                height: 16

                                StyledText {
                                    text: qsTr("PROJECTION")
                                    color: root.fgDim
                                    font.pointSize: 7.5
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.8
                                }
                                StyledText {
                                    anchors.right: parent.right
                                    width: Math.min(implicitWidth, parent.width - 90)
                                    elide: Text.ElideRight
                                    text: root.projMessage || (root.projExternals.length > 0 ? root.projExternals.map(e => e.title).join(", ") : qsTr("Aucun second écran branché"))
                                    color: root.projMessage ? "#ff453a" : root.fgDim
                                    font.pointSize: 8
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: [["internal", "laptop_chromebook", qsTr("PC seul")], ["duplicate", "content_copy", qsTr("Dupliquer")], ["extend", "width_full", qsTr("Étendre")], ["external", "tv", qsTr("2d écran")]]

                                    Rectangle {
                                        id: proj

                                        required property var modelData
                                        readonly property bool on: root.projMode === modelData[0]
                                        readonly property bool usable: modelData[0] === "internal" || root.projExternals.length > 0

                                        width: (parent.width - 18) / 4
                                        height: 70
                                        radius: 18
                                        opacity: usable ? 1 : 0.4
                                        color: "transparent"
                                        // Verre liquide (iOS 27) sous le contenu
                                        GlassControl {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            bevel: parent.height > 60 ? 16 : 0
                                            tintColour: on ? Qt.alpha(root.accent, 0.22) : projArea.containsMouse && usable ? Qt.alpha(root.fg, 0.12) : Qt.alpha(root.fg, 0.07)
                                            visible: tintColour.a > 0.01
                                            pressed: projArea.pressed
                                            hovered: projArea.containsMouse
                                            pointer: projArea.containsMouse ? Qt.point(projArea.mouseX / Math.max(1, width), projArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                        }
                                        border.width: on ? 2 : 1
                                        border.color: on ? Qt.alpha(root.accent, 0.7) : Qt.alpha(root.fg, 0.08)
                                        scale: projArea.pressed && usable ? 0.95 : 1

                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: 140
                                                easing.type: Easing.OutBack
                                            }
                                        }

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 5

                                            MaterialIcon {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: proj.modelData[1]
                                                color: proj.on ? root.accent : root.fg
                                                fontStyle: Tokens.font.icon.size(20).build()
                                                fill: proj.on ? 1 : 0

                                                RotationAnimation on rotation {
                                                    running: root.projPending === proj.modelData[0]
                                                    from: 0
                                                    to: 360
                                                    duration: 900
                                                    loops: Animation.Infinite
                                                    onRunningChanged: if (!running) parent.rotation = 0
                                                }
                                            }
                                            StyledText {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: proj.modelData[2]
                                                color: root.fg
                                                font.pointSize: 8.5
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                        MouseArea {
                                            id: projArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: proj.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (proj.usable && !proj.on) root.setProjection(proj.modelData[0])
                                        }
                                    }
                                }
                            }

                            BigPill {
                                text: qsTr("Position, résolution, échelle…")
                                onClicked: {
                                    root.close();
                                    root.run([root.displayTool]);
                                }
                            }
                        }
                    }
                }

                // ── Caféine : garder l'écran allumé ──
                Column {
                    id: caffPage

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    visible: root.page === "caffeine"
                    spacing: 10

                    // État (cadran radial 270°)
                    Tile {
                        width: parent.width
                        height: 88

                        Rectangle {
                            id: cup

                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            height: 56
                            radius: 16
                            color: Qt.alpha(IdleInhibitor.enabled ? root.amber : root.fg, 0.1)
                            border.width: 0.5
                            border.color: Qt.alpha(IdleInhibitor.enabled ? root.amber : root.fg, 0.32)

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Qt.alpha(root.fg, 0.14)
                                    strokeWidth: 3.5
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 28
                                        centerY: 28
                                        radiusX: 20
                                        radiusY: 20
                                        startAngle: 135
                                        sweepAngle: 270
                                    }
                                }
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: IdleInhibitor.enabled ? root.amber : Qt.alpha(root.fg, 0.25)
                                    strokeWidth: 3.5
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 28
                                        centerY: 28
                                        radiusX: 20
                                        radiusY: 20
                                        startAngle: 135
                                        sweepAngle: IdleInhibitor.enabled ? 270 : 0
                                    }
                                }
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "coffee"
                                fill: IdleInhibitor.enabled ? 1 : 0
                                color: IdleInhibitor.enabled ? root.amber : root.fg
                                fontStyle: Tokens.font.icon.size(20).build()
                            }
                        }
                        Column {
                            anchors.left: cup.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: IdleInhibitor.enabled ? qsTr("VERROU D'ÉVEIL ACTIF") : qsTr("VEILLE AUTOMATIQUE")
                                color: IdleInhibitor.enabled ? root.amber : root.fgDim
                                font.pointSize: 6.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }
                            StyledText {
                                text: IdleInhibitor.enabled ? qsTr("L'écran reste allumé") : qsTr("Veille normale")
                                color: root.fg
                                font.pointSize: 12
                                font.weight: Font.Bold
                            }
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: !IdleInhibitor.enabled ? qsTr("Choisis une durée pour l'activer") : IdleInhibitor.until > 0 ? qsTr("Encore %1 · jusqu'à %2").arg(IdleInhibitor.remainingText()).arg(Qt.formatTime(new Date(IdleInhibitor.until), "HH:mm")) : qsTr("Sans limite · depuis %1").arg(Qt.formatTime(IdleInhibitor.enabledSince, "HH:mm"))
                                color: root.fgDim
                                font.pointSize: 8.5
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    // Durée : un clic active pour ce temps-là
                    Tile {
                        width: parent.width
                        height: 88

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            StyledText {
                                text: qsTr("DURÉE D'ACTIVATION")
                                color: root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            Row {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: [[15, "15 min"], [30, "30 min"], [60, "1 h"], [120, "2 h"], [0, "∞"]]

                                    Rectangle {
                                        id: dur

                                        required property var modelData
                                        readonly property bool on: IdleInhibitor.enabled && root.caffMinutes === modelData[0]

                                        width: (parent.width - 24) / 5
                                        height: 34
                                        radius: 17
                                        color: "transparent"
                                        border.width: 0.5
                                        border.color: on ? Qt.alpha(root.amber, 0.5) : Qt.alpha(root.fg, 0.08)

                                        GlassControl {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            bevel: parent.height > 60 ? 16 : 0
                                            tintColour: on ? root.amber : durMouse.containsMouse ? Qt.alpha(root.fg, 0.14) : root.fgFaint
                                            visible: tintColour.a > 0.01
                                            pressed: durMouse.pressed
                                            hovered: durMouse.containsMouse
                                            pointer: durMouse.containsMouse ? Qt.point(durMouse.mouseX / Math.max(1, width), durMouse.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                        }

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: dur.modelData[1]
                                            color: dur.on ? "#1f1202" : root.fg
                                            font.pointSize: dur.modelData[0] === 0 ? 13 : 9.5
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }
                                        MouseArea {
                                            id: durMouse

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.caffMinutes = dur.modelData[0];
                                                IdleInhibitor.enableFor(dur.modelData[0]);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Veille automatique quand la caféine est coupée
                    Tile {
                        width: parent.width
                        height: idleCol.implicitHeight + 24

                        Column {
                            id: idleCol

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 6

                            StyledText {
                                text: qsTr("MINUTERIES D'INACTIVITÉ (SANS CAFÉINE)")
                                color: root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }

                            Repeater {
                                model: GlobalConfig.general.idle.timeouts

                                Item {
                                    id: idleRow

                                    required property var modelData
                                    required property int index
                                    readonly property bool active: modelData.enabled ?? true
                                    readonly property int minutes: Math.max(1, Math.round(modelData.timeout / 60))

                                    width: parent.width
                                    height: 40
                                    opacity: IdleInhibitor.enabled ? 0.45 : 1

                                    MaterialIcon {
                                        id: idleIcon

                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.idleIcon(idleRow.modelData.idleAction)
                                        color: idleRow.active ? root.fg : root.fgDim
                                        fontStyle: Tokens.font.icon.size(15).build()
                                    }
                                    StyledText {
                                        anchors.left: idleIcon.right
                                        anchors.leftMargin: 10
                                        anchors.right: idleCtl.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: root.idleName(idleRow.modelData.idleAction)
                                        color: idleRow.active ? root.fg : root.fgDim
                                        font.pointSize: 10
                                    }
                                    Row {
                                        id: idleCtl

                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        IconBtn {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: idleRow.active
                                            icon: "remove"
                                            onClicked: root.setIdle(idleRow.index, "timeout", Math.max(1, idleRow.minutes - (idleRow.minutes > 10 ? 5 : 1)) * 60)
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 48
                                            horizontalAlignment: Text.AlignHCenter
                                            text: idleRow.active ? (idleRow.minutes >= 60 && idleRow.minutes % 60 === 0 ? qsTr("%1 h").arg(idleRow.minutes / 60) : qsTr("%1 min").arg(idleRow.minutes)) : qsTr("Jamais")
                                            color: idleRow.active ? root.fg : root.fgDim
                                            font.pointSize: 9.5
                                            font.weight: Font.DemiBold
                                            font.features: {
                                                "tnum": 1
                                            }
                                        }
                                        IconBtn {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: idleRow.active
                                            icon: "add"
                                            onClicked: root.setIdle(idleRow.index, "timeout", Math.min(240, idleRow.minutes + (idleRow.minutes >= 10 ? 5 : 1)) * 60)
                                        }
                                        Switch {
                                            anchors.verticalCenter: parent.verticalCenter
                                            on: idleRow.active
                                            onToggled: root.setIdle(idleRow.index, "enabled", !idleRow.active)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Enregistrement de l'écran ──
                Column {
                    id: recordPage

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    visible: root.page === "record"
                    spacing: 10

                    // En cours : cadran radial 270° + chrono + pause / arrêter
                    Tile {
                        width: parent.width
                        height: 92
                        visible: Recorder.running

                        Rectangle {
                            id: liveDot

                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            height: 56
                            radius: 16
                            color: Qt.alpha(Recorder.paused ? root.amber : root.red, 0.1)
                            border.width: 0.5
                            border.color: Qt.alpha(Recorder.paused ? root.amber : root.red, 0.35)

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Qt.alpha(root.fg, 0.14)
                                    strokeWidth: 3.5
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 28
                                        centerY: 28
                                        radiusX: 20
                                        radiusY: 20
                                        startAngle: 135
                                        sweepAngle: 270
                                    }
                                }
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Recorder.paused ? root.amber : root.red
                                    strokeWidth: 3.5
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 28
                                        centerY: 28
                                        radiusX: 20
                                        radiusY: 20
                                        startAngle: 135
                                        sweepAngle: 270 * Math.max(0.05, (Recorder.elapsed % 60) / 60)
                                    }
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10
                                height: 10
                                radius: Recorder.paused ? 2 : 5
                                color: Recorder.paused ? root.amber : root.red

                                SequentialAnimation on opacity {
                                    running: Recorder.running && !Recorder.paused && root.page === "record"
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
                        }
                        Column {
                            anchors.left: liveDot.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            StyledText {
                                text: Recorder.paused ? qsTr("EN PAUSE") : qsTr("CAPTURE EN DIRECT")
                                color: Recorder.paused ? root.amber : root.red
                                font.pointSize: 6.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }
                            StyledText {
                                text: {
                                    const s = Math.floor(Recorder.elapsed);
                                    return `${Math.floor(s / 60).toString().padStart(2, "0")}:${(s % 60).toString().padStart(2, "0")}`;
                                }
                                color: root.fg
                                font.pointSize: 20
                                font.weight: Font.Bold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            BigPill {
                                text: Recorder.paused ? qsTr("Reprendre") : qsTr("Pause")
                                onClicked: Recorder.togglePause()
                            }
                            BigPill {
                                text: qsTr("Arrêter")
                                red: true
                                onClicked: {
                                    Recorder.stop();
                                    root.close();
                                }
                            }
                        }
                    }

                    // Ce qu'on filme
                    Row {
                        width: parent.width
                        spacing: 10
                        visible: !Recorder.running

                        ChoiceCard {
                            width: (parent.width - 10) / 2
                            icon: "desktop_windows"
                            title: qsTr("Plein écran")
                            subtitle: qsTr("Tout l'écran")
                            on: !root.recRegion
                            onClicked: root.recRegion = false
                        }
                        ChoiceCard {
                            width: (parent.width - 10) / 2
                            icon: "crop_free"
                            title: qsTr("Zone")
                            subtitle: qsTr("Choisie à la souris")
                            on: root.recRegion
                            onClicked: root.recRegion = true
                        }
                    }

                    // Le son
                    Tile {
                        width: parent.width
                        height: 124
                        visible: !Recorder.running

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            StyledText {
                                text: qsTr("PISTES AUDIO")
                                color: root.fgDim
                                font.pointSize: 7.5
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            OptionRow {
                                icon: "volume_up"
                                title: qsTr("Son de l'ordinateur")
                                subtitle: Audio.sink?.description || Audio.sink?.nickname || qsTr("Sortie actuelle")
                                on: root.recSound
                                onToggled: root.recSound = !root.recSound
                            }
                            OptionRow {
                                icon: "mic"
                                title: qsTr("Micro")
                                subtitle: Audio.source?.description || Audio.source?.nickname || qsTr("Entrée actuelle")
                                on: root.recMic
                                onToggled: root.recMic = !root.recMic
                            }
                        }

                        StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            y: 12
                            text: root.recSound && root.recMic ? qsTr("Son + micro") : root.recSound ? qsTr("Son seulement") : root.recMic ? qsTr("Voix seulement") : qsTr("Sans son")
                            color: root.accent
                            font.pointSize: 8
                            font.weight: Font.DemiBold
                        }
                    }

                    // Options
                    Tile {
                        width: parent.width
                        height: 110
                        visible: !Recorder.running

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            OptionRow {
                                icon: "timer_3"
                                title: qsTr("Compte à rebours")
                                subtitle: root.recRegion ? qsTr("Plein écran seulement") : qsTr("3 secondes dans l'île")
                                on: root.recCountdown && !root.recRegion
                                enabled: !root.recRegion
                                onToggled: root.recCountdown = !root.recCountdown
                            }
                            OptionRow {
                                icon: "content_paste"
                                title: qsTr("Copier la vidéo")
                                subtitle: qsTr("Chemin dans le presse-papiers à la fin")
                                on: root.recCopy
                                onToggled: root.recCopy = !root.recCopy
                            }
                        }
                    }

                    // Lancer
                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: 25
                        visible: !Recorder.running
                        color: "transparent"
                        border.width: 0.5
                        border.color: Qt.alpha("white", 0.25)

                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: parent.height > 60 ? 16 : 0
                            tintColour: startArea.pressed ? Qt.darker("#ff453a", 1.1) : startArea.containsMouse ? Qt.lighter("#ff453a", 1.08) : "#ff453a"
                            visible: tintColour.a > 0.01
                            pressed: startArea.pressed
                            hovered: startArea.containsMouse
                            pointer: startArea.containsMouse ? Qt.point(startArea.mouseX / Math.max(1, width), startArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }
                        scale: startArea.pressed ? 0.97 : 1

                        Behavior on scale {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutBack
                            }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 12
                                radius: 6
                                color: "white"
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.recRegion ? qsTr("Choisir la zone et enregistrer") : qsTr("Démarrer l'enregistrement")
                                color: "white"
                                font.pointSize: 10.5
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: startArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startRecording()
                        }
                    }
                }

                // ── Studio Audio (Sorties + Entrée Micro + Mixeur par application) ──
                Flickable {
                    id: audioList

                    anchors.top: subHead.bottom
                    anchors.topMargin: 8
                    anchors.bottom: parent.bottom
                    width: parent.width
                    visible: root.page === "audio"
                    clip: true
                    contentHeight: audioStudioCol.implicitHeight + 8
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: audioStudioCol

                        width: parent.width
                        spacing: 10

                        // 1. Sorties audio (Sinks)
                        Tile {
                            width: parent.width
                            height: sinksCol.implicitHeight + 22

                            Column {
                                id: sinksCol

                                x: 12
                                y: 11
                                width: parent.width - 24
                                spacing: 5

                                StyledText {
                                    text: qsTr("PÉRIPHÉRIQUES DE SORTIE")
                                    color: root.fgDim
                                    font.pointSize: 7.2
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.7
                                }

                                Repeater {
                                    model: Audio.sinks

                                    Rectangle {
                                        id: sinkItem

                                        required property var modelData
                                        readonly property bool current: Audio.sink === modelData

                                        width: sinksCol.width
                                        height: 44
                                        radius: 13
                                        color: "transparent"
                                        border.width: 0.5
                                        border.color: current ? Qt.alpha(root.accent, 0.45) : sinkArea.containsMouse ? Qt.alpha("white", 0.14) : Qt.alpha(root.fg, 0.06)

                                        GlassControl {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            bevel: 0
                                            tintColour: current ? Qt.alpha(root.accent, 0.16) : sinkArea.containsMouse ? root.tileColour : Qt.alpha(root.fg, 0.03)
                                            visible: tintColour.a > 0.01
                                            pressed: sinkArea.pressed
                                            hovered: sinkArea.containsMouse
                                            pointer: sinkArea.containsMouse ? Qt.point(sinkArea.mouseX / Math.max(1, width), sinkArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                        }

                                        Rectangle {
                                            x: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 28
                                            height: 28
                                            radius: 9
                                            color: sinkItem.current ? root.accent : root.fgFaint

                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                text: (sinkItem.modelData.name ?? "").startsWith("bluez") ? "headphones" : (sinkItem.modelData.name ?? "").includes("hdmi") ? "tv" : "speaker"
                                                color: sinkItem.current ? root.onAccent : root.fg
                                                fontStyle: Tokens.font.icon.size(13).build()
                                                fill: 1
                                            }
                                        }
                                        StyledText {
                                            x: 44
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 78
                                            elide: Text.ElideRight
                                            text: sinkItem.modelData.description || sinkItem.modelData.nickname || sinkItem.modelData.name
                                            color: root.fg
                                            font.pointSize: 9.5
                                            font.weight: sinkItem.current ? Font.Bold : Font.DemiBold
                                        }
                                        MaterialIcon {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: sinkItem.current
                                            text: "check_circle"
                                            color: root.accent
                                            fontStyle: Tokens.font.icon.size(13).build()
                                            fill: 1
                                        }

                                        MouseArea {
                                            id: sinkArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Audio.setAudioSink(sinkItem.modelData)
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Entrée Microphone (Gain + Sources)
                        Tile {
                            width: parent.width
                            height: micCol.implicitHeight + 22

                            Column {
                                id: micCol

                                x: 12
                                y: 11
                                width: parent.width - 24
                                spacing: 7

                                Item {
                                    width: parent.width
                                    height: 20

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: qsTr("ENTRÉE MICROPHONE")
                                            color: root.fgDim
                                            font.pointSize: 7.2
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.7
                                        }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: micPctTxt.implicitWidth + 10
                                            height: 17
                                            radius: 8.5
                                            color: Audio.sourceMuted ? Qt.alpha(root.red, 0.16) : Qt.alpha(root.fg, 0.08)
                                            border.width: 0.5
                                            border.color: Audio.sourceMuted ? Qt.alpha(root.red, 0.4) : Qt.alpha(root.fg, 0.12)

                                            StyledText {
                                                id: micPctTxt

                                                anchors.centerIn: parent
                                                text: Audio.sourceMuted ? qsTr("COUPÉ") : `${Math.round(Audio.sourceVolume * 100)} %`
                                                color: Audio.sourceMuted ? root.red : root.fg
                                                font.pointSize: 7
                                                font.weight: Font.Bold
                                                font.features: { "tnum": 1 }
                                            }
                                        }
                                    }
                                }

                                GlassSlider {
                                    width: parent.width
                                    icon: Audio.sourceMuted ? "mic_off" : "mic"
                                    value: Audio.sourceVolume
                                    dim: Audio.sourceMuted
                                    onMoved: v => Audio.setSourceVolume(v)
                                    onIconClicked: {
                                        if (Audio.source?.audio)
                                            Audio.source.audio.muted = !Audio.source.audio.muted;
                                    }
                                }

                                Repeater {
                                    model: Audio.sources

                                    Rectangle {
                                        id: srcItem

                                        required property var modelData
                                        readonly property bool current: Audio.source === modelData

                                        width: micCol.width
                                        height: 38
                                        radius: 11
                                        color: "transparent"
                                        border.width: 0.5
                                        border.color: current ? Qt.alpha(root.accent, 0.4) : Qt.alpha(root.fg, 0.06)

                                        GlassControl {
                                            anchors.fill: parent
                                            radius: parent.radius
                                            bevel: 0
                                            tintColour: current ? Qt.alpha(root.accent, 0.14) : srcArea.containsMouse ? root.tileColour : Qt.alpha(root.fg, 0.02)
                                            visible: tintColour.a > 0.01
                                            pressed: srcArea.pressed
                                            hovered: srcArea.containsMouse
                                            pointer: srcArea.containsMouse ? Qt.point(srcArea.mouseX / Math.max(1, width), srcArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                                        }

                                        MaterialIcon {
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "settings_voice"
                                            color: srcItem.current ? root.accent : root.fgDim
                                            fontStyle: Tokens.font.icon.size(12).build()
                                            fill: 1
                                        }
                                        StyledText {
                                            x: 32
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 62
                                            elide: Text.ElideRight
                                            text: srcItem.modelData.description || srcItem.modelData.nickname || srcItem.modelData.name
                                            color: root.fg
                                            font.pointSize: 8.8
                                            font.weight: srcItem.current ? Font.Bold : Font.Normal
                                        }
                                        MaterialIcon {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: srcItem.current
                                            text: "check"
                                            color: root.accent
                                            fontStyle: Tokens.font.icon.size(12).build()
                                        }

                                        MouseArea {
                                            id: srcArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Audio.setAudioSource(srcItem.modelData)
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Mixeur par application (PipeWire streams)
                        Tile {
                            width: parent.width
                            height: streamsCol.implicitHeight + 22
                            visible: Audio.streams.length > 0

                            Column {
                                id: streamsCol

                                x: 12
                                y: 11
                                width: parent.width - 24
                                spacing: 8

                                StyledText {
                                    text: qsTr("MIXEUR D'APPLICATIONS (%1)").arg(Audio.streams.length)
                                    color: root.fgDim
                                    font.pointSize: 7.2
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.7
                                    font.features: { "tnum": 1 }
                                }

                                Repeater {
                                    model: Audio.streams

                                    Column {
                                        id: streamRow

                                        required property var modelData
                                        readonly property real sVol: Audio.getStreamVolume(modelData)
                                        readonly property bool sMuted: Audio.getStreamMuted(modelData)

                                        width: streamsCol.width
                                        spacing: 4

                                        Item {
                                            width: parent.width
                                            height: 18

                                            StyledText {
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 60
                                                elide: Text.ElideRight
                                                text: Audio.getStreamName(streamRow.modelData)
                                                color: root.fg
                                                font.pointSize: 8.8
                                                font.weight: Font.DemiBold
                                            }
                                            StyledText {
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: streamRow.sMuted ? qsTr("MUET") : `${Math.round(streamRow.sVol * 100)} %`
                                                color: streamRow.sMuted ? root.red : root.fgDim
                                                font.pointSize: 7.8
                                                font.weight: Font.Bold
                                                font.features: { "tnum": 1 }
                                            }
                                        }

                                        GlassSlider {
                                            width: parent.width
                                            height: 22
                                            icon: streamRow.sMuted ? "volume_off" : "graphic_eq"
                                            value: streamRow.sVol
                                            dim: streamRow.sMuted
                                            tint: root.accent
                                            onMoved: v => Audio.setStreamVolume(streamRow.modelData, v)
                                            onIconClicked: Audio.setStreamMuted(streamRow.modelData, !streamRow.sMuted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }

    Timer {
        id: captureDelay

        interval: 420
        onTriggered: root.run(["qs", "-c", "caelestia", "ipc", "call", "picker", "open"])
    }

    // ════════════════════ Composants ════════════════════

    // Plaque de verre biseautée (Liquid Glass optique 0.5px + reflet spéculaire supérieur)
    component Tile: Item {
        property real radius: 22
        property color borderTint: root.tileBorder

        GlassControl {
            anchors.fill: parent
            radius: parent.radius
            bevel: 16
            tintColour: Qt.alpha(Colours.palette.m3onSurface, Colours.light ? 0.05 : 0.065)
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 0.5
            border.color: parent.borderTint

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 0.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(0, parent.width - parent.radius * 1.7)
                height: 0.6
                color: Qt.alpha("white", Colours.light ? 0.45 : 0.16)
            }
        }
    }

    // Ligne de connexion matérielle : puits squircle biseauté + texte + badge télémétrique + chevron
    component ConnRow: Item {
        id: cr

        property string icon
        property string title
        property string subtitle
        property string badgeText: ""
        property bool on
        property bool hasSubpage: false
        property color activeTint: Colours.palette.m3primary
        signal toggle
        signal open

        width: parent?.width ?? 0
        height: 46

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -4
            anchors.rightMargin: -4
            radius: 14
            color: crOpenArea.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.05) : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }
        }

        GlassButton {
            id: crDot

            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 12
            tint: cr.on ? Qt.alpha(cr.activeTint, 0.92) : Qt.alpha(Colours.palette.m3onSurface, 0.1)
            onClicked: cr.toggle()

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: "transparent"
                border.width: 0.5
                border.color: cr.on ? Qt.alpha("white", 0.3) : Qt.alpha(Colours.palette.m3onSurface, 0.12)
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: cr.icon
                color: cr.on ? (cr.activeTint === root.green ? "#05200a" : Colours.palette.m3onPrimary) : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.size(14).build()
                fill: 1
            }
        }

        Column {
            anchors.left: crDot.right
            anchors.leftMargin: 9
            anchors.right: crRightRow.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0.5

            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: cr.title
                color: Colours.palette.m3onSurface
                font.pointSize: 9.2
                font.weight: Font.Bold
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: cr.subtitle
                color: cr.on ? cr.activeTint : Qt.alpha(Colours.palette.m3onSurface, 0.55)
                font.pointSize: 7.8
                font.weight: cr.on ? Font.DemiBold : Font.Normal
            }
        }

        Row {
            id: crRightRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: cr.badgeText !== ""
                width: crBadgeLbl.implicitWidth + 9
                height: 17
                radius: 8.5
                color: Qt.alpha(cr.activeTint, 0.15)
                border.width: 0.5
                border.color: Qt.alpha(cr.activeTint, 0.35)

                StyledText {
                    id: crBadgeLbl

                    anchors.centerIn: parent
                    text: cr.badgeText
                    color: cr.activeTint
                    font.pointSize: 6.8
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
            }

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: cr.hasSubpage
                text: "chevron_right"
                color: Qt.alpha(Colours.palette.m3onSurface, crOpenArea.containsMouse ? 0.8 : 0.4)
                fontStyle: Tokens.font.icon.size(12).build()
            }
        }

        MouseArea {
            id: crOpenArea

            anchors.left: crDot.right
            anchors.right: parent.right
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cr.open()
        }
    }

    // Grande tuile à bascule en verre biseautée (Concentration, Apparence)
    component WideToggle: GlassButton {
        id: wt

        property string icon
        property string title
        property string subtitle
        property bool on
        property bool hasSubpage: false
        property color activeTint: Colours.palette.m3primary

        implicitHeight: 83
        radius: 22
        bevel: 16
        tint: wt.on ? Qt.alpha(wt.activeTint, 0.15) : Qt.alpha(Colours.palette.m3onSurface, 0.065)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 0.5
            border.color: wt.on ? Qt.alpha(wt.activeTint, 0.42) : root.tileBorder

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 0.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(0, parent.width - parent.radius * 1.7)
                height: 0.6
                color: Qt.alpha("white", Colours.light ? 0.45 : 0.16)
            }
        }

        GlassControl {
            id: wtDot

            x: 11
            y: 11
            width: 32
            height: 32
            radius: 11
            tintColour: wt.on ? Qt.alpha(wt.activeTint, 0.92) : Qt.alpha(Colours.palette.m3onSurface, 0.11)

            Rectangle {
                anchors.fill: parent
                radius: 11
                color: "transparent"
                border.width: 0.5
                border.color: wt.on ? Qt.alpha("white", 0.3) : Qt.alpha(Colours.palette.m3onSurface, 0.1)
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: wt.icon
                color: wt.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.size(13).build()
                fill: 1
            }
        }

        // Indicateur lumineux ou chevron en haut à droite
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 11
            anchors.top: parent.top
            anchors.topMargin: 13
            spacing: 4

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: wt.on
                width: 6
                height: 6
                radius: 3
                color: wt.activeTint
            }
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: wt.hasSubpage
                text: "chevron_right"
                color: Qt.alpha(Colours.palette.m3onSurface, 0.45)
                fontStyle: Tokens.font.icon.size(11).build()
            }
        }

        Column {
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 9
            width: parent.width - 24
            spacing: 0.5

            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: wt.title
                color: Colours.palette.m3onSurface
                font.pointSize: 9.2
                font.weight: Font.Bold
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: wt.subtitle
                color: wt.on ? wt.activeTint : Qt.alpha(Colours.palette.m3onSurface, 0.58)
                font.pointSize: 7.8
                font.weight: wt.on ? Font.DemiBold : Font.Normal
            }
        }
    }

    // Cellule matérielle biseautée pour la grille 4x2 de raccourcis rapides
    component RoundToggle: GlassButton {
        id: rt

        property string icon
        property string label
        property bool on
        property color activeTint: Colours.palette.m3primary

        width: 82
        height: 58
        radius: 16
        bevel: 12
        tint: rt.on ? Qt.alpha(rt.activeTint, 0.22) : Qt.alpha(Colours.palette.m3onSurface, rt.hovered ? 0.11 : 0.065)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 0.5
            border.color: rt.on ? Qt.alpha(rt.activeTint, 0.55) : Qt.alpha(Colours.palette.m3onSurface, rt.hovered ? 0.18 : 0.09)

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 0.5
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(0, parent.width - parent.radius * 1.6)
                height: 0.5
                color: Qt.alpha("white", Colours.light ? 0.4 : 0.14)
            }
        }

        // Point témoin LED actif en haut à droite
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 8
            width: 5
            height: 5
            radius: 2.5
            visible: rt.on
            color: rt.activeTint
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 8
            spacing: 4

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: rt.icon
                color: rt.on ? rt.activeTint : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.size(15).build()
                fill: rt.on ? 1 : 0
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: rt.label
                color: rt.on ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.78)
                font.pointSize: 7.4
                font.weight: rt.on ? Font.Bold : Font.DemiBold
            }
        }
    }

    // Jauge matérielle en verre biseauté, graduée, glissable + molette de précision
    component GlassSlider: Item {
        id: gs

        property string icon
        property real value
        property bool dim
        property color tint: Colours.palette.m3onSurface
        signal moved(real v)
        signal iconClicked

        height: 28

        Item {
            id: track

            anchors.fill: parent
            scale: gsArea.pressed ? 1.03 : 1

            Behavior on scale {
                SpringAnimation {
                    spring: 5
                    damping: 0.35
                }
            }

            GlassControl {
                anchors.fill: parent
                radius: height / 2
                bevel: 10
                tintColour: Qt.alpha(Colours.palette.m3onSurface, 0.1)
                hovered: gsArea.containsMouse
                pointer: gsArea.containsMouse ? Qt.point((gsArea.mouseX + 30) / track.width, gsArea.mouseY / track.height) : Qt.point(-1, -1)
            }

            // Graduations optiques subtiles (25 %, 50 %, 75 %)
            Repeater {
                model: [0.25, 0.5, 0.75]

                Rectangle {
                    required property real modelData
                    x: parent.width * modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 6
                    radius: 0.5
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.14)
                }
            }

            GlassControl {
                id: fillBar

                height: parent.height
                width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, gs.value)))
                radius: height / 2
                bevel: 10
                tintColour: gs.dim ? Qt.alpha(Colours.palette.m3onSurface, 0.35) : Qt.alpha(gs.tint, 0.92)
                pressed: gsArea.pressed

                Behavior on width {
                    enabled: !gsArea.pressed

                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }

                // Curseur vertical optique à l'extrémité droite
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2.5
                    height: 10
                    radius: 1.25
                    visible: fillBar.width > parent.height + 10
                    color: gs.dim ? Qt.alpha(Colours.palette.m3onSurface, 0.5) : Qt.alpha(Colours.palette.m3surface, 0.55)
                }
            }

            // Biseau optique sur le pourtour de la piste
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 0.5
                border.color: gsArea.containsMouse ? Qt.alpha("white", 0.22) : Qt.alpha(Colours.palette.m3onSurface, 0.12)
            }

            MouseArea {
                id: gsArea

                anchors.fill: parent
                anchors.leftMargin: 30
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: e => gs.moved(Math.max(0, Math.min(1, (e.x + 30) / track.width)))
                onPositionChanged: e => {
                    if (pressed)
                        gs.moved(Math.max(0, Math.min(1, (e.x + 30) / track.width)));
                }
                onWheel: wheel => {
                    const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02;
                    gs.moved(Math.max(0, Math.min(1, gs.value + step)));
                }
            }
        }

        MaterialIcon {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: gs.icon
            color: gs.value > 0.08 && !gs.dim ? Colours.palette.m3surface : Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.size(12).build()
            fill: 1

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: gs.iconClicked()
            }
        }
    }

    // Bouton icône rond en verre biseauté
    component IconBtn: GlassButton {
        id: ib

        property string icon
        property bool big
        property bool danger
        property bool spinning

        width: big ? 38 : 32
        height: width
        tint: ib.danger ? Qt.alpha("#ff453a", 0.18) : Qt.alpha(Colours.palette.m3onSurface, ib.hovered ? 0.12 : 0.05)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 0.5
            border.color: ib.danger ? Qt.alpha("#ff453a", 0.4) : Qt.alpha(Colours.palette.m3onSurface, ib.hovered ? 0.18 : 0.08)
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: ib.icon
            color: ib.danger ? "#ff453a" : Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.size(ib.big ? 18 : 13).build()
            fill: 1

            RotationAnimation on rotation {
                running: ib.spinning
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }
    }

    // Grande carte de choix en verre biseautée (plein écran / zone)
    component ChoiceCard: GlassButton {
        id: cc

        property string icon
        property string title
        property string subtitle
        property bool on

        height: 104
        radius: 22
        bevel: 16
        tint: cc.on ? Qt.alpha(Colours.palette.m3primary, 0.24) : Qt.alpha(Colours.palette.m3onSurface, 0.065)

        Rectangle {
            anchors.fill: parent
            radius: 22
            color: "transparent"
            border.width: cc.on ? 1.5 : 0.5
            border.color: cc.on ? Qt.alpha(Colours.palette.m3primary, 0.75) : root.tileBorder
        }

        Column {
            anchors.centerIn: parent
            spacing: 4

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: cc.icon
                color: cc.on ? Colours.palette.m3primary : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.size(22).build()
                fill: cc.on ? 1 : 0
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: cc.title
                color: Colours.palette.m3onSurface
                font.pointSize: 10
                font.weight: Font.Bold
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: cc.subtitle
                color: Qt.alpha(Colours.palette.m3onSurface, 0.6)
                font.pointSize: 8
            }
        }
    }

    // Ligne d'option : icône, texte, interrupteur
    component OptionRow: Item {
        id: orow

        property string icon
        property string title
        property string subtitle
        property bool on
        signal toggled

        width: parent?.width ?? 0
        height: 44
        opacity: enabled ? 1 : 0.45

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: orow.icon
            color: orow.on ? Colours.palette.m3primary : Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.size(14).build()
            fill: 1
        }
        Column {
            x: 30
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 90

            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: orow.title
                color: Colours.palette.m3onSurface
                font.pointSize: 9.5
                font.weight: Font.DemiBold
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: orow.subtitle
                color: Qt.alpha(Colours.palette.m3onSurface, 0.6)
                font.pointSize: 8
            }
        }
        Switch {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            on: orow.on
            onToggled: orow.toggled()
        }
    }

    // Pilule en verre biseautée (rouge pour les actions risquées)
    component BigPill: GlassButton {
        id: bp

        property string text
        property bool red

        width: bpLbl.implicitWidth + 30
        height: 38
        tint: bp.red ? Qt.alpha("#ff453a", 0.88) : Qt.alpha(Colours.palette.m3onSurface, 0.12)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 0.5
            border.color: bp.red ? Qt.alpha("white", 0.3) : Qt.alpha(Colours.palette.m3onSurface, 0.15)
        }

        StyledText {
            id: bpLbl

            anchors.centerIn: parent
            text: bp.text
            color: bp.red ? "white" : Colours.palette.m3onSurface
            font.pointSize: 9.5
            font.weight: Font.Bold
        }
    }

    // Interrupteur façon iOS 27 : piste en verre biseautée, pastille-lentille qui s'étire à l'appui
    component Switch: Item {
        id: sw

        property bool on
        signal toggled

        width: 44
        height: 26

        GlassControl {
            anchors.fill: parent
            bevel: 9
            tintColour: sw.on ? Qt.alpha("#32d74b", 0.92) : Qt.alpha(Colours.palette.m3onSurface, 0.16)
        }

        Rectangle {
            anchors.fill: parent
            radius: 13
            color: "transparent"
            border.width: 0.5
            border.color: sw.on ? Qt.alpha("white", 0.28) : Qt.alpha(Colours.palette.m3onSurface, 0.15)
        }

        GlassControl {
            x: sw.on ? sw.width - width - 3 : 3
            y: 3
            width: swArea.pressed ? 28 : 20
            height: 20
            tintColour: Qt.alpha("white", 0.96)
            pressed: swArea.pressed

            Behavior on x {
                NumberAnimation {
                    duration: 240
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.4
                }
            }
            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutBack
                }
            }
        }

        MouseArea {
            id: swArea

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }
}

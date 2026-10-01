pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// Horloge façon macOS 27 (Super + Maj + O), dans le même verre que l'île :
// une goutte tombe de l'île ; Minuteur, Chrono, Pomodoro et Alarmes.
// L'île reste la source de vérité : commandes `qs ipc call island …`, état lu dans
// ~/.local/state/caelestia/island-clock.json, alarmes dans ~/.local/share/caelestia/alarms.json.
// Tout continue dans l'île une fois le panneau fermé.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.clock ?? false

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
    readonly property color orange: "#ff9f0a"
    readonly property color green: "#32d74b"
    readonly property color red: "#ff453a"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── Onglets ──
    readonly property var tabs: [
        {
            key: "timer",
            glyph: "󰔛",
            title: qsTr("Minuteur")
        },
        {
            key: "stopwatch",
            glyph: "󱎫",
            title: qsTr("Chrono")
        },
        {
            key: "pomodoro",
            glyph: "󰄉",
            title: qsTr("Pomodoro")
        },
        {
            key: "alarms",
            glyph: "󰀠",
            title: qsTr("Alarmes")
        }
    ]
    property int tab: 0

    // ── État de l'île ──
    property var st: ({})
    property real now: Date.now()
    readonly property string kind: st.kind ?? ""
    readonly property bool paused: !!st.paused
    readonly property var pomo: st.pomodoro ?? {}
    readonly property bool pomoOn: !!pomo.on && kind === "timer"
    readonly property bool timerOn: kind === "timer" && !pomoOn
    readonly property bool swOn: kind === "stopwatch"
    readonly property var ring: st.ring ?? null
    readonly property real total: Math.max(1, st.total ?? 1)
    readonly property real value: {
        const t = st.paused || now;
        if (kind === "timer")
            return Math.max(0, ((st.end ?? 0) - t) / 1000);
        if (kind === "stopwatch")
            return (t - (st.start ?? 0)) / 1000;
        return 0;
    }
    readonly property var laps: swOn ? (st.laps ?? []) : []

    // ── Réglages (gardés d'une fois sur l'autre) ──
    property int tH: 0
    property int tM: 5
    property int tS: 0
    property int work: 25
    property int rest: 5
    property var alarms: []
    property bool editing: false
    property int aH: 7
    property int aM: 0
    property var aDays: []

    function close(): void {
        screenState.clock = false;
    }

    function cmd(args: var): void {
        Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "island", ...args]);
    }

    function fmt(sec: real, centi: bool): string {
        sec = Math.max(0, sec);
        const h = Math.floor(sec / 3600);
        const m = Math.floor(sec % 3600 / 60);
        const s = Math.floor(sec % 60);
        const p = n => n.toString().padStart(2, "0");
        if (centi) {
            const cs = Math.floor((sec - Math.floor(sec)) * 100);
            return (h ? `${h}:${p(m)}` : p(m)) + `:${p(s)},${p(cs)}`;
        }
        return h ? `${h}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
    }

    function timerMain(): void {
        if (timerOn)
            cmd(["pause"]);
        else {
            const sec = tH * 3600 + tM * 60 + tS;
            if (sec > 0)
                cmd(["timerFor", `${sec}s`, timerName.text.trim()]);
            savePrefs();
        }
    }

    function stopwatchMain(): void {
        cmd([swOn ? "pause" : "stopwatch"]);
    }

    function pomoMain(): void {
        if (pomoOn)
            cmd(["pause"]);
        else {
            cmd(["pomodoro", `${work}m`, `${rest}m`]);
            savePrefs();
        }
    }

    function mainAction(): void {
        if (tab === 0)
            timerMain();
        else if (tab === 1)
            stopwatchMain();
        else if (tab === 2)
            pomoMain();
    }

    function savePrefs(): void {
        prefsFile.setText(JSON.stringify({
            tab: tabs[tab].key,
            timer: [tH, tM, tS],
            work: work,
            rest: rest
        }));
    }

    function saveAlarms(list: var): void {
        list.sort((a, b) => a.time.localeCompare(b.time));
        alarms = list;
        alarmsFile.setText(JSON.stringify(list, null, 2));
    }

    function addAlarm(): void {
        const p = n => n.toString().padStart(2, "0");
        saveAlarms([...alarms, {
                id: Math.random().toString(16).slice(2, 10),
                time: `${p(aH)}:${p(aM)}`,
                label: alarmName.text.trim(),
                days: aDays,
                enabled: true
            }]);
        alarmName.text = "";
        aDays = [];
        editing = false;
    }

    function daysText(days: var): string {
        if (!days || days.length === 0)
            return qsTr("Une fois");
        const s = [...days].sort().join(",");
        if (s === "0,1,2,3,4,5,6")
            return qsTr("Tous les jours");
        if (s === "1,2,3,4,5")
            return qsTr("En semaine");
        if (s === "0,6")
            return qsTr("Le week-end");
        const names = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."];
        return [1, 2, 3, 4, 5, 6, 0].filter(d => days.includes(d)).map(d => names[d]).join(" ");
    }

    readonly property string nextAlarm: {
        const n = new Date(now);
        let best = null;
        for (const a of alarms) {
            if (!a.enabled)
                continue;
            const [h, m] = a.time.split(":").map(Number);
            for (let add = 0; add < 8; add++) {
                const d = new Date(n.getFullYear(), n.getMonth(), n.getDate() + add, h, m, 0);
                if (d > n && (!a.days?.length || a.days.includes(d.getDay()))) {
                    if (!best || d < best)
                        best = d;
                    break;
                }
            }
        }
        if (!best)
            return qsTr("Aucune alarme prévue");
        const mins = Math.floor((best - n) / 60000);
        const h = Math.floor(mins / 60);
        return h ? qsTr("Prochaine alarme dans %1 h %2").arg(h).arg((mins % 60).toString().padStart(2, "0")) : qsTr("Prochaine alarme dans %1 min").arg(mins % 60);
    }

    visible: morph > 0.001
    implicitWidth: 470
    implicitHeight: 600 + (ring ? 78 : 0)

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
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
            stateFile.reload();
            alarmsFile.reload();
            editing = false;
            // Ouvre l'onglet de ce qui tourne
            if (pomoOn)
                tab = 2;
            else if (swOn)
                tab = 1;
            else if (timerOn)
                tab = 0;
            content.forceActiveFocus();
        }
    }

    // Rafraîchissement fluide pendant qu'un minuteur ou un chrono tourne
    Timer {
        interval: root.swOn ? 33 : 250
        repeat: true
        running: root.shown
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    FileView {
        id: stateFile

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/island-clock.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.st = JSON.parse(text()) ?? {};
            } catch (e) {}
        }
    }

    FileView {
        id: alarmsFile

        path: `${Quickshell.env("HOME")}/.local/share/caelestia/alarms.json`
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.alarms = JSON.parse(text()) ?? [];
            } catch (e) {
                root.alarms = [];
            }
        }
    }

    FileView {
        id: prefsFile

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/clock-app.json`
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const p = JSON.parse(text());
                const t = p.timer ?? [0, 5, 0];
                root.tH = t[0];
                root.tM = t[1];
                root.tS = t[2];
                root.work = p.work ?? 25;
                root.rest = p.rest ?? 5;
                root.tab = Math.max(0, root.tabs.findIndex(t => t.key === p.tab));
            } catch (e) {}
        }
    }

    // ── Petits composants ──

    // Anneau de progression lumineux (minuteur, pomodoro)
    component ProgressRing: Item {
        id: pr

        property real progress: 1
        property color colour: root.orange
        property bool dim
        property real lw: 13

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: pr.lw
                strokeColor: root.fgFaint
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: pr.width / 2
                    centerY: pr.height / 2
                    radiusX: pr.width / 2 - pr.lw
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }
            // Halo sous l'arc
            ShapePath {
                strokeWidth: pr.lw + 12
                strokeColor: Qt.alpha(pr.colour, pr.dim ? 0.05 : 0.13)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: pr.width / 2
                    centerY: pr.height / 2
                    radiusX: pr.width / 2 - pr.lw
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0.0001, pr.progress)
                }
            }
            ShapePath {
                strokeWidth: pr.lw
                strokeColor: Qt.alpha(pr.colour, pr.dim ? 0.45 : 1)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: pr.width / 2
                    centerY: pr.height / 2
                    radiusX: pr.width / 2 - pr.lw
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0.0001, pr.progress)
                }
            }
        }

        // Point lumineux au bout de l'arc
        Rectangle {
            readonly property real a: (-90 + 360 * pr.progress) * Math.PI / 180
            readonly property real r: pr.width / 2 - pr.lw

            visible: pr.progress > 0.002
            width: pr.lw - 6
            height: width
            radius: width / 2
            x: pr.width / 2 + r * Math.cos(a) - width / 2
            y: pr.height / 2 + r * Math.sin(a) - height / 2
            color: Qt.alpha("white", pr.dim ? 0.5 : 0.95)
        }
    }

    // Bouton pilule (gris, orange, vert, rouge)
    component Pill: Rectangle {
        id: pill

        property string text
        property color tint: Qt.alpha(root.fg, 0.12)
        property color textColour: root.fg
        property bool enabledPill: true
        signal clicked

        width: Math.max(96, lbl.implicitWidth + 36)
        height: 42
        radius: 21
        color: pillArea.containsMouse && enabledPill ? Qt.lighter(tint, 1.18) : tint
        opacity: enabledPill ? 1 : 0.4
        scale: pillArea.pressed && enabledPill ? 0.94 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Text {
            id: lbl

            anchors.centerIn: parent
            text: pill.text
            color: pill.textColour
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: pillArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pill.enabledPill ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (pill.enabledPill)
                pill.clicked()
        }
    }

    // Roue de réglage d'un nombre : molette, ▲ ▼
    component Wheel: Item {
        id: wh

        property int value
        property int max: 59
        property string unit
        signal changed(int v)

        function step(d: int): void {
            wh.changed((value + d + max + 1) % (max + 1));
        }

        width: 74
        height: 112

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            text: "󰅃"
            font.family: root.glyphFont
            font.pixelSize: 18
            color: upArea.containsMouse ? root.fg : root.fgDim

            MouseArea {
                id: upArea

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: wh.step(1)
            }
        }

        Text {
            anchors.centerIn: parent
            text: wh.value.toString().padStart(2, "0")
            color: root.fg
            font.pixelSize: 44
            font.weight: Font.Light
            font.features: {
                "tnum": 1
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            text: wh.unit
            color: root.fgDim
            font.pixelSize: 11
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: "󰅀"
            font.family: root.glyphFont
            font.pixelSize: 18
            color: downArea.containsMouse ? root.fg : root.fgDim

            MouseArea {
                id: downArea

                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: wh.step(-1)
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: 24
            anchors.bottomMargin: 24
            acceptedButtons: Qt.NoButton
            onWheel: wheel => wh.step(wheel.angleDelta.y > 0 ? 1 : -1)
        }
    }

    // Champ texte arrondi
    component Field: Rectangle {
        id: fld

        property alias text: ti.text
        property string placeholder
        signal accepted

        height: 40
        radius: 20
        color: Qt.alpha(root.fg, 0.07)
        border.width: 1
        border.color: ti.activeFocus ? Qt.alpha(root.accent, 0.6) : Qt.alpha(root.fg, 0.08)

        TextInput {
            id: ti

            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            verticalAlignment: TextInput.AlignVCenter
            color: root.fg
            selectionColor: Qt.alpha(root.accent, 0.4)
            font.pixelSize: 13
            clip: true
            onAccepted: fld.accepted()
            Keys.onEscapePressed: content.forceActiveFocus()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !ti.text
                text: fld.placeholder
                color: Qt.alpha(root.fg, 0.38)
                font: ti.font
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
                const k = event.key;
                const ctrl = event.modifiers & Qt.ControlModifier;
                if (k === Qt.Key_Escape) {
                    if (root.editing)
                        root.editing = false;
                    else
                        root.close();
                } else if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_4)
                    root.tab = k - Qt.Key_1;
                else if (k === Qt.Key_Tab)
                    root.tab = (root.tab + 1) % 4;
                else if (k === Qt.Key_Backtab)
                    root.tab = (root.tab + 3) % 4;
                else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter)
                    root.mainAction();
                else
                    return;
                event.accepted = true;
            }

            MouseArea {
                anchors.fill: parent
                onClicked: content.forceActiveFocus()
            }

            // ── Bandeau « ça sonne » ──
            Rectangle {
                id: banner

                x: 14
                y: 14
                width: parent.width - 28
                height: root.ring ? 64 : 0
                radius: 20
                color: Qt.alpha(root.orange, 0.2)
                border.width: 1
                border.color: Qt.alpha(root.orange, 0.5)
                opacity: root.ring ? 1 : 0
                visible: opacity > 0.01
                clip: true

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Text {
                    id: bellIcon

                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: ({
                            timer: "󰔛",
                            pomoWork: "󰒲",
                            pomoRest: "󱐋"
                        })[root.ring?.kind] ?? "󰀠"
                    font.family: root.glyphFont
                    font.pixelSize: 24
                    color: root.orange

                    SequentialAnimation on rotation {
                        running: !!root.ring && root.shown
                        loops: Animation.Infinite

                        NumberAnimation {
                            to: 14
                            duration: 90
                        }
                        NumberAnimation {
                            to: -14
                            duration: 180
                        }
                        NumberAnimation {
                            to: 0
                            duration: 90
                        }
                        PauseAnimation {
                            duration: 700
                        }
                    }
                }

                Column {
                    anchors.left: bellIcon.right
                    anchors.leftMargin: 12
                    anchors.right: bannerBtns.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: root.ring?.kind === "alarm" ? `${root.ring?.sub ?? ""}  ·  ${root.ring?.label ?? ""}` : root.ring?.label ?? ""
                        color: root.fg
                        elide: Text.ElideRight
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        readonly property int since: Math.max(0, Math.floor((root.now - (root.ring?.since ?? root.now)) / 1000))

                        text: qsTr("Sonne depuis %1").arg(`${Math.floor(since / 60)}:${(since % 60).toString().padStart(2, "0")}`)
                        color: root.fgDim
                        font.pixelSize: 11
                    }
                }

                Row {
                    id: bannerBtns

                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Pill {
                        height: 36
                        readonly property bool pomoRing: (root.ring?.kind ?? "").startsWith("pomo")
                        text: pomoRing ? qsTr("Terminer") : root.ring?.kind === "timer" ? qsTr("Relancer") : qsTr("Répéter")
                        onClicked: root.cmd([pomoRing ? "stopAll" : "snooze"])
                    }
                    Pill {
                        height: 36
                        tint: root.orange
                        textColour: "white"
                        text: ({
                                pomoWork: qsTr("Pause"),
                                pomoRest: qsTr("Reprendre")
                            })[root.ring?.kind] ?? qsTr("Arrêter")
                        onClicked: root.cmd([(root.ring?.kind ?? "").startsWith("pomo") ? "ringNext" : "stopAlarm"])
                    }
                }
            }

            // ── Contrôle segmenté avec pastille qui glisse ──
            Rectangle {
                id: seg

                anchors.horizontalCenter: parent.horizontalCenter
                y: (root.ring ? banner.y + 64 + 12 : 18)
                width: parent.width - 40
                height: 40
                radius: 20
                color: Qt.alpha(root.fg, 0.07)

                Behavior on y {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    x: 3 + root.tab * (seg.width - 6) / 4
                    y: 3
                    width: (seg.width - 6) / 4
                    height: seg.height - 6
                    radius: height / 2
                    color: Qt.alpha(root.fg, Colours.light ? 0.9 : 0.16)
                    border.width: 1
                    border.color: Qt.alpha(root.fg, 0.12)

                    Behavior on x {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 3

                    Repeater {
                        model: root.tabs

                        Item {
                            id: tabItem

                            required property var modelData
                            required property int index

                            width: (seg.width - 6) / 4
                            height: parent.height

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: tabItem.modelData.glyph
                                    font.family: root.glyphFont
                                    font.pixelSize: 14
                                    color: root.tab === tabItem.index ? root.orange : root.fgDim
                                }
                                Text {
                                    text: tabItem.modelData.title
                                    color: root.tab === tabItem.index ? root.fg : root.fgDim
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.tab = tabItem.index;
                                    root.savePrefs();
                                    content.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            // ── Pages : elles glissent de gauche à droite ──
            Item {
                id: pages

                anchors.top: seg.bottom
                anchors.topMargin: 18
                anchors.bottom: footer.top
                width: parent.width
                clip: true

                Row {
                    x: -root.tab * pages.width
                    height: parent.height

                    Behavior on x {
                        NumberAnimation {
                            duration: 380
                            easing.type: Easing.OutCubic
                        }
                    }

                    // ═══ Minuteur ═══
                    Item {
                        width: pages.width
                        height: pages.height

                        ProgressRing {
                            id: tRing

                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 270
                            height: 270
                            progress: root.timerOn ? root.value / root.total : 1
                            dim: root.paused || !root.timerOn

                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                visible: root.timerOn

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.st.label || qsTr("Minuteur")
                                    color: root.fgDim
                                    font.pixelSize: 13
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.fmt(root.value, false)
                                    color: root.fg
                                    font.pixelSize: 54
                                    font.weight: Font.Light
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.paused ? qsTr("En pause") : qsTr("Fin à %1").arg(Qt.formatTime(new Date(root.st.end ?? 0), "HH:mm"))
                                    color: root.paused ? root.orange : root.fgDim
                                    font.pixelSize: 12
                                }
                            }

                            Row {
                                anchors.centerIn: parent
                                visible: !root.timerOn

                                Wheel {
                                    value: root.tH
                                    max: 23
                                    unit: "h"
                                    onChanged: v => root.tH = v
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -4
                                    text: ":"
                                    color: root.fgDim
                                    font.pixelSize: 36
                                }
                                Wheel {
                                    value: root.tM
                                    unit: "min"
                                    onChanged: v => root.tM = v
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -4
                                    text: ":"
                                    color: root.fgDim
                                    font.pixelSize: 36
                                }
                                Wheel {
                                    value: root.tS
                                    unit: "s"
                                    onChanged: v => root.tS = v
                                }
                            }
                        }

                        // Durées rapides + nom
                        Flow {
                            id: presets

                            anchors.top: tRing.bottom
                            anchors.topMargin: 14
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 5 * 74 + 4 * 6
                            spacing: 6
                            visible: !root.timerOn

                            Repeater {
                                model: [1, 3, 5, 10, 15, 20, 25, 30, 45, 60]

                                Rectangle {
                                    id: chip

                                    required property int modelData
                                    readonly property bool active: root.tH * 60 + root.tM === modelData && root.tS === 0

                                    width: 74
                                    height: 30
                                    radius: 15
                                    color: active ? Qt.alpha(root.orange, 0.25) : chipArea.containsMouse ? Qt.alpha(root.fg, 0.12) : Qt.alpha(root.fg, 0.06)
                                    border.width: 1
                                    border.color: active ? Qt.alpha(root.orange, 0.6) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: chip.modelData < 60 ? `${chip.modelData} min` : "1 h"
                                        color: chip.active ? root.orange : root.fg
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: chipArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.tH = Math.floor(chip.modelData / 60);
                                            root.tM = chip.modelData % 60;
                                            root.tS = 0;
                                        }
                                    }
                                }
                            }
                        }

                        Field {
                            id: timerName

                            anchors.top: presets.bottom
                            anchors.topMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: presets.width
                            visible: !root.timerOn
                            placeholder: qsTr("Nom du minuteur (optionnel) — ex. Pâtes")
                            onAccepted: root.timerMain()
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Pill {
                                text: qsTr("Annuler")
                                enabledPill: root.timerOn
                                onClicked: root.cmd(["stop"])
                            }
                            Pill {
                                visible: root.timerOn
                                text: qsTr("+1 min")
                                onClicked: root.cmd(["addMinute"])
                            }
                            Pill {
                                tint: root.timerOn && !root.paused ? Qt.alpha(root.orange, 0.25) : root.orange
                                textColour: root.timerOn && !root.paused ? root.orange : "white"
                                text: root.timerOn ? (root.paused ? qsTr("Reprendre") : qsTr("Pause")) : qsTr("Démarrer")
                                onClicked: root.timerMain()
                            }
                        }
                    }

                    // ═══ Chrono ═══
                    Item {
                        width: pages.width
                        height: pages.height

                        // Cadran : graduations + aiguilles (tour en cours et total)
                        Canvas {
                            id: dial

                            readonly property real elapsed: root.swOn ? root.value : 0
                            readonly property real lapElapsed: root.laps.length ? elapsed - root.laps[root.laps.length - 1] : -1

                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 230
                            height: 230
                            onElapsedChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                const w = width, h = height, cx = w / 2, cy = h / 2, r = w / 2 - 4;
                                ctx.reset();
                                const fgc = root.fg;
                                for (let i = 0; i < 240; i += 4) {
                                    const a = i / 240 * Math.PI * 2 - Math.PI / 2;
                                    const major = i % 20 === 0;
                                    const ln = major ? 12 : 6;
                                    ctx.strokeStyle = Qt.rgba(fgc.r, fgc.g, fgc.b, major ? 0.85 : 0.3);
                                    ctx.lineWidth = major ? 2.2 : 1.2;
                                    ctx.beginPath();
                                    ctx.moveTo(cx + (r - ln) * Math.cos(a), cy + (r - ln) * Math.sin(a));
                                    ctx.lineTo(cx + r * Math.cos(a), cy + r * Math.sin(a));
                                    ctx.stroke();
                                }
                                ctx.fillStyle = Qt.rgba(fgc.r, fgc.g, fgc.b, 0.7);
                                ctx.font = "12px sans-serif";
                                ctx.textAlign = "center";
                                ctx.textBaseline = "middle";
                                for (let n = 5; n <= 60; n += 5) {
                                    const a = n / 60 * Math.PI * 2 - Math.PI / 2;
                                    ctx.fillText(n.toString(), cx + (r - 28) * Math.cos(a), cy + (r - 28) * Math.sin(a));
                                }
                                const hand = (v, col, wd) => {
                                    const a = (v % 60) / 60 * Math.PI * 2 - Math.PI / 2;
                                    ctx.strokeStyle = col;
                                    ctx.lineWidth = wd;
                                    ctx.lineCap = "round";
                                    ctx.beginPath();
                                    ctx.moveTo(cx - 16 * Math.cos(a), cy - 16 * Math.sin(a));
                                    ctx.lineTo(cx + (r - 8) * Math.cos(a), cy + (r - 8) * Math.sin(a));
                                    ctx.stroke();
                                };
                                if (lapElapsed >= 0)
                                    hand(lapElapsed, root.accent, 2.5);
                                hand(elapsed, root.orange, 3);
                                ctx.fillStyle = root.orange;
                                ctx.beginPath();
                                ctx.arc(cx, cy, 5.5, 0, Math.PI * 2);
                                ctx.fill();
                            }
                        }

                        Text {
                            id: swTime

                            anchors.top: dial.bottom
                            anchors.topMargin: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.fmt(root.swOn ? root.value : 0, true)
                            color: root.fg
                            font.pixelSize: 46
                            font.weight: Font.Light
                            font.features: {
                                "tnum": 1
                            }
                        }

                        // Tours : meilleur en vert, plus lent en rouge
                        ListView {
                            anchors.top: swTime.bottom
                            anchors.topMargin: 6
                            anchors.bottom: swBtns.top
                            anchors.bottomMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 60
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: {
                                const l = root.laps;
                                const splits = l.map((v, i) => v - (i ? l[i - 1] : 0));
                                const best = splits.length > 1 ? Math.min(...splits) : -1;
                                const worst = splits.length > 1 ? Math.max(...splits) : -1;
                                return splits.map((s, i) => ({
                                            n: i + 1,
                                            s: s,
                                            best: s === best,
                                            worst: s === worst
                                        })).reverse();
                            }

                            delegate: Item {
                                id: lap

                                required property var modelData

                                width: ListView.view.width
                                height: 30

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: root.fgFaint
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Tour %1").arg(lap.modelData.n)
                                    color: lap.modelData.best ? root.green : lap.modelData.worst ? root.red : root.fg
                                    font.pixelSize: 13
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.fmt(lap.modelData.s, true)
                                    color: lap.modelData.best ? root.green : lap.modelData.worst ? root.red : root.fg
                                    font.pixelSize: 13
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                            }
                        }

                        Row {
                            id: swBtns

                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Pill {
                                text: root.swOn && root.paused ? qsTr("Réinitialiser") : qsTr("Tour")
                                enabledPill: root.swOn
                                onClicked: root.cmd([root.paused ? "stop" : "lap"])
                            }
                            Pill {
                                readonly property bool running: root.swOn && !root.paused

                                tint: running ? Qt.alpha(root.red, 0.25) : Qt.alpha(root.green, 0.25)
                                textColour: running ? root.red : root.green
                                text: root.swOn ? (root.paused ? qsTr("Reprendre") : qsTr("Arrêter")) : qsTr("Démarrer")
                                onClicked: root.stopwatchMain()
                            }
                        }
                    }

                    // ═══ Pomodoro ═══
                    Item {
                        width: pages.width
                        height: pages.height

                        readonly property bool resting: root.pomo.phase === "rest"

                        ProgressRing {
                            id: pRing

                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 270
                            height: 270
                            progress: root.pomoOn ? root.value / root.total : 1
                            colour: root.pomoOn && parent.resting ? root.green : root.orange
                            dim: root.paused || !root.pomoOn

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.pomoOn ? (pRing.parent.resting ? qsTr("Pause") : qsTr("Focus")) : qsTr("Pomodoro")
                                    color: root.pomoOn ? pRing.colour : root.fgDim
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.fmt(root.pomoOn ? root.value : root.work * 60, false)
                                    color: root.fg
                                    font.pixelSize: 54
                                    font.weight: Font.Light
                                    font.features: {
                                        "tnum": 1
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.pomoOn ? qsTr("Session %1").arg(root.pomo.round ?? 1) : qsTr("%1 min de focus · %2 min de pause").arg(root.work).arg(root.rest)
                                    color: root.fgDim
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // Durées de focus et de pause
                        Row {
                            anchors.top: pRing.bottom
                            anchors.topMargin: 16
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12
                            opacity: root.pomoOn ? 0.4 : 1
                            enabled: !root.pomoOn

                            Repeater {
                                model: [
                                    {
                                        key: "work",
                                        title: qsTr("Focus"),
                                        lo: 5,
                                        hi: 90,
                                        stepBy: 5
                                    },
                                    {
                                        key: "rest",
                                        title: qsTr("Pause"),
                                        lo: 1,
                                        hi: 30,
                                        stepBy: 1
                                    }
                                ]

                                Rectangle {
                                    id: card

                                    required property var modelData

                                    width: 170
                                    height: 58
                                    radius: 18
                                    color: Qt.alpha(root.fg, 0.06)

                                    Column {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            text: card.modelData.title
                                            color: root.fgDim
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: `${root[card.modelData.key]} min`
                                            color: root.fg
                                            font.pixelSize: 17
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        Repeater {
                                            model: [-1, 1]

                                            Rectangle {
                                                id: stepBtn

                                                required property int modelData

                                                width: 30
                                                height: 30
                                                radius: 15
                                                color: stepArea.containsMouse ? Qt.alpha(root.fg, 0.16) : Qt.alpha(root.fg, 0.08)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: stepBtn.modelData < 0 ? "−" : "+"
                                                    color: root.fg
                                                    font.pixelSize: 17
                                                }

                                                MouseArea {
                                                    id: stepArea

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const m = card.modelData;
                                                        root[m.key] = Math.max(m.lo, Math.min(m.hi, root[m.key] + stepBtn.modelData * m.stepBy));
                                                        root.savePrefs();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Pill {
                                text: qsTr("Arrêter")
                                enabledPill: root.pomoOn
                                onClicked: root.cmd(["stop"])
                            }
                            Pill {
                                tint: root.pomoOn && !root.paused ? Qt.alpha(root.orange, 0.25) : root.orange
                                textColour: root.pomoOn && !root.paused ? root.orange : "white"
                                text: root.pomoOn ? (root.paused ? qsTr("Reprendre") : qsTr("Pause")) : qsTr("Commencer")
                                onClicked: root.pomoMain()
                            }
                        }
                    }

                    // ═══ Alarmes ═══
                    Item {
                        width: pages.width
                        height: pages.height

                        Text {
                            id: nextTxt

                            x: 24
                            text: root.nextAlarm
                            color: root.fgDim
                            font.pixelSize: 13
                            anchors.verticalCenter: addBtn.verticalCenter
                        }

                        Rectangle {
                            id: addBtn

                            anchors.right: parent.right
                            anchors.rightMargin: 20
                            width: 36
                            height: 36
                            radius: 18
                            color: root.editing ? Qt.alpha(root.orange, 0.3) : addArea.containsMouse ? Qt.alpha(root.orange, 0.85) : root.orange
                            rotation: root.editing ? 45 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: 260
                                    easing.type: Easing.OutBack
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰐕"
                                font.family: root.glyphFont
                                font.pixelSize: 19
                                color: root.editing ? root.orange : "white"
                            }

                            MouseArea {
                                id: addArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.editing) {
                                        const d = new Date(root.now + 3600000);
                                        root.aH = d.getHours();
                                        root.aM = 0;
                                    }
                                    root.editing = !root.editing;
                                }
                            }
                        }

                        // Éditeur (glisse depuis le haut)
                        Rectangle {
                            id: editor

                            anchors.top: addBtn.bottom
                            anchors.topMargin: 12
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 40
                            height: root.editing ? 270 : 0
                            radius: 22
                            color: Qt.alpha(root.fg, 0.06)
                            clip: true
                            opacity: root.editing ? 1 : 0

                            Behavior on height {
                                NumberAnimation {
                                    duration: 320
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 220
                                }
                            }

                            Column {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 8
                                spacing: 8

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Wheel {
                                        value: root.aH
                                        max: 23
                                        unit: "h"
                                        onChanged: v => root.aH = v
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: -4
                                        text: ":"
                                        color: root.fgDim
                                        font.pixelSize: 36
                                    }
                                    Wheel {
                                        value: root.aM
                                        unit: "min"
                                        onChanged: v => root.aM = v
                                    }
                                }

                                Field {
                                    id: alarmName

                                    width: editor.width - 32
                                    placeholder: qsTr("Nom de l'alarme — ex. Réveil")
                                    onAccepted: root.addAlarm()
                                }

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 6

                                    Repeater {
                                        // Lundi → dimanche (jour JavaScript : 0 = dimanche)
                                        model: [[1, "L"], [2, "M"], [3, "M"], [4, "J"], [5, "V"], [6, "S"], [0, "D"]]

                                        Rectangle {
                                            id: day

                                            required property var modelData
                                            readonly property bool on: root.aDays.includes(modelData[0])

                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: on ? root.orange : dayArea.containsMouse ? Qt.alpha(root.fg, 0.14) : Qt.alpha(root.fg, 0.07)

                                            Text {
                                                anchors.centerIn: parent
                                                text: day.modelData[1]
                                                color: day.on ? "white" : root.fg
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: dayArea

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.aDays = day.on ? root.aDays.filter(d => d !== day.modelData[0]) : [...root.aDays, day.modelData[0]]
                                            }
                                        }
                                    }
                                }

                                Pill {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 38
                                    tint: root.orange
                                    textColour: "white"
                                    text: root.aDays.length ? qsTr("Enregistrer") : qsTr("Enregistrer (une seule fois)")
                                    onClicked: root.addAlarm()
                                }
                            }
                        }

                        ListView {
                            anchors.top: editor.bottom
                            anchors.topMargin: 10
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 40
                            clip: true
                            spacing: 8
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.alarms

                            delegate: Rectangle {
                                id: al

                                required property var modelData

                                width: ListView.view.width
                                height: 70
                                radius: 20
                                color: Qt.alpha(root.fg, 0.06)

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: al.modelData.enabled ? 1 : 0.45

                                    Text {
                                        text: al.modelData.time
                                        color: root.fg
                                        font.pixelSize: 30
                                        font.weight: Font.Light
                                        font.features: {
                                            "tnum": 1
                                        }
                                    }
                                    Text {
                                        text: `${al.modelData.label || qsTr("Alarme")}  ·  ${root.daysText(al.modelData.days)}`
                                        color: root.fgDim
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    anchors.right: toggle.left
                                    anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰩹"
                                    font.family: root.glyphFont
                                    font.pixelSize: 17
                                    color: delArea.containsMouse ? root.red : root.fgDim

                                    MouseArea {
                                        id: delArea

                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.saveAlarms(root.alarms.filter(a => a.id !== al.modelData.id))
                                    }
                                }

                                // Interrupteur façon macOS
                                Rectangle {
                                    id: toggle

                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 46
                                    height: 28
                                    radius: 14
                                    color: al.modelData.enabled ? root.green : Qt.alpha(root.fg, 0.18)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 180
                                        }
                                    }

                                    Rectangle {
                                        x: al.modelData.enabled ? parent.width - width - 3 : 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: "white"

                                        Behavior on x {
                                            NumberAnimation {
                                                duration: 220
                                                easing.type: Easing.OutBack
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.saveAlarms(root.alarms.map(a => a.id === al.modelData.id ? Object.assign({}, a, {
                                                        enabled: !a.enabled
                                                    }) : a))
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 30
                            visible: root.alarms.length === 0 && !root.editing
                            horizontalAlignment: Text.AlignHCenter
                            text: qsTr("Aucune alarme.\nAppuie sur + pour en créer une.")
                            color: root.fgDim
                            font.pixelSize: 13
                        }
                    }
                }
            }

            Text {
                id: footer

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Tout continue dans l'île, même fermé  ·  Espace : démarrer  ·  Tab : onglet")
                color: Qt.alpha(root.fg, 0.4)
                font.pixelSize: 11
            }
        }
    }
}

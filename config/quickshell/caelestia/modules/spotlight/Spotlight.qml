pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.components
import qs.services

// Spotlight façon macOS 27 (Super + Espace), dessiné dans le même verre que l'île :
// la goutte de verre se détache de l'île, descend au centre de l'écran et devient
// une barre de recherche ; les résultats font grandir le verre vers le bas.
// Les recherches sont faites par `caelestia-spotlight serve` (applis, actions, calculs,
// notes, tâches, fichiers, suggestions, Wikipédia et web).
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.spotlight ?? false

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
    readonly property real curR: fromR + (barH / 2 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Couleurs ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.6)
    readonly property color fgFaint: Qt.alpha(fg, 0.1)
    readonly property color accent: Colours.palette.m3primary
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── Recherche ──
    readonly property real barH: 60
    readonly property real maxListH: 470
    property string query: ""
    property int seq: 0
    property var stages: ({})
    property bool webPending: false
    property int sel: 0
    readonly property var items: {
        if (!query)
            return [];
        const s = stages;
        const list = [...(s.local ?? []), ...(s.files ?? []), ...(s.suggest ?? []), ...(s.web ?? [])];
        list.push({
            kind: "google",
            section: "Sur le Web",
            title: `Rechercher « ${query} » sur Google`,
            sub: "Ouvre le navigateur  ·  Ctrl + Entrée",
            glyph: "󰊭",
            action: "https://www.google.com/search?q=" + encodeURIComponent(query)
        });
        return list;
    }
    readonly property real listH: items.length > 0 ? Math.min(maxListH, results.contentHeight + 12) : 0

    function open(): void {
        screenState.spotlight = true;
    }

    function close(): void {
        screenState.spotlight = false;
    }

    function search(text: string): void {
        query = text.trim();
        seq += 1;
        sel = 0;
        if (!query) {
            stages = {};
            webPending = false;
            return;
        }
        webPending = true;
        backend.send({
            seq: seq,
            q: query
        });
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.seq !== seq)
            return;
        const s = Object.assign({}, stages);
        s[msg.stage] = msg.items;
        // Les résultats rapides remplacent tout : on repart d'une liste propre
        if (msg.stage === "local") {
            delete s.files;
            delete s.suggest;
            delete s.web;
        }
        if (msg.stage === "web")
            webPending = false;
        stages = s;
        sel = Math.min(sel, Math.max(0, items.length - 1));
    }

    function activate(index: int): void {
        const it = items[index];
        if (!it)
            return;
        if (it.action.startsWith("suggest:")) {
            input.text = it.action.slice(8);
            input.cursorPosition = input.text.length;
            return;
        }
        backend.send({
            run: it.action
        });
        close();
    }

    function iconSource(it: var): string {
        if (!it.icon)
            return "";
        if (it.kind === "web")
            return it.icon;
        if (it.icon.startsWith("/"))
            return "file://" + it.icon;
        return Quickshell.iconPath(it.icon, it.fallback ?? "application-x-executable");
    }

    visible: morph > 0.001
    implicitWidth: 700
    implicitHeight: barH + (listH > 0 ? listH + 1 : 0)

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 340
            easing.type: Easing.OutBack
            easing.overshoot: 0.7
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
            backend.running = true;
            input.text = "";
            search("");
            input.forceActiveFocus();
        }
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
        // Relancé tout seul s'il s'arrête (le premier lancement charge la liste des applis)
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

            // ── Barre de recherche ──
            Item {
                id: bar

                width: parent.width
                height: root.barH

                Text {
                    id: lens

                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    font.family: root.glyphFont
                    font.pixelSize: 24
                    color: root.fgDim
                }

                TextInput {
                    id: input

                    anchors.left: lens.right
                    anchors.leftMargin: 14
                    anchors.right: busy.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    color: root.fg
                    selectionColor: Qt.alpha(root.accent, 0.4)
                    selectedTextColor: root.fg
                    font.pixelSize: 23
                    font.weight: Font.Light
                    clip: true
                    onTextChanged: root.search(text)

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier)) {
                            root.sel = Math.min(root.items.length - 1, root.sel + 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier)) {
                            root.sel = Math.max(0, root.sel - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (event.modifiers & Qt.ControlModifier)
                                root.activate(root.items.length - 1);
                            else
                                root.activate(root.sel);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            const it = root.items[root.sel];
                            if (it && it.kind === "suggest")
                                root.activate(root.sel);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (text)
                                text = "";
                            else
                                root.close();
                            event.accepted = true;
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: qsTr("Recherche Spotlight")
                        color: Qt.alpha(root.fg, 0.38)
                        font: input.font
                    }
                }

                // Petit indicateur pendant que le web répond
                Item {
                    id: busy

                    anchors.right: parent.right
                    anchors.rightMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    opacity: root.webPending && root.query ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: root.fgFaint
                    }

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: root.accent
                        x: parent.width / 2 - 3 + 6 * Math.cos(spin.angle)
                        y: parent.height / 2 - 3 + 6 * Math.sin(spin.angle)
                    }

                    NumberAnimation {
                        id: spin

                        property real angle

                        target: spin
                        property: "angle"
                        from: 0
                        to: Math.PI * 2
                        duration: 900
                        loops: Animation.Infinite
                        running: busy.opacity > 0
                    }
                }
            }

            Rectangle {
                anchors.top: bar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                height: 1
                color: root.fgFaint
                opacity: root.listH > 0 ? 1 : 0
            }

            // ── Résultats ──
            ListView {
                id: results

                anchors.top: bar.bottom
                anchors.topMargin: 7
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                height: Math.max(0, root.listH - 12)
                clip: true
                model: root.items
                currentIndex: root.sel
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 3000
                highlightFollowsCurrentItem: false
                highlightMoveDuration: 0
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                // Pastille de sélection qui glisse d'un résultat à l'autre
                highlight: Rectangle {
                    readonly property Item cur: results.currentItem

                    width: results.width
                    y: cur ? cur.y + cur.headerH : 0
                    height: cur ? cur.rowH : 0
                    radius: 12
                    color: Qt.alpha(root.accent, Colours.light ? 0.2 : 0.28)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.35)
                    visible: !!cur

                    Behavior on y {
                        NumberAnimation {
                            duration: 170
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: 170
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property var it: modelData
                    readonly property bool header: index === 0 || root.items[index - 1]?.section !== it.section
                    readonly property real headerH: header ? 28 : 0
                    readonly property real rowH: it.kind === "hit" ? 98 : it.top ? 60 : it.kind === "web" ? 52 : it.kind === "suggest" ? 36 : 46
                    readonly property bool selected: root.sel === index

                    width: results.width
                    height: headerH + rowH

                    Text {
                        visible: row.header
                        x: 12
                        y: 9
                        text: row.it.section
                        color: root.fgDim
                        font.pixelSize: 11.5
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        y: row.headerH
                        width: parent.width
                        height: row.rowH
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.sel = row.index
                        onClicked: root.activate(row.index)
                    }

                    // Icône : appli, fichier, favicon, ou glyphe
                    Item {
                        id: iconBox

                        x: 10
                        y: row.headerH + (row.it.kind === "hit" ? 12 : (row.rowH - height) / 2)
                        width: row.it.top ? 40 : row.it.kind === "suggest" ? 22 : 30
                        height: width

                        IconImage {
                            anchors.fill: parent
                            visible: row.it.kind === "app" || row.it.kind === "file"
                            source: visible ? root.iconSource(row.it) : ""
                            asynchronous: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: row.it.kind === "web"
                            radius: 8
                            color: Qt.alpha(root.fg, 0.08)

                            Image {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: parent.visible ? root.iconSource(row.it) : ""
                                asynchronous: true
                                smooth: true
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: !!row.it.glyph && row.it.kind !== "suggest"
                            radius: 9
                            color: row.it.kind === "task" ? Qt.alpha(row.it.late ? "#ff453a" : row.it.priority === "urgent" || row.it.priority === "high" ? "#ff9f0a" : root.accent, 0.18) : Qt.alpha(root.accent, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: row.it.glyph ?? ""
                                font.family: root.glyphFont
                                font.pixelSize: 17
                                color: row.it.kind === "task" ? (row.it.late ? "#ff453a" : row.it.priority === "urgent" || row.it.priority === "high" ? "#ff9f0a" : root.accent) : root.accent
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: row.it.kind === "suggest"
                            text: row.it.glyph ?? ""
                            font.family: root.glyphFont
                            font.pixelSize: 16
                            color: root.fgDim
                        }
                    }

                    Column {
                        anchors.left: iconBox.right
                        anchors.leftMargin: 12
                        anchors.right: tag.left
                        anchors.rightMargin: 10
                        y: row.headerH + (row.it.kind === "hit" ? 10 : (row.rowH - height) / 2)
                        spacing: 2

                        Text {
                            width: parent.width
                            text: row.it.title ?? ""
                            color: root.fg
                            elide: Text.ElideRight
                            font.pixelSize: row.it.top ? 16 : row.it.kind === "calc" ? 17 : 14
                            font.weight: row.it.top || row.it.kind === "hit" || row.it.kind === "calc" ? Font.DemiBold : Font.Normal
                            font.strikeout: !!row.it.done
                        }

                        Text {
                            width: parent.width
                            visible: !!(row.it.sub || row.it.domain)
                            text: row.it.kind === "web" ? (row.it.domain + (row.it.sub ? "  ·  " + row.it.sub : "")) : (row.it.sub ?? "")
                            color: row.it.late ? "#ff453a" : root.fgDim
                            elide: Text.ElideRight
                            wrapMode: row.it.kind === "hit" ? Text.WordWrap : Text.NoWrap
                            maximumLineCount: row.it.kind === "hit" ? 3 : 1
                            font.pixelSize: 12
                            lineHeight: 1.1
                        }
                    }

                    // Étiquette à droite : « Récent », raccourci d'ouverture…
                    Text {
                        id: tag

                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        y: row.headerH + (row.rowH - height) / 2
                        text: row.selected ? "↵" : (row.it.tag ?? "")
                        color: root.fgDim
                        font.pixelSize: row.selected ? 15 : 11
                    }
                }
            }
        }
    }
}

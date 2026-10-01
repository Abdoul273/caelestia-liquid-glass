pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.components.effects
import qs.services

// Raccourcis (Super + H) façon Spotlight, dans le même verre que l'île :
// une ligne de recherche ; les raccourcis trouvés s'affichent avec leurs touches
// dessinées, et Entrée déclenche le raccourci (le panneau se ferme et la combinaison
// est rejouée avec ydotool, comme si on l'avait tapée).
// La liste vient de `caelestia-shortcuts --json` (liste SHORTCUTS du script).
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.keyhelp ?? false

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
    readonly property color fgDim: Qt.alpha(fg, 0.58)
    readonly property color fgFaint: Qt.alpha(fg, 0.1)
    readonly property color accent: Colours.palette.m3primary
    readonly property string glyphFont: "JetBrainsMono Nerd Font"
    readonly property string tool: `${Quickshell.env("HOME")}/.local/bin/caelestia-shortcuts`

    // ── Recherche ──
    readonly property real barH: 60
    readonly property real maxListH: 470
    property var all: []
    property string query: ""
    property int sel: 0
    property string hint: ""
    readonly property var items: {
        const q = fold(query);
        if (!q)
            return [];
        const words = q.split(/\s+/).filter(w => w);
        const scored = [];
        for (const it of all) {
            const hay = it.hay;
            if (!words.every(w => hay.includes(w)))
                continue;
            const d = fold(it.desc);
            let score = 0;
            if (d.startsWith(q))
                score += 30;
            if (words.some(w => d.split(/[\s'’:,/()]+/).some(x => x.startsWith(w))))
                score += 20;
            if (fold(it.keys).includes(q))
                score += 15;
            if (it.run)
                score += 5;
            scored.push([score, it]);
        }
        // Meilleur résultat d'abord, puis le reste groupé par catégorie (ordre de la liste)
        scored.sort((a, b) => b[0] - a[0]);
        if (scored.length === 0)
            return [];
        const best = Object.assign({}, scored[0][1], {
            section: qsTr("Meilleur résultat"),
            top: true
        });
        const rest = scored.slice(1).map(s => s[1]).sort((a, b) => a.order - b.order).map(it => Object.assign({}, it, {
                    section: it.cat
                }));
        return [best, ...rest].slice(0, 40);
    }
    readonly property real listH: items.length > 0 ? Math.min(maxListH, results.contentHeight + 12) : 0

    function fold(text: string): string {
        return (text ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
    }

    function close(): void {
        screenState.keyhelp = false;
    }

    function activate(index: int): void {
        const it = items[index];
        if (!it)
            return;
        if (!it.run) {
            showHint(qsTr("Celui-là se fait à la souris, au pavé tactile ou dans une app : ") + it.keys);
            return;
        }
        close();
        Quickshell.execDetached([tool, "--press", it.keys]);
    }

    function showHint(text: string): void {
        hint = text;
        hintTimer.restart();
    }

    visible: morph > 0.001
    implicitWidth: 760
    implicitHeight: barH + (listH > 0 ? listH + 1 : 0) + (hint ? 34 : 0)

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
            input.text = "";
            hint = "";
            loader.running = true;
            input.forceActiveFocus();
        }
    }

    Timer {
        id: hintTimer

        interval: 3500
        onTriggered: root.hint = ""
    }

    // Liste relue à chaque ouverture (elle change quand on ajoute un raccourci)
    Process {
        id: loader

        command: [root.tool, "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text);
                    root.all = list.map((it, i) => Object.assign(it, {
                            order: i,
                            hay: root.fold(it.desc + " " + it.keys + " " + it.cat)
                        }));
                } catch (e) {}
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

            // ── Ligne de recherche ──
            Item {
                id: bar

                width: parent.width
                height: root.barH

                Text {
                    id: lens

                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰌌"
                    font.family: root.glyphFont
                    font.pixelSize: 24
                    color: root.fgDim
                }

                TextInput {
                    id: input

                    anchors.left: lens.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    color: root.fg
                    selectionColor: Qt.alpha(root.accent, 0.4)
                    selectedTextColor: root.fg
                    font.pixelSize: 23
                    font.weight: Font.Light
                    clip: true
                    onTextChanged: {
                        root.query = text;
                        root.sel = 0;
                        root.hint = "";
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            root.sel = Math.min(root.items.length - 1, root.sel + 1);
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                            root.sel = Math.max(0, root.sel - 1);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.activate(root.sel);
                        } else if (event.key === Qt.Key_Escape) {
                            if (text)
                                text = "";
                            else
                                root.close();
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: qsTr("Rechercher un raccourci  (ex. capture, bureau, volume…)")
                        color: Qt.alpha(root.fg, 0.38)
                        font: input.font
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
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                highlight: GlassControl {
                    readonly property Item cur: results.currentItem

                    width: results.width
                    y: cur ? cur.y + cur.headerH : 0
                    height: cur ? cur.rowH : 0
                    tintColour: Qt.alpha(root.accent, Colours.light ? 0.3 : 0.36)
                    radius: 13
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
                    readonly property real rowH: it.top ? 62 : 50
                    readonly property bool selected: root.sel === index

                    width: results.width
                    height: headerH + rowH

                    Text {
                        visible: row.header
                        x: 12
                        y: 9
                        text: row.it.section
                        color: root.fgDim
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        y: row.headerH
                        width: parent.width
                        height: row.rowH
                        hoverEnabled: true
                        cursorShape: row.it.run ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: root.sel = row.index
                        onClicked: root.activate(row.index)
                    }

                    Rectangle {
                        id: icon

                        x: 10
                        y: row.headerH + (row.rowH - height) / 2
                        width: row.it.top ? 38 : 30
                        height: width
                        radius: 9
                        color: Qt.alpha(root.accent, 0.16)

                        Text {
                            anchors.centerIn: parent
                            text: row.it.icon || "󰌌"
                            font.family: root.glyphFont
                            font.pixelSize: row.it.top ? 19 : 16
                            color: root.accent
                        }
                    }

                    Column {
                        anchors.left: icon.right
                        anchors.leftMargin: 12
                        anchors.right: caps.left
                        anchors.rightMargin: 12
                        y: row.headerH + (row.rowH - height) / 2
                        spacing: 2

                        Text {
                            width: parent.width
                            text: row.it.desc
                            color: root.fg
                            elide: Text.ElideRight
                            font.pixelSize: row.it.top ? 15 : 13
                            font.weight: row.it.top ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            width: parent.width
                            text: row.it.top ? row.it.cat + (row.it.run ? qsTr("  ·  Entrée pour le déclencher") : "") : row.selected && row.it.run ? qsTr("Entrée pour le déclencher") : row.it.cat
                            color: root.fgDim
                            elide: Text.ElideRight
                            font.pixelSize: 11
                        }
                    }

                    // Touches dessinées : « Super » « Maj » « S », puis « ou » pour les variantes
                    Row {
                        id: caps

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        y: row.headerH + (row.rowH - height) / 2
                        spacing: 4

                        Repeater {
                            model: {
                                const groups = row.it.keys.split("|").map(g => g.trim()).slice(0, 2);
                                const out = [];
                                groups.forEach((g, gi) => {
                                    if (gi > 0)
                                        out.push({
                                            or: true,
                                            t: qsTr("ou")
                                        });
                                    g.split(" + ").forEach(k => out.push({
                                            or: false,
                                            t: k.trim()
                                        }));
                                });
                                return out;
                            }

                            Item {
                                id: cap

                                required property var modelData

                                width: modelData.or ? orTxt.implicitWidth + 6 : Math.max(26, capTxt.implicitWidth + 14)
                                height: 26

                                Text {
                                    id: orTxt

                                    anchors.centerIn: parent
                                    visible: cap.modelData.or
                                    text: cap.modelData.t
                                    color: root.fgDim
                                    font.pixelSize: 11
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    visible: !cap.modelData.or
                                    radius: 7
                                    color: Qt.alpha(root.fg, row.selected ? 0.16 : 0.09)
                                    border.width: 1
                                    border.color: Qt.alpha(root.fg, 0.16)

                                    // Petite ombre en bas, comme une vraie touche
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 1
                                        height: 3
                                        radius: 2
                                        color: Qt.alpha("black", 0.12)
                                    }

                                    Text {
                                        id: capTxt

                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        text: cap.modelData.t
                                        color: root.fg
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Message (raccourci qui ne se déclenche pas au clavier)
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.right: parent.right
                anchors.rightMargin: 22
                visible: !!root.hint
                text: root.hint
                color: "#ff9f0a"
                elide: Text.ElideRight
                font.pixelSize: 12
            }
        }
    }
}

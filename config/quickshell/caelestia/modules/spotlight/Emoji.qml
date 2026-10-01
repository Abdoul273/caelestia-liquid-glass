pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.components.effects
import qs.services

// Emojis (Super + .) dans le même verre que l'île, façon sélecteur de macOS :
// une goutte tombe de l'île ; recherche en haut, grille d'emojis, catégories en bas.
// Entrée (ou clic) insère l'emoji dans la fenêtre d'avant et le garde dans les récents.
// Tout passe par `caelestia-emoji-pro serve`.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.emoji ?? false

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
    readonly property real curR: fromR + (28 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Couleurs ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.55)
    readonly property color fgFaint: Qt.alpha(fg, 0.1)
    readonly property color accent: Colours.palette.m3primary
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── Données ──
    readonly property var categories: [
        {
            key: "recents",
            glyph: "󰥔",
            title: qsTr("Récents")
        },
        {
            key: "smileys",
            glyph: "󰱱",
            title: qsTr("Smileys")
        },
        {
            key: "people",
            glyph: "󰀄",
            title: qsTr("Personnes")
        },
        {
            key: "nature",
            glyph: "󰌪",
            title: qsTr("Nature")
        },
        {
            key: "food",
            glyph: "󰉛",
            title: qsTr("Nourriture")
        },
        {
            key: "travel",
            glyph: "󰿄",
            title: qsTr("Voyages")
        },
        {
            key: "activities",
            glyph: "󰝚",
            title: qsTr("Activités")
        },
        {
            key: "objects",
            glyph: "󰦬",
            title: qsTr("Objets")
        },
        {
            key: "symbols",
            glyph: "󰘨",
            title: qsTr("Symboles")
        },
        {
            key: "flags",
            glyph: "󰈻",
            title: qsTr("Drapeaux")
        },
        {
            key: "kaomoji",
            glyph: "ツ",
            title: qsTr("Kaomoji")
        },
        {
            key: "glyphs",
            glyph: "󰣇",
            title: qsTr("Glyphes")
        }
    ]
    property string category: "recents"
    property string query: ""
    property var items: []
    property int total: 0
    property int sel: 0
    property int seq: 0
    readonly property real cell: 46
    readonly property int columns: 10
    readonly property var current: items[sel] ?? null
    readonly property bool wide: category === "kaomoji" && !query

    function close(): void {
        screenState.emoji = false;
    }

    function load(): void {
        seq += 1;
        backend.send({
            seq: seq,
            q: query,
            cat: category
        });
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.stage !== "emojis" || msg.seq !== seq)
            return;
        // Pas encore de récents : on ouvre sur les smileys
        if (category === "recents" && !query && msg.items.length === 0 && !msg.hasRecents) {
            category = "smileys";
            return;
        }
        items = msg.items;
        total = msg.total;
        sel = 0;
        grid.positionViewAtBeginning();
    }

    function pick(index: int): void {
        const it = items[index];
        if (!it)
            return;
        backend.send({
            pick: it[0],
            paste: true
        });
        close();
    }

    function move(dx: int, dy: int): void {
        const cols = wide ? 3 : columns;
        sel = Math.max(0, Math.min(items.length - 1, sel + dx + dy * cols));
    }

    onCategoryChanged: if (shown)
        load()
    onQueryChanged: if (shown)
        load()

    visible: morph > 0.001
    implicitWidth: columns * cell + 28
    implicitHeight: 58 + 34 + cell * 7 + 8 + 50

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
            query = "";
            backend.running = true;
            if (category !== "recents")
                category = "recents";
            else
                load();
            input.forceActiveFocus();
        }
    }

    Process {
        id: backend

        function send(msg: var): void {
            if (running)
                write(JSON.stringify(msg) + "\n");
        }

        command: [`${Quickshell.env("HOME")}/.local/bin/caelestia-emoji-pro`, "serve"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        onStarted: if (root.shown)
            root.load()
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

            // ── Recherche ──
            Rectangle {
                id: search

                x: 14
                y: 12
                width: parent.width - 28
                height: 38
                radius: 19
                color: Qt.alpha(root.fg, 0.07)
                border.width: 1
                border.color: Qt.alpha(root.fg, 0.08)

                Text {
                    id: lens

                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    font.family: root.glyphFont
                    font.pixelSize: 16
                    color: root.fgDim
                }

                TextInput {
                    id: input

                    anchors.left: lens.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    color: root.fg
                    selectionColor: Qt.alpha(root.accent, 0.4)
                    font.pixelSize: 15
                    clip: true
                    onTextChanged: root.query = text.trim()

                    Keys.onPressed: event => {
                        const k = event.key;
                        if (k === Qt.Key_Right && (!text || cursorPosition === text.length))
                            root.move(1, 0);
                        else if (k === Qt.Key_Left && (!text || cursorPosition === 0))
                            root.move(-1, 0);
                        else if (k === Qt.Key_Down)
                            root.move(0, 1);
                        else if (k === Qt.Key_Up)
                            root.move(0, -1);
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                            root.pick(root.sel);
                        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
                            const i = root.categories.findIndex(c => c.key === root.category);
                            const n = root.categories.length;
                            input.text = "";
                            root.category = root.categories[(i + (k === Qt.Key_Tab ? 1 : n - 1)) % n].key;
                        } else if (k === Qt.Key_Escape) {
                            if (text)
                                text = "";
                            else
                                root.close();
                        } else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: qsTr("Rechercher un emoji")
                        color: Qt.alpha(root.fg, 0.38)
                        font: input.font
                    }
                }
            }

            // Titre de la section
            Text {
                id: sectionTitle

                x: 18
                anchors.top: search.bottom
                anchors.topMargin: 10
                text: root.query ? qsTr("Résultats") + "  ·  " + root.total : (root.categories.find(c => c.key === root.category)?.title ?? "")
                color: root.fgDim
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            // ── Grille ──
            GridView {
                id: grid

                x: 14
                anchors.top: search.bottom
                anchors.topMargin: 34
                width: root.columns * root.cell
                height: root.cell * 7
                cellWidth: root.wide ? width / 3 : root.cell
                cellHeight: root.cell
                clip: true
                model: root.items
                currentIndex: root.sel
                boundsBehavior: Flickable.StopAtBounds
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 120
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                highlight: GlassControl {
                    tintColour: Qt.alpha(root.accent, Colours.light ? 0.3 : 0.36)
                    radius: 13
                }

                delegate: Item {
                    id: emo

                    required property var modelData
                    required property int index

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        horizontalAlignment: Text.AlignHCenter
                        text: emo.modelData[0]
                        color: root.fg
                        elide: Text.ElideRight
                        font.family: root.category === "glyphs" && !root.query ? root.glyphFont : ""
                        font.pixelSize: root.wide ? 14 : 27
                        scale: emoArea.containsMouse ? 1.18 : 1

                        Behavior on scale {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutBack
                            }
                        }
                    }

                    MouseArea {
                        id: emoArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.sel = emo.index
                        onClicked: root.pick(emo.index)
                    }
                }
            }

            Text {
                anchors.centerIn: grid
                visible: root.items.length === 0
                text: root.query ? qsTr("Aucun emoji trouvé") : qsTr("Rien ici pour l'instant")
                color: root.fgDim
                font.pixelSize: 13
            }

            Rectangle {
                anchors.top: grid.bottom
                anchors.topMargin: 4
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                height: 1
                color: root.fgFaint
            }

            // ── Catégories + nom de l'emoji choisi ──
            Row {
                id: cats

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 9
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2

                Repeater {
                    model: root.categories

                    GlassButton {
                        id: cat

                        required property var modelData
                        readonly property bool active: !root.query && root.category === modelData.key

                        width: 36
                        height: 32
                        radius: 12
                        tint: active ? Qt.alpha(root.accent, 0.32) : Qt.alpha(root.fg, hovered ? 0.07 : 0)
                        onClicked: {
                            input.text = "";
                            root.category = cat.modelData.key;
                            input.forceActiveFocus();
                        }

                        Text {
                            anchors.centerIn: parent
                            text: cat.modelData.glyph
                            font.family: root.glyphFont
                            font.pixelSize: 16
                            color: cat.active ? root.accent : root.fgDim
                        }

                    }
                }
            }

            // Nom de l'emoji survolé, au-dessus des catégories
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: sectionTitle.verticalCenter
                width: parent.width * 0.55
                horizontalAlignment: Text.AlignRight
                text: root.current ? root.current[1] : ""
                color: root.fgDim
                elide: Text.ElideRight
                font.pixelSize: 12
            }
        }
    }
}

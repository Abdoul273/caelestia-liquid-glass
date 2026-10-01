pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.components.effects
import qs.services

// Presse-papiers (Super + V) dans le même verre que l'île : une goutte tombe de l'île,
// ligne de recherche comme Spotlight, filtres (Tout, Texte, Images, Liens, Fichiers,
// Favoris), historique à gauche et aperçu à droite (texte ou image).
// Entrée copie, Ctrl + P épingle, Suppr efface. Tout passe par `caelestia-clipboard-pro serve`.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.clipboard ?? false

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
    readonly property real curR: fromR + (30 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Couleurs ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.55)
    readonly property color fgFaint: Qt.alpha(fg, 0.1)
    readonly property color accent: Colours.palette.m3primary
    readonly property color gold: "#ffcc00"
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    // ── Données ──
    readonly property var categories: [
        {
            key: "all",
            title: qsTr("Tout")
        },
        {
            key: "text",
            title: qsTr("Texte")
        },
        {
            key: "image",
            title: qsTr("Images")
        },
        {
            key: "link",
            title: qsTr("Liens")
        },
        {
            key: "file",
            title: qsTr("Fichiers")
        },
        {
            key: "favorite",
            title: qsTr("Favoris")
        }
    ]
    readonly property var kindGlyph: ({
            text: "󰦪",
            image: "󰋩",
            link: "󰌷",
            file: "󰉋",
            binary: "󰆓"
        })
    property var all: []
    property string category: "all"
    property string query: ""
    property int sel: 0
    property var preview: null
    property int previewSeq: 0
    property bool loading: false
    property string hint: ""
    property bool wipeArmed: false
    readonly property var items: {
        const q = query.toLowerCase();
        return all.filter(it => {
            if (category === "favorite") {
                if (!it.fav)
                    return false;
            } else if (it.stored)
                return false;
            else if (category !== "all" && it.kind !== category)
                return false;
            return !q || (it.title + "\n" + it.sub).toLowerCase().includes(q);
        });
    }
    readonly property var current: items[sel] ?? null

    function count(key: string): int {
        if (key === "favorite")
            return all.filter(it => it.fav).length;
        return all.filter(it => !it.stored && (key === "all" || it.kind === key)).length;
    }

    function close(): void {
        screenState.clipboard = false;
    }

    function receive(line: string): void {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.stage === "list") {
            const id = current?.id;
            all = msg.items;
            loading = false;
            const idx = items.findIndex(it => it.id === id);
            sel = Math.max(0, idx);
            if (msg.message)
                showHint(msg.message);
            requestPreview();
        } else if (msg.stage === "preview") {
            if (msg.seq === previewSeq)
                preview = msg;
        } else if (msg.stage === "copied") {
            if (msg.ok)
                close();
            else
                showHint(qsTr("Impossible de copier cet élément"));
        }
    }

    function requestPreview(): void {
        previewTimer.restart();
    }

    function copyCurrent(): void {
        if (current)
            backend.send({
                copy: current.id
            });
    }

    function favCurrent(): void {
        if (current)
            backend.send({
                fav: current.id
            });
    }

    function deleteCurrent(): void {
        if (current)
            backend.send({
                delete: current.id
            });
    }

    function wipe(): void {
        if (!wipeArmed) {
            wipeArmed = true;
            wipeTimer.restart();
            return;
        }
        wipeArmed = false;
        backend.send({
            wipe: true
        });
    }

    function showHint(text: string): void {
        hint = text;
        hintTimer.restart();
    }

    function move(step: int): void {
        sel = Math.max(0, Math.min(items.length - 1, sel + step));
    }

    onSelChanged: requestPreview()
    onItemsChanged: {
        sel = Math.min(sel, Math.max(0, items.length - 1));
        requestPreview();
    }

    visible: morph > 0.001
    implicitWidth: 860
    implicitHeight: 60 + 46 + 400 + 40

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
            category = "all";
            sel = 0;
            hint = "";
            wipeArmed = false;
            loading = true;
            backend.running = true;
            backend.send({
                list: true
            });
            input.forceActiveFocus();
        }
    }

    Timer {
        id: previewTimer

        interval: 60
        onTriggered: {
            root.previewSeq += 1;
            if (!root.current) {
                root.preview = null;
                return;
            }
            backend.send({
                preview: root.current.id,
                seq: root.previewSeq
            });
        }
    }

    Timer {
        id: hintTimer

        interval: 2500
        onTriggered: root.hint = ""
    }

    Timer {
        id: wipeTimer

        interval: 4000
        onTriggered: root.wipeArmed = false
    }

    Process {
        id: backend

        function send(msg: var): void {
            if (running)
                write(JSON.stringify(msg) + "\n");
        }

        command: [`${Quickshell.env("HOME")}/.local/bin/caelestia-clipboard-pro`, "serve"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.receive(data)
        }
        onStarted: if (root.shown)
            send({
                list: true
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

            // ── Ligne de recherche ──
            Item {
                id: bar

                width: parent.width
                height: 60

                Text {
                    id: lens

                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅌"
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
                    font.pixelSize: 22
                    font.weight: Font.Light
                    clip: true
                    onTextChanged: {
                        root.query = text.trim();
                        root.sel = 0;
                    }

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down) {
                            root.move(1);
                        } else if (event.key === Qt.Key_Up) {
                            root.move(-1);
                        } else if (event.key === Qt.Key_PageDown) {
                            root.move(8);
                        } else if (event.key === Qt.Key_PageUp) {
                            root.move(-8);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.copyCurrent();
                        } else if (ctrl && event.key === Qt.Key_P) {
                            root.favCurrent();
                        } else if (event.key === Qt.Key_Delete && cursorPosition === text.length) {
                            root.deleteCurrent();
                        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            const i = root.categories.findIndex(c => c.key === root.category);
                            const n = root.categories.length;
                            root.category = root.categories[(i + (event.key === Qt.Key_Tab ? 1 : n - 1)) % n].key;
                            root.sel = 0;
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
                        text: qsTr("Rechercher dans le presse-papiers")
                        color: Qt.alpha(root.fg, 0.38)
                        font: input.font
                    }
                }
            }

            // ── Filtres ──
            Row {
                id: chips

                anchors.top: bar.bottom
                x: 18
                spacing: 6

                Repeater {
                    model: root.categories

                    GlassButton {
                        id: chip

                        required property var modelData
                        readonly property bool active: root.category === modelData.key

                        width: chipRow.implicitWidth + 24
                        height: 32
                        tint: active ? Qt.alpha(root.accent, 0.32) : Qt.alpha(root.fg, 0.06)
                        onClicked: {
                            root.category = chip.modelData.key;
                            root.sel = 0;
                            input.forceActiveFocus();
                        }

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: chip.modelData.title
                                color: chip.active ? root.accent : root.fg
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: root.count(chip.modelData.key)
                                color: root.fgDim
                                font.pixelSize: 11
                            }
                        }

                    }
                }
            }

            Rectangle {
                anchors.top: chips.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                height: 1
                color: root.fgFaint
            }

            // ── Historique ──
            ListView {
                id: list

                anchors.top: chips.bottom
                anchors.topMargin: 19
                x: 10
                width: 340
                height: 394
                clip: true
                model: root.items
                currentIndex: root.sel
                boundsBehavior: Flickable.StopAtBounds
                highlightFollowsCurrentItem: false
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                highlight: GlassControl {
                    readonly property Item cur: list.currentItem

                    width: list.width
                    y: cur ? cur.y : 0
                    height: cur ? cur.height : 0
                    tintColour: Qt.alpha(root.accent, Colours.light ? 0.3 : 0.36)
                    radius: 13
                    visible: !!cur

                    Behavior on y {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index

                    width: list.width
                    height: 52

                    Rectangle {
                        id: kindIcon

                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        radius: 9
                        color: Qt.alpha(root.accent, 0.14)

                        Text {
                            anchors.centerIn: parent
                            text: root.kindGlyph[row.modelData.kind] ?? "󰦪"
                            font.family: root.glyphFont
                            font.pixelSize: 16
                            color: root.accent
                        }
                    }

                    Column {
                        anchors.left: kindIcon.right
                        anchors.leftMargin: 10
                        anchors.right: star.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: row.modelData.title
                            color: root.fg
                            elide: Text.ElideRight
                            font.pixelSize: 13
                        }
                        Text {
                            width: parent.width
                            text: row.modelData.sub
                            color: root.fgDim
                            elide: Text.ElideRight
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        id: star

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.fav ? "󰓎" : ""
                        font.family: root.glyphFont
                        font.pixelSize: 14
                        color: root.gold
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sel = row.index;
                            input.forceActiveFocus();
                        }
                        onDoubleClicked: {
                            root.sel = row.index;
                            root.copyCurrent();
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: list
                visible: root.items.length === 0
                text: root.loading ? qsTr("Chargement…") : root.query ? qsTr("Aucun résultat") : qsTr("Rien ici pour l'instant")
                color: root.fgDim
                font.pixelSize: 13
            }

            // ── Aperçu ──
            Rectangle {
                id: previewBox

                anchors.top: list.top
                anchors.left: list.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 16
                height: list.height - 52
                radius: 18
                color: Qt.alpha(root.fg, 0.05)
                border.width: 1
                border.color: Qt.alpha(root.fg, 0.07)
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 14
                    visible: root.preview?.kind === "image"
                    source: visible && root.preview.image ? "file://" + root.preview.image : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    sourceSize: Qt.size(900, 900)
                }

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: root.preview && root.preview.kind !== "image"
                    contentHeight: previewText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        id: previewText

                        width: parent.width
                        text: root.preview?.text ?? ""
                        color: root.fg
                        wrapMode: Text.WrapAnywhere
                        font.family: root.preview?.kind === "link" ? "" : "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        textFormat: Text.PlainText
                    }
                }
            }

            // Infos + actions sous l'aperçu
            Item {
                anchors.top: previewBox.bottom
                anchors.left: previewBox.left
                anchors.right: previewBox.right
                height: 52

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.preview?.info ?? ""
                    color: root.fgDim
                    font.pixelSize: 12
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: [
                            {
                                glyph: root.current?.fav ? "󰓎" : "󰓒",
                                title: root.current?.fav ? qsTr("Épinglé") : qsTr("Épingler"),
                                act: "fav"
                            },
                            {
                                glyph: "󰆴",
                                title: qsTr("Supprimer"),
                                act: "delete"
                            },
                            {
                                glyph: "󰆏",
                                title: qsTr("Copier"),
                                act: "copy"
                            }
                        ]

                        GlassButton {
                            id: btn

                            required property var modelData
                            readonly property bool main: modelData.act === "copy"

                            width: btnLbl.implicitWidth + 26
                            height: 32
                            tint: main ? Qt.alpha(root.accent, 0.85) : Qt.alpha(root.fg, 0.08)
                            onClicked: {
                                if (btn.modelData.act === "copy")
                                    root.copyCurrent();
                                else if (btn.modelData.act === "fav")
                                    root.favCurrent();
                                else
                                    root.deleteCurrent();
                                input.forceActiveFocus();
                            }

                            Text {
                                id: btnLbl

                                anchors.centerIn: parent
                                text: btn.modelData.glyph + "  " + btn.modelData.title
                                color: btn.main ? Colours.palette.m3onPrimary : btn.modelData.act === "fav" && root.current?.fav ? root.gold : root.fg
                                font.family: root.glyphFont
                                font.pixelSize: 12
                            }

                        }
                    }
                }
            }

            // ── Pied : aide + vider ──
            Item {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 40

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hint || qsTr("↑↓ parcourir  ·  Entrée copier  ·  Ctrl+P épingler  ·  Suppr effacer  ·  Tab filtre")
                    color: root.hint ? root.accent : Qt.alpha(root.fg, 0.42)
                    font.pixelSize: 11
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.wipeArmed ? qsTr("Cliquer encore pour tout vider") : qsTr("Vider l'historique")
                    color: root.wipeArmed || wipeArea.containsMouse ? "#ff453a" : root.fgDim
                    font.pixelSize: 11
                    font.weight: root.wipeArmed ? Font.DemiBold : Font.Normal

                    MouseArea {
                        id: wipeArea

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.wipe()
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import qs.components
import qs.components.effects
import qs.services

// Annoter une capture (remplace swappy) dans le même verre que l'île : une goutte tombe
// de l'île et devient l'éditeur. Outils : pinceau (B), texte (T), rectangle (R),
// ellipse (O), flèche (A), flou (D) ; couleurs, épaisseur, remplissage ; annuler / refaire ;
// Ctrl + C copie, Ctrl + S enregistre dans ~/Images/Captures, Échap ferme.
// Ouvert par `qs ipc call annotate open <fichier>` (relais ~/.local/bin/swappy).
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.annotate ?? false
    readonly property string path: screenState?.annotatePath ?? ""

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

    // ── Outils ──
    readonly property var tools: [
        {
            key: "brush",
            glyph: "󰏫",
            letter: "B",
            title: qsTr("Pinceau")
        },
        {
            key: "text",
            glyph: "󰊄",
            letter: "T",
            title: qsTr("Texte")
        },
        {
            key: "rect",
            glyph: "󰝤",
            letter: "R",
            title: qsTr("Rectangle")
        },
        {
            key: "ellipse",
            glyph: "󰺡",
            letter: "O",
            title: qsTr("Ellipse")
        },
        {
            key: "arrow",
            glyph: "󰁜",
            letter: "A",
            title: qsTr("Flèche")
        },
        {
            key: "blur",
            glyph: "󰂵",
            letter: "D",
            title: qsTr("Flou")
        }
    ]
    readonly property var palette: ["#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#0a84ff", "#bf5af2", "#ffffff", "#1c1c1e"]
    property string tool: "brush"
    property color colour: "#ff3b30"
    property int lineSize: 5
    property int textSize: 22
    property bool fill: false

    // ── Dessin ──
    property var shapes: []
    property var redoStack: []
    property var drawing: null
    property int editingText: -1
    property string hint: ""
    readonly property real imgW: Math.max(1, img.implicitWidth)
    readonly property real imgH: Math.max(1, img.implicitHeight)
    readonly property real barH: 64
    readonly property real view: Math.min(1, (screen.width * 0.82) / imgW, (screen.height * 0.8 - barH - 46) / imgH)

    function close(): void {
        commitText();
        screenState.annotate = false;
    }

    function push(shape: var): void {
        shapes = [...shapes, shape];
        redoStack = [];
    }

    function undo(): void {
        commitText();
        if (!shapes.length)
            return;
        redoStack = [...redoStack, shapes[shapes.length - 1]];
        shapes = shapes.slice(0, -1);
    }

    function redo(): void {
        if (!redoStack.length)
            return;
        shapes = [...shapes, redoStack[redoStack.length - 1]];
        redoStack = redoStack.slice(0, -1);
    }

    function clearAll(): void {
        editingText = -1;
        if (shapes.length)
            redoStack = [...redoStack, ...shapes.slice().reverse()];
        shapes = [];
    }

    function commitText(): void {
        if (editingText < 0)
            return;
        const s = shapes.slice();
        const t = textEditor.text.trim();
        if (t)
            s[editingText] = Object.assign({}, s[editingText], {
                text: t
            });
        else
            s.splice(editingText, 1);
        shapes = s;
        editingText = -1;
        content.forceActiveFocus();
    }

    function stamp(): string {
        const d = new Date();
        const p = n => n.toString().padStart(2, "0");
        return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
    }

    // Rend l'image annotée en taille réelle puis la copie ou l'enregistre
    function exportImage(save: bool): void {
        commitText();
        const out = save ? `${Quickshell.env("HOME")}/Images/Captures/capture_${stamp()}.png` : `/tmp/caelestia-annotate-${Date.now()}.png`;
        doc.grabToImage(result => {
            if (save)
                Quickshell.execDetached(["mkdir", "-p", `${Quickshell.env("HOME")}/Images/Captures`]);
            if (!result.saveToFile(out)) {
                showHint(qsTr("Impossible d'écrire l'image"));
                return;
            }
            if (save) {
                Quickshell.execDetached(["sh", "-c", `wl-copy --type image/png < '${out}'`]);
                Quickshell.execDetached(["notify-send", "-a", "Caelestia", "-i", out, qsTr("Capture enregistrée"), out.replace(Quickshell.env("HOME"), "~")]);
            } else {
                Quickshell.execDetached(["sh", "-c", `wl-copy --type image/png < '${out}'`]);
                Quickshell.execDetached(["notify-send", "-a", "Caelestia", "-i", out, qsTr("Capture copiée"), qsTr("L'image annotée est dans le presse-papiers")]);
            }
            root.close();
        }, Qt.size(imgW, imgH));
    }

    function showHint(text: string): void {
        hint = text;
        hintTimer.restart();
    }

    visible: morph > 0.001
    implicitWidth: Math.max(860, imgW * view + 36)
    implicitHeight: barH + imgH * view + 18 + 40

    Behavior on morph {
        NumberAnimation {
            duration: root.shown ? 640 : 380
            easing.type: root.shown ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 0.7
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
            shapes = [];
            redoStack = [];
            editingText = -1;
            hint = "";
            content.forceActiveFocus();
        }
    }

    Timer {
        id: hintTimer

        interval: 2500
        onTriggered: root.hint = ""
    }

    // ── Petits composants ──
    component ToolBtn: GlassButton {
        id: tb

        property string glyph
        property bool on

        width: 40
        height: 40
        radius: 13
        tint: on ? Qt.alpha(root.accent, 0.4) : Qt.alpha(root.fg, 0.07)

        Text {
            anchors.centerIn: parent
            text: tb.glyph
            font.family: root.glyphFont
            font.pixelSize: 18
            color: tb.on ? root.fg : Qt.alpha(root.fg, 0.8)
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
            scale: 0.95 + 0.05 * root.reveal
            transformOrigin: Item.Top

            Keys.onPressed: event => {
                const ctrl = event.modifiers & Qt.ControlModifier;
                const shift = event.modifiers & Qt.ShiftModifier;
                if (event.key === Qt.Key_Escape)
                    root.editingText >= 0 ? root.commitText() : root.close();
                else if (ctrl && event.key === Qt.Key_Z)
                    shift ? root.redo() : root.undo();
                else if (ctrl && event.key === Qt.Key_Y)
                    root.redo();
                else if (ctrl && event.key === Qt.Key_C)
                    root.exportImage(false);
                else if (ctrl && event.key === Qt.Key_S)
                    root.exportImage(true);
                else if (!ctrl && root.editingText < 0) {
                    const t = root.tools.find(t => t.letter === event.text.toUpperCase());
                    if (!t)
                        return;
                    root.tool = t.key;
                } else
                    return;
                event.accepted = true;
            }

            // ── Barre d'outils ──
            Row {
                id: toolbar

                x: 16
                height: root.barH
                spacing: 6

                Repeater {
                    model: root.tools

                    ToolBtn {
                        required property var modelData

                        anchors.verticalCenter: parent.verticalCenter
                        glyph: modelData.glyph
                        on: root.tool === modelData.key
                        onClicked: {
                            root.commitText();
                            root.tool = modelData.key;
                        }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 26
                    color: root.fgFaint
                }

                // Couleurs : pastilles de verre teintées
                Repeater {
                    model: root.palette

                    GlassButton {
                        id: sw

                        required property string modelData
                        readonly property bool on: Qt.colorEqual(root.colour, modelData)

                        anchors.verticalCenter: parent.verticalCenter
                        width: on ? 30 : 24
                        height: width
                        tint: Qt.alpha(modelData, 0.95)
                        onClicked: root.colour = modelData

                        Behavior on width {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutBack
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 6
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.alpha(root.fg, 0.7)
                            visible: sw.on
                        }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 26
                    color: root.fgFaint
                }

                // Épaisseur (ou taille du texte)
                GlassButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    onClicked: root.tool === "text" ? root.textSize = Math.max(10, root.textSize - 2) : root.lineSize = Math.max(1, root.lineSize - 1)

                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: root.fg
                        font.pixelSize: 16
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    horizontalAlignment: Text.AlignHCenter
                    text: root.tool === "text" ? root.textSize : root.lineSize
                    color: root.fg
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                GlassButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    onClicked: root.tool === "text" ? root.textSize = Math.min(96, root.textSize + 2) : root.lineSize = Math.min(40, root.lineSize + 1)

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: root.fg
                        font.pixelSize: 16
                    }
                }

                ToolBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: root.fill ? "󰝤" : "󰹞"
                    on: root.fill
                    onClicked: root.fill = !root.fill
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                height: root.barH
                spacing: 6

                ToolBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰕌"
                    enabled: root.shapes.length > 0
                    onClicked: root.undo()
                }
                ToolBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰑎"
                    enabled: root.redoStack.length > 0
                    onClicked: root.redo()
                }
                ToolBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰆴"
                    enabled: root.shapes.length > 0
                    onClicked: root.clearAll()
                }
                ToolBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰆏"
                    onClicked: root.exportImage(false)
                }
                GlassButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: saveLbl.implicitWidth + 30
                    height: 40
                    radius: 13
                    tint: Qt.alpha(root.accent, 0.85)
                    onClicked: root.exportImage(true)

                    Text {
                        id: saveLbl

                        anchors.centerIn: parent
                        text: "󰆓  " + qsTr("Enregistrer")
                        font.family: root.glyphFont
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Colours.palette.m3onPrimary
                    }
                }
            }

            // ── Zone de dessin (affichée réduite, rendue en taille réelle) ──
            Rectangle {
                id: frame

                anchors.top: toolbar.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.imgW * root.view
                height: root.imgH * root.view
                radius: 12
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.fg, 0.15)
                clip: true

                Item {
                    id: doc

                    width: root.imgW
                    height: root.imgH
                    transform: Scale {
                        xScale: root.view
                        yScale: root.view
                    }

                    Image {
                        id: img

                        anchors.fill: parent
                        source: root.path ? "file://" + root.path : ""
                        cache: false
                        asynchronous: false
                        smooth: true
                    }

                    Repeater {
                        model: root.shapes

                        Loader {
                            id: sh

                            required property var modelData
                            required property int index

                            sourceComponent: ({
                                    brush: brushComp,
                                    rect: rectComp,
                                    ellipse: ellipseComp,
                                    arrow: arrowComp,
                                    blur: blurComp,
                                    text: textComp
                                })[modelData.kind]
                        }
                    }

                    // Forme en cours de tracé (ajoutée à la liste au relâchement)
                    Loader {
                        readonly property var modelData: root.drawing
                        readonly property int index: -1

                        active: !!root.drawing
                        sourceComponent: root.drawing ? ({
                                brush: brushComp,
                                rect: rectComp,
                                ellipse: ellipseComp,
                                arrow: arrowComp,
                                blur: blurComp
                            })[root.drawing.kind] : null
                    }

                    // Éditeur du texte en cours de saisie
                    TextInput {
                        id: textEditor

                        readonly property var d: root.editingText >= 0 ? root.shapes[root.editingText] : null

                        visible: !!d
                        x: d?.x ?? 0
                        y: d?.y ?? 0
                        z: 10
                        color: d?.colour ?? "white"
                        font.pixelSize: d?.size ?? 22
                        font.weight: Font.Bold
                        cursorVisible: visible
                        onAccepted: root.commitText()

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -5
                            z: -1
                            radius: 6
                            color: Qt.alpha("black", 0.15)
                            border.width: 1
                            border.color: Qt.alpha("white", 0.7)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: 5
                        cursorShape: root.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
                        onPressed: e => {
                            root.commitText();
                            if (root.tool === "text") {
                                root.push({
                                    kind: "text",
                                    x: e.x,
                                    y: e.y - root.textSize * 0.6,
                                    text: "",
                                    colour: root.colour.toString(),
                                    size: root.textSize
                                });
                                root.editingText = root.shapes.length - 1;
                                textEditor.text = "";
                                textEditor.forceActiveFocus();
                                return;
                            }
                            root.drawing = {
                                kind: root.tool,
                                colour: root.colour.toString(),
                                size: root.lineSize,
                                fill: root.fill,
                                x1: e.x,
                                y1: e.y,
                                x2: e.x,
                                y2: e.y,
                                points: [Qt.point(e.x, e.y)]
                            };
                        }
                        onPositionChanged: e => {
                            if (!pressed || !root.drawing)
                                return;
                            const d = Object.assign({}, root.drawing);
                            d.x2 = e.x;
                            d.y2 = e.y;
                            if (d.kind === "brush")
                                d.points = [...d.points, Qt.point(e.x, e.y)];
                            root.drawing = d;
                        }
                        onReleased: {
                            const d = root.drawing;
                            root.drawing = null;
                            // Un simple clic sans tracé ne laisse rien (sauf un point au pinceau)
                            if (d && (d.kind === "brush" || Math.abs(d.x2 - d.x1) >= 3 || Math.abs(d.y2 - d.y1) >= 3))
                                root.push(d);
                        }
                    }
                }
            }

            // ── Pied ──
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 13
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hint || (root.tools.find(t => t.key === root.tool)?.title ?? "") + qsTr("  ·  B T R O A D : outils  ·  Ctrl+Z annuler  ·  Ctrl+C copier  ·  Ctrl+S enregistrer  ·  Échap fermer")
                color: root.hint ? "#ff453a" : Qt.alpha(root.fg, 0.45)
                font.pixelSize: 11
            }
        }
    }

    // ── Rendu des formes (coordonnées de l'image) ──

    Component {
        id: brushComp

        Shape {
            id: bs

            readonly property var d: parent?.modelData ?? ({})

            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: bs.d.colour ?? "red"
                strokeWidth: bs.d.size ?? 5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: bs.d.points ?? []
                }
            }
        }
    }

    Component {
        id: rectComp

        Rectangle {
            readonly property var d: parent?.modelData ?? ({})

            x: Math.min(d.x1, d.x2)
            y: Math.min(d.y1, d.y2)
            width: Math.abs(d.x2 - d.x1)
            height: Math.abs(d.y2 - d.y1)
            radius: 4
            color: d.fill ? d.colour : "transparent"
            border.width: d.size
            border.color: d.colour
        }
    }

    Component {
        id: ellipseComp

        Shape {
            id: es

            readonly property var d: parent?.modelData ?? ({})

            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: es.d.colour
                strokeWidth: es.d.size
                fillColor: es.d.fill ? es.d.colour : "transparent"

                PathAngleArc {
                    centerX: (es.d.x1 + es.d.x2) / 2
                    centerY: (es.d.y1 + es.d.y2) / 2
                    radiusX: Math.abs(es.d.x2 - es.d.x1) / 2
                    radiusY: Math.abs(es.d.y2 - es.d.y1) / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
    }

    Component {
        id: arrowComp

        Shape {
            id: ar

            readonly property var d: parent?.modelData ?? ({})
            readonly property real ang: Math.atan2(d.y2 - d.y1, d.x2 - d.x1)
            readonly property real head: Math.max(14, d.size * 4)

            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: ar.d.colour
                strokeWidth: ar.d.size
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathPolyline {
                    path: [Qt.point(ar.d.x1, ar.d.y1), Qt.point(ar.d.x2 - Math.cos(ar.ang) * ar.head * 0.6, ar.d.y2 - Math.sin(ar.ang) * ar.head * 0.6)]
                }
            }
            ShapePath {
                strokeColor: ar.d.colour
                strokeWidth: 1
                fillColor: ar.d.colour
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: [Qt.point(ar.d.x2, ar.d.y2), Qt.point(ar.d.x2 - ar.head * Math.cos(ar.ang - 0.45), ar.d.y2 - ar.head * Math.sin(ar.ang - 0.45)), Qt.point(ar.d.x2 - ar.head * Math.cos(ar.ang + 0.45), ar.d.y2 - ar.head * Math.sin(ar.ang + 0.45)), Qt.point(ar.d.x2, ar.d.y2)]
                }
            }
        }
    }

    Component {
        id: blurComp

        Item {
            id: bl

            readonly property var d: parent?.modelData ?? ({})

            x: Math.min(d.x1, d.x2)
            y: Math.min(d.y1, d.y2)
            width: Math.max(1, Math.abs(d.x2 - d.x1))
            height: Math.max(1, Math.abs(d.y2 - d.y1))
            clip: true

            ShaderEffectSource {
                id: part

                anchors.fill: parent
                sourceItem: img
                sourceRect: Qt.rect(bl.x, bl.y, bl.width, bl.height)
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: part
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1
                blurMax: 64
            }
        }
    }

    Component {
        id: textComp

        Text {
            readonly property var d: parent?.modelData ?? ({})
            readonly property int idx: parent?.index ?? -1

            visible: root.editingText !== idx
            x: d.x
            y: d.y
            text: d.text ?? ""
            color: d.colour
            font.pixelSize: d.size
            font.weight: Font.Bold
            style: Text.Outline
            styleColor: Qt.alpha("black", 0.35)
        }
    }
}

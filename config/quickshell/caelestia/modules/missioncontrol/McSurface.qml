pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services
import qs.utils

StyledWindow {
    id: win

    required property var mc

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property HyprlandWorkspace activeWs: monitor?.activeWorkspace ?? null

    // Fenêtres de l'espace courant (hors fenêtres cachées), triées de gauche à droite
    readonly property var windows: {
        const wsId = activeWs?.id ?? -9999;
        return Hypr.toplevels.values.filter(t => t.workspace?.id === wsId && t.lastIpcObject?.at && !t.lastIpcObject.hidden).sort((a, b) => {
            const pa = a.lastIpcObject.at, pb = b.lastIpcObject.at;
            return pa[1] - pb[1] || pa[0] - pb[0];
        });
    }

    // Espaces de travail de cet écran
    readonly property var spaces: Hypr.workspaces.values.filter(w => w.id > 0 && w.monitor?.name === monitor?.name).sort((a, b) => a.id - b.id)

    // 0 = fenêtres à leur vraie place, 1 = grille Mission Control
    property real progress: mc.open ? 1 : 0

    readonly property real topBarHeight: 170
    readonly property var layout: computeLayout()

    function computeLayout(): var {
        const n = windows.length;
        if (n === 0)
            return [];
        const areaX = 70, areaY = topBarHeight + 30;
        const areaW = width - 140, areaH = height - areaY - 70;
        const gap = 34;
        let best = null;
        for (let cols = 1; cols <= n; cols++) {
            const rows = Math.ceil(n / cols);
            const cellW = (areaW - gap * (cols - 1)) / cols;
            const cellH = (areaH - gap * (rows - 1)) / rows;
            let area = 0;
            const scales = [];
            for (const t of windows) {
                const s = t.lastIpcObject.size;
                const sc = Math.min(cellW / s[0], (cellH - 26) / s[1], 0.92);
                scales.push(sc);
                area += s[0] * s[1] * sc * sc;
            }
            if (!best || area > best.area)
                best = { cols, rows, cellW, cellH, scales, area };
        }
        const out = [];
        for (let i = 0; i < n; i++) {
            const row = Math.floor(i / best.cols);
            const inRow = Math.min(best.cols, n - row * best.cols);
            const col = i % best.cols;
            const rowW = inRow * best.cellW + (inRow - 1) * gap;
            const startX = areaX + (areaW - rowW) / 2;
            const totalH = best.rows * best.cellH + (best.rows - 1) * gap;
            const startY = areaY + (areaH - totalH) / 2;
            const s = windows[i].lastIpcObject.size;
            const w = s[0] * best.scales[i], h = s[1] * best.scales[i];
            out.push({
                x: startX + col * (best.cellW + gap) + (best.cellW - w) / 2,
                y: startY + row * (best.cellH + gap) + (best.cellH - 26 - h) / 2,
                w: w,
                h: h
            });
        }
        return out;
    }

    // Mission Control garde le clavier en exclusivité tant qu'il est ouvert, et Hyprland
    // refuse alors de changer le focus : on ferme d'abord, puis on envoie la commande.
    property string pendingDispatch
    property int pendingWs: -1
    property int attempts

    function runAfterClose(request: string, wsId: int): void {
        pendingDispatch = request;
        pendingWs = wsId;
        attempts = 0;
        mc.close();
        dispatchTimer.restart();
    }

    function focusWindow(t: var): void {
        runAfterClose(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${t.address}" })` : `focuswindow address:0x${t.address}`, t.workspace?.id ?? -1);
    }

    // Comme sur macOS : choisir un bureau y emmène et referme Mission Control
    function goToSpace(id: int): void {
        runAfterClose(Hypr.usingLua ? `hl.dsp.focus({ workspace = "${id}" })` : `workspace ${id}`, id);
    }

    // Envoie la commande une fois le clavier libéré, puis vérifie qu'on est bien
    // arrivé ; sinon la renvoie (jusqu'à 4 essais)
    Timer {
        id: dispatchTimer

        interval: 90
        onTriggered: {
            if (!win.pendingDispatch)
                return;
            Hypr.dispatch(win.pendingDispatch);
            win.attempts++;
            verifyTimer.restart();
        }
    }

    Timer {
        id: verifyTimer

        interval: 160
        onTriggered: {
            Hyprland.refreshMonitors();
            const arrived = win.pendingWs < 0 || Hyprland.focusedMonitor?.activeWorkspace?.id === win.pendingWs;
            if (arrived || win.attempts >= 4)
                win.pendingDispatch = "";
            else
                dispatchTimer.restart();
        }
    }

    name: "missioncontrol"
    visible: mc.shown
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: mc.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on progress {
        NumberAnimation {
            duration: Motion.enabled ? Motion.defaultSpatial : 450
            easing: Motion.spatialSoft

            onRunningChanged: {
                if (!running && !win.mc.open)
                    win.mc.shown = false;
            }
        }
    }

    // Fond : voile sombre (le flou vient de la règle Hyprland de la couche)
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("#05060c", 0.42 * win.progress)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: win.mc.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.mc.close()
        Keys.onPressed: event => {
            // 1…9 : aller à l'espace correspondant
            const n = event.key - Qt.Key_1 + 1;
            if (n >= 1 && n <= 9) {
                win.goToSpace(n);
                event.accepted = true;
            }
        }
    }

    // ---- Barre des espaces de travail
    Row {
        id: spacesRow

        anchors.horizontalCenter: parent.horizontalCenter
        y: 26 - 40 * (1 - win.progress)
        opacity: win.progress
        spacing: 18

        Repeater {
            model: win.spaces

            Item {
                id: space

                required property HyprlandWorkspace modelData
                readonly property bool current: modelData.id === win.activeWs?.id
                readonly property real cardW: 200
                readonly property real cardH: cardW * win.height / win.width

                width: cardW
                height: cardH + 26

                Item {
                    id: card

                    width: space.cardW
                    height: space.cardH
                    scale: cardHover.hovered ? 1.05 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    LiquidGlass {
                        anchors.fill: parent
                        radius: 14
                        tintColour: space.current ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainer
                        tintOpacity: space.current ? 0.5 : 0.32
                        hovered: cardHover.hovered
                        pointer: Qt.point(cardHover.point.position.x / Math.max(1, width), cardHover.point.position.y / Math.max(1, height))
                    }

                    // Miniatures : un rectangle par fenêtre avec l'icône de l'appli
                    Repeater {
                        model: Hypr.toplevels.values.filter(t => t.workspace?.id === space.modelData.id && t.lastIpcObject?.at)

                        Rectangle {
                            required property var modelData
                            readonly property real sx: space.cardW / win.width
                            readonly property var ipc: modelData.lastIpcObject

                            x: (ipc.at[0] - (win.monitor?.x ?? 0)) * sx
                            y: (ipc.at[1] - (win.monitor?.y ?? 0)) * sx
                            width: ipc.size[0] * sx
                            height: ipc.size[1] * sx
                            radius: 5
                            color: Qt.alpha(Colours.palette.m3onSurface, 0.1)
                            border.width: 1
                            border.color: Qt.alpha("white", 0.14)

                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: Math.min(parent.width, parent.height) * 0.45
                                source: Icons.getAppIcon(parent.ipc.class ?? "", "application-x-executable")
                                asynchronous: true
                            }

                            // Clic sur une mini-fenêtre : aller directement à cette fenêtre
                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: win.focusWindow(parent.modelData)
                            }
                        }
                    }

                    HoverHandler {
                        id: cardHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: win.goToSpace(space.modelData.id)
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: qsTr("Bureau %1").arg(space.modelData.id)
                    color: space.current ? "white" : Qt.alpha("white", 0.7)
                    font.pointSize: 10
                    font.weight: space.current ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    // ---- Fenêtres de l'espace courant
    Repeater {
        model: win.windows

        Item {
            id: tile

            required property var modelData
            required property int index
            readonly property var ipc: modelData.lastIpcObject
            readonly property var target: win.layout[index] ?? { x: 0, y: 0, w: 0, h: 0 }
            readonly property real realX: ipc.at[0] - (win.monitor?.x ?? 0)
            readonly property real realY: ipc.at[1] - (win.monitor?.y ?? 0)
            readonly property real p: win.progress

            x: realX + (target.x - realX) * p
            y: realY + (target.y - realY) * p
            width: ipc.size[0] + (target.w - ipc.size[0]) * p
            height: ipc.size[1] + (target.h - ipc.size[1]) * p
            z: hover.hovered ? 2 : 1
            scale: hover.hovered && win.mc.open ? 1.035 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            ClippingRectangle {
                anchors.fill: parent
                radius: 10 + 4 * tile.p
                color: Qt.alpha(Colours.palette.m3surface, 0.6)

                ScreencopyView {
                    anchors.fill: parent
                    captureSource: win.mc.shown ? tile.modelData.wayland : null // qmllint disable unresolved-type
                    live: false
                }
            }

            // Liseré de verre au survol
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: 16
                color: "transparent"
                border.width: 2.5
                border.color: Qt.alpha(Colours.palette.m3primary, hover.hovered ? 0.9 : 0)

                Behavior on border.color {
                    ColorAnimation {
                        duration: 180
                    }
                }
            }

            // Icône et titre sous la fenêtre
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: 8
                spacing: 7
                opacity: tile.p

                IconImage {
                    implicitSize: 18
                    source: Icons.getAppIcon(tile.ipc.class ?? "", "application-x-executable")
                    asynchronous: true
                }

                StyledText {
                    width: Math.min(implicitWidth, tile.width - 30)
                    elide: Text.ElideRight
                    text: tile.ipc.title ?? ""
                    color: "white"
                    font.pointSize: 10
                }
            }

            HoverHandler {
                id: hover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: win.focusWindow(tile.modelData)
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: win.windows.length === 0
        opacity: win.progress * 0.8
        text: qsTr("Aucune fenêtre sur ce bureau")
        color: "white"
        font.pointSize: 16
    }
}

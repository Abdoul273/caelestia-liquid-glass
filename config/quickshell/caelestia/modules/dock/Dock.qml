pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

// Dock façon macOS, pensé pour le tiling : il ne réserve aucune place à l'écran.
// Il sort du bas (dans le verre du cadre) quand la souris touche le bord, reste visible
// sur un bureau vide et se cache en plein écran ou quand le lanceur est ouvert.
//   clic : ouvrir l'app / aller à sa fenêtre (clics suivants : fenêtre suivante)
//   clic milieu : nouvelle fenêtre     clic droit : épingler / désépingler
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property bool fullscreen

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property bool emptyWorkspace: (monitor?.activeWorkspace?.toplevels?.values?.length ?? 1) === 0
    property bool hovered
    property bool stayOpen // survol + petite attente avant de se cacher
    readonly property bool shown: Island.dock && !(FocusMode.active && FocusMode.hideDock) && !fullscreen && !(screenState?.launcher ?? false) && !(screenState?.controlCenter ?? false) && (stayOpen || emptyWorkspace || contextFor !== "" || dragging)
    property real reveal: shown ? 1 : 0

    readonly property real iconSize: 48
    readonly property real maxIcon: 72
    readonly property real pad: 10
    readonly property real bodyHeight: iconSize + pad * 2 + 8
    property real mouseX: -1000
    property real mouseY: -1000
    // Souris sur le verre du Dock ou sur le menu (la zone transparente au-dessus ne compte pas)
    property string contextFor: "" // app dont le menu (clic droit) est ouvert
    property real contextX: 0

    // ── Glisser-déposer façon macOS : ranger, épingler une app ouverte, retirer en la sortant ──
    property string dragId: ""
    property int dragFrom: -1
    property real dragDX: 0
    property real dragDY: 0
    readonly property bool dragging: dragId !== ""
    readonly property real step: iconSize + 6
    readonly property int pinnedCount: items.filter(i => i.pinned).length
    readonly property bool dragIsPinned: dragging && (items[dragFrom]?.pinned ?? false)
    // Sortie vers le haut : l'app est retirée du Dock au relâchement
    readonly property bool dragRemove: dragIsPinned && dragDY < -80
    // Place visée : parmi les apps épinglées (une app ouverte non épinglée peut y entrer)
    readonly property int dragTo: {
        if (!dragging || dragRemove)
            return dragFrom;
        const maxT = dragIsPinned ? pinnedCount - 1 : dragFrom;
        let t = Math.round(dragFrom + dragDX / step);
        t = Math.max(0, Math.min(maxT, t));
        // App non épinglée laissée parmi les apps ouvertes : elle ne bouge pas
        if (!dragIsPinned && t >= pinnedCount)
            return dragFrom;
        return t;
    }

    // Décalage des autres icônes pour faire de la place à celle qu'on déplace
    function shiftFor(index: int): real {
        if (!dragging || index === dragFrom || dragTo === dragFrom)
            return 0;
        if (dragTo > dragFrom && index > dragFrom && index <= dragTo)
            return -step;
        if (dragTo < dragFrom && index >= dragTo && index < dragFrom)
            return step;
        return 0;
    }

    function startDrag(index: int): void {
        contextFor = "";
        dragFrom = index;
        dragDX = 0;
        dragDY = 0;
        dragId = items[index]?.id ?? "";
    }

    function endDrag(): void {
        if (!dragging)
            return;
        const id = dragId;
        if (dragRemove) {
            pinned = pinned.filter(p => p !== id && (DesktopEntries.byId(p) ?? DesktopEntries.heuristicLookup(p))?.id !== id);
            savePins();
        } else if (dragTo !== dragFrom) {
            // Ordre affiché (apps trouvées), puis les épinglées introuvables pour ne rien perdre
            const shown = items.filter(i => i.pinned).map(i => i.id);
            const next = shown.filter(p => p !== id);
            next.splice(dragTo, 0, id);
            const known = new Set(items.map(i => i.id));
            pinned = [...next, ...pinned.filter(p => !known.has(p) && !next.includes(p) && !items.some(i => i.pinned && (DesktopEntries.byId(p) ?? DesktopEntries.heuristicLookup(p))?.id === i.id))];
            savePins();
        }
        dragId = "";
        dragFrom = -1;
        dragDX = 0;
        dragDY = 0;
    }

    // ── Apps épinglées (~/.local/state/caelestia/dock.json) ──
    property list<string> pinned: ["org.gnome.Nautilus", "kitty", "google-chrome", "aura", "antigravity", "org.telegram.desktop", "com.anthropic.Claude"]

    FileView {
        id: pinFile

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/dock.json`
        printErrors: false
        // Fichier modifié ailleurs (à la main, sauvegarde restaurée…) : le Dock suit
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (Array.isArray(d.pinned))
                    root.pinned = d.pinned;
            } catch (e) {}
        }
    }

    function savePins(): void {
        pinFile.setText(JSON.stringify({
            pinned: pinned
        }, null, 2));
    }

    function togglePin(id: string): void {
        pinned = pinned.includes(id) ? pinned.filter(p => p !== id) : [...pinned, id];
        savePins();
    }

    // ── Fenêtres ouvertes, rangées par app ──
    function entryFor(cls: string): var {
        return DesktopEntries.byId(cls) ?? DesktopEntries.heuristicLookup(cls);
    }

    readonly property var windowsByApp: {
        const map = {};
        for (const t of Hyprland.toplevels.values) {
            const cls = t.lastIpcObject?.class ?? "";
            if (!cls)
                continue;
            const e = entryFor(cls);
            const id = e?.id ?? cls;
            (map[id] = map[id] ?? []).push(t);
        }
        return map;
    }

    readonly property var items: {
        const list = [];
        for (const id of pinned) {
            const e = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
            if (e)
                list.push({
                    id: e.id,
                    entry: e,
                    pinned: true
                });
        }
        const seen = new Set(list.map(i => i.id));
        let first = true;
        // Apps qui tournent encore en arrière-plan (fenêtres fermées) : elles restent au Dock
        for (const id of Object.keys(bgUnits)) {
            if (seen.has(id) || windowsByApp[id])
                continue;
            seen.add(id);
            list.push({
                id: id,
                entry: DesktopEntries.byId(id),
                pinned: false,
                separator: first
            });
            first = false;
        }
        for (const id of Object.keys(windowsByApp)) {
            if (seen.has(id))
                continue;
            const e = DesktopEntries.byId(id) ?? entryFor(windowsByApp[id][0].lastIpcObject?.class ?? id);
            list.push({
                id: id,
                entry: e,
                pinned: false,
                separator: first
            });
            first = false;
        }
        return list;
    }

    // ── Apps lancées dont le processus tourne encore (unités systemd app-*) ──
    property var bgUnits: ({}) // id de l'app → unité systemd

    function unitApp(unit: string): string {
        const key = unit.replace(/^app-/, "").replace(/^[Hh]yprland-/, "").replace(/(@[^.]*)?\.(scope|service)$/, "").replace(/-\d+$/, "");
        if (!key || /kitty|terminal|foot|quickshell|caelestia/i.test(key))
            return "";
        const e = DesktopEntries.byId(key) ?? DesktopEntries.heuristicLookup(key);
        return e?.id ?? "";
    }

    Process {
        id: unitsProc

        command: ["systemctl", "--user", "list-units", "--type=scope,service", "--state=running", "--no-legend", "--plain", "app-*"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.split("\n")) {
                    const unit = line.trim().split(/\s+/)[0];
                    const id = unit ? root.unitApp(unit) : "";
                    if (id)
                        map[id] = unit;
                }
                if (JSON.stringify(map) !== JSON.stringify(root.bgUnits))
                    root.bgUnits = map;
            }
        }
    }

    Timer {
        running: root.shown || root.hovered
        repeat: true
        triggeredOnStart: true
        interval: 2500
        onTriggered: unitsProc.running = true
    }

    // Quitter vraiment l'app (fenêtres + processus en arrière-plan)
    function quitApp(item: var): void {
        const unit = bgUnits[item.id];
        const pid = windowsByApp[item.id]?.[0]?.lastIpcObject?.pid;
        const args = unit ? ["--unit", unit] : pid ? ["--pid", String(pid)] : [];
        if (args.length)
            Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/caelestia-quit-app`, ...args]);
        else
            closeApp(item);
        const b = Object.assign({}, bgUnits);
        delete b[item.id];
        bgUnits = b;
    }

    // Apps en cours de lancement (l'icône rebondit jusqu'à l'arrivée de la fenêtre)
    property var launching: ({})

    function launch(item: var): void {
        if (!item.entry)
            return;
        item.entry.execute();
        const l = Object.assign({}, launching);
        l[item.id] = Date.now();
        launching = l;
        launchTimeout.restart();
    }

    Timer {
        id: launchTimeout

        interval: 8000
        onTriggered: root.launching = ({})
    }

    onWindowsByAppChanged: {
        let changed = false;
        const l = Object.assign({}, launching);
        for (const id of Object.keys(l)) {
            if (windowsByApp[id]) {
                delete l[id];
                changed = true;
            }
        }
        if (changed)
            launching = l;
    }

    property var cycleIndex: ({})

    function activate(item: var): void {
        const wins = windowsByApp[item.id] ?? [];
        if (wins.length === 0) {
            launch(item);
            return;
        }
        // Fenêtre suivante de la même app à chaque clic
        const i = ((cycleIndex[item.id] ?? -1) + 1) % wins.length;
        const c = Object.assign({}, cycleIndex);
        c[item.id] = i;
        cycleIndex = c;
        const t = wins[i];
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "address:0x${t.address}" })` : `focuswindow address:0x${t.address}`);
    }

    function closeApp(item: var): void {
        for (const t of windowsByApp[item.id] ?? [])
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.close({ window = "address:0x${t.address}" })` : `closewindow address:0x${t.address}`);
    }

    // ── Taille : une bande invisible de 3 px garde le survol quand il est caché ──
    // Hauteur du verre (le reste, au-dessus, sert aux icônes agrandies et au menu)
    readonly property real blobHeight: bodyHeight * reveal
    readonly property real headroom: reveal > 0.01 ? (contextFor !== "" ? 190 : dragging ? 130 : 40) : 0

    // Largeur au repos (icônes non agrandies) : le Dock ne bouge plus quand les icônes grossissent,
    // sinon le pointeur change de place par rapport aux icônes et elles clignotent
    readonly property real restRowWidth: {
        const n = items.length;
        if (n === 0)
            return iconSize + 6 + 1;
        return iconSize + 6 + 1 + 6 + n * (iconSize + 6) - 6 + (items.some(i => i.separator) ? 7 : 0);
    }

    // Centre d'une icône au repos, dans le repère du Dock (-1 : bouton Applications)
    function restCentre(index: int): real {
        if (index < 0)
            return pad + iconSize / 2;
        let x = pad + iconSize + 6 + 1 + 6 + index * (iconSize + 6);
        for (let i = 0; i <= index && i < items.length; i++)
            if (items[i].separator)
                x += 7;
        return x + iconSize / 2;
    }

    implicitWidth: restRowWidth + pad * 2
    implicitHeight: Math.max(3, blobHeight + headroom)

    Behavior on reveal {
        NumberAnimation {
            duration: root.shown ? 420 : 300
            easing.type: root.shown ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 0.8
        }
    }

    HoverHandler {
        onHoveredChanged: {
            root.hovered = hovered;
            if (hovered) {
                hideTimer.stop();
                root.stayOpen = true;
            } else {
                hideTimer.restart();
                root.mouseX = -1000;
                root.mouseY = -1000;
            }
        }
        onPointChanged: {
            root.mouseX = point.position.x;
            root.mouseY = point.position.y;
        }
    }

    // Le menu fermé (ou le glisser fini), le Dock se cache normalement si la souris est partie
    onContextForChanged: if (contextFor === "" && !hovered) hideTimer.restart()
    onDraggingChanged: if (!dragging && !hovered) hideTimer.restart()

    // Clic en dehors du Dock (autre fenêtre, bureau) : le menu se ferme
    HyprlandFocusGrab {
        active: root.contextFor !== ""
        windows: [QsWindow.window]
        onCleared: root.contextFor = ""
    }

    Timer {
        id: hideTimer

        interval: 450
        onTriggered: {
            if (!root.hovered && root.contextFor === "" && !root.dragging)
                root.stayOpen = false;
        }
    }

    // ════════════════════ Contenu ════════════════════
    Item {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        y: root.height - root.blobHeight
        height: root.bodyHeight
        opacity: Math.min(1, root.reveal * 1.5)

        Row {
            id: row

            // Les icônes agrandies débordent des deux côtés à parts égales
            x: root.pad - (row.width - root.restRowWidth) / 2
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.pad + 6
            spacing: 6

            // Applications (lanceur de Caelestia)
            DockIcon {
                dock: root
                appId: "__launcher"
                label: qsTr("Applications")
                symbol: "apps"
                onPrimary: root.screenState.launcher = true
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                width: 1
                height: root.iconSize - 16
                color: Qt.alpha(Colours.palette.m3onSurface, 0.18)
            }

            Repeater {
                model: root.items

                Row {
                    id: slot

                    required property var modelData
                    required property int index

                    anchors.bottom: parent?.bottom
                    spacing: 6
                    z: root.dragFrom === index ? 10 : 0

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        visible: slot.modelData.separator ?? false
                        width: 1
                        height: root.iconSize - 16
                        color: Qt.alpha(Colours.palette.m3onSurface, 0.18)
                    }

                    DockIcon {
                        id: dockIcon

                        dock: root
                        appId: slot.modelData.id
                        index: slot.index
                        draggable: true
                        label: slot.modelData.entry?.name ?? slot.modelData.id
                        iconSource: Quickshell.iconPath(slot.modelData.entry?.icon ?? "", "application-x-executable")
                        running: (root.windowsByApp[slot.modelData.id]?.length ?? 0) > 0 || root.bgUnits[slot.modelData.id] !== undefined
                        windows: root.windowsByApp[slot.modelData.id]?.length ?? 0
                        bouncing: root.launching[slot.modelData.id] !== undefined
                        onPrimary: root.activate(slot.modelData)
                        onMiddle: root.launch(slot.modelData)
                        onSecondary: {
                            root.contextX = dockIcon.mapToItem(root, dockIcon.width / 2, 0).x;
                            root.contextFor = root.contextFor === slot.modelData.id ? "" : slot.modelData.id;
                        }
                    }
                }
            }
        }
    }

    // ── Menu du clic droit (au-dessus du Dock) ──
    Rectangle {
        id: ctxMenu

        readonly property var item: root.items.find(i => i.id === root.contextFor) ?? null

        visible: root.contextFor !== "" && root.reveal > 0.9
        x: Math.max(0, Math.min(root.width - width, root.contextX - width / 2))
        anchors.bottom: body.top
        anchors.bottomMargin: 34
        width: ctxCol.width + 12
        height: ctxCol.height + 12
        radius: 16
        color: Qt.alpha(Colours.palette.m3surface, 0.94)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)

        Column {
            id: ctxCol

            x: 6
            y: 6

            CtxEntry {
                text: ctxMenu.item?.pinned ? qsTr("Retirer du Dock") : qsTr("Garder dans le Dock")
                onClicked: {
                    root.togglePin(root.contextFor);
                    root.contextFor = "";
                }
            }
            CtxEntry {
                text: qsTr("Nouvelle fenêtre")
                onClicked: {
                    if (ctxMenu.item)
                        root.launch(ctxMenu.item);
                    root.contextFor = "";
                }
            }
            CtxEntry {
                visible: (root.windowsByApp[root.contextFor]?.length ?? 0) > 0
                text: (root.windowsByApp[root.contextFor]?.length ?? 0) > 1 ? qsTr("Tout fermer") : qsTr("Fermer")
                danger: true
                onClicked: {
                    if (ctxMenu.item)
                        root.closeApp(ctxMenu.item);
                    root.contextFor = "";
                }
            }
            CtxEntry {
                visible: (root.windowsByApp[root.contextFor]?.length ?? 0) > 0 || root.bgUnits[root.contextFor] !== undefined
                text: qsTr("Quitter")
                danger: true
                onClicked: {
                    if (ctxMenu.item)
                        root.quitApp(ctxMenu.item);
                    root.contextFor = "";
                }
            }
        }
    }

    // Le menu se ferme si la souris quitte le Dock un moment
    // Pendant la capture (menu ouvert) le survol n'est plus fiable : on lit la vraie position du curseur
    property bool cursorAway
    Process {
        id: cursorProc

        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text);
                    const win = QsWindow.window;
                    const o = root.mapToItem(win.contentItem, 0, 0);
                    const x = c.x - (root.monitor?.x ?? 0) - o.x;
                    const y = c.y - (root.monitor?.y ?? 0) - o.y;
                    const onBody = x >= 0 && x <= root.width && y >= root.height - root.blobHeight - 6 && y <= root.height + 4;
                    const m = ctxMenu.mapToItem(root, 0, 0);
                    const onMenu = x >= m.x - 8 && x <= m.x + ctxMenu.width + 8 && y >= m.y - 8 && y <= m.y + ctxMenu.height + 40;
                    root.cursorAway = !onBody && !onMenu;
                } catch (e) {}
            }
        }
    }
    Timer {
        running: root.contextFor !== ""
        repeat: true
        interval: 250
        onTriggered: cursorProc.running = true
        onRunningChanged: root.cursorAway = false
    }
    Timer {
        running: root.contextFor !== "" && root.cursorAway
        interval: 600
        onTriggered: {
            root.contextFor = "";
            root.hovered = false;
            root.stayOpen = false;
        }
    }

    // ════════════════════ Composants ════════════════════

    component DockIcon: Item {
        id: di

        required property var dock
        property string appId
        property string label
        property string iconSource
        property string symbol
        property bool running
        property int windows
        property bool bouncing
        property int index: -1
        property bool draggable
        readonly property bool dragged: di.dock.dragging && di.dock.dragFrom === index
        property real shift: di.dock.shiftFor(index)
        property bool pressedForDrag
        property real pressX
        property real pressY
        property bool wasDrag

        Behavior on shift {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
        signal primary
        signal middle
        signal secondary

        // Grossissement façon macOS selon la distance au pointeur
        // Centre de l'icône au repos (indépendant du grossissement, pour éviter une boucle)
        readonly property real centreX: di.dock.restCentre(di.index)
        readonly property real dist: Math.abs(di.dock.mouseX - centreX)
        readonly property real zoom: di.dock.hovered && !di.dock.dragging ? Math.max(0, 1 - dist / 150) : 0
        readonly property real size: di.dock.iconSize + (di.dock.maxIcon - di.dock.iconSize) * zoom * zoom

        width: size
        height: di.dock.iconSize

        Behavior on width {
            NumberAnimation {
                duration: 90
            }
        }

        Item {
            id: iconBox

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: di.size
            height: di.size

            // Rebond pendant le lancement
            property real hop: 0

            transform: Translate {
                x: di.dragged ? di.dock.dragDX : di.shift
                y: -iconBox.hop + (di.dragged ? Math.min(0, di.dock.dragDY) : 0)
            }

            scale: di.dragged ? 1.12 : 1
            opacity: di.dragged && di.dock.dragRemove ? 0.55 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutBack
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }
            }

            SequentialAnimation on hop {
                running: di.bouncing
                loops: Animation.Infinite
                NumberAnimation {
                    to: 22
                    duration: 260
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    to: 0
                    duration: 260
                    easing.type: Easing.InQuad
                }
                onRunningChanged: if (!running) iconBox.hop = 0
            }

            IconImage {
                anchors.fill: parent
                visible: di.iconSource !== ""
                source: di.iconSource
                asynchronous: true
                scale: diArea.pressed ? 0.9 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutBack
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: parent.width * 0.06
                visible: di.symbol !== ""
                radius: width * 0.26
                color: Qt.alpha(Colours.palette.m3primary, 0.9)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: di.symbol
                    color: Colours.palette.m3onPrimary
                    fontStyle: Tokens.font.icon.size(di.size * 0.28).build()
                    fill: 1
                }
            }
        }

        // Point sous les apps ouvertes (deux points si plusieurs fenêtres)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 3
            spacing: 3

            Repeater {
                model: di.running ? Math.max(1, Math.min(2, di.windows)) : 0

                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: Colours.palette.m3onSurface
                    opacity: 0.8
                }
            }
        }

        // Sortie vers le haut : « Retirer »
        Rectangle {
            visible: di.dragged && di.dock.dragRemove
            x: (parent.width - width) / 2 + di.dock.dragDX
            y: -height - 12 + Math.min(0, di.dock.dragDY)
            width: rmTip.implicitWidth + 20
            height: 26
            radius: 13
            color: Qt.alpha(Colours.palette.m3error, 0.9)

            StyledText {
                id: rmTip

                anchors.centerIn: parent
                text: qsTr("Retirer")
                color: Colours.palette.m3onError
                font.pointSize: 9
                font.weight: Font.DemiBold
            }
        }

        // Nom de l'app au survol
        Rectangle {
            visible: diArea.containsMouse && di.dock.contextFor === "" && !di.dock.dragging
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: iconBox.top
            anchors.bottomMargin: 10
            width: tip.implicitWidth + 20
            height: 26
            radius: 13
            color: Qt.alpha(Colours.palette.m3surface, 0.92)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)

            StyledText {
                id: tip

                anchors.centerIn: parent
                text: di.label
                color: Colours.palette.m3onSurface
                font.pointSize: 9
                font.weight: Font.Medium
            }
        }

        MouseArea {
            id: diArea

            anchors.fill: iconBox
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: di.dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            preventStealing: true
            onPressed: e => {
                di.wasDrag = false;
                di.pressedForDrag = di.draggable && e.button === Qt.LeftButton;
                di.pressX = e.x;
                di.pressY = e.y;
            }
            onPositionChanged: e => {
                if (!di.pressedForDrag)
                    return;
                const dx = e.x - di.pressX, dy = e.y - di.pressY;
                if (!di.dock.dragging && Math.hypot(dx, dy) > 8) {
                    di.wasDrag = true;
                    di.dock.startDrag(di.index);
                }
                if (di.dragged) {
                    di.dock.dragDX = dx;
                    di.dock.dragDY = dy;
                }
            }
            onReleased: {
                di.pressedForDrag = false;
                if (di.dragged)
                    di.dock.endDrag();
            }
            onCanceled: {
                di.pressedForDrag = false;
                if (di.dragged)
                    di.dock.endDrag();
            }
            onClicked: e => {
                if (di.wasDrag)
                    return;
                if (e.button === Qt.MiddleButton)
                    di.middle();
                else if (e.button === Qt.RightButton)
                    di.secondary();
                else
                    di.primary();
            }
        }
    }

    component CtxEntry: Rectangle {
        id: ce

        property string text
        property bool danger
        signal clicked

        width: Math.max(170, ceLbl.implicitWidth + 28)
        height: 34
        radius: 10
        color: ceArea.containsMouse ? Qt.alpha(Colours.palette.m3onSurface, 0.1) : "transparent"

        StyledText {
            id: ceLbl

            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: ce.text
            color: ce.danger ? "#ff453a" : Colours.palette.m3onSurface
            font.pointSize: 9.5
        }

        MouseArea {
            id: ceArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ce.clicked()
        }
    }
}

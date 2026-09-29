pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: contentItem.Config.border.thickness * (1 - fsTransitionProg)
    readonly property real borderRounding: contentItem.Config.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness

    property color surfaceColour: Colours.tPalette.m3surface

    readonly property int dragMaskPadding: {
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.lastIpcObject.windows > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: screenState.launcher || screenState.session || screenState.notesActive || screenState.controlCenter ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: hasFullscreen ? emptyRegion : regions

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {}
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    Region {
        id: emptyRegion

        x: panels.notifications.x + bar.implicitWidth
        y: panels.notifications.y + root.borderThickness
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: root.width - width
            y: panels.osdWrapper.y + root.borderThickness
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + root.borderThickness
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled) || s.controlCenter)
                return true;
            if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.dashboard = false;
            root.screenState.controlCenter = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: Glass.panels ? 1 : root.surfaceColour.a
        layer.enabled: true
        layer.effect: Glass.panels ? glassBlobEffect : shadowEffect

        BlobGroup {
            id: blobGroup

            color: Glass.panels ? Qt.alpha(root.surfaceColour, 1) : root.surfaceColour
            smoothing: root.contentItem.Config.border.smoothing
        }

        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: root.borderRounding
            borderLeft: bar.implicitWidth - anchors.margins - root.sdfBorderOffset
            borderRight: root.borderThickness - anchors.margins - root.sdfBorderOffset
            // Avec l'île, le bord haut disparaît : elle sort directement du haut de l'écran
            borderTop: (Island.hideTopBorder ? 0 : root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderBottom: root.borderThickness - anchors.margins - root.sdfBorderOffset
        }

        PanelBg {
            id: dashBg


            panel: panels.dashboard
            deformAmount: 0.1
            visible: panels.dashboard.visible
            // Le verre naît de l'île (même taille, même place) et grandit jusqu'au panneau.
            // Le haut dépasse de l'écran : seuls les coins du bas sont arrondis.
            radius: Math.min(panels.dashboard.fromH / 2, 32) + (Tokens.rounding.extraLarge - Math.min(panels.dashboard.fromH / 2, 32)) * panels.dashboard.morph
            x: panel.x + bar.implicitWidth + (panel.width - panels.dashboard.curW) / 2
            implicitWidth: panels.dashboard.curW
            // Fermé : rangé bien au-dessus de l'écran (sinon il se fond dans l'île au repos et change ses bords)
            y: panels.dashboard.visible ? -radius : -radius - 200
            implicitHeight: panels.dashboard.visible ? Math.max(0, panel.y + root.borderThickness + panels.dashboard.visBottom) + radius : radius
        }

        // Épaules du dashboard (Notes, Tâches…) : il sort du bord de l'écran comme l'île
        Shoulders {
            lx: dashBg.x
            rx: dashBg.x + dashBg.width
            // Même épaules que l'île au départ, puis celles du panneau
            s: panels.dashboard.visible ? Math.min(18, panels.dashboard.fromH * 0.55) + (26 - Math.min(18, panels.dashboard.fromH * 0.55)) * panels.dashboard.morph : 0
        }

        // L'île fait partie de la forme fluide : même verre, même fusion que les panneaux.
        // Le rectangle dépasse au-dessus de l'écran pour que seuls les coins du bas soient arrondis.
        PanelBg {
            id: islandBg

            panel: panels.island
            deformAmount: 0.12
            radius: panels.island.radius
            // Repliée : le rectangle remonte bien au-dessus de l'écran pour que la fusion ne laisse aucune bosse
            y: -radius - Math.max(0, 30 - panels.island.h * 3)
            implicitHeight: panels.island.h + radius
        }

        // Épaules de l'île : deux arrondis concaves qui la font sortir du bord de l'écran
        Shoulders {
            lx: islandBg.x
            rx: islandBg.x + islandBg.width
            s: Math.min(18, panels.island.h * 0.55)
        }

        // Centre de contrôle : même verre, collé au haut de l'écran
        PanelBg {
            id: ccBg

            readonly property var cc: panels.controlCenter
            readonly property real fromR: Math.min((cc.fromBottom + root.borderThickness) / 2, 32)

            panel: panels.controlCenter
            deformAmount: 0.08
            // Le verre part de l'île (même place, même taille) et file vers le coin haut droit
            radius: fromR + (30 - fromR) * cc.morph
            x: cc.curX + bar.implicitWidth
            implicitWidth: cc.curW
            // Fermé : rangé au-dessus de l'écran (sinon il se fondrait dans l'île au repos)
            y: cc.visible ? -radius : -radius - 200
            implicitHeight: cc.visible ? Math.max(0, cc.curBottom + root.borderThickness) + radius : radius
            visible: cc.visible
        }

        Shoulders {
            lx: ccBg.x
            rx: ccBg.x + ccBg.width
            s: panels.controlCenter.visible ? Math.min(18, (panels.controlCenter.fromBottom + root.borderThickness) * 0.55) + (22 - Math.min(18, (panels.controlCenter.fromBottom + root.borderThickness) * 0.55)) * panels.controlCenter.morph : 0
        }

        // Dock : même verre ; replié, le rectangle descend bien sous l'écran (aucune bosse)
        PanelBg {
            id: dockBg

            panel: panels.dock
            deformAmount: 0.06
            radius: 26
            y: panel.y + root.borderThickness + panel.height - panels.dock.blobHeight + 30 * (1 - panels.dock.reveal)
            implicitHeight: panels.dock.blobHeight + radius
            // Replié : largeur nulle, sinon il creuse le bord bas du cadre
            implicitWidth: panels.dock.reveal > 0.001 ? panel.width : 0
            x: panel.x + bar.implicitWidth + (panels.dock.reveal > 0.001 ? 0 : panel.width / 2)
        }

        PanelBg {
            id: launcherBg


            panel: panels.launcher
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg


            panel: panels.sessionWrapper
            deformAmount: 0.2
            x: panels.sessionWrapper.x + panels.session.x + bar.implicitWidth
            implicitWidth: panels.session.width
        }

        PanelBg {
            id: sidebarBg

            panel: panels.sidebar
            deformAmount: 0.03
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [utilsBg]
            bottomLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: osdBg


            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.osdWrapper.x + panels.osd.x + bar.implicitWidth
            implicitWidth: panels.osd.width
        }

        // En mode verre, le panneau des notifications fusionne avec le cadre ;
        // sinon chaque carte flotte seule
        PanelBg {
            id: notifsBg

            panel: panels.notifications
            group: Glass.panels ? blobGroup : null
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: popoutBg


            // Extra width to prevent vertical movement deformation partially detaching panel from bar
            property real extraWidth: panels.popouts.isDetached ? 0 : 0.2

            panel: panels.popoutsWrapper
            deformAmount: panels.popouts.isDetached ? 0.05 : panels.popouts.hasCurrent ? 0.15 : 0.1
            x: panels.popoutsWrapper.x + panels.popouts.x + bar.implicitWidth - panels.popouts.width * extraWidth
            implicitWidth: panels.popouts.width * (1 + extraWidth)

            Behavior on extraWidth {
                Anim {}
            }
        }
    }

    Component {
        id: shadowEffect

        MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }
    }

    // Fond d'écran lu par le verre « iOS » pour la réfraction (demi-résolution : léger en mémoire)
    Image {
        id: wallpaperImg

        anchors.fill: parent
        asynchronous: true
        cache: false
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.round(width / 2), Math.round(height / 2))
        source: Glass.ios && Wallpapers.current ? `file://${Wallpapers.current}` : ""
    }

    ShaderEffectSource {
        id: wallpaperTex

        anchors.fill: parent
        sourceItem: wallpaperImg
        hideSource: true
        live: false
        visible: false
        textureSize: Qt.size(Math.round(width / 2), Math.round(height / 2))

        Connections {
            target: wallpaperImg

            function onStatusChanged(): void {
                if (wallpaperImg.status === Image.Ready)
                    wallpaperTex.scheduleUpdate();
            }
        }
    }

    // Cadre, barre, sidebar et utilitaires en liquid glass
    Component {
        id: glassBlobEffect

        ShaderEffect {
            // Uniformes du style iOS (ignorés par le shader classique)
            readonly property vector4d zone: Qt.vector4d(bar.implicitWidth, root.borderThickness, root.borderThickness, root.borderThickness)
            readonly property real refraction: wallpaperImg.status === Image.Ready ? 0.65 : 0
            readonly property var wallpaper: wallpaperTex

            readonly property vector2d texel: Qt.vector2d(1 / Math.max(1, width), 1 / Math.max(1, height))
            readonly property vector3d tint: Qt.vector3d(root.surfaceColour.r, root.surfaceColour.g, root.surfaceColour.b)
            readonly property real tintAlpha: Glass.ios ? Glass.surfaceOpacity : Colours.light ? 0.56 : 0.46
            readonly property real light: Glass.highlightStrength
            readonly property real shadowStrength: 0.17 * Math.max(0, root.shadowOpacity) / 0.7
            readonly property point mouse: Qt.point(interactions.mouseX / Math.max(1, width), interactions.mouseY / Math.max(1, height))
            property real hover: interactions.containsMouse ? 1 : 0

            Behavior on hover {
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.OutCubic
                }
            }

            fragmentShader: Qt.resolvedUrl(Quickshell.shellPath(Glass.ios ? "assets/shaders/liquidios.frag.qsb" : "assets/shaders/glassblob.frag.qsb"))
        }
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            borderThickness: root.borderThickness

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            island.fullscreen: root.hasFullscreen
            dock.fullscreen: root.hasFullscreen
            controlCenter.transform: Matrix4x4 {
                matrix: ccBg.deformMatrix
            }
            island.transform: Matrix4x4 {
                matrix: islandBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: Glass.panels ? notifsBg.deformMatrix : Qt.matrix4x4()
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: popoutBg.deformMatrix
            }
        }

        BarWrapper {
            id: bar

            anchors.top: parent.top
            anchors.bottom: parent.bottom

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts

            fullscreen: root.hasFullscreen
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    // Deux arrondis concaves en haut d'un panneau collé au bord de l'écran (île, dashboard, centre de contrôle)
    component Shoulders: Shape {
        id: shoulders

        required property real s
        required property real lx
        required property real rx

        anchors.fill: parent
        visible: Island.hideTopBorder && s > 0.5
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: blobGroup.color
            strokeColor: "transparent"
            startX: shoulders.lx - shoulders.s
            startY: -1
            PathLine {
                x: shoulders.lx + 1
                y: -1
            }
            PathLine {
                x: shoulders.lx + 1
                y: shoulders.s
            }
            PathArc {
                x: shoulders.lx - shoulders.s
                y: 0
                radiusX: shoulders.s
                radiusY: shoulders.s
                direction: PathArc.Counterclockwise
            }
        }

        ShapePath {
            fillColor: blobGroup.color
            strokeColor: "transparent"
            startX: shoulders.rx + shoulders.s
            startY: -1
            PathLine {
                x: shoulders.rx - 1
                y: -1
            }
            PathLine {
                x: shoulders.rx - 1
                y: shoulders.s
            }
            PathArc {
                x: shoulders.rx + shoulders.s
                y: 0
                radiusX: shoulders.s
                radiusY: shoulders.s
            }
        }
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15

        group: blobGroup
        x: panel.x + bar.implicitWidth
        y: panel.y + root.borderThickness
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.extraLarge
        deformScale: (deformAmount * Config.appearance.deformScale) / 10000
    }
}

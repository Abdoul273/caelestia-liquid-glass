pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus

// Paramètres (Super + I) dans le même verre que l'île : une goutte se détache de l'île,
// descend au centre de l'écran et devient le panneau Nexus (navigation + pages).
// Le bouton en haut à droite le détache en fenêtre ; Échap le referme.
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.settings ?? false

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
    readonly property real curR: fromR + (34 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.45) / 0.55))

    function close(): void {
        screenState.settings = false;
    }

    visible: morph > 0.001
    implicitWidth: Math.round(implicitHeight * Tokens.sizes.nexus.ratio)
    implicitHeight: Math.round(screen.height * Tokens.sizes.nexus.heightMult)

    Behavior on morph {
        NumberAnimation {
            duration: root.shown ? 680 : 400
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
            content.forceActiveFocus();
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

            Keys.onEscapePressed: root.close()

            // Nexus n'existe que pendant l'ouverture (il est lourd : pages, listes…)
            Loader {
                anchors.fill: parent
                active: root.morph > 0.001
                asynchronous: false

                sourceComponent: Nexus {
                    nState.screen: root.screen
                    nState.isWindow: false
                    nState.animatingContainer: root.morph < 0.999
                    // Le verre de l'île sert de fond : le cadre de Nexus reste léger
                    blobColour: Qt.alpha(Colours.palette.m3surfaceContainerLow, 0.5)
                    onClose: root.close()
                }
            }
        }
    }
}

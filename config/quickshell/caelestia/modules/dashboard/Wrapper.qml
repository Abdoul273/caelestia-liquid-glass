pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.utils

Item {
    id: root

    required property ScreenState screenState
    readonly property FileDialog facePicker: FileDialog {
        title: qsTr("Choisir une photo de profil")
        filterLabel: qsTr("Fichiers image")
        filters: Images.validImageExtensions
        onAccepted: path => {
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "low", "-h", `STRING:image-path:${path}`, qsTr("Photo de profil modifiée"), qsTr("Photo de profil modifiée pour %1").arg(Paths.shortenHome(path))]);
            else
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", qsTr("Impossible de changer la photo de profil"), qsTr("Échec du changement de photo de profil pour %1").arg(Paths.shortenHome(path))]);
        }
    }

    readonly property real nonAnimHeight: (content.item as Content)?.nonAnimHeight ?? 0
    readonly property bool shouldBeActive: screenState.dashboard && Config.dashboard.enabled

    // ── Ouverture façon Dynamic Island : le panneau naît de l'île et grandit à partir d'elle ──
    property Item island // l'île (pour partir de sa taille exacte)
    property real screenTop // décalage entre le haut du panneau et le haut de l'écran
    property real fromW: 240
    property real fromH: 40
    property real morph: shouldBeActive ? 1 : 0
    readonly property real offsetScale: 1 - morph
    // Forme visible actuelle (le verre de ContentWindow la suit)
    readonly property real curW: fromW + (width - fromW) * morph
    readonly property real visBottom: (fromH - screenTop) + (height - fromH + screenTop) * morph

    onShouldBeActiveChanged: {
        if (shouldBeActive && island && island.h > 1) {
            fromW = island.w;
            fromH = island.h;
        } else if (shouldBeActive) {
            fromW = 240;
            fromH = 40;
        }
    }

    visible: morph > 0.001
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 854 // Hard coded fallback for first open

    Behavior on morph {
        NumberAnimation {
            duration: root.shouldBeActive ? 560 : 360
            easing.type: root.shouldBeActive ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 0.7
        }
    }

    // Le contenu est découpé à la forme qui grandit, puis se pose en fondu + léger zoom
    Item {
        id: clipper

        x: (root.width - root.curW) / 2
        y: -root.screenTop - 60
        width: Math.max(0, root.curW)
        height: Math.max(0, root.visBottom + root.screenTop + 60)
        clip: root.morph < 0.999

        Loader {
            id: content

            x: (root.width - width) / 2 - clipper.x
            y: -clipper.y

            active: root.shouldBeActive || root.visible

            readonly property real reveal: Math.max(0, Math.min(1, (root.morph - 0.4) / 0.6))
            opacity: reveal
            scale: 0.92 + 0.08 * reveal
            transformOrigin: Item.Top

            sourceComponent: Content {
                screenState: root.screenState
                facePicker: root.facePicker
            }
        }
    }
}

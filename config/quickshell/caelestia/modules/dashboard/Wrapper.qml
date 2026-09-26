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
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 854 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        active: root.shouldBeActive || root.visible

        // Ouverture façon macOS : le contenu se pose avec un léger zoom et un fondu
        // un peu en retard sur le panneau, pour une sensation de profondeur.
        property real reveal: root.shouldBeActive ? 1 : 0
        opacity: reveal
        scale: 0.94 + 0.06 * reveal
        transformOrigin: Item.Top

        Behavior on reveal {
            SequentialAnimation {
                PauseAnimation {
                    duration: root.shouldBeActive ? 60 : 0
                }
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
        }

        sourceComponent: Content {
            screenState: root.screenState
            facePicker: root.facePicker
        }
    }
}

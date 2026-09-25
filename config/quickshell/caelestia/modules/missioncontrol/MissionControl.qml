pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.components.misc
import qs.services

// Mission Control façon macOS : les fenêtres de l'espace courant se rangent
// en grille, les espaces de travail s'affichent en haut.
// Ouvrir/fermer : raccourci global « caelestia:missionControl » ou
// `qs -c caelestia ipc call missioncontrol toggle`.
Scope {
    id: root

    property bool open
    // Reste vrai pendant l'animation de fermeture
    property bool shown

    function toggle(): void {
        if (open) {
            open = false;
            return;
        }
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
        shown = true;
        open = true;
    }

    function close(): void {
        open = false;
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "missionControl"
        description: qsTr("Mission Control : voir toutes les fenêtres")
        onPressed: root.toggle()
    }

    // Utilisés par les gestes du pavé tactile (réaction instantanée)
    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "missionControlOpen"
        description: qsTr("Ouvrir Mission Control")
        onPressed: {
            if (!root.open)
                root.toggle();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "missionControlClose"
        description: qsTr("Fermer Mission Control")
        onPressed: root.close()
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            if (!root.open)
                root.toggle();
        }

        function close(): void {
            root.close();
        }

        target: "missioncontrol"
    }

    Variants {
        model: Quickshell.screens

        McSurface {
            required property ShellScreen modelData

            screen: modelData
            mc: root
        }
    }
}

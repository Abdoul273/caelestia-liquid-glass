import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.components.misc
import qs.services
import qs.modules.nexus

Scope {
    id: root

    property bool launcherInterrupted
    // Super+Maj+N / Super+Maj+T : panneau Notes ou Tâches seul ; même raccourci = fermer
    function toggleQuick(kind: string): void {
        if (hasFullscreen)
            return;
        const screenState = ShellState.forActive();
        const wasOpen = screenState.dashboard && (kind === "tasks" ? screenState.quickTasks : screenState.quickNotes);
        screenState.controlCenter = false;
        screenState.quickNotes = kind === "notes";
        screenState.quickTasks = kind === "tasks";
        screenState.dashboardTab = 0;
        screenState.dashboard = !wasOpen;
    }

    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "nexus"
        description: qsTr("Ouvrir les paramètres Nexus")
        onPressed: WindowFactory.create()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "showall"
        description: qsTr("Afficher/Masquer le lanceur, le tableau de bord et l'OSD")
        onPressed: {
            if (root.hasFullscreen)
                return;
            const v = ShellState.forActive();
            v.launcher = v.dashboard = v.osd = v.utilities = !(v.launcher || v.dashboard || v.osd || v.utilities);
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "dashboard"
        description: qsTr("Afficher/Masquer le tableau de bord")
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            if (Island.controlCenter) {
                screenState.dashboard = false;
                screenState.quickNotes = false;
                screenState.quickTasks = false;
                screenState.controlCenter = !screenState.controlCenter;
                return;
            }
            screenState.quickNotes = false;
            screenState.quickTasks = false;
            screenState.dashboard = !screenState.dashboard;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "spotlight"
        description: qsTr("Ouvrir/Fermer Spotlight")
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            const open = !screenState.spotlight;
            if (open) {
                screenState.controlCenter = false;
                screenState.launcher = false;
                screenState.dashboard = false;
            }
            screenState.spotlight = open;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "quicknotes"
        description: qsTr("Ouvrir les notes rapides")
        onPressed: root.toggleQuick("notes")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "quicktasks"
        description: qsTr("Ouvrir les tâches AuraTask")
        onPressed: root.toggleQuick("tasks")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "session"
        description: qsTr("Afficher/Masquer le menu de session")
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.session = !screenState.session;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcher"
        description: qsTr("Afficher/Masquer le lanceur")
        onPressed: root.launcherInterrupted = false
        onReleased: {
            if (!root.launcherInterrupted && !root.hasFullscreen) {
                const screenState = ShellState.forActive();
                screenState.launcher = !screenState.launcher;
            }
            root.launcherInterrupted = false;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "launcherInterrupt"
        description: qsTr("Interrompre le raccourci du lanceur")
        onPressed: root.launcherInterrupted = true
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "sidebar"
        description: qsTr("Afficher/Masquer le volet latéral")
        onPressed: {
            if (root.hasFullscreen)
                return;
            if (Island.controlCenter) {
                Island.notifCenter = !Island.notifCenter;
                return;
            }
            const screenState = ShellState.forActive();
            screenState.sidebar = !screenState.sidebar;
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "utilities"
        description: qsTr("Afficher/Masquer les utilitaires")
        onPressed: {
            if (root.hasFullscreen)
                return;
            const screenState = ShellState.forActive();
            screenState.utilities = !screenState.utilities;
        }
    }

    IpcHandler {
        function toggle(drawer: string): void {
            if (list().split("\n").includes(drawer)) {
                if (root.hasFullscreen && ["launcher", "session", "dashboard"].includes(drawer))
                    return;
                const screenState = ShellState.forActive();
                screenState[drawer] = !screenState[drawer];
            } else {
                console.warn(lc, `Drawer "${drawer}" does not exist`);
            }
        }

        function list(): string {
            const screenState = ShellState.forActive();
            return Object.keys(screenState).filter(k => typeof screenState[k] === "boolean").join("\n");
        }

        function isOpen(drawer: string): string {
            const screenState = ShellState.forActive();
            if (typeof screenState[drawer] !== "boolean")
                return "unknown";
            return screenState[drawer] ? "1" : "0";
        }

        target: "drawers"
    }

    IpcHandler {
        function open(): void {
            WindowFactory.create();
        }

        target: "nexus"
    }

    IpcHandler {
        function info(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Info);
        }

        function success(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Success);
        }

        function warn(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Warning);
        }

        function error(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Error);
        }

        target: "toaster"
    }

    LoggingCategory {
        id: lc

        name: "caelestia.qml.shortcuts"
        defaultLogLevel: LoggingCategory.Info
    }
}

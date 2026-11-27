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

    // Gouttes de verre de l'île (Spotlight, calculatrice, projection, presse-papiers…) : une seule à la fois
    readonly property var drops: ["spotlight", "calculator", "display", "clipboard", "emoji", "keyhelp", "clock", "settings", "annotate", "earbuds", "agentos", "dictation", "writing", "translate", "siri"]
    function toggleDrop(kind: string): void {
        if (hasFullscreen)
            return;
        const screenState = ShellState.forActive();
        const open = !screenState[kind];
        if (open) {
            screenState.controlCenter = false;
            screenState.launcher = false;
            screenState.dashboard = false;
            for (const d of drops)
                if (d !== kind && d in screenState)
                    screenState[d] = false;
        }
        screenState[kind] = open;
    }

    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "nexus"
        description: I18n.tr("Ouvrir les paramètres Nexus")
        onPressed: root.toggleDrop("settings")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "showall"
        description: I18n.tr("Afficher/Masquer le lanceur, le tableau de bord et l'OSD")
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
        description: I18n.tr("Afficher/Masquer le tableau de bord")
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
        description: I18n.tr("Ouvrir/Fermer Spotlight")
        onPressed: root.toggleDrop("spotlight")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clipboard"
        description: I18n.tr("Presse-papiers (Super + V) : même goutte de verre")
        onPressed: root.toggleDrop("clipboard")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "emoji"
        description: I18n.tr("Emojis (Super + .) : même goutte de verre")
        onPressed: root.toggleDrop("emoji")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "keyhelp"
        description: I18n.tr("Raccourcis (Super + H) : recherche façon Spotlight")
        onPressed: root.toggleDrop("keyhelp")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clock"
        description: I18n.tr("Horloge (Super + Maj + O) : même goutte de verre")
        onPressed: root.toggleDrop("clock")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "settings"
        description: I18n.tr("Paramètres (Super + I) : Nexus dans la goutte de verre")
        onPressed: root.toggleDrop("settings")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "annotate"
        description: I18n.tr("Annoter une capture : même goutte de verre")
        onPressed: root.toggleDrop("annotate")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "earbuds"
        description: I18n.tr("Écouteurs 3D (Super + Maj + B) : même goutte de verre façon AirPodsDesktop")
        onPressed: root.toggleDrop("earbuds")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "agentos"
        description: I18n.tr("Agent OS (Super + Maj + A) : cockpit multi-agents Liquid Glass façon Katana")
        onPressed: root.toggleDrop("agentos")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "display"
        description: I18n.tr("Ouvrir/Fermer la projection (choix de l'écran)")
        onPressed: root.toggleDrop("display")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "calculator"
        description: I18n.tr("Ouvrir/Fermer la calculatrice")
        onPressed: root.toggleDrop("calculator")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "dictation"
        description: I18n.tr("Dictée : parler, puis le texte est tapé dans le champ actif")
        onPressed: root.toggleDrop("dictation")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "writing"
        description: I18n.tr("Outils d'écriture sur le texte sélectionné (corriger, reformuler…)")
        onPressed: root.toggleDrop("writing")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "translate"
        description: I18n.tr("Traduction rapide (reprend le texte sélectionné)")
        onPressed: root.toggleDrop("translate")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "siri"
        description: I18n.tr("Assistant vocal (Gemini Live) dans le verre de l'île")
        onPressed: root.toggleDrop("siri")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "quicknotes"
        description: I18n.tr("Ouvrir les notes rapides")
        onPressed: root.toggleQuick("notes")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "quicktasks"
        description: I18n.tr("Ouvrir les tâches AuraTask")
        onPressed: root.toggleQuick("tasks")
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "session"
        description: I18n.tr("Afficher/Masquer le menu de session")
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
        description: I18n.tr("Afficher/Masquer le lanceur")
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
        description: I18n.tr("Interrompre le raccourci du lanceur")
        onPressed: root.launcherInterrupted = true
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "sidebar"
        description: I18n.tr("Afficher/Masquer le volet latéral")
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
        description: I18n.tr("Afficher/Masquer les utilitaires")
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
            const screenState = ShellState.forActive();
            if (!screenState.settings)
                root.toggleDrop("settings");
        }
        function window(): void {
            WindowFactory.create();
        }

        target: "nexus"
    }

    // Éditeur d'annotation des captures (remplace swappy) : annotate open <fichier>
    IpcHandler {
        function open(path: string): void {
            const screenState = ShellState.forActive();
            screenState.annotatePath = path;
            if (!screenState.annotate)
                root.toggleDrop("annotate");
        }
        function close(): void {
            ShellState.forActive().annotate = false;
        }

        target: "annotate"
    }

    IpcHandler {
        function toggle(): void {
            root.toggleDrop("earbuds");
        }
        function open(): void {
            const screenState = ShellState.forActive();
            if (!screenState.earbuds)
                root.toggleDrop("earbuds");
        }
        function close(): void {
            ShellState.forActive().earbuds = false;
        }

        target: "earbuds"
    }

    IpcHandler {
        function toggle(): void {
            root.toggleDrop("agentos");
        }
        function open(): void {
            const screenState = ShellState.forActive();
            if (screenState && !screenState.agentos)
                root.toggleDrop("agentos");
        }
        function close(): void {
            const screenState = ShellState.forActive();
            if (screenState)
                screenState.agentos = false;
        }

        target: "agentos"
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

import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool quickNotes
    property bool quickTasks
    readonly property bool quick: quickNotes || quickTasks
    property bool utilities
    property bool sidebar
    property bool controlCenter
    property bool spotlight
    property bool calculator
    property bool dictation
    property bool writing
    property bool translate
    property bool display
    property bool annotate
    property string annotatePath
    property bool settings
    property bool clock
    property bool keyhelp
    property bool emoji
    property bool clipboard

    // Dashboard state
    property int dashboardTab
    property bool notesActive
    property date dashboardDate: new Date()

    // Le tableau de bord complet est retiré : il ne s'ouvre plus qu'en Notes (Super+Maj+N) ou Tâches (Super+Maj+T)
    onDashboardChanged: {
        if (dashboard && !quick)
            dashboard = false;
    }
}

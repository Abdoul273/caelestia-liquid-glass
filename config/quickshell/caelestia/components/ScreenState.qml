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
    property bool utilities
    property bool sidebar
    property bool controlCenter

    // Dashboard state
    property int dashboardTab
    property bool notesActive
    property date dashboardDate: new Date()
}

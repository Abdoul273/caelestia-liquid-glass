pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

// Onglet « Notes » du tableau de bord : liste à gauche, éditeur à droite.
// Enregistrement automatique (Notes.qml), raccourcis :
//   Ctrl+N nouvelle note · Ctrl+F rechercher · Ctrl+P épingler · Ctrl+Suppr supprimer
//   Ctrl+Z après suppression : restaurer · Ctrl+L case à cocher · Ctrl+Entrée cocher/décocher
Item {
    id: root

    required property ScreenState screenState

    property string query

    // Super+Maj+N : panneau de notes seules, sans le sélecteur Notes | Tâches
    readonly property bool quick: screenState.quickNotes
    readonly property string shownMode: quick ? "notes" : Notes.mode

    readonly property list<var> visibleNotes: {
        const q = query.trim().toLowerCase();
        return q ? Notes.sorted.filter(n => n.body.toLowerCase().includes(q)) : Notes.sorted;
    }

    implicitWidth: 860
    implicitHeight: 440

    function relTime(ms: real): string {
        const diff = (Date.now() - ms) / 1000;
        if (diff < 60)
            return qsTr("à l'instant");
        if (diff < 3600)
            return qsTr("il y a %1 min").arg(Math.floor(diff / 60));
        const d = new Date(ms);
        const today = new Date();
        if (d.toDateString() === today.toDateString())
            return d.toLocaleTimeString(Qt.locale(), "HH:mm");
        const yest = new Date(today.getTime() - 86400000);
        if (d.toDateString() === yest.toDateString())
            return qsTr("hier");
        if (d.getFullYear() === today.getFullYear())
            return d.toLocaleDateString(Qt.locale(), "d MMM");
        return d.toLocaleDateString(Qt.locale(), "d MMM yyyy");
    }

    function focusMode(): void {
        if (root.shownMode === "tasks") {
            tasksPane.focusInput();
            return;
        }
        if (!Notes.current)
            Notes.create();
        editor.forceActiveFocus();
    }

    function setMode(m: string): void {
        Notes.mode = m;
        focusMode();
    }

    function newNote(): void {
        Notes.mode = "notes";
        query = "";
        Notes.create();
        editor.forceActiveFocus();
    }

    function open(id: string): void {
        Notes.currentId = id;
        editor.forceActiveFocus();
    }

    Component.onCompleted: {
        if (Notes.loaded && !Notes.current)
            Notes.currentId = Notes.sorted[0]?.id ?? "";
        if (root.screenState.notesActive)
            focusTimer.restart();
    }

    // Curseur directement dans la note quand on arrive sur l'onglet
    Connections {
        target: root.screenState

        function onNotesActiveChanged(): void {
            if (root.screenState.notesActive)
                focusTimer.restart();
        }

        function onDashboardChanged(): void {
            if (root.screenState.dashboard && root.screenState.notesActive)
                focusTimer.restart();
        }
    }

    Timer {
        id: focusTimer

        interval: 120
        onTriggered: root.focusMode()
    }

    Shortcut {
        sequence: "Ctrl+N"
        enabled: root.screenState.notesActive
        onActivated: root.newNote()
    }

    Shortcut {
        sequence: "Ctrl+T"
        enabled: root.screenState.notesActive && !root.quick
        onActivated: root.setMode(root.shownMode === "tasks" ? "notes" : "tasks")
    }

    Shortcut {
        sequence: "Ctrl+F"
        enabled: root.screenState.notesActive
        onActivated: {
            Notes.mode = "notes";
            search.forceActiveFocus();
        }
    }

    Shortcut {
        sequence: "Ctrl+P"
        enabled: root.screenState.notesActive && !!Notes.current
        onActivated: Notes.togglePin(Notes.currentId)
    }

    Shortcut {
        sequence: "Ctrl+Del"
        enabled: root.screenState.notesActive && !!Notes.current
        onActivated: Notes.remove(Notes.currentId)
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        // ───────────── Liste des notes ─────────────
        StyledRect {
            Layout.preferredWidth: 270
            Layout.fillHeight: true

            radius: Tokens.rounding.extraLarge
            color: Glass.tile(Colours.tPalette.m3surfaceContainer)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                // En-tête des notes rapides
                RowLayout {
                    visible: root.quick
                    Layout.fillWidth: true
                    Layout.leftMargin: Tokens.padding.small
                    Layout.topMargin: Tokens.padding.extraSmall
                    Layout.bottomMargin: Tokens.padding.extraSmall
                    spacing: Tokens.spacing.small

                    StyledRect {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "edit_note"
                            fill: 1
                            color: Colours.palette.m3onPrimary
                            fontStyle: Tokens.font.icon.builders.medium.scale(0.85).build()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: qsTr("Notes")
                            font: Tokens.font.body.builders.large.size(15).weight(Font.DemiBold).build()
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            text: qsTr("Ctrl+N nouvelle · Échap fermer")
                            font: Tokens.font.label.small
                            color: Colours.palette.m3outline
                        }
                    }
                }

                // Sélecteur Notes | Tâches
                StyledRect {
                    id: modeSwitch

                    visible: !root.quick
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Tokens.rounding.full
                    color: Glass.tile(Colours.tPalette.m3surfaceContainerHigh)

                    StyledRect {
                        x: root.shownMode === "tasks" ? parent.width / 2 + 2 : 4
                        y: 4
                        width: parent.width / 2 - 6
                        height: parent.height - 8
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        Behavior on x {
                            Anim {}
                        }
                    }

                    Row {
                        anchors.fill: parent

                        ModeButton {
                            mode: "notes"
                            icon: "sticky_note_2"
                            label: qsTr("Notes")
                        }

                        ModeButton {
                            mode: "tasks"
                            icon: "task_alt"
                            label: Tasks.todoCount > 0 ? qsTr("Tâches · %1").arg(Tasks.todoCount) : qsTr("Tâches")
                        }
                    }
                }

                RowLayout {
                    visible: root.shownMode === "notes"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    SearchBar {
                        id: search

                        Layout.fillWidth: true
                        placeholderText: qsTr("Rechercher")
                        text: root.query
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: {
                            if (text)
                                clear();
                            else
                                editor.forceActiveFocus();
                        }
                        Keys.onReturnPressed: {
                            if (root.visibleNotes.length > 0)
                                root.open(root.visibleNotes[0].id);
                        }
                        Keys.onDownPressed: list.forceActiveFocus()
                    }

                    IconButton {
                        icon: "add"
                        type: IconButton.Filled
                        radius: Tokens.rounding.full
                        onClicked: root.newNote()
                    }
                }

                StyledListView {
                    id: list

                    visible: root.shownMode === "notes"
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    clip: true
                    spacing: Tokens.spacing.extraSmall
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.visibleNotes
                    currentIndex: root.visibleNotes.findIndex(n => n.id === Notes.currentId)
                    keyNavigationEnabled: true
                    highlightFollowsCurrentItem: false

                    Keys.onReturnPressed: editor.forceActiveFocus()
                    Keys.onUpPressed: {
                        if (currentIndex <= 0)
                            search.forceActiveFocus();
                        else
                            Notes.currentId = root.visibleNotes[currentIndex - 1].id;
                    }
                    Keys.onDownPressed: {
                        if (currentIndex < count - 1)
                            Notes.currentId = root.visibleNotes[currentIndex + 1].id;
                    }

                    add: Transition {
                        Anim {
                            properties: "opacity,scale"
                            from: 0
                            to: 1
                        }
                    }

                    remove: Transition {
                        Anim {
                            properties: "opacity,scale"
                            to: 0
                        }
                    }

                    displaced: Transition {
                        Anim {
                            property: "y"
                        }
                    }

                    delegate: StyledRect {
                        id: noteItem

                        required property var modelData
                        readonly property bool selected: modelData.id === Notes.currentId

                        width: ListView.view.width
                        implicitHeight: itemLayout.implicitHeight + Tokens.padding.medium * 2

                        radius: Tokens.rounding.large
                        color: selected ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.85) : "transparent"

                        StateLayer {
                            radius: noteItem.radius
                            color: Colours.palette.m3onSurface
                            onClicked: root.open(noteItem.modelData.id)
                        }

                        ColumnLayout {
                            id: itemLayout

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.padding.large
                            anchors.rightMargin: Tokens.padding.large
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.extraSmall

                                MaterialIcon {
                                    visible: noteItem.modelData.pinned
                                    text: "keep"
                                    fill: 1
                                    color: Colours.palette.m3primary
                                    fontStyle: Tokens.font.icon.builders.medium.scale(0.75).build()
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Notes.titleOf(noteItem.modelData)
                                    elide: Text.ElideRight
                                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                                    color: noteItem.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                                }

                                StyledText {
                                    text: root.relTime(noteItem.modelData.updated)
                                    font: Tokens.font.label.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: Notes.previewOf(noteItem.modelData)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: root.query ? qsTr("Aucun résultat") : qsTr("Aucune note\nCtrl+N pour commencer")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                }

                // Résumé des tâches (mode Tâches)
                ColumnLayout {
                    visible: root.shownMode === "tasks"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacing.medium

                    Item {
                        Layout.fillHeight: true
                    }

                    CircularProgress {
                        id: ring

                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 130
                        implicitSize: 130
                        strokeWidth: 8
                        value: Tasks.tasks.length ? Tasks.doneCount / Tasks.tasks.length : 0

                        Behavior on clampedVal {
                            Anim {}
                        }

                        Column {
                            anchors.centerIn: parent

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Tasks.tasks.length ? `${Math.round(ring.value * 100)} %` : "—"
                                font: Tokens.font.body.builders.large.size(22).weight(Font.DemiBold).build()
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: qsTr("accompli")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Tasks.tasks.length === 0 ? qsTr("Aucune tâche") : Tasks.todoCount === 0 ? qsTr("Tout est fait 🎉") : Tasks.todoCount === 1 ? qsTr("1 tâche à faire") : qsTr("%1 tâches à faire").arg(Tasks.todoCount)
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    TextButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: Tasks.doneCount > 0
                        text: qsTr("Effacer les terminées")
                        type: TextButton.Text
                        onClicked: Tasks.clearDone()
                    }
                }

                StyledText {
                    visible: root.shownMode === "notes"
                    Layout.alignment: Qt.AlignHCenter
                    readonly property int n: Notes.notes.filter(n => n.body.trim()).length

                    text: n === 1 ? qsTr("1 note") : qsTr("%1 notes").arg(n)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }
            }
        }

        // ───────────── Éditeur ─────────────
        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            radius: Tokens.rounding.extraLarge
            color: Glass.tile(Colours.tPalette.m3surfaceContainer)

            TasksPane {
                id: tasksPane

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                visible: root.shownMode === "tasks"
            }

            ColumnLayout {
                visible: root.shownMode === "notes"
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.topMargin: Tokens.padding.medium
                spacing: Tokens.spacing.small

                // Barre d'outils
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.small
                        text: Notes.current ? qsTr("Modifiée %1").arg(root.relTime(Notes.current.updated)) : ""
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }

                    // Indicateur d'enregistrement
                    Row {
                        spacing: Tokens.spacing.extraSmall
                        opacity: Notes.current ? 1 : 0
                        scale: Notes.dirty ? 1.04 : 1

                        Behavior on scale {
                            Anim {}
                        }

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notes.dirty ? "sync" : "cloud_done"
                            color: Notes.dirty ? Colours.palette.m3tertiary : Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.builders.medium.scale(0.8).build()
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notes.dirty ? qsTr("Enregistrement…") : qsTr("Enregistré")
                            font: Tokens.font.label.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    Item {
                        implicitWidth: Tokens.spacing.medium
                    }

                    IconButton {
                        icon: "checklist"
                        type: IconButton.Text
                        enabled: !!Notes.current
                        onClicked: editor.insertCheckbox()
                    }

                    IconButton {
                        icon: "keep"
                        type: IconButton.Text
                        isToggle: true
                        checked: Notes.current?.pinned ?? false
                        enabled: !!Notes.current
                        onClicked: Notes.togglePin(Notes.currentId)
                    }

                    IconButton {
                        icon: "content_copy"
                        type: IconButton.Text
                        enabled: !!Notes.current?.body
                        onClicked: {
                            editor.selectAll();
                            editor.copy();
                            editor.deselect();
                            Toaster.toast(qsTr("Note copiée"), Notes.titleOf(Notes.current), "content_copy");
                        }
                    }

                    IconButton {
                        icon: "delete"
                        type: IconButton.Text
                        enabled: !!Notes.current
                        onClicked: Notes.remove(Notes.currentId)
                    }
                }

                StyledFlickable {
                    id: flick

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    clip: true
                    contentWidth: width
                    contentHeight: editor.height
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    function ensureVisible(r: rect): void {
                        if (contentY >= r.y)
                            contentY = r.y;
                        else if (contentY + height <= r.y + r.height)
                            contentY = r.y + r.height - height;
                    }

                    TextEdit {
                        id: editor

                        property bool syncing

                        width: flick.width
                        // Toute la carte est cliquable, pas seulement les lignes écrites
                        height: Math.max(implicitHeight, flick.height)
                        leftPadding: Tokens.padding.small
                        rightPadding: Tokens.padding.small
                        bottomPadding: Tokens.padding.large

                        enabled: !!Notes.current
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        selectByMouse: true
                        persistentSelection: true
                        font: Tokens.font.body.builders.large.size(13).build()
                        color: Colours.palette.m3onSurface
                        selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                        selectedTextColor: color

                        onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                        onTextChanged: {
                            if (!syncing && Notes.current)
                                Notes.update(Notes.currentId, text);
                        }

                        function load(): void {
                            syncing = true;
                            text = Notes.current?.body ?? "";
                            cursorPosition = text.length;
                            syncing = false;
                            flick.contentY = 0;
                        }

                        function lineBounds(): var {
                            const start = text.lastIndexOf("\n", cursorPosition - 1) + 1;
                            let end = text.indexOf("\n", cursorPosition);
                            if (end < 0)
                                end = text.length;
                            return [start, end];
                        }

                        function insertCheckbox(): void {
                            const [start] = lineBounds();
                            const line = text.slice(start, lineBounds()[1]);
                            if (!/^\s*[-*] \[[ xX]\] /.test(line))
                                insert(start, "- [ ] ");
                            forceActiveFocus();
                        }

                        function toggleCheckbox(): void {
                            const [start, end] = lineBounds();
                            const line = text.slice(start, end);
                            const m = line.match(/^(\s*[-*] \[)([ xX])\]/);
                            if (!m) {
                                insertCheckbox();
                                return;
                            }
                            const pos = start + m[1].length;
                            const keep = cursorPosition;
                            remove(pos, pos + 1);
                            insert(pos, m[2] === " " ? "x" : " ");
                            cursorPosition = keep;
                        }

                        Connections {
                            target: Notes

                            function onCurrentIdChanged(): void {
                                editor.load();
                            }

                            function onLoadedChanged(): void {
                                editor.load();
                            }
                        }

                        Component.onCompleted: load()

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                toggleCheckbox();
                                event.accepted = true;
                            } else if (ctrl && event.key === Qt.Key_Delete) {
                                Notes.remove(Notes.currentId);
                                event.accepted = true;
                            } else if (ctrl && event.key === Qt.Key_L) {
                                insertCheckbox();
                                event.accepted = true;
                            } else if (ctrl && event.key === Qt.Key_Z && !canUndo && Notes.trashed) {
                                Notes.restore();
                                event.accepted = true;
                            } else if (!ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                // Continuer automatiquement les listes (-, *, •, 1., cases à cocher)
                                const [start] = lineBounds();
                                const line = text.slice(start, cursorPosition);
                                const m = line.match(/^(\s*)([-*•] \[[ xX]\] |[-*•] |(\d+)[.)] )(.*)$/);
                                if (!m)
                                    return;
                                event.accepted = true;
                                if (!m[4].trim()) {
                                    // Ligne de liste vide → on sort de la liste
                                    remove(start, cursorPosition);
                                    insert(cursorPosition, "\n");
                                    return;
                                }
                                let bullet = m[2];
                                if (m[3])
                                    bullet = `${parseInt(m[3]) + 1}${m[2].slice(m[3].length)}`;
                                else
                                    bullet = bullet.replace(/\[[xX]\]/, "[ ]");
                                insert(cursorPosition, `\n${m[1]}${bullet}`);
                            } else if (event.key === Qt.Key_Tab) {
                                insert(cursorPosition, "    ");
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.screenState.dashboard = false;
                                event.accepted = true;
                            }
                        }

                        StyledText {
                            x: editor.leftPadding
                            visible: !editor.text
                            text: Notes.current ? qsTr("Commence à écrire…\nLa première ligne sert de titre.") : qsTr("Crée une note avec + ou Ctrl+N")
                            color: Colours.palette.m3outline
                            font: editor.font
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            cursorShape: Qt.IBeamCursor
                        }
                    }
                }
            }
        }
    }

    component ModeButton: Item {
        id: btn

        required property string mode
        required property string icon
        required property string label
        readonly property bool active: Notes.mode === mode

        width: modeSwitch.width / 2
        height: modeSwitch.height

        Row {
            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.icon
                fill: btn.active ? 1 : 0
                color: btn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.builders.medium.scale(0.8).build()
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                font: Tokens.font.label.large
                color: btn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setMode(btn.mode)
        }
    }
}

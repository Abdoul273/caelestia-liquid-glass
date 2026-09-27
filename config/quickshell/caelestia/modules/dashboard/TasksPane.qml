pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.effects
import qs.services

// Mode « Tâches » de l'onglet Notes : vraies cases à cocher, enregistrées dans Tasks.qml.
// Entrée ajoute · clic sur la case coche · clic sur le texte modifie · Ctrl+Z restaure la dernière supprimée
ColumnLayout {
    id: root

    // Filtre : "all", "today", "overdue"
    property string filter: "all"
    readonly property list<var> shown: filter === "today" ? Tasks.sorted.filter(t => !t.done && Tasks.isToday(t)) : filter === "overdue" ? Tasks.sorted.filter(t => Tasks.isOverdue(t)) : Tasks.sorted

    function priorityColour(p: string): color {
        if (p === "urgent")
            return Colours.palette.m3error;
        if (p === "high")
            return Colours.palette.m3tertiary;
        if (p === "low")
            return Colours.palette.m3outline;
        return Colours.palette.m3primary;
    }

    function focusInput(): void {
        input.forceActiveFocus();
    }

    spacing: Tokens.spacing.small

    // Champ d'ajout
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: input.implicitHeight + Tokens.padding.medium * 2

        radius: Tokens.rounding.full
        color: Glass.tile(Colours.tPalette.m3surfaceContainerHigh)

        MaterialIcon {
            id: addIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.large

            text: "add_task"
            color: input.activeFocus ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.medium.scale(0.9).build()
        }

        TextInput {
            id: input

            anchors.left: addIcon.right
            anchors.right: addBtn.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacing.medium
            anchors.rightMargin: Tokens.spacing.small

            font: Tokens.font.body.builders.large.size(13).build()
            color: Colours.palette.m3onSurface
            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
            selectByMouse: true
            clip: true

            onAccepted: {
                Tasks.add(text);
                clear();
            }

            Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z && !canUndo && Tasks.trashed) {
                    Tasks.restore();
                    event.accepted = true;
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: qsTr("Ajouter une tâche…   ! haute · !! urgente · demain")
                color: Colours.palette.m3outline
                font: input.font
            }
        }

        IconButton {
            id: addBtn

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Tokens.padding.small

            icon: "arrow_upward"
            type: IconButton.Filled
            radius: Tokens.rounding.full
            opacity: input.text.trim() ? 1 : 0
            enabled: opacity > 0
            onClicked: input.accepted()

            Behavior on opacity {
                Anim {}
            }
        }
    }

    StyledListView {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: true

        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown

        add: Transition {
            Anim {
                properties: "opacity,scale"
                from: 0
                to: 1
            }
        }

        remove: Transition {
            Anim {
                properties: "opacity"
                to: 0
            }
        }

        move: Transition {
            Anim {
                property: "y"
            }
        }

        displaced: Transition {
            Anim {
                property: "y"
            }
        }

        delegate: Item {
            id: task

            required property var modelData
            required property int index
            readonly property bool done: modelData.done
            readonly property bool firstDone: done && index > 0 && !root.shown[index - 1].done
            property bool editing

            width: ListView.view.width
            implicitHeight: row.implicitHeight + (firstDone ? doneHeader.implicitHeight + Tokens.spacing.medium : 0)

            // Séparateur « Terminées » avant la première tâche cochée
            StyledText {
                id: doneHeader

                visible: task.firstDone
                x: Tokens.padding.large
                text: qsTr("Terminées · %1").arg(Tasks.doneCount)
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledRect {
                id: row

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: Math.max(checkbox.implicitHeight, textCol.implicitHeight) + Tokens.padding.medium * 1.6

                radius: Tokens.rounding.large
                color: hover.hovered ? Qt.alpha(Colours.palette.m3onSurface, 0.06) : "transparent"

                Behavior on color {
                    CAnim {}
                }

                HoverHandler {
                    id: hover
                }

                // Case à cocher
                StyledRect {
                    id: checkbox

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.medium

                    implicitWidth: 22
                    implicitHeight: 22
                    radius: 7
                    color: Glass.lensControls ? "transparent" : task.done ? Colours.palette.m3primary : "transparent"
                    border.width: task.done || Glass.lensControls ? 0 : 2
                    border.color: checkMouse.containsMouse ? Colours.palette.m3primary : task.modelData.priority === "urgent" || task.modelData.priority === "high" ? root.priorityColour(task.modelData.priority) : Colours.palette.m3outline
                    scale: checkMouse.pressed ? 0.85 : 1

                    Behavior on color {
                        CAnim {}
                    }

                    Behavior on scale {
                        Anim {}
                    }

                    // Case en verre bombé : teintée quand cochée, verre clair sinon
                    GlassControl {
                        visible: Glass.lensControls
                        anchors.fill: parent
                        radius: 7
                        tintColour: task.done ? Colours.palette.m3primary : task.modelData.priority === "urgent" || task.modelData.priority === "high" ? Qt.alpha(root.priorityColour(task.modelData.priority), 0.35) : Qt.alpha(Colours.palette.m3onSurface, checkMouse.containsMouse ? 0.2 : 0.12)
                        pressed: checkMouse.pressed
                        hovered: checkMouse.containsMouse
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "check"
                        color: Colours.palette.m3onPrimary
                        fontStyle: Tokens.font.icon.builders.medium.scale(0.75).build()
                        scale: task.done ? 1 : 0

                        Behavior on scale {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    MouseArea {
                        id: checkMouse

                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Tasks.toggle(task.modelData.id)
                    }
                }

                ColumnLayout {
                    id: textCol

                    anchors.left: checkbox.right
                    anchors.right: prioBtn.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.spacing.medium
                    anchors.rightMargin: Tokens.spacing.small
                    spacing: 2

                    StyledText {
                        id: label

                        Layout.fillWidth: true
                        text: task.modelData.text
                        wrapMode: Text.Wrap
                        font.pointSize: 13
                        font.strikeout: task.done
                        color: task.editing ? "transparent" : task.done ? Colours.palette.m3outline : Colours.palette.m3onSurface

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: {
                                task.editing = true;
                                editField.text = task.modelData.text;
                                editField.forceActiveFocus();
                                editField.selectAll();
                            }
                        }

                        TextInput {
                            id: editField

                            anchors.fill: parent
                            visible: task.editing
                            font: label.font
                            color: Colours.palette.m3onSurface
                            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter

                            onAccepted: focus = false
                            onActiveFocusChanged: {
                                if (!activeFocus && task.editing) {
                                    task.editing = false;
                                    Tasks.edit(task.modelData.id, text);
                                }
                            }
                            Keys.onEscapePressed: {
                                text = task.modelData.text;
                                focus = false;
                            }
                        }
                    }

                    // Détails venus d'AuraTask : échéance, sous-tâches, catégorie
                    Row {
                        readonly property bool overdue: Tasks.isOverdue(task.modelData)

                        visible: !task.done && (task.modelData.due > 0 || task.modelData.subTotal > 0 || task.modelData.category)
                        spacing: Tokens.spacing.medium

                        Meta {
                            visible: task.modelData.due > 0
                            icon: parent.overdue ? "event_busy" : "event"
                            text: Tasks.dueLabel(task.modelData)
                            colour: parent.overdue ? Colours.palette.m3error : Tasks.isToday(task.modelData) ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        }

                        Meta {
                            visible: task.modelData.subTotal > 0
                            icon: "checklist"
                            text: `${task.modelData.subDone}/${task.modelData.subTotal}`
                        }

                        Meta {
                            visible: !!task.modelData.category
                            icon: "label"
                            text: task.modelData.category
                        }
                    }
                }

                // Priorité : un clic la fait tourner (basse → moyenne → haute → urgente)
                IconButton {
                    id: prioBtn

                    readonly property bool strong: task.modelData.priority === "urgent" || task.modelData.priority === "high"

                    anchors.right: delBtn.left
                    anchors.verticalCenter: parent.verticalCenter

                    visible: !task.done
                    icon: "flag"
                    type: IconButton.Text
                    label.color: root.priorityColour(task.modelData.priority)
                    opacity: strong || hover.hovered ? 1 : 0
                    enabled: opacity > 0
                    onClicked: Tasks.cyclePriority(task.modelData.id)

                    Behavior on opacity {
                        Anim {}
                    }
                }

                IconButton {
                    id: delBtn

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: Tokens.padding.small

                    icon: "close"
                    type: IconButton.Text
                    opacity: hover.hovered ? 1 : 0
                    enabled: hover.hovered
                    onClicked: Tasks.remove(task.modelData.id)

                    Behavior on opacity {
                        Anim {}
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            visible: list.count === 0
            spacing: Tokens.spacing.small

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "task_alt"
                color: Colours.palette.m3outline
                fontStyle: Tokens.font.icon.builders.large.scale(1.6).build()
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.filter === "overdue" ? qsTr("Rien en retard 👌") : root.filter === "today" ? qsTr("Rien de prévu aujourd'hui") : qsTr("Rien à faire. Profite !")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }
    }

    component Meta: Row {
        property string icon
        property string text
        property color colour: Colours.palette.m3onSurfaceVariant

        spacing: 3

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.icon
            color: parent.colour
            fontStyle: Tokens.font.icon.builders.medium.scale(0.62).build()
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.text
            color: parent.colour
            font: Tokens.font.label.small
        }
    }
}

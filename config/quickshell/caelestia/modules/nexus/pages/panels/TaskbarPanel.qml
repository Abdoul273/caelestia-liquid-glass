pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Barre des tâches")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: qsTr("Comportement")
        }

        ToggleRow {
            first: true
            text: qsTr("Persistant")
            subtext: qsTr("Conserver la barre toujours visible")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: qsTr("Afficher au survol")
            subtext: qsTr("Afficher la barre lorsque le curseur atteint le bord de l'écran")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Seuil de glissement")
            subtext: qsTr("Distance de glissement avant d'afficher la barre (px)")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader {
            text: qsTr("Composants")
        }

        NavRow {
            first: true
            icon: "workspaces"
            text: qsTr("Espaces de travail")
            subtext: qsTr("Indicateurs, icônes d'applications")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "web_asset"
            text: qsTr("Fenêtre active")
            subtext: qsTr("Affichage du titre, volet")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "widgets"
            text: qsTr("Boîte à miniatures")
            subtext: qsTr("Icônes de la boîte à miniatures")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "signal_cellular_alt"
            text: qsTr("Icônes d'état")
            subtext: qsTr("Indicateurs visibles")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "schedule"
            text: qsTr("Horloge")
            subtext: qsTr("Date, icône, arrière-plan")
            onClicked: root.nState.openSubPage(10)
        }

        // Scroll actions
        SectionHeader {
            text: qsTr("Actions au défilement")
        }

        ToggleRow {
            first: true
            text: qsTr("Espaces de travail")
            subtext: qsTr("Défilez sur l'indicateur pour basculer d'espace de travail")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            text: qsTr("Volume")
            subtext: qsTr("Défilez sur la moitié supérieure pour régler le volume")
            checked: Config.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Luminosité")
            subtext: qsTr("Défilez sur la moitié inférieure pour régler la luminosité")
            checked: Config.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}

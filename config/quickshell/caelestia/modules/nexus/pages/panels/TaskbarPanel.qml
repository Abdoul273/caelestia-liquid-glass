pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common
import qs.services

PageBase {
    id: root

    title: I18n.tr("Barre des tâches")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: I18n.tr("Comportement")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Persistant")
            subtext: I18n.tr("Conserver la barre toujours visible")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: I18n.tr("Afficher au survol")
            subtext: I18n.tr("Afficher la barre lorsque le curseur atteint le bord de l'écran")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: I18n.tr("Seuil de glissement")
            subtext: I18n.tr("Distance de glissement avant d'afficher la barre (px)")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader {
            text: I18n.tr("Composants")
        }

        NavRow {
            first: true
            icon: "workspaces"
            text: I18n.tr("Espaces de travail")
            subtext: I18n.tr("Indicateurs, icônes d'applications")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "web_asset"
            text: I18n.tr("Fenêtre active")
            subtext: I18n.tr("Affichage du titre, volet")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "widgets"
            text: I18n.tr("Boîte à miniatures")
            subtext: I18n.tr("Icônes de la boîte à miniatures")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            icon: "signal_cellular_alt"
            text: I18n.tr("Icônes d'état")
            subtext: I18n.tr("Indicateurs visibles")
            onClicked: root.nState.openSubPage(9)
        }

        NavRow {
            last: true
            icon: "schedule"
            text: I18n.tr("Horloge")
            subtext: I18n.tr("Date, icône, arrière-plan")
            onClicked: root.nState.openSubPage(10)
        }

        // Scroll actions
        SectionHeader {
            text: I18n.tr("Actions au défilement")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Espaces de travail")
            subtext: I18n.tr("Défilez sur l'indicateur pour basculer d'espace de travail")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

        ToggleRow {
            text: I18n.tr("Volume")
            subtext: I18n.tr("Défilez sur la moitié supérieure pour régler le volume")
            checked: Config.bar.scrollActions.volume
            onToggled: GlobalConfig.bar.scrollActions.volume = checked
        }

        ToggleRow {
            last: true
            text: I18n.tr("Luminosité")
            subtext: I18n.tr("Défilez sur la moitié inférieure pour régler la luminosité")
            checked: Config.bar.scrollActions.brightness
            onToggled: GlobalConfig.bar.scrollActions.brightness = checked
        }
    }
}

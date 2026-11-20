import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common
import qs.services

PageBase {
    id: root

    title: I18n.tr("Panneaux")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        NavRow {
            first: true
            icon: "dashboard"
            text: I18n.tr("Tableau de bord")
            subtext: Config.dashboard.enabled ? I18n.tr("Activé") : I18n.tr("Désactivé")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "dock_to_bottom"
            text: I18n.tr("Barre des tâches")
            subtext: Config.bar.persistent ? I18n.tr("Toujours visible") : Config.bar.showOnHover ? I18n.tr("Afficher au survol") : I18n.tr("Afficher par glissement")
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            icon: "apps"
            text: I18n.tr("Lanceur")
            subtext: Config.launcher.enabled ? I18n.tr("Activé") : I18n.tr("Désactivé")
            onClicked: root.nState.openSubPage(3)
        }

        NavRow {
            icon: "dock_to_right"
            text: I18n.tr("Volet latéral")
            subtext: Config.sidebar.enabled ? I18n.tr("Activé") : I18n.tr("Désactivé")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            last: true
            icon: "construction"
            text: I18n.tr("Utilitaires")
            subtext: Config.utilities.enabled ? I18n.tr("Activé") : I18n.tr("Désactivé")
            onClicked: root.nState.openSubPage(5)
        }
    }
}

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Panneaux")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        NavRow {
            first: true
            icon: "dashboard"
            text: qsTr("Tableau de bord")
            subtext: Config.dashboard.enabled ? qsTr("Activé") : qsTr("Désactivé")
            onClicked: root.nState.openSubPage(1)
        }

        NavRow {
            icon: "dock_to_bottom"
            text: qsTr("Barre des tâches")
            subtext: Config.bar.persistent ? qsTr("Toujours visible") : Config.bar.showOnHover ? qsTr("Afficher au survol") : qsTr("Afficher par glissement")
            onClicked: root.nState.openSubPage(2)
        }

        NavRow {
            icon: "apps"
            text: qsTr("Lanceur")
            subtext: Config.launcher.enabled ? qsTr("Activé") : qsTr("Désactivé")
            onClicked: root.nState.openSubPage(3)
        }

        NavRow {
            icon: "dock_to_right"
            text: qsTr("Volet latéral")
            subtext: Config.sidebar.enabled ? qsTr("Activé") : qsTr("Désactivé")
            onClicked: root.nState.openSubPage(4)
        }

        NavRow {
            last: true
            icon: "construction"
            text: qsTr("Utilitaires")
            subtext: Config.utilities.enabled ? qsTr("Activé") : qsTr("Désactivé")
            onClicked: root.nState.openSubPage(5)
        }
    }
}

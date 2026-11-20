pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common
import qs.services

PageBase {
    id: root

    function isToggleOn(id: string): bool {
        const item = Config.utilities.quickToggles.values.find(t => t.id === id);
        return item?.enabled ?? false;
    }

    function setToggleOn(id: string, on: bool): void {
        const list = GlobalConfig.utilities.quickToggles;
        for (let i = 0; i < list.count; i++) {
            const item = list.at(i);
            if (item.id === id) {
                item.enabled = on;
                return;
            }
        }
        list.insert({
            id,
            enabled: on
        });
    }

    title: I18n.tr("Utilitaires")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: I18n.tr("Général")
        }

        ToggleRow {
            first: true
            last: true
            text: I18n.tr("Activé")
            subtext: I18n.tr("Afficher le panneau des utilitaires")
            checked: Config.utilities.enabled
            onToggled: GlobalConfig.utilities.enabled = checked
        }

        // Cards
        SectionHeader {
            text: I18n.tr("Cartes")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Rester éveillé")
            subtext: I18n.tr("Afficher la carte de maintien éveillé")
            checked: Config.utilities.cards.keepAwake
            onToggled: GlobalConfig.utilities.cards.keepAwake = checked
        }

        ToggleRow {
            text: I18n.tr("Enregistreur d'écran")
            subtext: I18n.tr("Afficher la carte de l'enregistreur d'écran")
            checked: Config.utilities.cards.recorder
            onToggled: GlobalConfig.utilities.cards.recorder = checked
        }

        ToggleRow {
            last: true
            text: I18n.tr("Raccourcis rapides")
            subtext: I18n.tr("Afficher la carte des raccourcis rapides")
            checked: Config.utilities.cards.quickToggles
            onToggled: GlobalConfig.utilities.cards.quickToggles = checked
        }

        // Quick toggles
        SectionHeader {
            text: I18n.tr("Raccourcis rapides")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Wi-Fi")
            subtext: I18n.tr("Activer/Désactiver le Wi-Fi")
            disabled: !Config.utilities.cards.quickToggles
            checked: root.isToggleOn("wifi")
            onToggled: root.setToggleOn("wifi", checked)
        }

        ToggleRow {
            text: I18n.tr("Bluetooth")
            subtext: I18n.tr("Activer/Désactiver le Bluetooth")
            disabled: !Config.utilities.cards.quickToggles
            checked: root.isToggleOn("bluetooth")
            onToggled: root.setToggleOn("bluetooth", checked)
        }

        ToggleRow {
            text: I18n.tr("Microphone")
            subtext: I18n.tr("Couper ou activer le microphone")
            disabled: !Config.utilities.cards.quickToggles
            checked: root.isToggleOn("mic")
            onToggled: root.setToggleOn("mic", checked)
        }

        ToggleRow {
            text: I18n.tr("Paramètres")
            subtext: I18n.tr("Ouvrir la fenêtre des paramètres")
            disabled: !Config.utilities.cards.quickToggles
            checked: root.isToggleOn("settings")
            onToggled: root.setToggleOn("settings", checked)
        }

        ToggleRow {
            text: I18n.tr("Mode jeu")
            subtext: I18n.tr("Activer/Désactiver le mode jeu")
            disabled: !Config.utilities.cards.quickToggles
            checked: root.isToggleOn("gameMode")
            onToggled: root.setToggleOn("gameMode", checked)
        }

        ToggleRow {
            text: I18n.tr("Ne pas déranger")
            subtext: I18n.tr("Mettre les notifications en sourdine")
            disabled: !Config.utilities.cards.quickToggles
            checked: root.isToggleOn("dnd")
            onToggled: root.setToggleOn("dnd", checked)
        }

        ToggleRow {
            last: true
            text: I18n.tr("VPN")
            subtext: I18n.tr("Connecter ou déconnecter le VPN")
            disabled: !Config.utilities.cards.quickToggles
            checked: root.isToggleOn("vpn")
            onToggled: root.setToggleOn("vpn", checked)
        }
    }
}

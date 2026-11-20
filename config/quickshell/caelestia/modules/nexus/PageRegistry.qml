pragma Singleton

import QtQuick
import qs.services

QtObject {
    id: root

    readonly property list<var> pages: [
        // Appearance
        {
            label: I18n.tr("Fond d'écran et style"),
            icon: "palette",
            description: I18n.tr("Fond d'écran, polices, couleurs"),
            category: "appearance"
        },

        // Connectivity
        // TODO
        // {
        //     label: qsTr("Affichage"),
        //     icon: "monitor",
        //     description: qsTr("Configuration de sortie"),
        //     category: "connectivity"
        // },
        {
            label: I18n.tr("Réseau"),
            icon: "wifi",
            description: I18n.tr("Wi-Fi, Ethernet, VPN"),
            category: "connectivity"
        },
        {
            label: I18n.tr("Appareils connectés"),
            icon: "devices_other",
            description: I18n.tr("Bluetooth, appairage"),
            category: "connectivity",
            noFill: true
        },
        {
            label: I18n.tr("Audio"),
            icon: "volume_up",
            description: I18n.tr("Volumes des applications, périphériques audio"),
            category: "connectivity"
        },

        // System
        {
            label: I18n.tr("Alimentation"),
            icon: "settings_power",
            description: I18n.tr("Capot, veille"),
            category: "system"
        },
        {
            label: I18n.tr("Mises à jour"),
            icon: "update",
            description: I18n.tr("Mises à jour système"),
            category: "system"
        },
        {
            label: I18n.tr("Extensions"),
            icon: "extension",
            description: I18n.tr("Gérer les extensions"),
            category: "system"
        },

        // Shell
        {
            label: I18n.tr("Panneaux"),
            icon: "dock_to_bottom",
            description: I18n.tr("Tableau de bord, barre des tâches, lanceur, volet latéral"),
            category: "shell"
        },
        {
            label: I18n.tr("Applications"),
            icon: "apps",
            description: I18n.tr("Applications par défaut, favoris, masquées"),
            category: "shell"
        },
        {
            label: I18n.tr("Services"),
            icon: "build",
            description: I18n.tr("Intervalles d'actualisation, fournisseur des paroles"),
            category: "shell"
        },
        {
            label: I18n.tr("Langue et région"),
            icon: "globe",
            description: I18n.tr("Langue de l'interface, ville météo, unités d'affichage"),
            category: "shell"
        },

        {
            label: I18n.tr("Façon macOS"),
            icon: "auto_awesome",
            description: I18n.tr("Dynamic Island, Centre de contrôle, Dock"),
            category: "shell"
        },

        // About
        {
            label: I18n.tr("À propos"),
            icon: "info",
            description: I18n.tr("Informations système, crédits"),
            category: "about"
        },
    ]
}

pragma Singleton

import QtQuick

QtObject {
    id: root

    readonly property list<var> pages: [
        // Appearance
        {
            label: qsTr("Fond d'écran et style"),
            icon: "palette",
            description: qsTr("Fond d'écran, polices, couleurs"),
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
            label: qsTr("Réseau"),
            icon: "wifi",
            description: qsTr("Wi-Fi, Ethernet, VPN"),
            category: "connectivity"
        },
        {
            label: qsTr("Appareils connectés"),
            icon: "devices_other",
            description: qsTr("Bluetooth, appairage"),
            category: "connectivity",
            noFill: true
        },
        {
            label: qsTr("Audio"),
            icon: "volume_up",
            description: qsTr("Volumes des applications, périphériques audio"),
            category: "connectivity"
        },

        // System
        {
            label: qsTr("Alimentation"),
            icon: "settings_power",
            description: qsTr("Capot, veille"),
            category: "system"
        },
        {
            label: qsTr("Mises à jour"),
            icon: "update",
            description: qsTr("Mises à jour système"),
            category: "system"
        },
        {
            label: qsTr("Extensions"),
            icon: "extension",
            description: qsTr("Gérer les extensions"),
            category: "system"
        },

        // Shell
        {
            label: qsTr("Panneaux"),
            icon: "dock_to_bottom",
            description: qsTr("Tableau de bord, barre des tâches, lanceur, volet latéral"),
            category: "shell"
        },
        {
            label: qsTr("Applications"),
            icon: "apps",
            description: qsTr("Applications par défaut, favoris, masquées"),
            category: "shell"
        },
        {
            label: qsTr("Services"),
            icon: "build",
            description: qsTr("Intervalles d'actualisation, fournisseur des paroles"),
            category: "shell"
        },
        {
            label: qsTr("Langue et région"),
            icon: "globe",
            description: qsTr("Langue de l'interface, ville météo, unités d'affichage"),
            category: "shell"
        },

        {
            label: qsTr("Façon macOS"),
            icon: "auto_awesome",
            description: qsTr("Dynamic Island, Centre de contrôle, Dock"),
            category: "shell"
        },

        // About
        {
            label: qsTr("À propos"),
            icon: "info",
            description: qsTr("Informations système, crédits"),
            category: "about"
        },
    ]
}

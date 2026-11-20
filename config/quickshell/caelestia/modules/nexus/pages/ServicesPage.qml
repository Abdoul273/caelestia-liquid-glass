import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Lyrics backends, ordered to match LyricsBackend::Backend (Auto, Local, LRCLIB, NetEase)
    readonly property list<MenuItem> lyricsItems: [
        MenuItem {
            text: I18n.tr("Auto")
        },
        MenuItem {
            text: "Local"
        },
        MenuItem {
            text: "LRCLIB"
        },
        MenuItem {
            text: "NetEase"
        }
    ]

    // GPU options + the config string each maps to (see Gpu::parseType)
    readonly property list<MenuItem> gpuItems: [
        MenuItem {
            text: I18n.tr("Auto")
        },
        MenuItem {
            text: "NVIDIA"
        },
        MenuItem {
            text: I18n.tr("Générique")
        },
        MenuItem {
            text: I18n.tr("Aucun")
        }
    ]
    readonly property list<string> gpuValues: ["", "NVIDIA", "GENERIC", "None"]

    function gpuKeyToIndex(key: string): int {
        const u = (key ?? "").trim().toUpperCase();
        if (u === "")
            return 0; // Auto
        if (u === "NVIDIA")
            return 1;
        if (u === "GENERIC")
            return 2;
        return 3; // None
    }

    title: I18n.tr("Services")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Detected running players, used as default-player options
        Variants {
            id: playerVariants

            model: [...new Set(Players.list.map(p => Players.getIdentity(p)).filter(id => id))]

            MenuItem {
                required property string modelData

                text: modelData
                icon: modelData === GlobalConfig.services.defaultPlayer ? "check" : ""
                activeIcon: "music_note"
            }
        }

        // Notifications
        SectionHeader {
            first: true
            text: I18n.tr("Notifications")
        }

        NavRow {
            first: true
            last: true
            icon: "notifications"
            text: I18n.tr("Notifications")
            subtext: I18n.tr("Notifications, toasts, délais")
            onClicked: root.nState.openSubPage(1)
        }

        // Polling
        SectionHeader {
            text: I18n.tr("Actualisation")
        }

        StepperRow {
            first: true
            label: I18n.tr("Actualisation média")
            subtext: I18n.tr("Fréquence de suivi de lecture (ms)")
            value: GlobalConfig.dashboard.mediaUpdateInterval
            from: 100
            to: 2000
            stepSize: 50
            onMoved: v => GlobalConfig.dashboard.mediaUpdateInterval = v
        }

        StepperRow {
            label: I18n.tr("Actualisation des statistiques système")
            subtext: I18n.tr("Intervalle d'actualisation CPU, mémoire et GPU (secondes)")
            value: GlobalConfig.dashboard.resourceUpdateInterval / 1000
            from: 0.5
            to: 10
            stepSize: 0.5
            onMoved: v => GlobalConfig.dashboard.resourceUpdateInterval = Math.round(v * 1000)
        }

        StepperRow {
            last: true
            label: I18n.tr("Recherche Wi-Fi")
            subtext: I18n.tr("Fréquence de détection des réseaux (secondes)")
            value: GlobalConfig.nexus.networkRescanInterval / 1000
            from: 5
            to: 120
            stepSize: 5
            onMoved: v => GlobalConfig.nexus.networkRescanInterval = Math.round(v * 1000)
        }

        // Media & lyrics
        SectionHeader {
            text: I18n.tr("Médias et paroles")
        }

        SelectRow {
            first: true
            label: I18n.tr("Fournisseur des paroles")
            subtext: I18n.tr("Source utilisée pour récupérer les paroles synchronisées")
            menuItems: root.lyricsItems
            active: root.lyricsItems[Lyrics.preferredBackend] ?? root.lyricsItems[0]
            onSelected: item => Lyrics.preferredBackend = root.lyricsItems.indexOf(item)
        }

        SelectRow {
            last: true
            label: I18n.tr("Lecteur par défaut")
            subtext: I18n.tr("Lecteur multimédia par défaut lorsque plusieurs sont actifs")
            menuItems: playerVariants.instances
            active: menuItems.find(i => i.text === GlobalConfig.services.defaultPlayer) ?? null
            fallbackIcon: "music_note"
            fallbackText: GlobalConfig.services.defaultPlayer || I18n.tr("Auto")
            onSelected: item => GlobalConfig.services.defaultPlayer = item.text
        }

        // Input increments
        SectionHeader {
            text: I18n.tr("Incréments de saisie")
        }

        StepperRow {
            first: true
            label: I18n.tr("Pas de volume")
            subtext: I18n.tr("Variation de volume par défilement (%)")
            value: Math.round(GlobalConfig.services.audioIncrement * 100)
            from: 1
            to: 50
            stepSize: 1
            onMoved: v => GlobalConfig.services.audioIncrement = v / 100
        }

        StepperRow {
            label: I18n.tr("Pas de luminosité")
            subtext: I18n.tr("Variation de luminosité par défilement (%)")
            value: Math.round(GlobalConfig.services.brightnessIncrement * 100)
            from: 1
            to: 50
            stepSize: 1
            onMoved: v => GlobalConfig.services.brightnessIncrement = v / 100
        }

        StepperRow {
            last: true
            label: I18n.tr("Volume maximal")
            subtext: I18n.tr("Limite maximale du volume de sortie (%)")
            value: Math.round(GlobalConfig.services.maxVolume * 100)
            from: 50
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.services.maxVolume = v / 100
        }

        // Service tuning
        SectionHeader {
            text: I18n.tr("Ajustement des services")
        }

        StepperRow {
            first: true
            label: I18n.tr("Barres du visualiseur")
            subtext: I18n.tr("Nombre de barres pour les visualiseurs")
            value: GlobalConfig.services.visualiserBars
            from: 10
            to: 120
            stepSize: 2
            onMoved: v => GlobalConfig.services.visualiserBars = v
        }

        ToggleRow {
            text: I18n.tr("Schéma de couleurs dynamique")
            subtext: I18n.tr("Adapter le thème et la nuance au fond d'écran")
            checked: GlobalConfig.services.smartScheme
            onToggled: GlobalConfig.services.smartScheme = checked
        }

        SelectRow {
            last: true
            label: I18n.tr("GPU")
            subtext: Gpu.name ? I18n.tr("Surveillance : %1").arg(Gpu.name) : I18n.tr("Forcer le type de GPU")
            menuOnTop: true
            menuItems: root.gpuItems
            active: root.gpuItems[root.gpuKeyToIndex(GlobalConfig.services.gpuType)]
            onSelected: item => GlobalConfig.services.gpuType = root.gpuValues[root.gpuItems.indexOf(item)]
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Interface language (index 0 = Auto, 1 = French, 2 = English — matches I18n.mode)
    readonly property list<MenuItem> langItems: [
        MenuItem {
            text: I18n.tr("Automatique (système)")
        },
        MenuItem {
            text: "Français"
        },
        MenuItem {
            text: "English"
        }
    ]

    // Temperature units (index 0 = Celsius, 1 = Fahrenheit — matches Weather.formatTemp)
    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: "°C"
        },
        MenuItem {
            text: "°F"
        }
    ]

    // Clock format (index 0 = 24-hour, 1 = 12-hour — matches Time.useTwelveHourClock)
    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: I18n.tr("24 heures")
        },
        MenuItem {
            text: I18n.tr("12 heures")
        }
    ]

    title: I18n.tr("Langue et région")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Language
        SectionHeader {
            first: true
            text: I18n.tr("Langue")
        }

        // Language selector (stored in ~/.config/caelestia/lang.json, live switch)
        SelectRow {
            first: true
            last: true
            label: I18n.tr("Langue de l'interface")
            subtext: I18n.tr("Appliqué immédiatement · système : %1").arg(Qt.locale().name)
            menuItems: root.langItems
            active: root.langItems[I18n.mode === "fr" ? 1 : I18n.mode === "en" ? 2 : 0]
            onSelected: item => {
                const idx = root.langItems.indexOf(item);
                I18n.setLang(idx === 1 ? "fr" : idx === 2 ? "en" : "auto");
            }
        }

        // Weather
        SectionHeader {
            text: I18n.tr("Météo")
        }

        // Placeholder until the map-based location picker lands
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: comingSoon.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: comingSoon

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.padding.extraSmall

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "map"
                    color: Colours.palette.m3outlineVariant
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Sélection de la ville disponible bientôt")
                    color: Colours.palette.m3outlineVariant
                    font: Tokens.font.title.small
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: I18n.tr("Choisissez votre ville météo sur une carte dans une prochaine mise à jour")
                    color: Colours.palette.m3outlineVariant
                    font: Tokens.font.body.small
                }
            }
        }

        // Units
        SectionHeader {
            text: I18n.tr("Unités")
        }

        SelectRow {
            first: true
            label: I18n.tr("Température")
            subtext: I18n.tr("Unités de température météo")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheit ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheit = root.tempItems.indexOf(item) === 1
        }

        SelectRow {
            last: true
            label: I18n.tr("Températures du système")
            subtext: I18n.tr("Unités de température CPU et GPU")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheitPerformance ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheitPerformance = root.tempItems.indexOf(item) === 1
        }

        // Time & date
        SectionHeader {
            text: I18n.tr("Date et heure")
        }

        SelectRow {
            first: true
            last: true
            label: I18n.tr("Format de l'horloge")
            subtext: I18n.tr("Format de l'heure dans l'interface")
            menuItems: root.clockItems
            active: root.clockItems[GlobalConfig.services.useTwelveHourClock ? 1 : 0]
            onSelected: item => GlobalConfig.services.useTwelveHourClock = root.clockItems.indexOf(item) === 1
        }
    }
}

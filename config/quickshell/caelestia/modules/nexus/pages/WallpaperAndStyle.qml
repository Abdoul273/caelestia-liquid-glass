pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Liquid glass : clés de glass.json, dans le même ordre que les menus
    readonly property list<string> shellModes: ["classic", "ios", "off"]
    readonly property list<MenuItem> shellItems: [
        MenuItem {
            text: I18n.tr("Classique")
            icon: "blur_on"
        },
        MenuItem {
            text: I18n.tr("Verre plein")
            icon: "water_drop"
        },
        MenuItem {
            text: I18n.tr("Désactivé")
            icon: "block"
        }
    ]
    readonly property list<string> gtkModes: ["nautilus", "complet", "off"]
    readonly property list<MenuItem> gtkItems: [
        MenuItem {
            text: I18n.tr("Nautilus")
            icon: "folder"
        },
        MenuItem {
            text: I18n.tr("Toutes")
            icon: "apps"
        },
        MenuItem {
            text: I18n.tr("Aucune")
            icon: "block"
        }
    ]
    readonly property list<string> perfModes: ["ultra", "eco", "auto"]
    readonly property list<MenuItem> perfItems: [
        MenuItem {
            text: I18n.tr("Puissance maximale")
            icon: "bolt"
        },
        MenuItem {
            text: I18n.tr("Fluide & autonomie")
            icon: "eco"
        },
        MenuItem {
            text: I18n.tr("Automatique")
            icon: "auto_awesome"
        }
    ]

    title: I18n.tr("Fond d'écran et style")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Glass.tile(Colours.tPalette.m3surfaceContainer)
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: I18n.tr("Fond d'écran désactivé")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: Wallpapers.current
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: I18n.tr("Fonds d'écran")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: I18n.tr("Couleurs")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            first: true
            text: I18n.tr("Afficher le fond d'écran")
            checked: Config.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: I18n.tr("Transparence")
            subtext: I18n.tr("Base %1, calques %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            last: true
            text: I18n.tr("Thème sombre")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        SectionHeader {
            text: I18n.tr("Liquid glass")
        }

        SelectRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            first: true
            label: I18n.tr("Style du verre")
            subtext: ({
                    classic: I18n.tr("Verre teinté et flouté : le bon compromis"),
                    ios: I18n.tr("Verre clair façon iOS 26 : on voit le fond à travers"),
                    off: I18n.tr("Panneaux opaques de Caelestia (les notifications restent en verre)")
                })[Glass.shellMode] ?? ""
            menuItems: root.shellItems
            active: root.shellItems[Math.max(0, root.shellModes.indexOf(Glass.shellMode))]
            onSelected: item => Glass.set("shell", root.shellModes[root.shellItems.indexOf(item)])
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            icon: "opacity"
            label: I18n.tr("Intensité du verre (shell et applis GTK)")
            valueLabel: value < 0.34 ? I18n.tr("Très transparent") : value < 0.46 ? I18n.tr("Transparent") : value <= 0.54 ? I18n.tr("Équilibré") : value < 0.75 ? I18n.tr("Dense") : I18n.tr("Très dense")
            value: Glass.density
            onMoved: v => Glass.set("density", Math.round(v * 100) / 100)
        }

        SelectRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            label: I18n.tr("Profil de performance")
            subtext: ({
                    ultra: I18n.tr("PC puissant : shader haute précision, panneaux préchargés en RAM, aucune réduction"),
                    eco: I18n.tr("Même rendu Liquid Glass, shader GPU ×2 plus léger et panneaux chargés à la demande"),
                    auto: I18n.tr("Pleine précision sur secteur, optimisé automatiquement sur batterie")
                })[Glass.perfMode] ?? ""
            menuItems: root.perfItems
            active: root.perfItems[Math.max(0, root.perfModes.indexOf(Glass.perfMode))]
            onSelected: item => Glass.set("performance", root.perfModes[root.perfItems.indexOf(item)])
        }

        SelectRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            last: true
            label: I18n.tr("Applis GTK en verre")
            subtext: ({
                    nautilus: I18n.tr("Seulement Nautilus, les autres applis restent opaques"),
                    complet: I18n.tr("Nautilus, Calculatrice, Éditeur de texte, Loupe, Thunar…"),
                    off: I18n.tr("Aucune : style GTK normal")
                })[Glass.gtkMode] ?? ""
            menuItems: root.gtkItems
            active: root.gtkItems[Math.max(0, root.gtkModes.indexOf(Glass.gtkMode))]
            onSelected: item => Glass.set("gtk", root.gtkModes[root.gtkItems.indexOf(item)])
        }
    }
}

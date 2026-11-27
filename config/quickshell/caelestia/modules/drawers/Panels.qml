import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.launcher as Launcher
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.session as Session
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities.toasts as Toasts
import qs.modules.island as IslandModule
import qs.modules.controlcenter as CC
import qs.modules.dock as DockModule
import qs.modules.spotlight as SpotlightModule

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness

    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias launcher: launcher
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar
    readonly property alias island: island
    readonly property alias controlCenter: controlCenter
    readonly property alias dock: dock
    readonly property alias spotlight: spotlight
    readonly property alias calculator: calculator
    readonly property alias dictation: dictation
    readonly property alias writing: writing
    readonly property alias translate: translate
    readonly property alias siri: siri
    readonly property alias display: display
    readonly property alias annotate: annotate
    readonly property alias settings: settings
    readonly property alias clock: clock
    readonly property alias keyhelp: keyhelp
    readonly property alias emoji: emoji
    readonly property alias clipboard: clipboard
    readonly property alias earbuds: earbuds
    readonly property alias agentos: agentos

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: bar.implicitWidth

    // Hôte plein cadre pour les Loaders des panneaux paresseux (conserve exact x/y dans Panels)
    Item {
        id: lazyHost

        anchors.fill: parent
        z: 10
    }

    Item {
        id: osdWrapper

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sessionWrapper.anchors.rightMargin + session.width * (1 - session.offsetScale)
        clip: sidebar.visible || session.visible

        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight

        Osd.Wrapper {
            id: osd

            screen: root.screen
            screenState: root.screenState
            sidebarOrSessionVisible: sidebar.visible || session.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Notifications.Wrapper {
        id: notifications

        screenState: root.screenState
        sidebarPanel: sidebar
        osdPanel: osdWrapper
        sessionPanel: sessionWrapper
        utilitiesPanel: utilities

        anchors.top: parent.top
        anchors.right: parent.right
    }

    Item {
        id: sessionWrapper

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)
        clip: sidebar.visible

        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight

        Session.Wrapper {
            id: session

            screenState: root.screenState
            sidebarVisible: sidebar.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Launcher.Wrapper {
        id: launcher

        screen: root.screen
        screenState: root.screenState
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    Dashboard.Wrapper {
        id: dashboard

        screenState: root.screenState
        island: island
        screenTop: root.borderThickness

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    // Dynamic Island : collée au haut de l'écran, toujours active
    IslandModule.Island {
        id: island

        screen: root.screen
        screenState: root.screenState

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -root.borderThickness
    }

    // ── Panneaux modaux / secondaires : à la demande en profil Fluide/Auto, préchargés en Ultra ──

    LazyPanel {
        id: controlCenter

        host: lazyHost
        wantOpen: root.screenState.controlCenter
        sourceComponent: Component {
            Item {
                property alias panel: ccPanel

                CC.ControlCenter {
                    id: ccPanel

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.top: parent.top
                    anchors.topMargin: -root.borderThickness
                }
            }
        }
    }

    LazyPanel {
        id: spotlight

        host: lazyHost
        wantOpen: root.screenState.spotlight
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Spotlight {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: calculator

        host: lazyHost
        wantOpen: root.screenState.calculator
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Calculator {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: siri

        host: lazyHost
        wantOpen: root.screenState.siri
        unloadDelayMs: 600000
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Siri {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: writing

        host: lazyHost
        wantOpen: root.screenState.writing
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.WritingTools {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: translate

        host: lazyHost
        wantOpen: root.screenState.translate
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Translate {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: dictation

        host: lazyHost
        wantOpen: root.screenState.dictation
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Dictation {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: display

        host: lazyHost
        wantOpen: root.screenState.display
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Display {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: clipboard

        host: lazyHost
        wantOpen: root.screenState.clipboard
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Clipboard {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.16)
                }
            }
        }
    }

    LazyPanel {
        id: emoji

        host: lazyHost
        wantOpen: root.screenState.emoji
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Emoji {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.16)
                }
            }
        }
    }

    LazyPanel {
        id: keyhelp

        host: lazyHost
        wantOpen: root.screenState.keyhelp
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.KeyHelp {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                }
            }
        }
    }

    LazyPanel {
        id: clock

        host: lazyHost
        wantOpen: root.screenState.clock
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Clock {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.1)
                }
            }
        }
    }

    LazyPanel {
        id: settings

        host: lazyHost
        wantOpen: root.screenState.settings
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Settings {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round((parent.height - height) / 2)
                }
            }
        }
    }

    LazyPanel {
        id: annotate

        host: lazyHost
        wantOpen: root.screenState.annotate
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Annotate {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, Math.round((parent.height - height) / 2))
                }
            }
        }
    }

    LazyPanel {
        id: earbuds

        host: lazyHost
        wantOpen: root.screenState.earbuds
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.Earbuds {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.12)
                }
            }
        }
    }

    LazyPanel {
        id: agentos

        host: lazyHost
        wantOpen: root.screenState.agentos
        sourceComponent: Component {
            Item {
                property alias panel: p

                SpotlightModule.AgentOS {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    island: root.island

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.11)
                }
            }
        }
    }

    // Dock : chargé uniquement si Island.dock est activé
    LazyPanel {
        id: dock

        host: lazyHost
        wantOpen: Island.dock
        keepLoaded: false
        unloadDelayMs: 5000
        sourceComponent: Component {
            Item {
                property alias panel: p

                DockModule.Dock {
                    id: p

                    screen: root.screen
                    screenState: root.screenState
                    fullscreen: dock.fullscreen

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -root.borderThickness
                }
            }
        }
    }

    BarPopouts.ClipWrapper {
        id: popoutsWrapper

        screen: root.screen
        borderThickness: root.borderThickness
    }

    Utilities.Wrapper {
        id: utilities

        screenState: root.screenState
        sidebar: sidebar
        popouts: popoutsWrapper.content

        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }

    Toasts.Toasts {
        id: toasts

        // Avec l'île, les bulles s'affichent en haut dans l'île
        visible: !Island.toasts

        anchors.bottom: sidebar.visible ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.margins: Tokens.padding.medium
    }

    Sidebar.Wrapper {
        id: sidebar

        screenState: root.screenState

        anchors.top: notifications.bottom
        anchors.bottom: utilities.top
        anchors.right: parent.right
        anchors.topMargin: -notifications.anchors.topMargin
    }
}

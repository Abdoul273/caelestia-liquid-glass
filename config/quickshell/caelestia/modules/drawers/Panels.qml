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

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: bar.implicitWidth

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

    // Dynamic Island : collée au haut de l'écran, au-dessus de la marge du cadre
    IslandModule.Island {
        id: island

        screen: root.screen
        screenState: root.screenState

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -root.borderThickness
    }

    // Centre de contrôle : descend du haut de l'écran, à droite
    CC.ControlCenter {
        id: controlCenter

        screen: root.screen
        screenState: root.screenState

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.top: parent.top
        anchors.topMargin: -root.borderThickness
        island: island
    }

    // Spotlight : une goutte de verre tombe de l'île jusqu'au centre de l'écran
    SpotlightModule.Spotlight {
        id: spotlight

        screen: root.screen
        screenState: root.screenState
        island: island

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.2)
    }

    // Calculatrice : même goutte de verre, sous l'île
    SpotlightModule.Calculator {
        id: calculator

        screen: root.screen
        screenState: root.screenState
        island: island

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.11)
    }

    // Dock : sort du bas de l'écran au survol
    DockModule.Dock {
        id: dock

        screen: root.screen
        screenState: root.screenState

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -root.borderThickness
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

pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState
    readonly property Props props: Props {}

    // Avec le Centre de contrôle, les notifications passent par l'île (clic sur l'heure / Super + N)
    readonly property bool shouldBeActive: !Island.controlCenter && screenState.sidebar && Config.sidebar.enabled
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5) * offsetScale
    implicitWidth: Tokens.sizes.sidebar.width
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.large
        anchors.margins: CUtils.clamp(anchors.leftMargin - Config.border.thickness, 0, anchors.leftMargin)
        anchors.bottomMargin: 0

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.margins
            props: root.props
            screenState: root.screenState
        }
    }
}

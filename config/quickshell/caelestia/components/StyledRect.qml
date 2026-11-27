import QtQuick
import qs.components.effects
import qs.services

Rectangle {
    id: root

    color: "transparent"

    // Carte en verre (Glass.tile) : lentille shader sur secteur, liseré léger 0-shader sur batterie
    Loader {
        anchors.fill: parent
        z: -1
        active: Glass.panels && root.width > 24 && root.height > 24 && Glass.isTile(root.color)
        asynchronous: true
        sourceComponent: Glass.tileLens ? tileLensComp : tileBorderComp
    }

    Component {
        id: tileLensComp

        GlassControl {
            tintColour: Qt.alpha(root.color, 0)
            radius: root.radius
            bevel: Math.min(16, Math.min(root.width, root.height) * 0.3)
        }
    }

    Component {
        id: tileBorderComp

        Rectangle {
            color: "transparent"
            radius: root.radius
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3onSurface, Colours.light ? 0.14 : 0.10)
        }
    }

    Behavior on color {
        CAnim {}
    }
}

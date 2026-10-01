import QtQuick
import qs.components.effects
import qs.services

Rectangle {
    id: root

    color: "transparent"

    // Carte en verre (Glass.tile) : biseau, reflets et liseré sous le contenu
    Loader {
        anchors.fill: parent
        z: -1
        active: Glass.tileLens && root.width > 24 && root.height > 24 && Glass.isTile(root.color)
        asynchronous: true

        sourceComponent: GlassControl {
            tintColour: Qt.alpha(root.color, 0)
            radius: root.radius
            bevel: Math.min(16, Math.min(root.width, root.height) * 0.3)
        }
    }

    Behavior on color {
        CAnim {}
    }
}

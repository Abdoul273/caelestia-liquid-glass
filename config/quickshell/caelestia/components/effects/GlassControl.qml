import QtQuick
import Quickshell
import qs.components
import qs.services

// Fond en verre bombé pour un contrôle (voir assets/shaders/glasscontrol.frag).
// tintColour = couleur du verre (alpha compris) ; lens = 0 → 1 pendant l'appui.
ShaderEffect {
    id: root

    property color tintColour: Qt.alpha(Colours.palette.m3onSurface, 0.1)
    property real radius: height / 2
    property bool pressed
    property bool hovered

    readonly property vector2d size: Qt.vector2d(width, height)
    readonly property color tint: tintColour
    readonly property real light: Colours.light ? 1.2 : 1
    property real lens: pressed ? 1 : 0
    property real hover: hovered ? 1 : 0

    blending: true
    fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("assets/shaders/glasscontrol.frag.qsb"))

    Behavior on lens {
        Anim {
            type: Anim.FastSpatial
        }
    }

    Behavior on hover {
        Anim {
            type: Anim.FastEffects
        }
    }

    Behavior on tintColour {
        CAnim {}
    }
}

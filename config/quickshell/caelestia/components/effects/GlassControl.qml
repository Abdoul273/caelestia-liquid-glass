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
    // Position du pointeur (0..1) pour la lumière qui le suit ; x < 0 = pas de pointeur
    property point pointer: Qt.point(-1, -1)
    // Largeur du biseau (px) : 0 = automatique ; ~14 pour les grandes cartes (sinon effet coussin)
    property real bevel: 0

    readonly property vector2d size: Qt.vector2d(width, height)
    readonly property color tint: tintColour
    readonly property real light: Colours.light ? 1.2 : 1
    property real lens: pressed ? 1 : 0
    property real hover: hovered ? 1 : 0
    readonly property point mouse: pointer

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

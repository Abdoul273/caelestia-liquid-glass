import QtQuick
import Quickshell

// Surface « liquid glass » : le flou vient de Hyprland, le shader dessine
// la teinte, le biseau lumineux et le reflet qui suit le pointeur.
ShaderEffect {
    id: root

    property real radius
    property color tintColour
    property real tintOpacity: 0.34
    property point pointer: Qt.point(0.5, 0)
    property bool hovered

    readonly property vector2d size: Qt.vector2d(width, height)
    readonly property vector3d tint: Qt.vector3d(tintColour.r, tintColour.g, tintColour.b)
    property real tintAlpha: tintOpacity
    readonly property point mouse: pointer
    property real hover: hovered ? 1 : 0
    property real light: 1

    fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("assets/shaders/liquidglass.frag.qsb"))

    Behavior on hover {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }

    Behavior on tintAlpha {
        NumberAnimation {
            duration: 250
        }
    }
}

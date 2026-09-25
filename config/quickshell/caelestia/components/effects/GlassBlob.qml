import QtQuick
import Quickshell
import qs.services

// Effet de calque « liquid glass » pour une forme fluide (blob) : à utiliser
// comme layer.effect. La forme doit être dessinée opaque ; la teinte et
// l'éclairage des bords sont appliqués ici.
ShaderEffect {
    property color tintColour: Colours.palette.m3surface
    property real tintOpacity: Colours.light ? 0.56 : 0.46
    property real shadow: 0.17
    property Item pointerArea
    property bool pointerActive

    readonly property vector2d texel: Qt.vector2d(1 / Math.max(1, width), 1 / Math.max(1, height))
    readonly property vector3d tint: Qt.vector3d(tintColour.r, tintColour.g, tintColour.b)
    readonly property real tintAlpha: tintOpacity
    readonly property real light: Colours.light ? 1.2 : 1
    readonly property real shadowStrength: shadow
    property point mouse: Qt.point(0.5, 0)
    property real hover: pointerActive ? 1 : 0

    fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("assets/shaders/glassblob.frag.qsb"))

    Behavior on hover {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }
}

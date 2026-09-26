import QtQuick
import Quickshell
import qs.services

// Effet de calque « liquid glass » pour une forme fluide (blob) : à utiliser
// comme layer.effect. La forme doit être dessinée opaque ; la teinte et
// l'éclairage des bords sont appliqués ici.
ShaderEffect {
    property color tintColour: Colours.palette.m3surface
    property real tintOpacity: Glass.ios ? (Colours.light ? 0.3 : 0.24) : Colours.light ? 0.56 : 0.46
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

    // Style iOS sans réfraction ici (fenêtres flottantes : le fond d'écran n'est pas derrière)
    readonly property vector4d zone: Qt.vector4d(0, 0, 0, 0)
    readonly property real refraction: 0
    readonly property var wallpaper: dummyTex

    fragmentShader: Qt.resolvedUrl(Quickshell.shellPath(Glass.ios ? "assets/shaders/liquidios.frag.qsb" : "assets/shaders/glassblob.frag.qsb"))

    ShaderEffectSource {
        id: dummyTex

        width: 1
        height: 1
        visible: false
        sourceItem: Item {
            width: 1
            height: 1
        }
    }

    Behavior on hover {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }
}

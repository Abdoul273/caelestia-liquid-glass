pragma Singleton

import QtQuick
import Quickshell

// Animations façon macOS : ressorts courts et nets, léger rebond sur les déplacements,
// fondus rapides. Mettre `enabled` à false pour retrouver les animations Caelestia d'origine.
Singleton {
    id: root

    readonly property bool enabled: true

    // Durées (ms) : plus courtes que Material, comme sur macOS
    readonly property int fastSpatial: 260
    readonly property int defaultSpatial: 420
    readonly property int slowSpatial: 560
    readonly property int fastEffects: 140
    readonly property int defaultEffects: 200
    readonly property int slowEffects: 300
    readonly property var standardDurations: [180, 260, 360, 480]

    // Courbes (récupérées depuis des animations témoins pour obtenir de vrais QEasingCurve)
    readonly property var spatial: springAnim.easing
    readonly property var spatialSoft: springSoftAnim.easing
    readonly property var effects: effectsAnim.easing
    readonly property var emphasized: emphasizedAnim.easing
    readonly property var standard: standardAnim.easing

    // Ressort réactif avec un rebond à peine perceptible (réponse ~0,4 s, amortissement ~0,85)
    NumberAnimation {
        id: springAnim

        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0.95, 0.3, 1.035, 1, 1]
    }

    // Ressort sans rebond pour les grands panneaux
    NumberAnimation {
        id: springSoftAnim

        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
    }

    // Fondus : départ vif, fin douce
    NumberAnimation {
        id: effectsAnim

        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1]
    }

    NumberAnimation {
        id: emphasizedAnim

        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }

    NumberAnimation {
        id: standardAnim

        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }
}

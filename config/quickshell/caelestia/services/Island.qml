pragma Singleton

import QtQuick
import Quickshell

// Réglages de la Dynamic Island (modules/island/Island.qml), intégrée au verre du cadre.
Singleton {
    id: root

    // false = plus d'île du tout (et le haut du cadre revient)
    readonly property bool enabled: true
    // Les notifications passent par l'île au lieu des bulles en haut à droite
    readonly property bool notifications: enabled
    // Bord haut du cadre invisible : l'île sort directement du haut de l'écran
    readonly property bool hideTopBorder: enabled
    // Au repos l'île affiche l'heure (façon barre de menus macOS) et l'horloge de la barre disparaît
    readonly property bool clock: enabled

    // Bus des notifications à afficher (émis par services/Notifs.qml)
    signal notify(var notif)
}

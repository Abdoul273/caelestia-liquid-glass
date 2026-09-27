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

    // Les bulles de Caelestia (bas à droite) passent aussi par l'île
    readonly property bool toasts: enabled
    // Le changement de bureau s'affiche dans l'île (l'ancien indicateur du bas est retiré)
    readonly property bool workspaces: enabled

    // Super + A ouvre le Centre de contrôle (en haut à droite) et la barre de gauche disparaît
    readonly property bool controlCenter: enabled
    readonly property bool noBar: controlCenter

    // Étagère : fichiers déposés sur l'île, gardés jusqu'au redémarrage du shell
    property list<string> shelf: []

    function addToShelf(urls: var): void {
        const next = [...shelf];
        for (const u of urls) {
            const s = String(u);
            if (s.startsWith("file://") && !next.includes(s))
                next.push(s);
        }
        shelf = next.slice(-8);
    }

    function removeFromShelf(url: string): void {
        shelf = shelf.filter(u => u !== url);
    }

    // Enregistrement demandé par le Centre de contrôle : l'île fait le compte à rebours puis lance
    signal recordRequest(var args, int delay)

    // Bus des notifications à afficher (émis par services/Notifs.qml)
    signal notify(var notif)
}

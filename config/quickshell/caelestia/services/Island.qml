pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Réglages de la Dynamic Island (modules/island/Island.qml), intégrée au verre du cadre.
Singleton {
    id: root

    // Réglages modifiables en direct depuis Paramètres (Super + I) → « Façon macOS »,
    // enregistrés dans ~/.config/caelestia/island.json (modifiable à la main aussi).
    readonly property bool enabled: opts.enabled
    // Les notifications passent par l'île au lieu des bulles en haut à droite
    readonly property bool notifications: enabled && opts.notifications
    // Bord haut du cadre invisible : l'île sort directement du haut de l'écran
    readonly property bool hideTopBorder: enabled && opts.hideTopBorder
    // Au repos l'île affiche la date et l'heure (et l'horloge de la barre disparaît)
    readonly property bool clock: enabled && opts.clock
    // Batterie à côté de l'heure au repos
    readonly property bool battery: clock && opts.battery
    // Les bulles de Caelestia (bas à droite) passent aussi par l'île
    readonly property bool toasts: enabled && opts.toasts
    // Le changement de bureau s'affiche dans l'île (l'ancien indicateur du bas est retiré)
    readonly property bool workspaces: enabled && opts.workspaces
    // Paroles synchronisées sous le titre de la musique
    readonly property bool lyrics: enabled && opts.lyrics
    // Points orange / vert quand le micro / la caméra sont utilisés
    readonly property bool privacy: enabled && opts.privacy

    // Super + A ouvre le Centre de contrôle (en haut à droite) au lieu du tableau de bord
    readonly property bool controlCenter: opts.controlCenter
    // Barre de gauche retirée
    readonly property bool noBar: opts.hideBar
    // Dock qui se cache (bas de l'écran), sans réserver de place aux fenêtres
    readonly property bool dock: opts.dock

    function set(key: string, value: var): void {
        opts[key] = value;
        file.writeAdapter();
    }

    FileView {
        id: file

        path: `${Quickshell.env("HOME")}/.config/caelestia/island.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: opts

            property bool enabled: true
            property bool notifications: true
            property bool hideTopBorder: true
            property bool clock: true
            property bool battery: true
            property bool toasts: true
            property bool workspaces: true
            property bool lyrics: true
            property bool privacy: true
            property bool controlCenter: true
            property bool hideBar: true
            property bool dock: true
        }
    }

    // Centre de notifications dans l'île (clic sur l'île au repos ou Super + N)
    property bool notifCenter

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

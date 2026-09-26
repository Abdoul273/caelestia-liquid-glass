pragma Singleton

import QtQuick
import Quickshell

// Réglages du liquid glass de tout le shell : barre, cadre, sidebar, utilitaires, OSD, launcher,
// session, dashboard, menus de la barre et écran de verrouillage.
// Mettre `panels` à false pour revenir au style Caelestia d'origine.
// Les notifications restent en verre dans tous les cas.
Singleton {
    id: root

    readonly property bool panels: true
    // Boutons et interrupteurs façon macOS (reflet, liseré, curseur lentille). false = style d'origine.
    readonly property bool controls: panels

    // Fond des cartes à l'intérieur d'un panneau en verre : voile translucide au lieu d'un aplat
    function tile(original: color): color {
        if (!panels)
            return original;
        // Plus la couleur d'origine est « haute » (container high, highest…), plus le voile
        // est marqué : les états actifs et sélectionnés restent bien distincts.
        const depth = Math.abs(original.hslLightness - Colours.palette.m3surface.hslLightness);
        const alpha = Math.max(0.035, Math.min(0.16, 0.04 + depth * 0.9));
        return Qt.alpha(Colours.palette.m3onSurface, alpha);
    }
}

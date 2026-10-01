pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Réglages du liquid glass de tout le shell : barre, cadre, sidebar, utilitaires, OSD, launcher,
// session, dashboard, menus de la barre et écran de verrouillage.
// Réglable en direct dans Paramètres (Super + I) → Fond d'écran et style → Liquid glass,
// enregistré dans ~/.config/caelestia/glass.json (modifiable à la main aussi) :
//   shell : "classic" (verre teinté, le compromis) | "ios" (verre plein) | "off" (Caelestia d'origine)
//   gtk   : "nautilus" | "complet" | "off" (appliqué par caelestia-glass-gtk)
//   density : intensité du verre de 0 (très transparent) à 1 (presque opaque), 0.5 = réglage d'origine
// Les notifications restent en verre dans tous les cas.
Singleton {
    id: root

    readonly property bool panels: opts.shell !== "off"
    // Rendu du verre : "ios" = liquid glass façon iOS 26/27 (verre clair, réfraction, franges
    // de couleur, épaisseur) ; "classic" = le verre précédent (teinte + flou + liseré).
    readonly property string style: opts.shell === "ios" ? "ios" : "classic"
    readonly property string shellMode: opts.shell
    readonly property string gtkMode: opts.gtk
    readonly property bool ios: panels && style === "ios"
    // Verre plein façon iOS 26 / macOS 27 : tout l'intérieur des panneaux posés sur le bureau
    // montre le fond net à travers une lentille (et plus seulement les bords). false = flou d'avant.
    readonly property bool clear: ios
    // Le verre montre aussi le fond animé (2ᵉ lecture de la vidéo, sur secteur seulement :
    // environ 15 % d'un cœur de plus). false = le verre montre l'image fixe de la vidéo.
    readonly property bool clearVideo: clear
    // Boutons et interrupteurs façon macOS (reflet, liseré, curseur lentille). false = style d'origine.
    readonly property bool controls: panels
    // Contrôles en verre bombé (shader glasscontrol) au lieu des simples dégradés. false = version d'avant.
    readonly property bool lensControls: controls
    // Opacité du verre quand le fond contraste avec le panneau (page blanche derrière un panneau
    // sombre…) : le panneau garde sa couleur, comme sur macOS. Plus bas = plus transparent.
    readonly property real thickAlpha: strength(Colours.light ? 0.44 : 0.45)

    // Intensité du verre (curseur des Paramètres) : 0.5 garde les opacités d'origine
    readonly property real density: Math.max(0, Math.min(1, opts.density))

    // Opacité d'origine → opacité selon l'intensité choisie (même formule que caelestia-glass-gtk)
    function strength(base: real): real {
        if (density <= 0.5)
            return base * (0.35 + 1.3 * density);
        return base + (0.95 - base) * (density - 0.5) * 2;
    }

    // Chaque carte en verre (couleur venant de tile()) devient sa propre pièce de verre
    // bombée (biseau, reflets, liseré), comme les widgets d'iOS 27. false = simple voile.
    readonly property bool tileLens: lensControls

    function isTile(c: color): bool {
        if (!panels || c.a < 0.025 || c.a > 0.17)
            return false;
        const o = Colours.palette.m3onSurface;
        return Math.abs(c.r - o.r) + Math.abs(c.g - o.g) + Math.abs(c.b - o.b) < 0.03;
    }

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

    function set(key: string, value: var): void {
        if (opts[key] === value)
            return;
        opts[key] = value;
        file.writeAdapter();
        if (key === "gtk")
            Quickshell.execDetached(["caelestia-glass-gtk", value]);
        else if (key === "density")
            gtkTimer.restart();
    }

    // Le curseur bouge en continu : on ne régénère le style GTK qu'une fois relâché
    Timer {
        id: gtkTimer

        interval: 450
        onTriggered: Quickshell.execDetached(["caelestia-glass-gtk"])
    }

    FileView {
        id: file

        path: `${Quickshell.env("HOME")}/.config/caelestia/glass.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: opts

            property string shell: "classic"
            property string gtk: "nautilus"
            property real density: 0.5
        }
    }
}

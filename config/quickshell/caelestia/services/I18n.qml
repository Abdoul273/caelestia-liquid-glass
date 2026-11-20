pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "I18nEn.js" as En

// Gestion bilingue FR/EN du shell.
// Par défaut ("auto"), suit la langue du système (français si LANG=fr_*, anglais sinon).
// Réglable en direct dans Paramètres → Langue et région (~/.config/caelestia/lang.json)
// ou via la variable d'environnement CAELESTIA_LANG=en|fr.
Singleton {
    id: root

    readonly property string mode: opts.lang === "fr" || opts.lang === "en" ? opts.lang : "auto"
    readonly property string envLang: (Quickshell.env("CAELESTIA_LANG") || "").toLowerCase()
    readonly property string systemLang: {
        const l = (envLang || Qt.locale().name || "en").toLowerCase();
        return l.startsWith("fr") ? "fr" : "en";
    }
    readonly property string lang: mode === "auto" ? systemLang : mode
    readonly property bool isFr: lang === "fr"
    readonly property bool isEn: lang === "en"
    readonly property var locale: Qt.locale(isFr ? "fr_FR" : "en_US")

    function setLang(value: string): void {
        const next = value === "fr" || value === "en" ? value : "auto";
        if (opts.lang === next)
            return;
        opts.lang = next;
        file.writeAdapter();
    }

    // Traduit une chaîne française en anglais quand root.lang === "en".
    // En français, retourne la chaîne d'origine intacte.
    function tr(text: string): string {
        if (root.lang !== "en")
            return text;
        const translated = En.strings[text];
        return translated !== undefined ? translated : text;
    }

    // Variante avec pluriel ("%n fichier(s)")
    function trn(text: string, n: int): string {
        if (root.lang === "en") {
            const enPlural = En.plurals[text];
            if (enPlural !== undefined)
                return (n === 1 ? enPlural[0] : enPlural[1]).replace("%n", String(n));
        } else {
            const frPlural = En.frPlurals[text];
            if (frPlural !== undefined)
                return (n === 1 ? frPlural[0] : frPlural[1]).replace("%n", String(n));
        }
        return tr(text).replace("%n", String(n));
    }

    FileView {
        id: file

        path: `${Quickshell.env("HOME")}/.config/caelestia/lang.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: opts

            property string lang: "auto"
        }
    }
}

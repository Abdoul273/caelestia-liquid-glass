pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

// « Façon macOS » : tous les réglages de la Dynamic Island, du Centre de contrôle et du Dock.
// Chaque interrupteur agit tout de suite ; tout est enregistré dans ~/.config/caelestia/island.json.
PageBase {
    id: root

    title: I18n.tr("Façon macOS")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ── Dynamic Island ──
        SectionHeader {
            first: true
            text: I18n.tr("Dynamic Island")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Dynamic Island")
            subtext: I18n.tr("La pastille en haut de l'écran : musique, volume, captures, écouteurs, minuteurs…")
            checked: Island.enabled
            onToggled: Island.set("enabled", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: I18n.tr("Notifications dans l'île")
            subtext: I18n.tr("Sinon, les bulles de Caelestia en haut à droite")
            checked: Island.notifications
            onToggled: Island.set("notifications", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: I18n.tr("Messages du système dans l'île")
            subtext: I18n.tr("Ne pas déranger, batterie faible, thème… au lieu des bulles du coin")
            checked: Island.toasts
            onToggled: Island.set("toasts", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: I18n.tr("Changement de bureau")
            subtext: I18n.tr("« Bureau 2 » et les points dans l'île")
            checked: Island.workspaces
            onToggled: Island.set("workspaces", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: I18n.tr("Paroles en direct")
            subtext: I18n.tr("Sous le titre de la musique (cache d'Aura, .lrc, LRCLIB en ligne)")
            checked: Island.lyrics
            onToggled: Island.set("lyrics", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            last: true
            text: I18n.tr("Micro et caméra utilisés")
            subtext: I18n.tr("Point orange (micro) ou vert (caméra) quand une app les utilise")
            checked: Island.privacy
            onToggled: Island.set("privacy", checked)
        }

        // ── Au repos ──
        SectionHeader {
            text: I18n.tr("Au repos")
        }

        ToggleRow {
            first: true
            enabled: Island.enabled
            text: I18n.tr("Date et heure dans l'île")
            subtext: I18n.tr("Désactivé : l'île disparaît quand il ne se passe rien")
            checked: Island.clock
            onToggled: Island.set("clock", checked)
        }

        ToggleRow {
            enabled: Island.clock
            text: I18n.tr("Batterie à côté de l'heure")
            subtext: I18n.tr("Verte en charge, rouge sous 20 %")
            checked: Island.battery
            onToggled: Island.set("battery", checked)
        }

        ToggleRow {
            enabled: Island.clock
            text: I18n.tr("Météo dans l'île au repos")
            subtext: I18n.tr("Icône météo teintée et température en direct à côté de l'heure")
            checked: Island.weather
            onToggled: Island.set("weather", checked)
        }

        ToggleRow {
            last: true
            enabled: Island.enabled
            text: I18n.tr("Bord haut invisible")
            subtext: I18n.tr("L'île sort directement du haut de l'écran")
            checked: Island.hideTopBorder
            onToggled: Island.set("hideTopBorder", checked)
        }

        // ── Bureau ──
        SectionHeader {
            text: I18n.tr("Bureau")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Centre de contrôle")
            subtext: I18n.tr("Super + A : Wi-Fi, Bluetooth, son, écran, enregistrement… (sinon le tableau de bord)")
            checked: Island.controlCenter
            onToggled: Island.set("controlCenter", checked)
        }

        ToggleRow {
            text: I18n.tr("Retirer la barre de gauche")
            subtext: I18n.tr("Cadre fin et uniforme sur les quatre côtés")
            checked: Island.noBar
            onToggled: Island.set("hideBar", checked)
        }

        ToggleRow {
            last: true
            text: I18n.tr("Dock")
            subtext: I18n.tr("Sort du bas de l'écran au survol, sans prendre de place aux fenêtres")
            checked: Island.dock
            onToggled: Island.set("dock", checked)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.normal
            Layout.leftMargin: Tokens.padding.largeIncreased
            wrapMode: Text.Wrap
            text: I18n.tr("Tout s'applique immédiatement. Réglages enregistrés dans ~/.config/caelestia/island.json.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
    }
}

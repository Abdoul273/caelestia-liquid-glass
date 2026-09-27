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

    title: qsTr("Façon macOS")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ── Dynamic Island ──
        SectionHeader {
            first: true
            text: qsTr("Dynamic Island")
        }

        ToggleRow {
            first: true
            text: qsTr("Dynamic Island")
            subtext: qsTr("La pastille en haut de l'écran : musique, volume, captures, écouteurs, minuteurs…")
            checked: Island.enabled
            onToggled: Island.set("enabled", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: qsTr("Notifications dans l'île")
            subtext: qsTr("Sinon, les bulles de Caelestia en haut à droite")
            checked: Island.notifications
            onToggled: Island.set("notifications", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: qsTr("Messages du système dans l'île")
            subtext: qsTr("Ne pas déranger, batterie faible, thème… au lieu des bulles du coin")
            checked: Island.toasts
            onToggled: Island.set("toasts", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: qsTr("Changement de bureau")
            subtext: qsTr("« Bureau 2 » et les points dans l'île")
            checked: Island.workspaces
            onToggled: Island.set("workspaces", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            text: qsTr("Paroles en direct")
            subtext: qsTr("Sous le titre de la musique (cache d'Aura, .lrc, LRCLIB en ligne)")
            checked: Island.lyrics
            onToggled: Island.set("lyrics", checked)
        }

        ToggleRow {
            enabled: Island.enabled
            last: true
            text: qsTr("Micro et caméra utilisés")
            subtext: qsTr("Point orange (micro) ou vert (caméra) quand une app les utilise")
            checked: Island.privacy
            onToggled: Island.set("privacy", checked)
        }

        // ── Au repos ──
        SectionHeader {
            text: qsTr("Au repos")
        }

        ToggleRow {
            first: true
            enabled: Island.enabled
            text: qsTr("Date et heure dans l'île")
            subtext: qsTr("Désactivé : l'île disparaît quand il ne se passe rien")
            checked: Island.clock
            onToggled: Island.set("clock", checked)
        }

        ToggleRow {
            enabled: Island.clock
            text: qsTr("Batterie à côté de l'heure")
            subtext: qsTr("Verte en charge, rouge sous 20 %")
            checked: Island.battery
            onToggled: Island.set("battery", checked)
        }

        ToggleRow {
            last: true
            enabled: Island.enabled
            text: qsTr("Bord haut invisible")
            subtext: qsTr("L'île sort directement du haut de l'écran")
            checked: Island.hideTopBorder
            onToggled: Island.set("hideTopBorder", checked)
        }

        // ── Bureau ──
        SectionHeader {
            text: qsTr("Bureau")
        }

        ToggleRow {
            first: true
            text: qsTr("Centre de contrôle")
            subtext: qsTr("Super + A : Wi-Fi, Bluetooth, son, écran, enregistrement… (sinon le tableau de bord)")
            checked: Island.controlCenter
            onToggled: Island.set("controlCenter", checked)
        }

        ToggleRow {
            text: qsTr("Retirer la barre de gauche")
            subtext: qsTr("Cadre fin et uniforme sur les quatre côtés")
            checked: Island.noBar
            onToggled: Island.set("hideBar", checked)
        }

        ToggleRow {
            last: true
            text: qsTr("Dock")
            subtext: qsTr("Sort du bas de l'écran au survol, sans prendre de place aux fenêtres")
            checked: Island.dock
            onToggled: Island.set("dock", checked)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.normal
            Layout.leftMargin: Tokens.padding.largeIncreased
            wrapMode: Text.Wrap
            text: qsTr("Tout s'applique immédiatement. Réglages enregistrés dans ~/.config/caelestia/island.json.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }
    }
}

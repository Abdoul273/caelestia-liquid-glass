import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Alimentation")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Capot")
        }

        ToggleRow {
            first: true
            text: qsTr("Rester allumé capot fermé")
            subtext: qsTr("Empêche l'extinction et la mise en veille à la fermeture du capot")
            checked: LidSwitch.ignoreClosed
            onToggled: LidSwitch.ignoreClosed = checked
        }

        InfoRow {
            last: true
            label: qsTr("État du capot")
            value: !LidSwitch.hasLid ? qsTr("Non détecté") : LidSwitch.lidClosed ? qsTr("Fermé") : qsTr("Ouvert")
            icon: !LidSwitch.hasLid ? "laptop" : LidSwitch.lidClosed ? "laptop_windows" : "laptop_mac"
        }

        SectionHeader {
            text: qsTr("Veille automatique")
        }

        ToggleRow {
            first: true
            text: qsTr("Verrouiller avant la mise en veille")
            subtext: qsTr("Verrouiller la session juste avant la veille")
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            text: qsTr("Rester éveillé pendant la lecture")
            subtext: qsTr("Empêche la veille si un média est en cours")
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Rester éveillé pendant la charge")
            subtext: qsTr("Empêche la veille automatique sur secteur")
            checked: GlobalConfig.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }
    }
}

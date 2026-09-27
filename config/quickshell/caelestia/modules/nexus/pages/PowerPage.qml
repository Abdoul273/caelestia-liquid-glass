import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Alimentation")

    function actionName(action: var): string {
        const a = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        if (a === "lock")
            return qsTr("Verrouiller l'écran");
        if (a.includes("dpms"))
            return qsTr("Éteindre l'écran");
        if (a.includes("hibernate") && !a.includes("suspend"))
            return qsTr("Hiberner");
        if (a.includes("suspend") || a.includes("sleep"))
            return qsTr("Mettre en veille");
        return a;
    }

    function setTimeoutAt(index: int, key: string, value: var): void {
        const list = GlobalConfig.general.idle.timeouts.map(t => Object.assign({}, t));
        list[index][key] = value;
        GlobalConfig.general.idle.timeouts = list;
    }

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
            text: qsTr("Caféine")
            subtext: IdleInhibitor.enabled ? qsTr("L'écran reste allumé, aucune action ci-dessous ne s'applique") : qsTr("Garder l'écran allumé")
            checked: IdleInhibitor.enabled
            onToggled: IdleInhibitor.enabled = checked
        }

        Repeater {
            model: GlobalConfig.general.idle.timeouts

            ColumnLayout {
                id: timeoutRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                ToggleRow {
                    text: root.actionName(timeoutRow.modelData.idleAction)
                    subtext: qsTr("Après %1 min d'inactivité").arg(Math.round(timeoutRow.modelData.timeout / 60))
                    checked: timeoutRow.modelData.enabled ?? true
                    onToggled: root.setTimeoutAt(timeoutRow.index, "enabled", checked)
                }

                StepperRow {
                    visible: timeoutRow.modelData.enabled ?? true
                    label: qsTr("Délai (minutes)")
                    value: Math.round(timeoutRow.modelData.timeout / 60)
                    from: 1
                    to: 240
                    onMoved: v => root.setTimeoutAt(timeoutRow.index, "timeout", Math.round(v) * 60)
                }
            }
        }

        ToggleRow {
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

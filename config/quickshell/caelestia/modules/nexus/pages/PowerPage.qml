import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: I18n.tr("Alimentation")

    function actionName(action: var): string {
        const a = Array.isArray(action) ? action.join(" ") : String(action ?? "");
        if (a === "lock")
            return I18n.tr("Verrouiller l'écran");
        if (a.includes("dpms"))
            return I18n.tr("Éteindre l'écran");
        if (a.includes("hibernate") && !a.includes("suspend"))
            return I18n.tr("Hiberner");
        if (a.includes("suspend") || a.includes("sleep"))
            return I18n.tr("Mettre en veille");
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
            text: I18n.tr("Capot")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Rester allumé capot fermé")
            subtext: I18n.tr("Empêche l'extinction et la mise en veille à la fermeture du capot")
            checked: LidSwitch.ignoreClosed
            onToggled: LidSwitch.ignoreClosed = checked
        }

        InfoRow {
            last: true
            label: I18n.tr("État du capot")
            value: !LidSwitch.hasLid ? I18n.tr("Non détecté") : LidSwitch.lidClosed ? I18n.tr("Fermé") : I18n.tr("Ouvert")
            icon: !LidSwitch.hasLid ? "laptop" : LidSwitch.lidClosed ? "laptop_windows" : "laptop_mac"
        }

        SectionHeader {
            text: I18n.tr("Veille automatique")
        }

        ToggleRow {
            first: true
            text: I18n.tr("Caféine")
            subtext: IdleInhibitor.enabled ? I18n.tr("L'écran reste allumé, aucune action ci-dessous ne s'applique") : I18n.tr("Garder l'écran allumé")
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
                    subtext: I18n.tr("Après %1 min d'inactivité").arg(Math.round(timeoutRow.modelData.timeout / 60))
                    checked: timeoutRow.modelData.enabled ?? true
                    onToggled: root.setTimeoutAt(timeoutRow.index, "enabled", checked)
                }

                StepperRow {
                    visible: timeoutRow.modelData.enabled ?? true
                    label: I18n.tr("Délai (minutes)")
                    value: Math.round(timeoutRow.modelData.timeout / 60)
                    from: 1
                    to: 240
                    onMoved: v => root.setTimeoutAt(timeoutRow.index, "timeout", Math.round(v) * 60)
                }
            }
        }

        ToggleRow {
            text: I18n.tr("Verrouiller avant la mise en veille")
            subtext: I18n.tr("Verrouiller la session juste avant la veille")
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            text: I18n.tr("Rester éveillé pendant la lecture")
            subtext: I18n.tr("Empêche la veille si un média est en cours")
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        ToggleRow {
            last: true
            text: I18n.tr("Rester éveillé pendant la charge")
            subtext: I18n.tr("Empêche la veille automatique sur secteur")
            checked: GlobalConfig.general.idle.inhibitWhenCharging
            onToggled: GlobalConfig.general.idle.inhibitWhenCharging = checked
        }
    }
}

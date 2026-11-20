import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.services

Scope {
    id: root

    readonly property list<var> warnLevels: [...GlobalConfig.general.battery.warnLevels].sort((a, b) => a.level - b.level)
    property real lastPercentage: 100

    function handleBatteryWarnings(): void {
        const p = UPower.displayDevice.percentage * 100;

        if (!UPower.onBattery) {
            root.lastPercentage = p;
            return;
        }

        if (root.lastPercentage >= 0) {
            for (const level of root.warnLevels) {
                if (p <= level.level && root.lastPercentage > level.level) {
                    Sounds.playBatteryLow();
                    // Pourcentage et autonomie restante ajoutés au message d'alerte
                    const rest = BatteryInfo.timeToEmpty > 0 ? I18n.tr(" · %1 restantes").arg(BatteryInfo.fmtDuration(BatteryInfo.timeToEmpty)) : "";
                    Toaster.toast(`${level.title ?? I18n.tr("Avertissement batterie")} · ${Math.round(p)} %`, `${level.message ?? I18n.tr("Batterie faible")}${rest}`, level.icon ?? "battery_android_alert", level.critical ? Toast.Error : Toast.Warning);
                    break;
                }
            }
        }

        if (!hibernateTimer.running && p <= GlobalConfig.general.battery.criticalLevel) {
            Toaster.toast(I18n.tr("Mise en veille prolongée dans 5 secondes"), I18n.tr("Mise en veille prolongée pour protéger vos données"), "battery_android_alert", Toast.Error);
            hibernateTimer.start();
        }

        root.lastPercentage = p;
    }

    Connections {
        function onOnBatteryChanged(): void {
            if (!UPower.displayDevice.ready)
                return;

            if (UPower.onBattery) {
                Sounds.playUnplug();
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(I18n.tr("Chargeur débranché"), I18n.tr("Batterie en décharge"), "power_off");
                root.handleBatteryWarnings();
            } else {
                Sounds.playPlug();
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(I18n.tr("Chargeur branché"), I18n.tr("Batterie en charge"), "power");
                root.lastPercentage = 100;
            }
        }

        target: UPower
    }

    Connections {
        function onReadyChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Connections {
        function onPercentageChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Timer {
        id: hibernateTimer

        interval: 5000
        onTriggered: SessionManager.hibernate()
    }
}

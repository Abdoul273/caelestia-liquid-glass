import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.services

Scope {
    Connections {
        function onLoaded(): void {
            if (GlobalConfig.utilities.toasts.configLoaded)
                Toaster.toast(I18n.tr("Configuration chargée"), I18n.tr("Configuration chargée avec succès !"), "rule_settings");
        }

        function onLoadFailed(error: string, screen: string): void {
            Toaster.toast(I18n.tr("Impossible de lire la configuration%1").arg(screen ? " for " + screen : ""), error, "settings_alert", Toast.Warning);
        }

        function onSaveFailed(error: string, screen: string): void {
            Toaster.toast(I18n.tr("Échec de l'enregistrement de la configuration%1").arg(screen ? " for " + screen : ""), error, "settings_alert", Toast.Error);
        }

        function onUnknownOption(key: string, screen: string): void {
            Toaster.toast(I18n.tr("Option inconnue dans la configuration%1").arg(screen ? " " + screen : ""), key, "question_mark", Toast.Warning);
        }

        target: GlobalConfig
    }

    Connections {
        function onLoadFailed(error: string, screen: string): void {
            Toaster.toast(I18n.tr("Impossible de lire la configuration des jetons%1").arg(screen ? "for " + screen : ""), error, "settings_alert", Toast.Warning);
        }

        function onUnknownOption(key: string, screen: string): void {
            Toaster.toast(I18n.tr("Option inconnue dans la configuration des jetons%1").arg(screen ? " " + screen : ""), key, "question_mark", Toast.Warning);
        }

        target: TokenConfig
    }
}

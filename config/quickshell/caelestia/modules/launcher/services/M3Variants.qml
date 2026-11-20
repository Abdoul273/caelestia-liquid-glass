pragma Singleton

import ".."
import QtQuick
import Quickshell
import Caelestia.Config
import qs.utils
import qs.services

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(`${GlobalConfig.launcher.actionPrefix}variant `.length);
    }

    list: [
        Variant {
            variant: "vibrant"
            icon: "sentiment_very_dissatisfied"
            name: I18n.tr("Éclatant")
            description: I18n.tr("Palette très saturée. La saturation de la palette principale est au maximum.")
        },
        Variant {
            variant: "tonalspot"
            icon: "android"
            name: I18n.tr("Tonal Spot")
            description: I18n.tr("Thème Material par défaut. Palette pastel à faible saturation.")
        },
        Variant {
            variant: "expressive"
            icon: "compare_arrows"
            name: I18n.tr("Expressif")
            description: I18n.tr("Palette moyennement saturée. La teinte varie par rapport à la couleur de base.")
        },
        Variant {
            variant: "fidelity"
            icon: "compare"
            name: I18n.tr("Fidélité")
            description: I18n.tr("Suit la couleur de base, même si elle est très vive.")
        },
        Variant {
            variant: "content"
            icon: "sentiment_calm"
            name: I18n.tr("Contenu")
            description: I18n.tr("Quasi identique au mode fidélité.")
        },
        Variant {
            variant: "fruitsalad"
            icon: "nutrition"
            name: I18n.tr("Salade de fruits")
            description: I18n.tr("Thème ludique — la teinte d'origine n'apparaît pas dans le thème.")
        },
        Variant {
            variant: "rainbow"
            icon: "looks"
            name: I18n.tr("Arc-en-ciel")
            description: I18n.tr("Thème ludique — la teinte d'origine n'apparaît pas dans le thème.")
        },
        Variant {
            variant: "neutral"
            icon: "contrast"
            name: I18n.tr("Neutre")
            description: I18n.tr("Proche du monochrome, avec une subtile nuance de couleur.")
        },
        Variant {
            variant: "monochrome"
            icon: "filter_b_and_w"
            name: I18n.tr("Monochrome")
            description: I18n.tr("Toutes les couleurs sont en niveaux de gris, sans saturation.")
        }
    ]
    useFuzzy: GlobalConfig.launcher.useFuzzy.variants

    component Variant: QtObject {
        required property string variant
        required property string icon
        required property string name
        required property string description

        function onClicked(list: AppList): void {
            list.screenState.launcher = false;
            Quickshell.execDetached(["caelestia", "scheme", "set", "-v", variant]);
        }
    }
}

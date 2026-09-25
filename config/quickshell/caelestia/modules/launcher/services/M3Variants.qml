pragma Singleton

import ".."
import QtQuick
import Quickshell
import Caelestia.Config
import qs.utils

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(`${GlobalConfig.launcher.actionPrefix}variant `.length);
    }

    list: [
        Variant {
            variant: "vibrant"
            icon: "sentiment_very_dissatisfied"
            name: qsTr("Éclatant")
            description: qsTr("Palette très saturée. La saturation de la palette principale est au maximum.")
        },
        Variant {
            variant: "tonalspot"
            icon: "android"
            name: qsTr("Tonal Spot")
            description: qsTr("Thème Material par défaut. Palette pastel à faible saturation.")
        },
        Variant {
            variant: "expressive"
            icon: "compare_arrows"
            name: qsTr("Expressif")
            description: qsTr("Palette moyennement saturée. La teinte varie par rapport à la couleur de base.")
        },
        Variant {
            variant: "fidelity"
            icon: "compare"
            name: qsTr("Fidélité")
            description: qsTr("Suit la couleur de base, même si elle est très vive.")
        },
        Variant {
            variant: "content"
            icon: "sentiment_calm"
            name: qsTr("Contenu")
            description: qsTr("Quasi identique au mode fidélité.")
        },
        Variant {
            variant: "fruitsalad"
            icon: "nutrition"
            name: qsTr("Salade de fruits")
            description: qsTr("Thème ludique — la teinte d'origine n'apparaît pas dans le thème.")
        },
        Variant {
            variant: "rainbow"
            icon: "looks"
            name: qsTr("Arc-en-ciel")
            description: qsTr("Thème ludique — la teinte d'origine n'apparaît pas dans le thème.")
        },
        Variant {
            variant: "neutral"
            icon: "contrast"
            name: qsTr("Neutre")
            description: qsTr("Proche du monochrome, avec une subtile nuance de couleur.")
        },
        Variant {
            variant: "monochrome"
            icon: "filter_b_and_w"
            name: qsTr("Monochrome")
            description: qsTr("Toutes les couleurs sont en niveaux de gris, sans saturation.")
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

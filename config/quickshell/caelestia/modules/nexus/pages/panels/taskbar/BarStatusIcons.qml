pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia.Config
import qs.modules.nexus.common
import qs.services

PageBase {
    id: root

    readonly property var builtinIcons: ({
            lockStatus: I18n.tr("Touches de verrouillage"),
            kbLayout: I18n.tr("Disposition du clavier"),
            audio: I18n.tr("Haut-parleurs"),
            microphone: I18n.tr("Microphone"),
            network: I18n.tr("Réseau"),
            bluetooth: I18n.tr("Bluetooth"),
            battery: I18n.tr("Batterie")
        })

    title: I18n.tr("Icônes d'état")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Visible icons
        SectionHeader {
            first: true
            text: I18n.tr("Icônes visibles")
        }

        ListEditor {
            function labelFor(item: var): string {
                const prettyName = root.builtinIcons[item.id];
                if (prettyName)
                    return prettyName;
                const label = item.id.replace(/([A-Z])/g, " $1");
                return label.charAt(0).toUpperCase() + label.slice(1).toLowerCase();
            }

            function toggledFor(item: var): bool {
                return item.enabled;
            }

            z: 1
            first: true
            values: Config.bar.statusIcons.values
            onItemMoved: (from, to) => GlobalConfig.bar.statusIcons.move(from, to)
            onItemRemoved: index => GlobalConfig.bar.statusIcons.remove(index)
            onItemToggled: (index, checked) => GlobalConfig.bar.statusIcons.at(index).enabled = checked
        }

        DialogSelectButton {
            id: addItemContainer

            rootParent: root.flickable
            icon: "add"
            label: I18n.tr("Ajouter une entrée")
            header: I18n.tr("Ajouter une entrée")
            acceptLabel: I18n.tr("Ajouter")

            model: {
                const builtins = Object.keys(root.builtinIcons).map(k => ({
                            id: k,
                            label: root.builtinIcons[k]
                        }));
                return builtins;
            }

            onAccepted: {
                if (!selectedItem) // Should never happen but just in case
                    return;

                GlobalConfig.bar.statusIcons.insert({
                    id: selectedItem,
                    enabled: true
                });
            }
        }

        // Behaviour
        SectionHeader {
            text: I18n.tr("Comportement")
        }

        ToggleRow {
            first: true
            last: true
            text: I18n.tr("Volet au survol")
            subtext: I18n.tr("Afficher les détails au survol des icônes d'état")
            checked: Config.bar.popouts.statusIcons
            onToggled: GlobalConfig.bar.popouts.statusIcons = checked
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

// Detail / settings sub-page for the active Wi-Fi network. Reached by tapping
// the active network row (settings icon) on NetworkPage.
PageBase {
    id: root

    readonly property string ssid: nState.selectedNetworkSsid
    readonly property var ap: Nmcli.findNetwork(root.ssid)
    readonly property var details: Nmcli.wirelessDeviceDetails
    readonly property bool isActive: !!Nmcli.active && Nmcli.active.ssid === root.ssid

    // Locally-edited IPv4 form state.
    property string ipMethod: "auto" // "auto" | "auto-dns" | "manual"
    property bool ipLoaded: false
    property bool savingIp: false
    property bool autoconnect: true

    // Snapshot of the saved IPv4 config, so the Apply button only shows up once
    // something actually changed.
    property string origMethod: "auto"
    property string origAddress: ""
    property string origGateway: ""
    property string origDns: ""

    readonly property bool hasChanges: root.ipLoaded && (root.ipMethod !== root.origMethod || (root.ipMethod === "manual" && (addressField.text.trim() !== root.origAddress || gatewayField.text.trim() !== root.origGateway)) || ((root.ipMethod === "manual" || root.ipMethod === "auto-dns") && dnsField.text.trim() !== root.origDns))
    readonly property bool showDnsSettings: root.ipMethod === "manual" || root.ipMethod === "auto-dns"

    function loadIpConfig(): void {
        if (!root.ssid)
            return;
        Nmcli.getIpv4Config(root.ssid, cfg => {
            if (!cfg)
                return;
            root.ipMethod = cfg.method; // "auto" | "auto-dns" | "manual"
            methodSelect.active = cfg.method === "manual" ? manualItem : (cfg.method === "auto-dns" ? autoDnsItem : autoItem);
            addressField.text = cfg.address;
            gatewayField.text = cfg.gateway;
            dnsField.text = cfg.dns;
            root.autoconnect = cfg.autoconnect;
            root.origMethod = cfg.method;
            root.origAddress = cfg.address;
            root.origGateway = cfg.gateway;
            root.origDns = cfg.dns;
            root.ipLoaded = true;
        });
    }

    function saveIpConfig(): void {
        if (!root.ssid)
            return;
        root.savingIp = true;
        Nmcli.setIpv4Config(root.ssid, {
            method: root.ipMethod,
            address: addressField.text.trim(),
            gateway: gatewayField.text.trim(),
            dns: dnsField.text.trim()
        }, result => {
            root.savingIp = false;
            if (!(result && result.success)) {
                if (root.ipMethod === "manual")
                    addressField.isError = true;
                else
                    dnsField.isError = true;
            } else {
                root.origMethod = root.ipMethod;
                root.origAddress = addressField.text.trim();
                root.origGateway = gatewayField.text.trim();
                root.origDns = dnsField.text.trim();
            }
        });
    }

    // Close if the network is no longer active (e.g. disconnected elsewhere).
    // ...But not when the page was opened from saved networks
    onApChanged: {
        if (!nState.networkDetailsFromSaved && root.ipLoaded && !root.ap)
            nState.closeSubPage();
    }

    title: root.ssid || qsTr("Réseau")
    isSubPage: true

    Component.onCompleted: {
        Nmcli.getWirelessDeviceDetails("", () => {});
        loadIpConfig();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ---- Action buttons --------------------------------------------------
        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * 0.7)
            spacing: Tokens.spacing.small

            ButtonBase {
                id: forgetBtn

                fillWidth: true
                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3errorContainer
                inactiveOnColour: Colours.palette.m3onErrorContainer

                implicitWidth: forgetLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: forgetLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    Nmcli.forgetNetwork(root.ssid);
                    root.nState.closeSubPage();
                }

                ColumnLayout {
                    id: forgetLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "delete"
                        color: forgetBtn.onColour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Oublier")
                        color: forgetBtn.onColour
                    }
                }
            }

            ButtonBase {
                id: connectBtn

                visible: !root.isActive
                fillWidth: true
                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer

                implicitWidth: connectLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: connectLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    if (root.ap) {
                        NetworkConnection.handleConnect(root.ap);
                    } else {
                        Nmcli.activateConnection(root.ssid, () => {});
                    }
                    root.nState.closeSubPage();
                }

                ColumnLayout {
                    id: connectLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "link"
                        color: connectBtn.onColour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Se connecter")
                        color: connectBtn.onColour
                    }
                }
            }

            ButtonBase {
                id: disconnectBtn

                visible: root.isActive
                fillWidth: true
                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer

                implicitWidth: disconnectLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: disconnectLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    Nmcli.disconnectFromNetwork();
                    root.nState.closeSubPage();
                }

                ColumnLayout {
                    id: disconnectLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "link_off"
                        color: disconnectBtn.onColour
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Se déconnecter")
                        color: disconnectBtn.onColour
                    }
                }
            }
        }

        // ---- Connection info (only shows when active) ---------------------------------
        SectionHeader {
            first: true
            text: qsTr("Connexion")
            visible: root.isActive
        }

        InfoRow {
            first: true
            icon: "signal_wifi_4_bar"
            label: qsTr("Signal")
            value: root.ap ? qsTr("%1 %").arg(root.ap.strength) : qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "lock"
            label: qsTr("Sécurité")
            value: root.ap?.security || qsTr("Ouvrir")
            visible: root.isActive
        }

        InfoRow {
            icon: "graphic_eq"
            label: qsTr("Fréquence")
            value: root.ap && root.ap.frequency > 0 ? qsTr("%1 MHz").arg(root.ap.frequency) : qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "lan"
            label: qsTr("Adresse IP")
            value: root.details?.ipAddress || qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "router"
            label: qsTr("Passerelle")
            value: root.details?.gateway || qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            last: true
            icon: "memory"
            label: qsTr("Adresse MAC")
            value: root.details?.macAddress || qsTr("—")
            visible: root.isActive
        }

        // ---- Behaviour -------------------------------------------------------
        SectionHeader {
            first: !root.isActive
            text: qsTr("Comportement")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            last: true
            text: qsTr("Connexion automatique")
            subtext: qsTr("Rejoindre ce réseau dès qu'il est à portée")
            checked: root.autoconnect
            enabled: root.ipLoaded
            onToggled: {
                root.autoconnect = checked;
                Nmcli.setAutoconnect(root.ssid, checked, () => {});
            }
        }

        // ---- IPv4 ------------------------------------------------------------
        SectionHeader {
            text: qsTr("IPv4")
        }

        SelectRow {
            id: methodSelect

            first: true
            last: root.ipMethod === "auto"
            label: qsTr("Attribution IP")
            fallbackText: qsTr("Automatique (DHCP)")
            fallbackIcon: "lan"

            onSelected: item => root.ipMethod = item === manualItem ? "manual" : (item === autoDnsItem ? "auto-dns" : "auto")

            menuItems: [
                MenuItem {
                    id: autoItem

                    icon: "lan"
                    text: qsTr("Automatique (DHCP)")
                },
                MenuItem {
                    id: autoDnsItem

                    icon: "dns"
                    text: qsTr("Automatique, DNS uniquement")
                },
                MenuItem {
                    id: manualItem

                    icon: "edit"
                    text: qsTr("Manuel")
                }
            ]

            Behavior on bottomLeftRadius {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on bottomRightRadius {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // Address + gateway: manual only. DNS: manual and DNS-only.
        Item {
            Layout.fillWidth: true
            Layout.topMargin: root.showDnsSettings ? Tokens.spacing.large : -parent.spacing
            implicitHeight: root.showDnsSettings ? dnsColumn.implicitHeight : 0
            opacity: root.showDnsSettings ? 1 : 0

            Behavior on Layout.topMargin {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on implicitHeight {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            ColumnLayout {
                id: dnsColumn

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: root.ipMethod === "manual" ? Tokens.spacing.large : 0

                Behavior on spacing {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: root.ipMethod === "manual" ? manualDnsColumn.implicitHeight : 0
                    opacity: root.ipMethod === "manual" ? 1 : 0

                    Behavior on implicitHeight {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    ColumnLayout {
                        id: manualDnsColumn

                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Tokens.spacing.large

                        StyledTextField {
                            id: addressField

                            Layout.fillWidth: true
                            placeholderText: qsTr("Adresse (CIDR)")
                            leadingIcon: "router"
                            supportingText: qsTr("IP et masque, ex. 192.168.1.50/24")
                            errorText: qsTr("Entrez une adresse valide en notation CIDR")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            validate: /^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\/(?:3[0-2]|[12]?\d)$/
                        }

                        StyledTextField {
                            id: gatewayField

                            Layout.fillWidth: true
                            placeholderText: qsTr("Passerelle")
                            leadingIcon: "exit_to_app"
                            errorText: qsTr("Entrez une adresse de passerelle valide")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            validate: /^$|^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$/
                        }
                    }
                }

                StyledTextField {
                    id: dnsField

                    Layout.fillWidth: true
                    placeholderText: qsTr("Serveurs DNS")
                    leadingIcon: "dns"
                    supportingText: qsTr("Séparés par des virgules")
                    errorText: qsTr("Entrez des adresses DNS valides")
                    inputMethodHints: Qt.ImhNoPredictiveText
                    validate: /^$|^\s*(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\s*,\s*(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d))*\s*$/
                }
            }
        }

        // Apply button — swaps to a loading spinner while applying, matching the
        // connect animation used in the Wi-Fi list. Only shown once the form
        // actually diverges from the saved config.
        Item {
            Layout.alignment: Qt.AlignRight
            implicitWidth: applyBtn.implicitWidth
            implicitHeight: root.hasChanges || root.savingIp ? applyBtn.implicitHeight : 0
            opacity: root.hasChanges || root.savingIp ? 1 : 0

            Behavior on implicitHeight {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            ButtonBase {
                id: applyBtn

                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                stateLayer.disabled: !root.ipLoaded || root.savingIp

                implicitWidth: applyMetrics.width + Tokens.padding.extraLarge * 2
                implicitHeight: applyMetrics.height + Tokens.padding.medium * 2

                onClicked: {
                    if (root.ipLoaded && !root.savingIp)
                        root.saveIpConfig();
                }

                TextMetrics {
                    id: applyMetrics

                    text: qsTr("Appliquer")
                    font: applyBtn.font
                }

                AnimLoader {
                    id: applyContent

                    anchors.centerIn: parent
                    sourceComp: root.savingIp ? applyLoadingComp : applyTextComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: applyLoadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.4)
                        color: applyBtn.onColour
                    }
                }

                Component {
                    id: applyTextComp

                    StyledText {
                        text: applyMetrics.text
                        font: applyBtn.font
                        color: applyBtn.onColour
                    }
                }
            }
        }
    }
}

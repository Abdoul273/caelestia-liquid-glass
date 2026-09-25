pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services

// Indicateur de bureau façon macOS : une pastille de verre avec un point par
// bureau apparaît en bas de l'écran pendant un changement de bureau.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
            readonly property int lastId: {
                let max = activeId;
                for (const w of Hypr.workspaces.values)
                    if (w.id > max && w.monitor?.name === monitor?.name)
                        max = w.id;
                return Math.max(max, 3);
            }
            property bool showing
            property bool ready

            screen: modelData
            name: "wshud"
            visible: showing || hud.opacity > 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            anchors.bottom: true
            implicitWidth: hud.width + 40
            implicitHeight: hud.height + 60

            onActiveIdChanged: {
                // Pas d'indicateur au démarrage du shell
                if (!ready)
                    return;
                showing = true;
                hideTimer.restart();
            }

            Component.onCompleted: Qt.callLater(() => win.ready = true)

            Timer {
                id: hideTimer

                interval: 1100
                onTriggered: win.showing = false
            }

            Item {
                id: hud

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 32 + (win.showing ? 0 : -14)
                width: row.width + 44
                height: 56
                opacity: win.showing ? 1 : 0
                scale: win.showing ? 1 : 0.92

                Behavior on opacity {
                    NumberAnimation {
                        duration: win.showing ? 180 : 320
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.3
                    }
                }

                Behavior on anchors.bottomMargin {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }

                LiquidGlass {
                    anchors.fill: parent
                    radius: height / 2
                    tintColour: Colours.palette.m3surfaceContainer
                    tintOpacity: 0.42
                }

                Row {
                    id: row

                    anchors.centerIn: parent
                    spacing: 16

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Bureau %1").arg(win.activeId)
                        color: "white"
                        font.pointSize: 12
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Repeater {
                            model: win.lastId

                            Rectangle {
                                required property int index
                                readonly property bool current: index + 1 === win.activeId

                                anchors.verticalCenter: parent.verticalCenter
                                width: current ? 26 : 9
                                height: 9
                                radius: 4.5
                                color: current ? "white" : Qt.alpha("white", 0.35)

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 380
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.4
                                    }
                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 250
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

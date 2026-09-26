pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Onglets du tableau de bord façon macOS : contrôle segmenté en verre.
// La pastille active glisse d'un onglet à l'autre et s'étire comme une goutte :
// le bord qui mène part vite, le bord qui suit rattrape avec un ressort plus lent.
Item {
    id: root

    required property real nonAnimWidth
    required property ScreenState screenState
    required property var tabs

    readonly property alias count: bar.count

    implicitHeight: track.implicitHeight + track.anchors.topMargin + Tokens.spacing.small

    // Piste du contrôle segmenté
    Rectangle {
        id: track

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 14

        implicitHeight: 42
        radius: height / 2
        color: Qt.alpha(Colours.palette.m3onSurface, 0.05)
        border.width: 1
        border.color: Qt.alpha("white", 0.07)

        // Pastille active
        Item {
            id: pill

            // Bords en fraction de la largeur (onglets de même largeur) : la pastille
            // reste juste même quand le panneau change de taille pendant l'animation.
            property real leftEdge
            property real rightEdge
            property bool movingRight

            function update(animate: bool): void {
                if (bar.count === 0)
                    return;
                const l = bar.currentIndex / bar.count;
                const r = (bar.currentIndex + 1) / bar.count;
                movingRight = l > leftEdge;
                leftBehavior.enabled = animate;
                rightBehavior.enabled = animate;
                leftEdge = l;
                rightEdge = r;
            }

            x: bar.x + leftEdge * bar.width + 4
            y: 4
            width: Math.max(0, (rightEdge - leftEdge) * bar.width - 8)
            height: parent.height - 8

            // Ombre douce
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 2
                anchors.bottomMargin: -2
                radius: height / 2
                color: Qt.alpha("black", 0.18)
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(Colours.palette.m3primary, 0.2)
                border.width: 1
                border.color: Qt.alpha("white", 0.2)

                // Reflet du verre
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.alpha("white", 0.2)
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.alpha("white", 0.02)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.alpha("white", 0.06)
                        }
                    }
                }
            }

            Behavior on leftEdge {
                id: leftBehavior

                Anim {
                    type: pill.movingRight ? Anim.DefaultSpatial : Anim.FastSpatial
                }
            }

            Behavior on rightEdge {
                id: rightBehavior

                Anim {
                    type: pill.movingRight ? Anim.FastSpatial : Anim.DefaultSpatial
                }
            }
        }

        TabBar {
            id: bar

            anchors.fill: parent

            currentIndex: root.screenState.dashboardTab
            onCurrentIndexChanged: {
                root.screenState.dashboardTab = currentIndex;
                pill.update(true);
            }
            onCountChanged: pill.update(false)
            Component.onCompleted: Qt.callLater(() => pill.update(false))

            background: null
            contentItem: RowLayout {
                spacing: 0

                Repeater {
                    model: bar.contentModel
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.tabs
                }

                delegate: Tab {
                    required property var modelData

                    iconName: modelData.iconName
                    text: modelData.text
                }
            }
        }
    }

    component Tab: TabButton {
        id: tab

        required property string iconName
        readonly property bool current: TabBar.tabBar.currentItem === this

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1 // Même largeur pour tous les onglets
        implicitWidth: implicitContentWidth
        implicitHeight: implicitContentHeight
        background: null

        contentItem: CustomMouseArea {
            id: mouse

            function onWheel(event: WheelEvent): void {
                if (event.angleDelta.y < 0)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, bar.count - 1);
                else if (event.angleDelta.y > 0)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            implicitWidth: content.implicitWidth + Tokens.padding.large * 2
            implicitHeight: content.implicitHeight

            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: root.screenState.dashboardTab = tab.TabBar.index

            // Survol discret des onglets inactifs
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: height / 2
                color: Qt.alpha(Colours.palette.m3onSurface, 0.06)
                opacity: mouse.containsMouse && !tab.current ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.FastEffects
                    }
                }
            }

            Row {
                id: content

                anchors.centerIn: parent
                spacing: Tokens.spacing.small
                scale: mouse.pressed ? 0.94 : 1

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                MaterialIcon {
                    id: icon

                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.iconName
                    color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fill: tab.current ? 1 : 0
                    fontStyle: Tokens.font.icon.builders.medium.scale(0.9).build()

                    Behavior on fill {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                StyledText {
                    id: label

                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.text
                    font.weight: tab.current ? Font.DemiBold : Font.Normal
                    color: tab.current ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}

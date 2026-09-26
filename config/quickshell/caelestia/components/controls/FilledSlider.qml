import "../effects"
import QtQuick
import QtQuick.Templates
import Caelestia.Config
import qs.components
import qs.services

Slider {
    id: root

    required property string icon
    property real oldValue
    property bool initialized

    orientation: Qt.Vertical

    background: StyledRect {
        color: Glass.controls ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Tokens.rounding.full
        border.width: Glass.controls ? 1 : 0
        border.color: Qt.alpha("white", 0.1)

        StyledRect {
            anchors.left: parent.left
            anchors.right: parent.right

            y: root.handle.y
            implicitHeight: parent.height - y

            color: Glass.controls ? Colours.palette.m3primary : Colours.palette.m3secondary
            radius: parent.radius

            Rectangle {
                visible: Glass.controls
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: Qt.alpha("white", 0.22)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha("white", 0)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha("white", 0.06)
                    }
                }
            }
        }
    }

    handle: Item {
        id: handle

        property alias moving: icon.moving

        y: root.visualPosition * (root.availableHeight - height)
        implicitWidth: root.width
        implicitHeight: root.width

        Elevation {
            anchors.fill: parent
            radius: rect.radius
            level: handleInteraction.containsMouse ? 2 : 1
        }

        StyledRect {
            id: rect

            anchors.fill: parent

            readonly property bool lens: Glass.controls && root.pressed

            color: Glass.controls ? (lens ? Qt.alpha("white", 0.18) : "white") : Colours.palette.m3inverseSurface
            radius: Tokens.rounding.full
            scale: lens ? 1.12 : 1
            border.width: Glass.controls ? (lens ? 1.5 : 0.5) : 0
            border.color: Qt.alpha("white", lens ? 0.85 : 0.5)

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            MouseArea {
                id: handleInteraction

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.NoButton
            }

            MaterialIcon {
                id: icon

                property bool moving

                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: moving ? Math.round(root.value * 100) : root.icon
                color: Glass.controls ? (rect.lens ? "white" : "#1d1d1f") : Colours.palette.m3inverseOnSurface
                font: moving ? Tokens.font.body.small : Tokens.font.icon.medium

                Behavior on moving {
                    SequentialAnimation {
                        Anim {
                            target: icon
                            property: "scale"
                            to: 0.3
                            duration: Tokens.anim.durations.small / 2
                            easing: Tokens.anim.standardAccel
                        }
                        PropertyAction {}
                        Anim {
                            target: icon
                            property: "scale"
                            to: 1
                            duration: Tokens.anim.durations.normal / 2
                            easing: Tokens.anim.standardDecel
                        }
                    }
                }
            }
        }
    }

    onPressedChanged: handle.moving = pressed

    onValueChanged: {
        if (!initialized) {
            initialized = true;
            return;
        }
        if (Math.abs(value - oldValue) < 0.01)
            return;
        oldValue = value;
        handle.moving = true;
        stateChangeDelay.restart();
    }

    Timer {
        id: stateChangeDelay

        interval: 500
        onTriggered: {
            if (!root.pressed)
                handle.moving = false;
        }
    }

    Behavior on value {
        Anim {
            type: Anim.StandardLarge
        }
    }
}

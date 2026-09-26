pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates
import Caelestia
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

Slider {
    id: root

    property bool wavy
    property bool animateWave
    property real waveFrequency: 6
    property int waveDuration: 1000
    property int radius: Tokens.rounding.medium
    property bool interactionOnMove: true
    readonly property bool dragging: mouse.pressed
    // Style verre façon macOS (sauf la barre ondulée des médias, gardée telle quelle)
    readonly property bool glass: Glass.controls && !wavy

    property color fgColour: enabled ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, 0.38)
    property color bgColour: enabled ? Colours.palette.m3secondaryContainer : Qt.alpha(Colours.palette.m3onSurface, 0.1)

    property real pos: visualPosition
    property real filledWidth

    signal interaction(v: real)

    Component.onCompleted: filledWidth = Qt.binding(() => (width - handle.implicitWidth - handle.anchors.leftMargin) * pos)

    implicitWidth: 200
    implicitHeight: 12

    contentItem: Item {
        anchors.fill: parent

        Item {
            id: glassSlider

            readonly property real trackH: Math.max(5, Math.min(root.height * 0.6, 10))
            readonly property real knobH: Math.max(16, trackH * 2.1)
            readonly property real knobW: knobH * 1.55
            readonly property real knobX: root.pos * (width - knobW)

            visible: root.glass
            anchors.fill: parent

            Rectangle {
                id: glassTrack

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: glassSlider.trackH
                radius: height / 2
                color: root.enabled ? Qt.alpha(Colours.palette.m3onSurface, 0.14) : Qt.alpha(Colours.palette.m3onSurface, 0.07)
                border.width: 1
                border.color: Qt.alpha("white", 0.1)
            }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, glassSlider.knobX + glassSlider.knobW / 2)
                height: glassSlider.trackH
                radius: height / 2
                color: root.fgColour

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.alpha("white", 0.25)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.alpha("white", 0)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha("white", 0.04)
                    }
                }
                }

                Behavior on color {
                    CAnim {}
                }
            }

            // Ombre du bouton
            Rectangle {
                x: knob.x
                y: knob.y + 1.5
                width: knob.width
                height: knob.height
                radius: height / 2
                scale: knob.scale
                color: Qt.alpha("black", root.dragging ? 0.08 : 0.28)

                Behavior on color {
                    CAnim {}
                }
            }

            Rectangle {
                id: knob

                x: glassSlider.knobX
                anchors.verticalCenter: parent.verticalCenter
                width: glassSlider.knobW
                height: glassSlider.knobH
                radius: height / 2
                scale: root.dragging ? 1.25 : knobHover.hovered ? 1.06 : 1

                // Pastille blanche au repos, lentille de verre pendant le glisser
                color: Glass.lensControls ? "transparent" : root.dragging ? Qt.alpha("white", 0.16) : root.enabled ? "white" : Qt.alpha("white", 0.5)
                border.width: Glass.lensControls ? 0 : root.dragging ? 1.5 : 0.5
                border.color: Qt.alpha("white", root.dragging ? 0.85 : 0.5)

                GlassControl {
                    visible: Glass.lensControls
                    anchors.fill: parent
                    tintColour: root.enabled ? "white" : Qt.alpha("white", 0.5)
                    pressed: root.dragging
                    hovered: knobHover.hovered
                }

                HoverHandler {
                    id: knobHover

                    cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                    visible: !Glass.lensControls
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 1.5
                    width: parent.width * 0.6
                    height: parent.height * 0.35
                    radius: height / 2
                    color: Qt.alpha("white", 0.55)
                    opacity: root.dragging ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on color {
                    CAnim {}
                }
            }
        }

        StyledRect {
            id: remaining

            visible: !root.glass

            anchors.left: handle.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacing.extraSmall

            implicitHeight: parent.height * (parent.height <= 12 ? opacity : Math.min(opacity * 2, 1))
            opacity: Math.min(width, 12) / 12

            radius: root.radius
            topLeftRadius: Tokens.rounding.extraSmall / 2
            bottomLeftRadius: Tokens.rounding.extraSmall / 2
            color: root.bgColour
        }

        StyledRect {
            visible: !root.glass
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 4 * remaining.opacity

            implicitWidth: implicitHeight
            implicitHeight: 4 * remaining.opacity
            opacity: remaining.opacity

            radius: Tokens.rounding.full
            color: root.fgColour
        }

        StyledRect {
            id: handle

            visible: !root.glass
            anchors.left: filled.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacing.extraSmall

            implicitWidth: 4
            implicitHeight: {
                const t = CUtils.clamp((parent.height - 12) / 16, 0, 1);
                const lerp = (a, b) => a + (b - a) * t;
                return parent.height * (mouse.pressed ? lerp(3.5, 1.5) : lerp(3, 1.2));
            }

            radius: Tokens.rounding.full
            color: root.fgColour

            Behavior on implicitHeight {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }

        Loader {
            id: filled

            visible: !root.glass
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            asynchronous: true

            sourceComponent: root.wavy ? waveComp : lineComp
        }

        Component {
            id: lineComp

            StyledRect {
                implicitWidth: root.filledWidth
                implicitHeight: root.height

                radius: root.radius
                topRightRadius: Tokens.rounding.extraSmall / 2
                bottomRightRadius: Tokens.rounding.extraSmall / 2
                color: root.fgColour
            }
        }

        Component {
            id: waveComp

            WavyLine {
                lineWidth: root.height * 0.7
                frequency: root.waveFrequency
                startX: x
                fullLength: root.width - handle.implicitWidth - handle.anchors.leftMargin
                color: root.fgColour

                implicitWidth: root.filledWidth
                implicitHeight: lineWidth * amplitudeMultiplier * 2 + lineWidth

                Anim on waveProgress {
                    running: true
                    paused: !root.animateWave
                    from: 0
                    to: 1
                    duration: root.waveDuration
                    easing.type: Easing.Linear
                    loops: Animation.Infinite
                }

                Behavior on color {
                    CAnim {}
                }
            }
        }
    }

    Binding {
        id: posBinding

        target: root
        property: "pos"
        value: CUtils.clamp(mouse.pressStartPos + mouse.dragMovement, 0, 1)
        when: mouse.pressed
    }

    MouseArea {
        id: mouse

        property real pressStartX
        property real pressStartPos
        property real dragMovement

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        preventStealing: true
        implicitHeight: handle.implicitHeight

        onPressed: e => {
            widthBehavior.enabled = false;
            pressStartX = e.x;
            pressStartPos = root.visualPosition;
        }
        onPositionChanged: e => {
            dragMovement = (e.x - pressStartX) / width;
            if (root.interactionOnMove)
                root.interaction(posBinding.value);
        }
        onReleased: e => {
            const clickPos = e.x / width;
            const finalPos = mouse.dragMovement !== 0 ? posBinding.value : CUtils.clamp(clickPos, 0, 1);
            root.interaction(finalPos);
            widthBehavior.enabled = true;
            dragMovement = 0;
        }
    }

    Behavior on filledWidth {
        id: widthBehavior

        Anim {}
    }
}

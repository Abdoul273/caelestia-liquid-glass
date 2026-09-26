import QtQuick
import QtQuick.Shapes
import QtQuick.Templates
import Caelestia.Config
import qs.components
import qs.services

Switch {
    id: root

    property int cLayer: 1
    property bool disabled

    enabled: !disabled

    implicitWidth: implicitIndicatorWidth
    implicitHeight: implicitIndicatorHeight

    indicator: Item {
        implicitWidth: materialSwitch.implicitWidth
        implicitHeight: materialSwitch.implicitHeight

    StyledRect {
        id: materialSwitch

        visible: !Glass.controls
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: {
            if (root.disabled)
                return root.checked ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.38);
            return root.checked ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3surfaceContainerHighest, root.cLayer);
        }

        implicitWidth: implicitHeight * 1.7
        implicitHeight: Tokens.font.body.medium.pointSize + Tokens.padding.small * 2

        StyledRect {
            readonly property real nonAnimWidth: root.pressed ? implicitHeight * 1.2 : implicitHeight

            radius: Tokens.rounding.full
            color: {
                if (root.disabled)
                    return root.checked ? Colours.palette.m3surface : Qt.alpha(Colours.palette.m3onSurface, 0.12);
                return root.checked ? Colours.palette.m3onPrimary : Colours.layer(Colours.palette.m3outline, root.cLayer + 1);
            }

            x: root.checked ? parent.implicitWidth - nonAnimWidth - Tokens.padding.extraSmall / 2 : Tokens.padding.extraSmall / 2
            implicitWidth: nonAnimWidth
            implicitHeight: parent.implicitHeight - Tokens.padding.extraSmall
            anchors.verticalCenter: parent.verticalCenter

            StyledRect {
                anchors.fill: parent
                radius: parent.radius

                color: root.checked ? Colours.palette.m3primary : Colours.palette.m3onSurface
                opacity: root.pressed ? 0.1 : root.hovered ? 0.08 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            Shape {
                id: icon

                property point start1: {
                    if (root.pressed)
                        return Qt.point(width * 0.2, height / 2);
                    if (root.checked)
                        return Qt.point(width * 0.15, height / 2);
                    return Qt.point(width * 0.15, height * 0.15);
                }
                property point end1: {
                    if (root.pressed) {
                        if (root.checked)
                            return Qt.point(width * 0.4, height / 2);
                        return Qt.point(width * 0.8, height / 2);
                    }
                    if (root.checked)
                        return Qt.point(width * 0.4, height * 0.7);
                    return Qt.point(width * 0.85, height * 0.85);
                }
                property point start2: {
                    if (root.pressed) {
                        if (root.checked)
                            return Qt.point(width * 0.4, height / 2);
                        return Qt.point(width * 0.2, height / 2);
                    }
                    if (root.checked)
                        return Qt.point(width * 0.4, height * 0.7);
                    return Qt.point(width * 0.15, height * 0.85);
                }
                property point end2: {
                    if (root.pressed)
                        return Qt.point(width * 0.8, height / 2);
                    if (root.checked)
                        return Qt.point(width * 0.85, height * 0.2);
                    return Qt.point(width * 0.85, height * 0.15);
                }

                anchors.centerIn: parent
                width: height
                height: parent.implicitHeight - Tokens.padding.medium
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                ShapePath {
                    strokeWidth: root.Tokens.font.body.large.pointSize * 0.15
                    strokeColor: {
                        if (root.disabled)
                            return root.checked ? Colours.palette.m3outline : Colours.palette.m3surfaceContainer;
                        return root.checked ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest;
                    }
                    fillColor: "transparent"
                    capStyle: root.Tokens.rounding.scale === 0 ? ShapePath.SquareCap : ShapePath.RoundCap

                    startX: icon.start1.x
                    startY: icon.start1.y

                    PathLine {
                        x: icon.end1.x
                        y: icon.end1.y
                    }
                    PathMove {
                        x: icon.start2.x
                        y: icon.start2.y
                    }
                    PathLine {
                        x: icon.end2.x
                        y: icon.end2.y
                    }

                    Behavior on strokeColor {
                        CAnim {}
                    }
                }

                Behavior on start1 {
                    PropAnim {}
                }
                Behavior on end1 {
                    PropAnim {}
                }
                Behavior on start2 {
                    PropAnim {}
                }
                Behavior on end2 {
                    PropAnim {}
                }
            }

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on implicitWidth {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }

    // Interrupteur en verre façon macOS : piste teintée avec reflet, curseur blanc
    // qui s'étire et devient une lentille transparente pendant l'appui.
    Item {
        id: glassSwitch

        visible: Glass.controls
        anchors.fill: parent
        opacity: root.disabled ? 0.4 : 1

        readonly property real inset: 2

        Rectangle {
            id: track

            anchors.fill: parent
            radius: height / 2
            color: root.checked ? Qt.alpha(Colours.palette.m3primary, 0.92) : Qt.alpha(Colours.palette.m3onSurface, root.hovered ? 0.2 : 0.14)
            border.width: 1
            border.color: Qt.alpha("white", root.checked ? 0.28 : 0.12)

            // Reflet du haut
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
                        position: 0.55
                        color: Qt.alpha("white", 0)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha("white", 0.05)
                    }
                }
            }

            Behavior on color {
                CAnim {}
            }

            Behavior on border.color {
                CAnim {}
            }
        }

        // Ombre douce sous le curseur
        Rectangle {
            x: thumb.x
            y: thumb.y + 1.5
            width: thumb.width
            height: thumb.height
            radius: height / 2
            scale: thumb.scale
            color: Qt.alpha("black", root.pressed ? 0.08 : 0.28)

            Behavior on color {
                CAnim {}
            }
        }

        Rectangle {
            id: thumb

            readonly property real restWidth: height * 1.22
            readonly property real pressWidth: height * 1.5

            y: glassSwitch.inset
            height: parent.height - glassSwitch.inset * 2
            width: root.pressed ? pressWidth : restWidth
            x: root.checked ? parent.width - width - glassSwitch.inset : glassSwitch.inset
            radius: height / 2
            scale: root.pressed ? 1.18 : 1

            // Au repos : pastille blanche ; à l'appui : lentille de verre claire
            color: root.pressed ? Qt.alpha("white", 0.18) : "white"
            border.width: root.pressed ? 1.5 : 0.5
            border.color: Qt.alpha("white", root.pressed ? 0.85 : 0.5)

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                opacity: root.pressed ? 0 : 1
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.alpha("white", 0)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha("#1a1f3a", 0.1)
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            // Petit éclat de lumière en haut de la lentille
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 1.5
                width: parent.width * 0.6
                height: parent.height * 0.35
                radius: height / 2
                color: Qt.alpha("white", 0.55)
                opacity: root.pressed ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on width {
                Anim {
                    type: Anim.FastSpatial
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
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: false
    }

    component PropAnim: PropertyAnimation {
        duration: Tokens.anim.durations.expressiveFastSpatial
        easing: Tokens.anim.expressiveFastSpatial
    }
}

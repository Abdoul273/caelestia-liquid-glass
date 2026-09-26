import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    enum ButtonType {
        Filled,
        Tonal,
        Text
    }

    property bool checked
    property alias disabled: stateLayer.disabled
    property bool isToggle
    property bool isRound

    property bool radiusMorph: true
    property alias shapeMorph: stateLayer.shapeMorph
    property bool fillWidth // For ButtonRow

    property font font: Tokens.font.body.small
    property int type: ButtonBase.Filled

    property real padding
    property real horizontalPadding: padding
    property real verticalPadding: padding

    readonly property alias pressed: stateLayer.pressed
    readonly property alias hovered: stateLayer.containsMouse
    readonly property alias stateLayer: stateLayer
    readonly property alias radiusAnim: radiusAnim

    property color activeColour
    property color inactiveColour
    property color activeOnColour
    property color inactiveOnColour
    property color disabledColour: Qt.alpha(Colours.palette.m3onSurface, 0.1)
    property color disabledOnColour: Qt.alpha(Colours.palette.m3onSurface, 0.38)

    property bool internalChecked
    property real shapeMorphExpansion: shapeMorph && pressed ? 24 : 0 // Apparently it's always 24px no matter the width of the button
    readonly property color onColour: disabled ? disabledOnColour : internalChecked ? activeOnColour : inactiveOnColour

    property real pressedRadius: Tokens.rounding.small
    property real checkedRadius: Tokens.rounding.medium
    property real defaultRadius: Tokens.rounding.large

    signal clicked

    onCheckedChanged: internalChecked = checked

    radius: {
        if (radiusMorph && pressed)
            return pressedRadius;
        if (internalChecked)
            return checkedRadius;
        if (isRound)
            return (height || implicitHeight) / 2 * Math.min(1, Tokens.rounding.scale);
        return defaultRadius;
    }
    readonly property color baseColour: type === ButtonBase.Text ? "transparent" : disabled ? disabledColour : internalChecked ? activeColour : inactiveColour
    color: lens ? "transparent" : baseColour

    // Make size required so we don't forget to set it
    required implicitWidth
    required implicitHeight

    // Verre façon macOS : reflet en haut, liseré lumineux, légère pression au clic
    readonly property bool glass: Glass.controls && type !== ButtonBase.Text
    readonly property bool lens: glass && Glass.lensControls

    scale: glass && pressed ? 0.96 : 1

    Behavior on scale {
        Anim {
            type: Anim.FastSpatial
        }
    }

    // Verre bombé (reflets, bord irisé, caustique) — voir components/effects/GlassControl.qml
    GlassControl {
        visible: root.lens
        anchors.fill: parent
        radius: root.radius
        tintColour: root.baseColour
        pressed: root.pressed
        hovered: root.hovered
    }

    Rectangle {
        visible: root.glass && !root.lens
        anchors.fill: parent
        radius: root.radius
        border.width: 1
        border.color: Qt.alpha("white", root.internalChecked || root.type === ButtonBase.Filled && !root.isToggle ? 0.26 : 0.13)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha("white", root.hovered ? 0.22 : 0.16)
            }
            GradientStop {
                position: 0.5
                color: Qt.alpha("white", 0)
            }
            GradientStop {
                position: 1
                color: Qt.alpha("white", 0.04)
            }
        }
    }

    StateLayer {
        id: stateLayer

        color: root.internalChecked ? root.activeOnColour : root.inactiveOnColour
        disabled: root.disabled
        onClicked: {
            if (root.isToggle)
                root.internalChecked = !root.internalChecked;
            root.clicked();
        }
    }

    Behavior on radius {
        Anim {
            id: radiusAnim

            type: Anim.DefaultEffects
        }
    }

    Behavior on shapeMorphExpansion {
        Anim {
            type: Anim.FastSpatial
        }
    }
}

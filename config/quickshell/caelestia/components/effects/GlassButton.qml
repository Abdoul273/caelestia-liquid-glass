import QtQuick
import qs.components
import qs.services

// Bouton en liquid glass façon iOS 27 : verre bombé (GlassControl) avec reflets, lumière
// qui suit le pointeur, et effet « gelée » : à l'appui le bouton gonfle et s'élargit un peu,
// puis revient en rebondissant. Le contenu (texte, icône…) se place à l'intérieur.
Item {
    id: root

    default property alias contentData: inner.data
    property color tint: Qt.alpha(Colours.palette.m3onSurface, 0.1)
    property real radius: height / 2
    property bool jelly: true
    property alias cursorShape: area.cursorShape
    property alias hoverEnabled: area.hoverEnabled
    readonly property bool hovered: area.containsMouse
    readonly property bool pressed: area.pressed

    signal clicked
    signal doubleClicked
    signal entered

    opacity: enabled ? 1 : 0.4

    // Gelée : gonfle à l'appui (plus en largeur), petit soulèvement au survol
    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.squashX
        yScale: root.squashY
    }

    property real squashX: !jelly ? 1 : pressed ? 1.09 : hovered ? 1.025 : 1
    property real squashY: !jelly ? 1 : pressed ? 1.05 : hovered ? 1.025 : 1

    Behavior on squashX {
        SpringAnimation {
            spring: 5
            damping: 0.22
            epsilon: 0.002
        }
    }
    Behavior on squashY {
        SpringAnimation {
            spring: 5
            damping: 0.3
            epsilon: 0.002
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 160
        }
    }

    GlassControl {
        anchors.fill: parent
        tintColour: root.tint
        radius: root.radius
        pressed: root.pressed
        hovered: root.hovered
        pointer: root.hovered ? Qt.point(area.mouseX / Math.max(1, root.width), area.mouseY / Math.max(1, root.height)) : Qt.point(-1, -1)
    }

    Item {
        id: inner

        anchors.fill: parent
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onDoubleClicked: root.doubleClicked()
        onEntered: root.entered()
    }
}

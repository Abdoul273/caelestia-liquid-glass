import QtQuick

// Molette ample et douce pour une liste (ListView, GridView, Flickable) des panneaux du verre.
// Le shell freine fort la molette de tous les Flickable (QT_QUICK_FLICKABLE_WHEEL_DECELERATION
// dans shell.qml), d'où un défilement lent : ici ~3 lignes par cran, animé comme sur macOS.
// Usage : `SmoothWheel { flick: maListe }` à l'intérieur de la liste.
WheelHandler {
    id: root

    required property Flickable flick
    property real step: 120
    property real wheelTarget: 0

    function scrollBy(dy: real): void {
        const top = flick.originY;
        const bottom = Math.max(top, flick.originY + flick.contentHeight - flick.height);
        const from = anim.running ? wheelTarget : flick.contentY;
        wheelTarget = Math.max(top, Math.min(bottom, from - dy));
        anim.restart();
    }

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
        // Pavé tactile : pixels réels ; molette : un cran = `step` pixels
        const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y * 1.6 : event.angleDelta.y / 120 * step;
        if (dy !== 0)
            scrollBy(dy);
        event.accepted = true;
    }

    property NumberAnimation anim: NumberAnimation {
        target: root.flick
        property: "contentY"
        to: root.wheelTarget
        duration: 220
        easing.type: Easing.OutCubic
    }
}

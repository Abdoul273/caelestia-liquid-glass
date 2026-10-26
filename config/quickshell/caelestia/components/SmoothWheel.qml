import QtQuick

// Défilement ample et doux pour une liste (ListView, GridView, Flickable) des panneaux du verre.
// Le shell freine fort la molette de tous les Flickable (QT_QUICK_FLICKABLE_WHEEL_DECELERATION
// dans shell.qml) et Hyprland réduit le pavé tactile à 30 % (touchpadScrollFactor = 0.3) :
// - molette : ~3 lignes par cran, animé ;
// - pavé tactile : suit les doigts (amplifié pour compenser le 0.3), puis élan au lâcher, comme sur macOS.
// Usage : `SmoothWheel { flick: maListe }` à l'intérieur de la liste.
WheelHandler {
    id: root

    required property Flickable flick
    property real step: 120
    property real touchFactor: 3.6
    property real wheelTarget: 0

    // Vitesse des doigts (px/s), pour l'élan quand on lâche le pavé
    property real velocity: 0
    property real lastTime: 0

    function bounds(): var {
        const top = flick.originY;
        return [top, Math.max(top, flick.originY + flick.contentHeight - flick.height)];
    }

    function scrollBy(dy: real): void {
        const b = bounds();
        const from = anim.running ? wheelTarget : flick.contentY;
        wheelTarget = Math.max(b[0], Math.min(b[1], from - dy));
        anim.restart();
    }

    function moveBy(dy: real): void {
        anim.stop();
        flick.cancelFlick();
        const b = bounds();
        flick.contentY = Math.max(b[0], Math.min(b[1], flick.contentY - dy));
        const now = Date.now();
        const dt = Math.max(8, now - lastTime);
        const v = dy / dt * 1000;
        velocity = now - lastTime > 120 ? v : velocity * 0.6 + v * 0.4;
        lastTime = now;
        release.restart();
    }

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
        const touch = event.pixelDelta.y !== 0 || event.device?.type === PointerDevice.TouchPad;
        if (touch) {
            const raw = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
            if (raw !== 0)
                moveBy(raw * touchFactor);
        } else if (event.angleDelta.y !== 0) {
            scrollBy(event.angleDelta.y / 120 * step);
        }
        event.accepted = true;
    }

    // Plus d'événement depuis un instant : les doigts ont quitté le pavé → élan
    property Timer release: Timer {
        interval: 60
        onTriggered: {
            if (Math.abs(root.velocity) > 250)
                root.flick.flick(0, root.velocity);
            root.velocity = 0;
        }
    }

    property NumberAnimation anim: NumberAnimation {
        target: root.flick
        property: "contentY"
        to: root.wheelTarget
        duration: 220
        easing.type: Easing.OutCubic
    }
}

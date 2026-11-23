import QtQuick
import qs.services

// Proxy léger pour charger les panneaux modaux/secondaires à la demande et libérer
// leur mémoire après inactivité (profil Fluide/Auto : ~250 Mo économisés).
// En profil Puissance maximale (`!Glass.lazyPanels`), les panneaux restent préchargés
// en mémoire (0 ms de latence à l'ouverture), sauf ceux explicitement désactivés (`keepLoaded: false`).
Item {
    id: root

    required property Item host
    required property bool wantOpen
    required property Component sourceComponent
    property int unloadDelayMs: 90000
    property bool keepLoaded: !Glass.lazyPanels
    property bool fullscreen: false

    readonly property Item loaded: loader.item ? (loader.item.panel ?? loader.item) : null

    x: loaded ? loaded.x : 0
    y: loaded ? loaded.y : 0
    width: loaded ? loaded.width : 0
    height: loaded ? loaded.height : 0
    implicitWidth: loaded ? loaded.implicitWidth : 0
    implicitHeight: loaded ? loaded.implicitHeight : 0
    visible: loaded ? loaded.visible : false

    // Propriétés de morphing / verre lues par ContentWindow.qml et Regions.qml
    readonly property real curX: loaded && loaded.curX !== undefined ? loaded.curX : 0
    readonly property real curW: loaded && loaded.curW !== undefined ? loaded.curW : 0
    readonly property real curTop: loaded && loaded.curTop !== undefined ? loaded.curTop : -400
    readonly property real curBottom: loaded && loaded.curBottom !== undefined ? loaded.curBottom : -400
    readonly property real curR: loaded && loaded.curR !== undefined ? loaded.curR : 19
    readonly property real fromBottom: loaded && loaded.fromBottom !== undefined ? loaded.fromBottom : 38
    readonly property real morph: loaded && loaded.morph !== undefined ? loaded.morph : 0
    readonly property real offsetScale: loaded && loaded.offsetScale !== undefined ? loaded.offsetScale : 1
    readonly property real blobHeight: loaded && loaded.blobHeight !== undefined ? loaded.blobHeight : 0
    readonly property real reveal: loaded && loaded.reveal !== undefined ? loaded.reveal : 0

    onKeepLoadedChanged: {
        if (keepLoaded) {
            unloadTimer.stop();
            loader.active = true;
        } else if (!wantOpen && !visible && loader.active && unloadDelayMs > 0) {
            unloadTimer.restart();
        }
    }

    onWantOpenChanged: {
        if (wantOpen) {
            unloadTimer.stop();
            loader.active = true;
        } else if (!keepLoaded && !visible && unloadDelayMs > 0) {
            unloadTimer.restart();
        }
    }

    onVisibleChanged: {
        if (!visible && !wantOpen && !keepLoaded && loader.active && unloadDelayMs > 0)
            unloadTimer.restart();
        else if (visible)
            unloadTimer.stop();
    }

    Timer {
        id: unloadTimer

        interval: root.unloadDelayMs
        onTriggered: {
            if (!root.wantOpen && !root.visible && !root.keepLoaded)
                loader.active = false;
        }
    }

    Loader {
        id: loader

        parent: root.host
        anchors.fill: parent
        active: root.wantOpen || root.keepLoaded
        sourceComponent: root.sourceComponent
    }
}

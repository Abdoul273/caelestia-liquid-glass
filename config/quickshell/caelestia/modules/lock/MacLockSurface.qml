pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.components.images
import qs.services
import qs.utils

// Écran de verrouillage façon macOS : fond d'écran net, date + grande horloge en haut,
// musique et notifications en cartes de verre, avatar + champ de mot de passe en bas.
// La vérification du mot de passe reste dans Pam.qml (inchangée).
WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam

    readonly property alias unlocking: unlockAnim.running
    readonly property bool typing: pam.buffer.length > 0 || pam.passwd.active
    // Activité récente (souris, clavier) : le fond se floute et le champ s'éclaire, comme sur macOS
    property bool active: true
    readonly property MprisPlayer player: Players.active
    readonly property bool hasMedia: !!player && (player.trackTitle ?? "") !== ""
    // Notifications groupées par app (la plus récente devant, le nombre en pile)
    readonly property list<var> notifGroups: {
        const groups = [];
        const byApp = {};
        for (const n of Notifs.notClosed.slice().reverse()) {
            const key = n.appName || "?";
            if (byApp[key]) {
                byApp[key].count++;
                continue;
            }
            byApp[key] = {
                n: n,
                count: 1
            };
            groups.push(byApp[key]);
        }
        return groups;
    }
    readonly property real s: Math.min(1, (screen?.height ?? 1080) / 1080) // échelle

    readonly property color fg: "white"
    readonly property color fgDim: Qt.rgba(1, 1, 1, 0.72)

    contentItem.Config.screen: screen?.name ?? ""
    contentItem.Tokens.screen: screen?.name ?? ""

    color: "black"

    function poke(): void {
        active = true;
        idleTimer.restart();
    }

    Timer {
        id: idleTimer

        interval: 12000
        running: true
        onTriggered: {
            if (!root.typing)
                root.active = false;
        }
    }

    Connections {
        target: root.lock

        function onUnlock(): void {
            unlockAnim.start();
        }
    }

    // Mauvais mot de passe : le champ secoue la tête
    Connections {
        target: root.pam

        function onFlashMsg(): void {
            if (root.pam.state === Pam.Failed || root.pam.state === Pam.MaxTries)
                shake.restart();
        }
    }

    // ── Apparition ──
    ParallelAnimation {
        running: true

        NumberAnimation {
            target: scene
            property: "opacity"
            from: 0
            to: 1
            duration: 420
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: wallpaper
            property: "scale"
            from: 1.08
            to: 1
            duration: 900
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: top
            property: "offset"
            from: -40
            to: 0
            duration: 700
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: bottom
            property: "offset"
            from: 40
            to: 0
            duration: 700
            easing.type: Easing.OutCubic
        }
    }

    // ── Déverrouillage : le bureau réapparaît en fondu, le fond s'agrandit légèrement ──
    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            NumberAnimation {
                target: ui
                property: "opacity"
                to: 0
                duration: 220
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: ui
                property: "scale"
                to: 0.96
                duration: 260
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: wallpaper
                property: "scale"
                to: 1.06
                duration: 420
                easing.type: Easing.InOutCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 120
                }
                NumberAnimation {
                    target: scene
                    property: "opacity"
                    to: 0
                    duration: 320
                    easing.type: Easing.InOutCubic
                }
            }
        }
        PropertyAction {
            target: root.lock
            property: "locked"
            value: false
        }
    }

    Item {
        id: scene

        anchors.fill: parent
        opacity: 0

        // Fond d'écran net ; il se floute quand on tape ou qu'on bouge la souris
        Item {
            id: wallpaper

            anchors.fill: parent

            CachingImage {
                id: wallImg

                anchors.fill: parent
                path: Wallpapers.current
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: wallImg
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: root.active || root.typing ? 0.55 : 0
                brightness: root.active || root.typing ? -0.08 : 0

                Behavior on blur {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on brightness {
                    NumberAnimation {
                        duration: 600
                    }
                }
            }

            // Voile léger en haut et en bas pour la lisibilité
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.rgba(0, 0, 0, 0.32)
                    }
                    GradientStop {
                        position: 0.35
                        color: Qt.rgba(0, 0, 0, 0.05)
                    }
                    GradientStop {
                        position: 0.7
                        color: Qt.rgba(0, 0, 0, 0.05)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: root.poke()
            onClicked: {
                root.poke();
                keys.forceActiveFocus();
            }
        }

        Item {
            id: ui

            anchors.fill: parent
            transformOrigin: Item.Center

            // ════════ Barre d'état, en haut à droite ════════
            Row {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 18 * root.s
                anchors.rightMargin: 26 * root.s
                spacing: 16

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Hypr.kbLayout !== ""
                    text: Hypr.kbLayout.toUpperCase()
                    color: root.fgDim
                    font.pointSize: 10
                    font.weight: Font.DemiBold
                }

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Nmcli.active !== null
                    text: Nmcli.active ? (Nmcli.active.strength > 66 ? "wifi" : Nmcli.active.strength > 33 ? "wifi_2_bar" : "wifi_1_bar") : "wifi_off"
                    color: root.fg
                    fontStyle: Tokens.font.icon.size(15).build()
                    fill: 1
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: UPower.displayDevice.isLaptopBattery
                    spacing: 6

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${Math.round((UPower.displayDevice.percentage ?? 0) * 100)} %`
                        color: root.fg
                        font.pointSize: 10
                        font.weight: Font.DemiBold
                        font.features: {
                            "tnum": 1
                        }
                    }

                    // Batterie : blanc, vert en charge, rouge sous 20 %
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 27
                        height: 13

                        readonly property real pct: UPower.displayDevice.percentage ?? 0
                        readonly property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging

                        Rectangle {
                            width: 24
                            height: 13
                            radius: 4
                            color: "transparent"
                            border.width: 1.3
                            border.color: Qt.rgba(1, 1, 1, 0.6)

                            Rectangle {
                                x: 2
                                y: 2
                                height: parent.height - 4
                                width: Math.max(2, (parent.width - 4) * parent.parent.pct)
                                radius: 2
                                antialiasing: true
                                color: parent.parent.charging ? "#32d74b" : parent.parent.pct < 0.2 ? "#ff453a" : "white"
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: parent.parent.charging
                                text: "bolt"
                                color: "white"
                                style: Text.Outline
                                styleColor: Qt.rgba(0, 0, 0, 0.3)
                                fontStyle: Tokens.font.icon.size(9).build()
                                fill: 1
                            }
                        }
                        Rectangle {
                            x: 25
                            y: 4.5
                            width: 2
                            height: 4
                            radius: 1
                            color: Qt.rgba(1, 1, 1, 0.6)
                        }
                    }
                }
            }

            // ════════ Date + grande horloge ════════
            Column {
                id: top

                property real offset: 0

                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.085 + offset
                spacing: -6 * root.s

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        const d = Qt.locale("fr_FR").toString(Time.date, "dddd d MMMM");
                        return d.charAt(0).toUpperCase() + d.slice(1);
                    }
                    color: root.fg
                    opacity: 0.92
                    font.pointSize: 19 * root.s
                    font.weight: Font.DemiBold
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.15)
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Time.format("HH:mm")
                    color: root.fg
                    opacity: 0.95
                    font.pointSize: 92 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: -2
                    font.features: {
                        "tnum": 1
                    }
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.12)
                }
            }

            // ════════ Musique + notifications (cartes de verre) ════════
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: top.y + top.height + 26 * root.s
                width: Math.min(420 * root.s + 20, parent.width - 60)
                spacing: 10

                // Lecture en cours
                GlassCard {
                    width: parent.width
                    height: 84
                    visible: root.hasMedia

                    ClippingRectangle {
                        id: art

                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 60
                        height: 60
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.12)

                        Image {
                            anchors.fill: parent
                            source: root.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(120, 120)
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: !(root.player?.trackArtUrl ?? "")
                            text: "music_note"
                            color: root.fgDim
                            fontStyle: Tokens.font.icon.size(22).build()
                            fill: 1
                        }
                    }

                    Column {
                        anchors.left: art.right
                        anchors.leftMargin: 14
                        anchors.right: mediaButtons.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.player?.trackTitle ?? ""
                            color: root.fg
                            font.pointSize: 11
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.player?.trackArtist ?? ""
                            color: root.fgDim
                            font.pointSize: 9.5
                        }
                    }

                    Row {
                        id: mediaButtons

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        RoundBtn {
                            icon: "skip_previous"
                            enabled: root.player?.canGoPrevious ?? false
                            onClicked: root.player?.previous()
                        }
                        RoundBtn {
                            icon: root.player?.isPlaying ? "pause" : "play_arrow"
                            big: true
                            onClicked: root.player?.togglePlaying()
                        }
                        RoundBtn {
                            icon: "skip_next"
                            enabled: root.player?.canGoNext ?? false
                            onClicked: root.player?.next()
                        }
                    }
                }

                // Notifications (les plus récentes, contenu discret)
                Repeater {
                    model: root.notifGroups.slice(0, 3)

                    Item {
                        id: group

                        required property var modelData
                        required property int index

                        width: parent.width
                        height: 62 + (modelData.count > 1 ? 8 : 0)
                        opacity: 1 - index * 0.12

                        // Pile : une carte plus étroite dépasse en dessous
                        GlassCard {
                            visible: group.modelData.count > 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            width: parent.width - 24
                            height: 62
                            opacity: 0.6
                        }

                        GlassCard {
                            id: card

                            readonly property var modelData: group.modelData.n

                            width: parent.width
                            height: 62

                            ClippingRectangle {
                                id: nIcon

                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 34
                                radius: 9
                                color: Qt.rgba(1, 1, 1, 0.14)

                                IconImage {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    source: Quickshell.iconPath(card.modelData.appIcon || card.modelData.appName?.toLowerCase() || "", "dialog-information")
                                    asynchronous: true
                                }
                            }

                            Column {
                                anchors.left: nIcon.right
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Item {
                                    width: parent.width
                                    height: nApp.height

                                    StyledText {
                                        id: nApp

                                        anchors.left: parent.left
                                        anchors.right: nTime.left
                                        anchors.rightMargin: 8
                                        elide: Text.ElideRight
                                        text: card.modelData.appName || qsTr("Notification")
                                        color: root.fgDim
                                        font.pointSize: 8.5
                                        font.weight: Font.DemiBold
                                        font.capitalization: Font.AllUppercase
                                    }
                                    StyledText {
                                        id: nTime

                                        anchors.right: parent.right
                                        text: (group.modelData.count > 1 ? qsTr("%1 notifications · ").arg(group.modelData.count) : "") + Qt.formatTime(card.modelData.time, "HH:mm")
                                        color: root.fgDim
                                        font.pointSize: 8.5
                                    }
                                }
                                StyledText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: card.modelData.summary || card.modelData.body || ""
                                    color: root.fg
                                    font.pointSize: 10
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.notifGroups.length > 3
                    text: qsTr("+ %1 autres apps").arg(root.notifGroups.length - 3)
                    color: root.fgDim
                    font.pointSize: 9
                    font.weight: Font.Medium
                }
            }

            // ════════ Avatar, nom et mot de passe ════════
            Column {
                id: bottom

                property real offset: 0

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.height * 0.075 - offset
                spacing: 12

                // Avatar
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 76 * root.s
                    height: width

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(1, 1, 1, 0.16)
                        border.width: 2
                        border.color: Qt.rgba(1, 1, 1, 0.3)

                        CachingImage {
                            id: face

                            anchors.fill: parent
                            path: `${Paths.home}/.face`
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: "person"
                            color: root.fg
                            fontStyle: Tokens.font.icon.size(32 * root.s).build()
                            fill: 1
                        }
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        const n = Quickshell.env("USER") ?? "";
                        return n.charAt(0).toUpperCase() + n.slice(1);
                    }
                    color: root.fg
                    font.pointSize: 13 * Math.max(0.9, root.s)
                    font.weight: Font.Bold
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.15)
                }

                // Champ de mot de passe (verre)
                Item {
                    id: field

                    property real shakeX: 0

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 250 * Math.max(0.9, root.s)
                    height: 38
                    transform: Translate {
                        x: field.shakeX
                    }

                    GlassCard {
                        anchors.fill: parent
                        radius: height / 2
                        strong: root.active || root.typing
                    }

                    // Texte d'aide
                    StyledText {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -10
                        visible: !root.typing
                        text: root.pam.state === Pam.MaxTries ? qsTr("Trop de tentatives") : root.pam.fprint.active ? qsTr("Empreinte ou mot de passe") : root.pam.howdy.canAttempt ? qsTr("Visage ou mot de passe") : qsTr("Saisir le mot de passe")
                        color: root.fgDim
                        font.pointSize: 9.5
                    }

                    // Points des caractères saisis
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.right: enter.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        clip: true
                        visible: root.pam.buffer.length > 0 && !root.pam.passwd.active

                        Repeater {
                            model: Math.min(root.pam.buffer.length, 24)

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: "white"
                                anchors.verticalCenter: parent?.verticalCenter

                                NumberAnimation on scale {
                                    from: 0
                                    to: 1
                                    duration: 160
                                    easing.type: Easing.OutBack
                                }
                            }
                        }
                    }

                    // Vérification en cours
                    Row {
                        anchors.centerIn: parent
                        visible: root.pam.passwd.active
                        spacing: 6

                        Repeater {
                            model: 3

                            Rectangle {
                                id: waitDot

                                required property int index

                                width: 7
                                height: 7
                                radius: 3.5
                                color: "white"

                                SequentialAnimation on opacity {
                                    running: root.pam.passwd.active
                                    loops: Animation.Infinite
                                    PauseAnimation {
                                        duration: waitDot.index * 140
                                    }
                                    NumberAnimation {
                                        to: 0.25
                                        duration: 360
                                    }
                                    NumberAnimation {
                                        to: 1
                                        duration: 360
                                    }
                                }
                            }
                        }
                    }

                    // Bouton valider
                    Rectangle {
                        id: enter

                        anchors.right: parent.right
                        anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        radius: 14
                        color: "transparent"
                        // Verre liquide (iOS 27) sous le contenu
                        GlassControl {
                            anchors.fill: parent
                            radius: parent.radius
                            bevel: parent.height > 60 ? 16 : 0
                            tintColour: enterArea.containsMouse ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.22)
                            visible: tintColour.a > 0.01
                            pressed: enterArea.pressed
                            hovered: enterArea.containsMouse
                            pointer: enterArea.containsMouse ? Qt.point(enterArea.mouseX / Math.max(1, width), enterArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
                        }
                        opacity: root.pam.buffer.length > 0 && !root.pam.passwd.active ? 1 : 0
                        scale: opacity > 0 ? (enterArea.pressed ? 0.9 : 1) : 0.6

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 180
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutBack
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "arrow_forward"
                            color: "white"
                            fontStyle: Tokens.font.icon.size(15).build()
                        }
                        MouseArea {
                            id: enterArea

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.opacity > 0.5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pam.passwd.start()
                        }
                    }

                    SequentialAnimation {
                        id: shake

                        NumberAnimation {
                            target: field
                            property: "shakeX"
                            to: -14
                            duration: 55
                        }
                        NumberAnimation {
                            target: field
                            property: "shakeX"
                            to: 12
                            duration: 70
                        }
                        NumberAnimation {
                            target: field
                            property: "shakeX"
                            to: -8
                            duration: 65
                        }
                        NumberAnimation {
                            target: field
                            property: "shakeX"
                            to: 5
                            duration: 60
                        }
                        NumberAnimation {
                            target: field
                            property: "shakeX"
                            to: 0
                            duration: 55
                        }
                    }
                }

                // Message : erreur, Verr. Maj, disposition du clavier
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, 420)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: {
                        const p = root.pam;
                        if (p.lockMessage)
                            return p.lockMessage;
                        if (p.state === Pam.Failed)
                            return qsTr("Mot de passe incorrect");
                        if (p.state === Pam.MaxTries)
                            return qsTr("Trop de tentatives, patientez un instant");
                        if (p.state === Pam.Error)
                            return qsTr("Erreur : %1").arg(p.passwd.message);
                        if (Hypr.capsLock)
                            return qsTr("⇪ Verrouillage majuscule activé");
                        return "";
                    }
                    color: root.pam.state === Pam.Failed || root.pam.state === Pam.MaxTries || root.pam.state === Pam.Error ? "#ff8a80" : root.fgDim
                    opacity: text ? 1 : 0
                    font.pointSize: 9.5
                    font.weight: Font.Medium

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }
            }
        }
    }

    // Clavier : tout va au mot de passe (comme avant)
    Item {
        id: keys

        anchors.fill: parent
        focus: true
        Component.onCompleted: forceActiveFocus()
        onActiveFocusChanged: {
            if (!activeFocus)
                forceActiveFocus();
        }

        Keys.onPressed: event => {
            if (root.unlocking)
                return;
            root.poke();
            if (event.key === Qt.Key_Escape) {
                root.pam.buffer = "";
                return;
            }
            root.pam.handleKey(event);
        }
    }

    // ── Carte de verre (sans shader : légère et nette) ──
    component GlassCard: Rectangle {
        property bool strong

        radius: 20
        color: Qt.rgba(1, 1, 1, strong ? 0.2 : 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)

        Behavior on color {
            ColorAnimation {
                duration: 300
            }
        }

        // Reflet en haut
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, 0.1)
                }
                GradientStop {
                    position: 0.5
                    color: "transparent"
                }
            }
        }
    }

    component RoundBtn: Rectangle {
        id: rb

        property string icon
        property bool big
        signal clicked

        width: big ? 38 : 32
        height: width
        radius: width / 2
        color: "transparent"
        // Verre liquide (iOS 27) sous le contenu
        GlassControl {
            anchors.fill: parent
            radius: parent.radius
            bevel: parent.height > 60 ? 16 : 0
            tintColour: rbArea.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
            visible: tintColour.a > 0.01
            pressed: rbArea.pressed
            hovered: rbArea.containsMouse
            pointer: rbArea.containsMouse ? Qt.point(rbArea.mouseX / Math.max(1, width), rbArea.mouseY / Math.max(1, height)) : Qt.point(-1, -1)
        }
        opacity: enabled ? 1 : 0.4
        scale: rbArea.pressed ? 0.9 : 1

        MaterialIcon {
            anchors.centerIn: parent
            text: rb.icon
            color: "white"
            fontStyle: Tokens.font.icon.size(rb.big ? 22 : 17).build()
            fill: 1
        }
        MouseArea {
            id: rbArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rb.clicked()
        }
    }
}

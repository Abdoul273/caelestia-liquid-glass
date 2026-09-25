// Écran de connexion « Liquid Glass » façon macOS pour SDDM (Qt 6)
// Repos : fond d'écran net + grande horloge.
// Actif (touche ou souris) : fond flouté, photo, mot de passe en verre.

import QtQuick
import QtQuick.Effects

Item {
    id: root

    width: 1920
    height: 1080

    readonly property var fr: Qt.locale("fr_FR")
    readonly property string fontFamily: "Rubik"
    property bool active: false
    property bool busy: false
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0

    // Utilisateur et session courants (lus via des listes invisibles)
    readonly property string userName: users.currentItem && users.currentItem.uName ? users.currentItem.uName : userModel.lastUser
    readonly property string userReal: users.currentItem && users.currentItem.uReal ? users.currentItem.uReal : userName
    readonly property string userIcon: users.currentItem ? users.currentItem.uIcon : ""
    readonly property string sessionName: sessions.currentItem ? sessions.currentItem.sName : ""

    function wake() {
        active = true;
        idleTimer.restart();
        password.forceActiveFocus();
    }

    function tryLogin() {
        if (busy)
            return;
        busy = true;
        message.text = "";
        sddm.login(userName, password.text, sessionIndex);
    }

    ListView {
        id: users

        visible: false
        model: userModel
        currentIndex: root.userIndex
        delegate: Item {
            property string uName: model.name
            property string uReal: model.realName
            property string uIcon: model.icon
        }
    }

    ListView {
        id: sessions

        visible: false
        model: sessionModel
        currentIndex: root.sessionIndex
        delegate: Item {
            property string sName: model.name
        }
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.busy = false;
            password.text = "";
            message.text = "Mot de passe incorrect";
            shake.restart();
            password.forceActiveFocus();
        }

        function onLoginSucceeded() {
            fadeOut.start();
        }

        function onInformationMessage(msg) {
            message.text = msg;
        }
    }

    Timer {
        id: idleTimer

        interval: (parseInt(config.idleTimeout) || 45) * 1000
        onTriggered: {
            if (password.text.length === 0 && !root.busy)
                root.active = false;
        }
    }

    // ------------------------------------------------------------ fond

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#1b1f2e" }
            GradientStop { position: 1; color: "#0b0d14" }
        }
    }

    Image {
        id: wallpaper

        anchors.fill: parent
        source: config.background ? "file://" + config.background : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready
        blurEnabled: true
        blurMax: 64
        blur: root.active ? 0.9 : 0
        brightness: root.active ? -0.12 : -0.04
        saturation: root.active ? 0.15 : 0

        Behavior on blur { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
        Behavior on brightness { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
    }

    // Léger voile pour la lisibilité de l'horloge
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.30) }
        }
    }

    // ------------------------------------------------------------ interactions

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: if (!root.active) root.wake()
        onClicked: root.wake()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.active = false;
            password.text = "";
            event.accepted = true;
            return;
        }
        if (!root.active) {
            root.wake();
            // La première touche tapée n'est pas perdue
            if (event.text.trim().length > 0)
                password.text += event.text;
            event.accepted = true;
        }
    }

    focus: true
    Component.onCompleted: forceActiveFocus()

    // ------------------------------------------------------------ horloge

    Column {
        id: clock

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.active ? root.height * 0.07 : root.height * 0.13
        scale: root.active ? 0.62 : 1
        spacing: 0

        Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }

        property var now: new Date()

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.now = new Date()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                const s = clock.now.toLocaleDateString(root.fr, "dddd d MMMM");
                return s.charAt(0).toUpperCase() + s.slice(1);
            }
            color: Qt.rgba(1, 1, 1, 0.9)
            font.family: root.fontFamily
            font.pixelSize: 26
            font.weight: Font.Medium
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.now.toLocaleTimeString(root.fr, "HH:mm")
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 132
            font.weight: Font.DemiBold
            font.letterSpacing: -2
        }
    }

    // ------------------------------------------------------------ connexion

    Column {
        id: login

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.36 + (root.active ? 0 : 40)
        spacing: 16
        opacity: root.active ? 1 : 0
        visible: opacity > 0
        scale: root.active ? 1 : 0.94

        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

        // Photo de profil ronde avec un anneau de verre
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 124
            height: 124

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1.5
                border.color: Qt.rgba(1, 1, 1, 0.45)
            }

            Image {
                id: avatar

                anchors.fill: parent
                anchors.margins: 4
                source: {
                    if (root.userIcon && root.userIcon.indexOf("liveuser") < 0)
                        return "file://" + root.userIcon;
                    return config.avatar ? "file://" + config.avatar : "";
                }
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(240, 240)
                visible: false
                layer.enabled: true
            }

            Rectangle {
                id: avatarMask

                anchors.fill: avatar
                radius: width / 2
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: avatar
                source: avatar
                maskEnabled: true
                maskSource: avatarMask
                visible: avatar.status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: avatar.status !== Image.Ready
                text: root.userReal.charAt(0).toUpperCase()
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: 52
                font.weight: Font.DemiBold
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userReal
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }

        // Champ mot de passe en verre
        Item {
            id: field

            anchors.horizontalCenter: parent.horizontalCenter
            width: 280
            height: 44

            SequentialAnimation {
                id: shake

                loops: 1
                NumberAnimation { target: fieldInner; property: "x"; to: -14; duration: 60 }
                NumberAnimation { target: fieldInner; property: "x"; to: 12; duration: 70 }
                NumberAnimation { target: fieldInner; property: "x"; to: -8; duration: 70 }
                NumberAnimation { target: fieldInner; property: "x"; to: 5; duration: 70 }
                NumberAnimation { target: fieldInner; property: "x"; to: 0; duration: 80 }
            }

            Rectangle {
                id: fieldInner

                width: parent.width
                height: parent.height
                radius: height / 2
                color: message.text === "Mot de passe incorrect" ? Qt.rgba(1, 0.35, 0.35, 0.18) : Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                border.color: password.activeFocus ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.28)

                Behavior on color { ColorAnimation { duration: 250 } }

                // Reflet en haut, comme une plaque de verre
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.12) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }

                TextInput {
                    id: password

                    anchors.left: parent.left
                    anchors.right: go.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 20
                    anchors.rightMargin: 8
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: "white"
                    selectionColor: Qt.rgba(1, 1, 1, 0.3)
                    font.family: root.fontFamily
                    font.pixelSize: 16
                    font.letterSpacing: 2
                    clip: true
                    enabled: !root.busy
                    onAccepted: root.tryLogin()
                    onTextChanged: idleTimer.restart()
                    Keys.onEscapePressed: {
                        root.active = false;
                        text = "";
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: password.text.length === 0
                        text: "Mot de passe"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: root.fontFamily
                        font.pixelSize: 15
                    }
                }

                // Bouton flèche, comme sur macOS
                Rectangle {
                    id: go

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 6
                    width: 32
                    height: 32
                    radius: 16
                    color: goArea.containsMouse ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.2)
                    opacity: password.text.length > 0 || root.busy ? 1 : 0
                    scale: opacity

                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: root.busy ? "…" : "→"
                        color: "white"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: goArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tryLogin()
                    }
                }
            }
        }

        Text {
            id: message

            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            color: "#ffb4ab"
            font.family: root.fontFamily
            font.pixelSize: 14
            height: 18
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: keyboard.capsLock
            text: "⇪ Majuscules activées"
            color: Qt.rgba(1, 1, 1, 0.7)
            font.family: root.fontFamily
            font.pixelSize: 13
        }
    }

    // Invitation discrète au repos
    Item {
        anchors.fill: parent
        opacity: root.active ? 0 : 1
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 300 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 70
            text: "Appuie sur une touche pour te connecter"
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 15

            SequentialAnimation on opacity {
                running: !root.active
                loops: Animation.Infinite
                NumberAnimation { to: 0.8; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.35; duration: 1600; easing.type: Easing.InOutSine }
            }
        }
    }

    // ------------------------------------------------------------ barre du bas

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 42
        spacing: 26
        opacity: root.active ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 380 } }

        // Session (Hyprland…) : un clic passe à la suivante
        GlassButton {
            visible: sessionModel.rowCount() > 1
            icon: "󰍹"
            label: root.sessionName
            onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessionModel.rowCount()
        }

        GlassButton {
            visible: sddm.canSuspend
            icon: "󰒲"
            label: "Veille"
            onClicked: sddm.suspend()
        }

        GlassButton {
            visible: sddm.canReboot
            icon: "󰜉"
            label: "Redémarrer"
            onClicked: sddm.reboot()
        }

        GlassButton {
            visible: sddm.canPowerOff
            icon: "󰐥"
            label: "Éteindre"
            onClicked: sddm.powerOff()
        }
    }

    // Disposition du clavier en haut à droite
    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 28
        visible: root.active && keyboard.layouts.length > 1
        text: keyboard.layouts.length > 0 ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
        color: Qt.rgba(1, 1, 1, 0.8)
        font.family: root.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    // Fondu vers le bureau après une connexion réussie
    Rectangle {
        id: blackout

        anchors.fill: parent
        color: "black"
        opacity: 0

        NumberAnimation on opacity {
            id: fadeOut

            running: false
            to: 1
            duration: 400
        }
    }

    component GlassButton: Item {
        id: btn

        property string icon
        property string label
        signal clicked

        width: Math.max(64, caption.implicitWidth)
        height: 76

        Rectangle {
            id: disc

            anchors.horizontalCenter: parent.horizontalCenter
            width: 46
            height: 46
            radius: 23
            color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.14)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.3)
            scale: area.pressed ? 0.92 : 1

            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: btn.icon
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
            }
        }

        Text {
            id: caption

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: btn.label
            color: Qt.rgba(1, 1, 1, 0.85)
            font.family: root.fontFamily
            font.pixelSize: 12
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}

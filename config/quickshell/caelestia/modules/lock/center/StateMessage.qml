pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.lock

Item {
    id: root

    required property Pam pam

    readonly property string msg: {
        // Errors
        if (pam.fprint.state === Pam.Error)
            return qsTr("ERREUR EMPREINTE : %1").arg(pam.fprint.message);
        if (pam.howdy.state === Pam.Error)
            return qsTr("ERREUR VISAGE : %1").arg(pam.howdy.message);
        if (pam.state === Pam.Error)
            return qsTr("ERREUR MDP : %1").arg(pam.passwd.message);

        // Fprint/howdy fail
        if (pam.state !== Pam.MaxTries) {
            if (pam.fprint.state === Pam.Failed)
                return qsTr("Empreinte non reconnue (%1/%2). Réessayez ou utilisez votre mot de passe.").arg(pam.fprint.tries).arg(GlobalConfig.lock.maxFprintTries);
            if (pam.howdy.state === Pam.Failed)
                return qsTr("Visage non reconnu (%1/%2). Réessayez ou utilisez votre mot de passe.").arg(pam.howdy.tries).arg(GlobalConfig.lock.maxHowdyTries);
        } else {
            if (pam.fprint.state === Pam.Failed)
                return qsTr("Empreinte non reconnue (%1/%2). Veuillez réessayer.").arg(pam.fprint.tries).arg(GlobalConfig.lock.maxFprintTries);
            if (pam.howdy.state === Pam.Failed)
                return qsTr("Visage non reconnu (%1/%2). Veuillez réessayer.").arg(pam.howdy.tries).arg(GlobalConfig.lock.maxHowdyTries);
        }

        if (pam.lockMessage) // Password max tries message
            return pam.lockMessage;

        // Password fail
        if (pam.state === Pam.Failed) {
            if (pam.fprint.available && pam.fprint.state !== Pam.MaxTries)
                return qsTr("Mot de passe incorrect. Réessayez ou utilisez l'empreinte.");
            if (pam.howdy.available && pam.howdy.state !== Pam.MaxTries)
                return qsTr("Mot de passe incorrect. Réessayez ou utilisez la reconnaissance faciale.");
            return qsTr("Mot de passe incorrect. Veuillez réessayer.");
        }

        // Maxed out
        if (pam.state === Pam.MaxTries) {
            if (pam.fprint.available && pam.fprint.state !== Pam.MaxTries)
                return qsTr("Tentatives de mot de passe épuisées. Utilisez votre empreinte.");
            if (pam.howdy.available && pam.howdy.state !== Pam.MaxTries)
                return qsTr("Tentatives de mot de passe épuisées. Utilisez la reconnaissance faciale.");
            if (pam.fprint.available || pam.howdy.available)
                return qsTr("Nombre maximal de tentatives atteint pour tous les modes d'authentification.");
            return qsTr("Nombre maximal de tentatives de mot de passe atteint.");
        }
        if (pam.fprint.state === Pam.MaxTries)
            return qsTr("Tentatives d'empreinte épuisées. Utilisez votre mot de passe.");
        if (pam.howdy.state === Pam.MaxTries)
            return qsTr("Tentatives faciales épuisées. Utilisez votre mot de passe.");

        return "";
    }

    readonly property string stateMsg: {
        if (Hypr.kbLayout !== Hypr.defaultKbLayout) {
            if (Hypr.capsLock && Hypr.numLock)
                return qsTr("Verr. Maj et Verr. Num sont activés.\nDisposition du clavier : %1").arg(Hypr.kbLayoutFull);
            if (Hypr.capsLock)
                return qsTr("Verr. Maj activé. Disposition : %1").arg(Hypr.kbLayoutFull);
            if (Hypr.numLock)
                return qsTr("Verr. Num activé. Disposition : %1").arg(Hypr.kbLayoutFull);
            return qsTr("Disposition du clavier : %1").arg(Hypr.kbLayoutFull);
        }

        if (Hypr.capsLock && Hypr.numLock)
            return qsTr("Verr. Maj et Verr. Num sont activés.");
        if (Hypr.capsLock)
            return qsTr("Verrouillage majuscule activé.");
        if (Hypr.numLock)
            return qsTr("Pavé numérique activé.");

        return "";
    }

    property bool stateMsgShouldBeVisible

    onMsgChanged: {
        if (msg) {
            if (message.opacity > 0) {
                message.animate = true;
                message.text = msg;
                message.animate = false;

                exitAnim.stop();
                if (message.scale < 1)
                    appearAnim.restart();
                else
                    flashAnim.restart();
            } else {
                message.text = msg;
                exitAnim.stop();
                appearAnim.restart();
            }
        } else {
            appearAnim.stop();
            flashAnim.stop();
            exitAnim.start();
        }
    }

    onStateMsgChanged: {
        if (stateMsg) {
            if (stateMessage.opacity > 0) {
                stateMessage.animate = true;
                stateMessage.text = stateMsg;
                stateMessage.animate = false;
            } else {
                stateMessage.text = stateMsg;
            }
            stateMsgShouldBeVisible = true;
        } else {
            stateMsgShouldBeVisible = false;
        }
    }

    implicitHeight: Math.max(message.implicitHeight, stateMessage.implicitHeight)

    Behavior on implicitHeight {
        Anim {}
    }

    StyledText {
        id: stateMessage

        anchors.left: parent.left
        anchors.right: parent.right

        scale: root.stateMsgShouldBeVisible && !root.msg ? 1 : 0.7
        opacity: root.stateMsgShouldBeVisible && !root.msg ? 1 : 0
        color: Colours.palette.m3onSurfaceVariant

        font: Tokens.font.body.small
        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        lineHeight: 1.2

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledText {
        id: message

        anchors.left: parent.left
        anchors.right: parent.right

        scale: 0.7
        opacity: 0
        color: Colours.palette.m3error

        font: Tokens.font.body.small
        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere

        Connections {
            function onFlashMsg(): void {
                exitAnim.stop();
                if (message.scale < 1)
                    appearAnim.restart();
                else
                    flashAnim.restart();
            }

            target: root.pam
        }

        Anim {
            id: appearAnim

            type: Anim.DefaultEffects
            target: message
            properties: "scale,opacity"
            to: 1
            onFinished: flashAnim.restart()
        }

        SequentialAnimation {
            id: flashAnim

            loops: 2

            FlashAnim {
                to: 0.3
            }
            FlashAnim {
                to: 1
            }
        }

        ParallelAnimation {
            id: exitAnim

            Anim {
                target: message
                property: "scale"
                to: 0.7
                type: Anim.StandardLarge
            }
            Anim {
                target: message
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
        }
    }

    component FlashAnim: NumberAnimation {
        target: message
        property: "opacity"
        duration: Tokens.anim.durations.small
        easing.type: Easing.Linear
    }
}

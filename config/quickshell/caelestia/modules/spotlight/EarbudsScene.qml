pragma ComponentBehavior: Bound

import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "../../assets/earbuds/earbuds-model.js" as M

// Scène 3D temps réel des écouteurs (boîtier galet + écouteur gauche BX012 + écouteur droit CETW572),
// inspirée de AirPodsDesktop : rotation fluide 60 fps, ouverture de la charnière au ressort,
// lévitation et LEDs indépendantes pour chaque écouteur selon qu'il est connecté ou rangé.
Item {
    id: root

    property bool active: false
    property bool leftConnected: false
    property bool rightConnected: false
    readonly property bool connected: leftConnected || rightConnected
    property real lidOpen: 1
    property real leftLift: 0
    property real rightLift: 0
    property real pitch: 22
    property real yaw: 0
    property bool dragging: false
    property color accentColor: "#38bdf8"

    // Convertit un tableau plat [x, y, z, ...] en liste de vector3d pour ProceduralMesh
    function toVec3List(arr: var): list<vector3d> {
        const out = [];
        if (!arr)
            return out;
        for (let i = 0; i < arr.length; i += 3)
            out.push(Qt.vector3d(arr[i], arr[i + 1], arr[i + 2]));
        return out;
    }

    function buildMesh(meshObj: ProceduralMesh, key: string): void {
        const d = M.meshes[key];
        if (!d)
            return;
        meshObj.positions = toVec3List(d.p);
        meshObj.normals = toVec3List(d.n);
        meshObj.indexes = d.i;
    }

    // Batterie faible : la LED de l'écouteur passe à l'orange / rouge
    property int leftPct: 100
    property int rightPct: 100

    // ── Moteur d'animation physique (une seule horloge pour tout) ──
    // Rotation à inertie : on lance le boîtier à la souris, il ralentit tout seul
    // jusqu'à la vitesse de repos ; respiration, LEDs et balancement des écouteurs
    // sont calculés à partir du même temps pour rester parfaitement synchrones.
    property real time: 0
    property real spinVel: idleSpeed
    readonly property real idleSpeed: 24
    property real dragVel: 0
    readonly property real floatY: Math.sin(time * 1.5) * 2.0
    readonly property real ledPulse: 0.72 + 0.28 * Math.sin(time * 2.6)
    readonly property real budSway: Math.sin(time * 1.25)
    property real caseScale: 1
    property real leftFlash: 0
    property real rightFlash: 0

    FrameAnimation {
        running: root.active
        onTriggered: {
            const dt = Math.min(0.05, frameTime);
            root.time += dt;
            if (root.dragging)
                return;
            root.spinVel += (root.idleSpeed - root.spinVel) * Math.min(1, dt * 1.4);
            root.yaw = (root.yaw + root.spinVel * dt) % 360;
        }
    }

    // Entrée en scène : le boîtier arrive en tourbillon, grossit au ressort puis se pose
    function playIntro(): void {
        yaw = -160;
        spinVel = 620;
        caseScale = 0.55;
        caseScale = 1;
    }

    Behavior on caseScale {
        SpringAnimation {
            spring: 3.2
            damping: 0.22
            epsilon: 0.002
        }
    }

    // Éclair de connexion : la LED flashe et l'écouteur fait un tour sur lui-même en sortant
    NumberAnimation {
        id: leftFlashAnim
        target: root
        property: "leftFlash"
        from: 1
        to: 0
        duration: 1400
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: rightFlashAnim
        target: root
        property: "rightFlash"
        from: 1
        to: 0
        duration: 1400
        easing.type: Easing.OutCubic
    }
    onLeftConnectedChanged: if (leftConnected) leftFlashAnim.restart()
    onRightConnectedChanged: if (rightConnected) rightFlashAnim.restart()

    function ledColor(pct: int): vector3d {
        if (pct < 20)
            return Qt.vector3d(1.0, 0.18, 0.12);
        if (pct < 40)
            return Qt.vector3d(1.0, 0.55, 0.05);
        return Qt.vector3d(0.35, 0.72, 1.0);
    }

    Behavior on lidOpen {
        SpringAnimation {
            spring: 3.4
            damping: 0.28
            epsilon: 0.002
        }
    }

    Behavior on leftLift {
        SpringAnimation {
            spring: 3.0
            damping: 0.29
            epsilon: 0.002
        }
    }

    Behavior on rightLift {
        SpringAnimation {
            spring: 3.0
            damping: 0.29
            epsilon: 0.002
        }
    }

    Behavior on pitch {
        SpringAnimation {
            spring: 4.5
            damping: 0.35
            epsilon: 0.01
        }
    }

    // Halo lumineux sous le boîtier
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: 190
        height: 36
        radius: 18
        color: Qt.alpha(root.connected ? "#32d74b" : root.accentColor, 0.16 * root.ledPulse)
        scale: 1 + 0.04 * (root.floatY / 2.2)
    }

    View3D {
        id: view

        anchors.fill: parent
        visible: root.active

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            lightProbe: Texture {
                textureData: ProceduralSkyTextureData {
                    sunEnergy: 0.9
                    groundBottomColor: Qt.rgba(0.05, 0.06, 0.09, 1)
                    groundHorizonColor: Qt.rgba(0.14, 0.17, 0.23, 1)
                    skyHorizonColor: Qt.rgba(0.28, 0.34, 0.46, 1)
                    skyTopColor: Qt.rgba(0.55, 0.65, 0.82, 1)
                }
            }
            probeExposure: 1.15
        }

        PerspectiveCamera {
            id: cam

            position: Qt.vector3d(0, 26, 134)
            eulerRotation.x: -11
            fieldOfView: 36
            clipNear: 10
            clipFar: 500
        }

        // Éclairage studio 3 points (key + fill froid + rim arrière)
        DirectionalLight {
            eulerRotation.x: -38
            eulerRotation.y: -32
            brightness: 1.45
            color: "#fff8f2"
            // Ombres propres : le couvercle et les écouteurs s'ombrent entre eux
            castsShadow: true
            shadowMapQuality: Light.ShadowMapQualityMedium
            shadowFactor: 40
            shadowBias: 0.4
        }

        DirectionalLight {
            eulerRotation.x: -18
            eulerRotation.y: 135
            brightness: 0.85
            color: "#93c5fd"
        }

        DirectionalLight {
            eulerRotation.x: 42
            eulerRotation.y: 12
            brightness: 0.55
            color: "#cbd5e1"
        }

        PointLight {
            position: Qt.vector3d(0, 12, 48)
            brightness: 0.65
            color: "#60a5fa"
            quadraticFade: 0.002
        }

        // ── Matériaux réalistes d'après les photos CETW572 ──
        PrincipledMaterial {
            id: matShell

            // Noir/anthracite satiné du boîtier
            baseColor: "#1b1e24"
            metalness: 0.18
            roughness: 0.34
            specularAmount: 0.65
            clearcoatAmount: 0.22
            clearcoatRoughnessAmount: 0.28
            cullMode: Material.NoCulling
        }

        PrincipledMaterial {
            id: matTray

            // Plateau intérieur mat légèrement plus doux
            baseColor: "#22262e"
            metalness: 0.10
            roughness: 0.48
            specularAmount: 0.45
            cullMode: Material.NoCulling
        }

        PrincipledMaterial {
            id: matBud

            // Corps et crochet en silicone/ABS noir profond
            baseColor: "#15181e"
            metalness: 0.12
            roughness: 0.38
            specularAmount: 0.55
            clearcoatAmount: 0.15
            cullMode: Material.NoCulling
        }

        PrincipledMaterial {
            id: matSilver

            // Anneau métallique chromé des écouteurs + tour USB-C
            baseColor: "#d8dee9"
            metalness: 0.92
            roughness: 0.16
            specularAmount: 0.95
            cullMode: Material.NoCulling
        }

        PrincipledMaterial {
            id: matCap

            // Bouton central circulaire brillant
            baseColor: "#262b35"
            metalness: 0.35
            roughness: 0.18
            clearcoatAmount: 0.75
            clearcoatRoughnessAmount: 0.08
            cullMode: Material.NoCulling
        }

        PrincipledMaterial {
            id: matDarkHole

            baseColor: "#08090c"
            metalness: 0.05
            roughness: 0.85
            cullMode: Material.NoCulling
        }

        PrincipledMaterial {
            id: matNotch

            baseColor: "#111318"
            metalness: 0.15
            roughness: 0.42
            cullMode: Material.NoCulling
        }

        // LED du boîtier
        PrincipledMaterial {
            id: matCaseLed

            baseColor: "#60a5fa"
            emissiveFactor: Qt.vector3d(0.35 * root.ledPulse, 0.72 * root.ledPulse, 1.0 * root.ledPulse)
            roughness: 0.1
        }

        // LED écouteur gauche (BX012) : brille intensément quand connecté, veille douce au boîtier
        PrincipledMaterial {
            id: matLedLeft

            readonly property real k: root.leftConnected ? root.ledPulse + root.leftFlash * 2.5 : 0.08
            readonly property vector3d c: root.ledColor(root.leftPct)
            baseColor: root.leftConnected ? Qt.rgba(c.x, c.y, c.z, 1) : "#1e293b"
            emissiveFactor: Qt.vector3d(c.x * k, c.y * k, c.z * k)
            roughness: 0.1
        }

        // LED écouteur droit (CETW572) : brille intensément quand connecté, veille douce au boîtier
        PrincipledMaterial {
            id: matLedRight

            readonly property real k: root.rightConnected ? root.ledPulse + root.rightFlash * 2.5 : 0.08
            readonly property vector3d c: root.ledColor(root.rightPct)
            baseColor: root.rightConnected ? Qt.rgba(c.x, c.y, c.z, 1) : "#1e293b"
            emissiveFactor: Qt.vector3d(c.x * k, c.y * k, c.z * k)
            roughness: 0.1
        }

        // ── Géométries chargées une seule fois au démarrage ──
        ProceduralMesh {
            id: geoCaseShell
            Component.onCompleted: root.buildMesh(this, "caseShell")
        }
        ProceduralMesh {
            id: geoCaseTray
            Component.onCompleted: root.buildMesh(this, "caseTray")
        }
        ProceduralMesh {
            id: geoLidInner
            Component.onCompleted: root.buildMesh(this, "lidInner")
        }
        ProceduralMesh {
            id: geoLidOuter
            Component.onCompleted: root.buildMesh(this, "lidOuter")
        }
        ProceduralMesh {
            id: geoBudL
            Component.onCompleted: root.buildMesh(this, "budL")
        }
        ProceduralMesh {
            id: geoBudR
            Component.onCompleted: root.buildMesh(this, "budR")
        }
        ProceduralMesh {
            id: geoBudRingL
            Component.onCompleted: root.buildMesh(this, "budRingL")
        }
        ProceduralMesh {
            id: geoBudRingR
            Component.onCompleted: root.buildMesh(this, "budRingR")
        }
        ProceduralMesh {
            id: geoBudCapL
            Component.onCompleted: root.buildMesh(this, "budCapL")
        }
        ProceduralMesh {
            id: geoBudCapR
            Component.onCompleted: root.buildMesh(this, "budCapR")
        }
        ProceduralMesh {
            id: geoPortRim
            Component.onCompleted: root.buildMesh(this, "portRim")
        }
        ProceduralMesh {
            id: geoPortHole
            Component.onCompleted: root.buildMesh(this, "portHole")
        }
        ProceduralMesh {
            id: geoPortTongue
            Component.onCompleted: root.buildMesh(this, "portTongue")
        }
        ProceduralMesh {
            id: geoLidNotch
            Component.onCompleted: root.buildMesh(this, "lidNotch")
        }

        // ── Groupe principal du boîtier ──
        Node {
            id: caseRoot

            position: Qt.vector3d(0, -2 + root.floatY, 0)
            eulerRotation: Qt.vector3d(root.pitch, root.yaw, 0)
            scale: Qt.vector3d(root.caseScale, root.caseScale, root.caseScale)

            Model {
                geometry: geoCaseShell
                materials: [matShell]
            }

            Model {
                geometry: geoCaseTray
                materials: [matTray]
            }

            // Port USB-C + encoche d'ouverture en façade (z = +31)
            Model {
                geometry: geoPortRim
                materials: [matSilver]
            }
            Model {
                geometry: geoPortHole
                materials: [matDarkHole]
            }
            Model {
                geometry: geoPortTongue
                materials: [matSilver]
            }
            Model {
                geometry: geoLidNotch
                materials: [matNotch]
            }

            // Voyant LED bleu en façade au-dessus du port USB-C (comme sur la photo 1)
            Model {
                source: "#Sphere"
                position: Qt.vector3d(0, -3.1, 31.05)
                scale: Qt.vector3d(0.013, 0.013, 0.006)
                materials: [matCaseLed]
            }

            // ── Écouteur Gauche (BX012) : lévitation indépendante s'il est connecté ──
            Node {
                id: leftBudNode

                // Sorti du boîtier : il flotte en balançant doucement, et tourne une fois à la connexion
                position: Qt.vector3d(-root.leftLift * 2.2, root.leftLift * (10.5 + 1.6 * root.budSway), root.leftLift * 2.5)
                eulerRotation: Qt.vector3d(root.leftLift * (14 + 4 * root.budSway), root.leftLift * (10 * root.budSway) + root.leftFlash * 360 * Math.min(1, root.leftLift * 2.3), root.leftLift * 6)

                Model {
                    geometry: geoBudL
                    materials: [matBud]
                }
                Model {
                    geometry: geoBudRingL
                    materials: [matSilver]
                }
                Model {
                    geometry: geoBudCapL
                    materials: [matCap]
                }
                Model {
                    source: "#Sphere"
                    position: Qt.vector3d(-21.2, 1.0, 20.3)
                    scale: Qt.vector3d(0.014, 0.011, 0.014)
                    materials: [matLedLeft]
                }
            }

            // ── Écouteur Droit (CETW572) : lévitation indépendante s'il est connecté ──
            Node {
                id: rightBudNode

                position: Qt.vector3d(root.rightLift * 2.2, root.rightLift * (10.5 - 1.6 * root.budSway), root.rightLift * 2.5)
                eulerRotation: Qt.vector3d(root.rightLift * (14 - 4 * root.budSway), -root.rightLift * (10 * root.budSway) - root.rightFlash * 360 * Math.min(1, root.rightLift * 2.3), -root.rightLift * 6)

                Model {
                    geometry: geoBudR
                    materials: [matBud]
                }
                Model {
                    geometry: geoBudRingR
                    materials: [matSilver]
                }
                Model {
                    geometry: geoBudCapR
                    materials: [matCap]
                }
                Model {
                    source: "#Sphere"
                    position: Qt.vector3d(21.2, 1.0, 20.3)
                    scale: Qt.vector3d(0.014, 0.011, 0.014)
                    materials: [matLedRight]
                }
            }

            // ── Couvercle articulé sur la charnière arrière (z = -31, y = 0) ──
            Node {
                id: lidPivot

                position: Qt.vector3d(0, 0, -31.0)
                eulerRotation.x: -78 * root.lidOpen

                Node {
                    position: Qt.vector3d(0, 0, 31.0)

                    Model {
                        geometry: geoLidInner
                        materials: [matTray]
                    }
                    Model {
                        geometry: geoLidOuter
                        materials: [matShell]
                    }
                }
            }
        }
    }

    // Glisser à la souris pour inspecter les écouteurs sous tous les angles ;
    // double-clic pour ouvrir/fermer le couvercle
    MouseArea {
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real lastX: 0
        property real lastY: 0
        property real lastT: 0

        onPressed: mouse => {
            root.dragging = true;
            root.dragVel = 0;
            lastX = mouse.x;
            lastY = mouse.y;
            lastT = Date.now();
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const dx = mouse.x - lastX;
            const dy = mouse.y - lastY;
            const now = Date.now();
            const dt = Math.max(0.004, (now - lastT) / 1000);
            lastX = mouse.x;
            lastY = mouse.y;
            lastT = now;
            root.yaw = (root.yaw + dx * 0.65) % 360;
            root.pitch = Math.max(-25, Math.min(68, root.pitch + dy * 0.45));
            // Vitesse lissée pour un lancer naturel au relâchement
            root.dragVel = root.dragVel * 0.6 + (dx * 0.65 / dt) * 0.4;
        }
        onReleased: {
            // Relâché immobile = pas d'élan ; lancé = le boîtier continue sur sa lancée
            root.spinVel = Date.now() - lastT > 90 ? 0 : Math.max(-900, Math.min(900, root.dragVel));
            root.dragging = false;
        }
        onCanceled: {
            root.dragging = false;
        }
        onDoubleClicked: {
            if (root.lidOpen > 0.5) {
                root.leftLift = 0;
                root.rightLift = 0;
                root.lidOpen = 0;
            } else {
                root.lidOpen = 1;
                root.leftLift = root.leftConnected ? 0.42 : 0;
                root.rightLift = root.rightConnected ? 0.42 : 0;
            }
        }
        onWheel: wheel => {
            const delta = wheel.angleDelta.y > 0 ? 0.15 : -0.15;
            root.lidOpen = Math.max(0, Math.min(1.1, root.lidOpen + delta));
            if (root.lidOpen < 0.4) {
                root.leftLift = 0;
                root.rightLift = 0;
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "../../assets/earbuds/earbuds-model.js" as M

// Scène 3D temps réel des écouteurs CETW572 (boîtier galet + deux écouteurs à crochet),
// inspirée de AirPodsDesktop : rotation fluide 60 fps, ouverture de la charnière
// au ressort, lévitation douce des écouteurs quand connectés, glisser pour tourner.
Item {
    id: root

    property bool active: false
    property bool connected: false
    property real lidOpen: 1
    property real budsLift: 0
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

    // Rotation continue style AirPodsDesktop quand on ne manipule pas à la souris
    NumberAnimation on yaw {
        running: root.active && !root.dragging
        from: root.yaw
        to: root.yaw + 360
        duration: 13500
        loops: Animation.Infinite
    }

    // Oscillation verticale subtile (respiration 3D)
    property real floatY: 0
    SequentialAnimation on floatY {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation {
            to: 2.2
            duration: 2100
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: -2.2
            duration: 2100
            easing.type: Easing.InOutSine
        }
    }

    // Pulsation des LEDs bleues des écouteurs
    property real ledPulse: 0.85
    SequentialAnimation on ledPulse {
        running: root.active
        loops: Animation.Infinite
        NumberAnimation {
            to: 1.0
            duration: 1200
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0.45
            duration: 1200
            easing.type: Easing.InOutSine
        }
    }

    Behavior on lidOpen {
        SpringAnimation {
            spring: 3.4
            damping: 0.28
            epsilon: 0.002
        }
    }

    Behavior on budsLift {
        SpringAnimation {
            spring: 3.0
            damping: 0.30
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

        PrincipledMaterial {
            id: matLed

            baseColor: "#60a5fa"
            emissiveFactor: Qt.vector3d(0.35 * root.ledPulse, 0.72 * root.ledPulse, 1.0 * root.ledPulse)
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
            id: geoBuds
            Component.onCompleted: root.buildMesh(this, "buds")
        }
        ProceduralMesh {
            id: geoBudRings
            Component.onCompleted: root.buildMesh(this, "budRings")
        }
        ProceduralMesh {
            id: geoBudCaps
            Component.onCompleted: root.buildMesh(this, "budCaps")
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
                materials: [matLed]
            }

            // ── Écouteurs gauche & droit dans leurs logements (avec lévitation douce) ──
            Node {
                id: budsGroup

                position: Qt.vector3d(0, root.budsLift * 9.5, root.budsLift * 2.0)
                eulerRotation.x: root.budsLift * 14

                Model {
                    geometry: geoBuds
                    materials: [matBud]
                }
                Model {
                    geometry: geoBudRings
                    materials: [matSilver]
                }
                Model {
                    geometry: geoBudCaps
                    materials: [matCap]
                }

                // Petites LEDs bleues sur la tranche basse des deux boutons (comme sur la photo 3)
                Model {
                    source: "#Sphere"
                    position: Qt.vector3d(-21.2, 1.0, 20.3)
                    scale: Qt.vector3d(0.014, 0.011, 0.014)
                    materials: [matLed]
                }
                Model {
                    source: "#Sphere"
                    position: Qt.vector3d(21.2, 1.0, 20.3)
                    scale: Qt.vector3d(0.014, 0.011, 0.014)
                    materials: [matLed]
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

        onPressed: mouse => {
            root.dragging = true;
            lastX = mouse.x;
            lastY = mouse.y;
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const dx = mouse.x - lastX;
            const dy = mouse.y - lastY;
            lastX = mouse.x;
            lastY = mouse.y;
            root.yaw = (root.yaw + dx * 0.65) % 360;
            root.pitch = Math.max(-25, Math.min(68, root.pitch + dy * 0.45));
        }
        onReleased: {
            root.dragging = false;
        }
        onCanceled: {
            root.dragging = false;
        }
        onDoubleClicked: {
            if (root.lidOpen > 0.5) {
                root.budsLift = 0;
                root.lidOpen = 0;
            } else {
                root.lidOpen = 1;
                root.budsLift = root.connected ? 0.35 : 0;
            }
        }
        onWheel: wheel => {
            const delta = wheel.angleDelta.y > 0 ? 0.15 : -0.15;
            root.lidOpen = Math.max(0, Math.min(1.1, root.lidOpen + delta));
            if (root.lidOpen < 0.4)
                root.budsLift = 0;
        }
    }
}

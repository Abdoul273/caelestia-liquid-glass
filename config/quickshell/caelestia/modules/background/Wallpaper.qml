pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source: Wallpapers.current
    property CachingImage current
    property bool completed

    onSourceChanged: {
        if (!source)
            current = null;
        else
            current = imgComp.createObject(this, {
                path: source
            });
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                current = imgComp.createObject(this, {
                    path: source
                });
                completed = true;
            });
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Fond d'écran introuvable ?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Choisir un fond d'écran")
                            filterLabel: qsTr("Fichiers image")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Choisir maintenant !")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    // Fond animé : seulement sur secteur. Sur batterie le Loader se vide
    // (lecteur et décodeur libérés) et l'image fixe en dessous reprend la main.
    Loader {
        id: animated

        readonly property string path: Wallpapers.animated
        readonly property bool isVideo: /\.(mp4|webm|mkv|mov|avi)$/i.test(path)

        anchors.fill: parent
        z: 1
        active: path !== "" && !UPower.onBattery && !Wallpapers.showPreview
        opacity: status === Loader.Ready && item?.ready ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }

        sourceComponent: isVideo ? videoComp : gifComp
    }

    Component {
        id: videoComp

        Video {
            readonly property bool ready: playbackState === MediaPlayer.PlayingState && hasVideo

            source: "file://" + animated.path
            fillMode: VideoOutput.PreserveAspectCrop
            loops: MediaPlayer.Infinite
            muted: true
            autoPlay: true
        }
    }

    Component {
        id: gifComp

        AnimatedImage {
            readonly property bool ready: status === AnimatedImage.Ready

            source: "file://" + animated.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            playing: true
        }
    }

    Component {
        id: imgComp

        CachingImage {
            id: img

            anchors.fill: parent

            opacity: 0

            onStatusChanged: {
                if (status === Image.Ready)
                    anim.start();
            }

            Anim on opacity {
                id: anim

                type: Anim.SlowEffects
                running: false
                from: 0
                to: 1
            }

            Timer {
                running: root.current !== img && root.current?.status === Image.Ready
                interval: anim.duration
                onTriggered: img.destroy()
            }
        }
    }
}

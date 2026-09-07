pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    required property MprisPlayer player
    required property QtObject blendedColors
    required property string displayedArtFilePath
    required property real radius
    signal toggleLyrics()

    // Follows the drag while scrubbing so the readout matches the handle
    readonly property real displayPosition: sliderLoader.item?.displayPosition ?? MediaUtils.trackPosition(root.player)
    // Seeking to a point needs a track length to place that point in
    readonly property bool seekable: MediaUtils.canSeekTo(root.player)

    component TrackChangeButton: RippleButton {
        implicitWidth: 24
        implicitHeight: 24
        property var iconName
        colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: root.blendedColors.colSecondaryContainerHover
        colRipple: root.blendedColors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: root.blendedColors.colOnSecondaryContainer
            text: iconName
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 13
        spacing: 15

        Rectangle {
            id: artBackground
            Layout.fillHeight: true
            implicitWidth: height
            radius: Appearance.rounding.verysmall
            color: ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artBackground.width
                    height: artBackground.height
                    radius: artBackground.radius + 6
                }
            }

            StyledImage {
                id: mediaArt
                property int size: parent.height
                anchors.fill: parent
                source: root.displayedArtFilePath
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                width: size
                height: size
                sourceSize.width: size
                sourceSize.height: size
            }

            // The cover doubles as the switch between the lyric views: karaoke sweep, line by line,
            // then the plain text of the song
            MouseArea {
                id: artClickArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: LyricsService.cycleMode()

                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: artClickArea.containsMouse
                    text: LyricsService.modeDescription
                }
            }
        }

        ColumnLayout {
            Layout.fillHeight: true
            spacing: 2

            StyledText {
                id: trackTitle
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large
                color: root.blendedColors.colOnLayer0
                elide: Text.ElideRight
                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }

            StyledText {
                id: trackArtist
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.blendedColors.colSubtext
                elide: Text.ElideRight
                text: root.player?.trackArtist
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }

            Item { Layout.fillHeight: true }

            Item {
                Layout.fillWidth: true
                implicitHeight: trackTime.implicitHeight + sliderRow.implicitHeight

                StyledText {
                    id: trackTime
                    anchors.bottom: sliderRow.top
                    anchors.bottomMargin: 5
                    anchors.left: parent.left
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                    font.features: { "tnum": 1 }
                    text: MediaUtils.friendlyProgress(root.displayPosition, root.player)
                }

                RowLayout {
                    id: sliderRow
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                    }

                    TrackChangeButton {
                        iconName: "skip_previous"
                        downAction: () => root.player?.previous()
                    }

                    Item {
                        id: progressBarContainer
                        Layout.fillWidth: true
                        // Hold the seek bar's height even while the thinner fallback
                        // indicator is mounted, so a player that publishes no track
                        // length doesn't shift the rest of the controls down
                        implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight, 24)

                        Loader {
                            id: sliderLoader
                            anchors.fill: parent
                            active: root.seekable
                            sourceComponent: MediaProgressSlider {
                                player: root.player
                                // Nothing here scrolls, so the wheel is free to seek
                                wheelSeek: true
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                handleColor: root.blendedColors.colPrimary
                            }
                        }

                        Loader {
                            id: progressBarLoader
                            anchors {
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                right: parent.right
                            }
                            active: !root.seekable
                            sourceComponent: StyledProgressBar {
                                wavy: root.player?.isPlaying
                                indeterminate: !MediaUtils.hasTrackLength(root.player)
                                highlightColor: root.blendedColors.colPrimary
                                trackColor: root.blendedColors.colSecondaryContainer
                                value: MediaUtils.trackProgress(root.player)
                            }
                        }
                    }

                    TrackChangeButton {
                        iconName: "skip_next"
                        downAction: () => root.player?.next()
                    }

                    TrackChangeButton {
                        iconName: "lyrics"
                        visible: !GlobalStates.sidebarRightOpen
                        downAction: () => root.toggleLyrics()
                    }
                }

                RippleButton {
                    id: playPauseButton
                    anchors.right: parent.right
                    anchors.bottom: sliderRow.top
                    anchors.bottomMargin: 5
                    property real size: 44
                    implicitWidth: size
                    implicitHeight: size
                    downAction: () => MprisController.togglePlayer(root.player)

                    buttonRadius: root.player?.isPlaying ? Appearance?.rounding.normal : size / 2
                    colBackground: root.player?.isPlaying ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
                    colBackgroundHover: root.player?.isPlaying ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
                    colRipple: root.player?.isPlaying ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive

                    contentItem: MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.huge
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: root.player?.isPlaying ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
                        text: root.player?.isPlaying ? "pause" : "play_arrow"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }
}
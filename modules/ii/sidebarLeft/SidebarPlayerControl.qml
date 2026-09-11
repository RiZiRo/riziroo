pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    property var player: Mpris.players.values[playerSelector.currentIndex] ?? Mpris.players.values[0]
    // The best art this player has offered for this track, not merely the latest one it published
    property var artUrl: MediaArt.urlFor(player)
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property color artDominantColor: Config.options.sidebar.media.artColors
        ? ColorUtils.mix(
            (colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary),
            Appearance.colors.colPrimaryContainer,
            0.8
          )
        : Appearance.colors.colPrimaryContainer
    property bool downloaded: false
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000
    property int visualizerSmoothing: 2
    property real radius

    property string displayedArtFilePath: {
        // Already a local snapshot, so there is nothing left to fetch
        if (root.artUrl && root.artUrl.startsWith("file://")) return root.artUrl
        return root.downloaded ? Qt.resolvedUrl(artFilePath) : ""
    }

    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player?.positionChanged()  
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length == 0) {
            root.artDominantColor = Appearance.m3colors.m3secondaryContainer
            // Without this the last track's flag stays set and the art path becomes the md5 of an
            // empty string, which is a file that never exists
            root.downloaded = false
            return
        }
        if (root.artUrl.startsWith("file://")) {
            root.downloaded = true
            return
        }
        coverArtDownloader.targetFile = root.artUrl
        coverArtDownloader.artFilePath = root.artFilePath
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c", `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: (exitCode, exitStatus) => { root.downloaded = true }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.topMargin: -1
        anchors.bottomMargin: 4
        color: ColorUtils.transparentize(artDominantColor, 0.9)
        radius: Appearance.rounding.normal

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: parent.height * 0.04
            spacing: 0

            // ── Album art ──
            // Host for the art plus the sync pill floating over it. The pill is a sibling rather
            // than a child of artBackground because that rectangle's rounded-corner mask would
            // clip it to the art's bounds as soon as it expands. Raised above the lyrics below so
            // the expanded pill draws over them instead of behind their clickable lines.
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(parent.width * 1, parent.height * 0.45)
                Layout.preferredHeight: Layout.preferredWidth
                z: 1

                Rectangle {
                    id: artBackground
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimaryContainer

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artBackground.width
                            height: artBackground.height
                            radius: artBackground.radius
                        }
                    }

                    StyledImage {
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        sourceSize.width: artBackground.width * 2
                        sourceSize.height: artBackground.height * 2
                    }

                    MaterialSymbol {
                        visible: MprisController.activePlayer === null
                        anchors.centerIn: parent
                        fill: 1
                        text: "music_note"
                        color: Appearance.colors.colPrimary
                        iconSize: Appearance.font.pixelSize.hugeass + 100
                    }

                    // The cover doubles as the switch between the lyric views: karaoke sweep, line by
                    // line, then the plain text of the song
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

                LyricsSyncPill {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 6
                    coverHovered: artClickArea.containsMouse
                }
            }

            // ── Title & Artist ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 20
                spacing: 5

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleText.implicitHeight
                    clip: true

                    StyledText {
                        id: titleText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: blendedColors.colOnLayer0
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Play"

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: titleText; property: "x"; to: -titleText.width; duration: 150; easing.type: Easing.InQuad }
                                PropertyAction { target: titleText; property: "text" }
                                NumberAnimation { target: titleText; property: "x"; from: titleText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: artistText.implicitHeight
                    clip: true

                    StyledText {
                        id: artistText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Appearance.font.pixelSize.large 
                        color: blendedColors.colSubtext
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: root.player?.trackArtist || "Something"

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: artistText; property: "x"; to: -artistText.width; duration: 150; easing.type: Easing.InQuad }
                                PropertyAction { target: artistText; property: "text" }
                                NumberAnimation { target: artistText; property: "x"; from: artistText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }
            }

            // ── Lyrics ──
            Lyrics {
                id: lyricsComp
                opacity: MprisController.activePlayer !== null ? 1 : 0 
                Layout.fillWidth: true
                Layout.fillHeight: true
                player: root.player
                textAlignment: Text.AlignHCenter
                textColor: blendedColors.colOnLayer0
                activeColor: blendedColors.colPrimary
                dimColor: blendedColors.colSubtext
                indicatorColor: {
                    let c = blendedColors.colPrimaryContainer
                    return (c && c != "#000000" && c != "transparent") ? c : root.artDominantColor
                }
                indicatorShapeColor: {
                    let c = blendedColors.colOnPrimaryContainer
                    if (c && c != "#000000" && c != "#ffffff" && c != "transparent") return c
                    return blendedColors.colPrimary || Appearance.colors.colPrimary
                }
            }

            // ── Progress ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 5
                spacing: 12

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: blendedColors.colSubtext
                    font.letterSpacing: -0.4
                    font.features: { "tnum": 1 }
                    text: StringUtils.friendlyTimeForSeconds(sliderLoader.item?.displayPosition ?? MediaUtils.trackPosition(root.player))
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                    Loader {
                        id: sliderLoader
                        anchors.fill: parent
                        active: MediaUtils.canSeekTo(root.player)
                        sourceComponent: MediaProgressSlider {
                            player: root.player
                            highlightColor: blendedColors.colPrimary
                            trackColor: blendedColors.colSecondaryContainer
                            handleColor: blendedColors.colPrimary
                            onSeeked: lyricsComp.syncNow()
                        }
                    }

                    Loader {
                        id: progressBarLoader
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                        }
                        active: !MediaUtils.canSeekTo(root.player)
                        sourceComponent: StyledProgressBar {
                            wavy: root.player?.isPlaying ?? false
                            indeterminate: !MediaUtils.hasTrackLength(root.player)
                            highlightColor: blendedColors.colPrimary
                            trackColor: blendedColors.colSecondaryContainer
                            value: MediaUtils.trackProgress(root.player)
                        }
                    }
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal 
                    color: blendedColors.colSubtext
                    font.letterSpacing: -0.4
                    font.features: { "tnum": 1 }
                    text: MediaUtils.friendlyTrackLength(root.player)
                }
            }

            // ── Controls ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 20
                Layout.alignment: Qt.AlignHCenter
                spacing: 15

                RippleButton {
                    property real baseSize: Math.max(42, parent.parent.height * 0.06)
                    implicitWidth: baseSize * 1.5
                    implicitHeight: baseSize * 1.5
                    buttonRadius: Appearance.rounding.verylarge
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.previous()
                    contentItem: MaterialSymbol {
                        iconSize: 25
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "skip_previous"
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(70, parent.parent.height * 0.1)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: (root.player?.isPlaying ?? false) ? Appearance.rounding.verylarge : baseSize / 2  
                    colBackground: (root.player?.isPlaying ?? false) ? blendedColors.colPrimary : blendedColors.colSecondaryContainer
                    colBackgroundHover: (root.player?.isPlaying ?? false) ? blendedColors.colPrimaryHover : blendedColors.colSecondaryContainerHover
                    colRipple: (root.player?.isPlaying ?? false) ? blendedColors.colPrimaryActive : blendedColors.colSecondaryContainerActive
                    downAction: () => MprisController.togglePlayer(root.player)
                    contentItem: MaterialSymbol {
                        iconSize: 50
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: (root.player?.isPlaying ?? false) ? blendedColors.colOnPrimary : blendedColors.colOnSecondaryContainer
                        text: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(42, parent.parent.height * 0.06)
                    implicitWidth: baseSize * 1.5
                    implicitHeight: baseSize * 1.5
                    buttonRadius: Appearance.rounding.verylarge
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.next()
                    contentItem: MaterialSymbol {
                        iconSize: 25
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "skip_next"
                    }
                }
            }

            // ── Volume ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 8

                RippleButton {
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    implicitWidth: baseSize
                    implicitHeight: baseSize
                    buttonRadius: Appearance.rounding.large
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => {
                        if (root.player) root.player.volume = (root.player.volume > 0) ? 0 : 1.0  
                    }
                    contentItem: MaterialSymbol {
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: (root.player?.volume ?? 1) <= 0 ? "volume_off"
                            : (root.player?.volume ?? 1) < 0.5 ? "volume_down"
                            : "volume_up"
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: Appearance.rounding.large
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => {
                        if (root.player) root.player.volume = Math.max(0, (root.player.volume ?? 1) - 0.1)  
                    }
                    contentItem: MaterialSymbol {
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "volume_down"
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: Appearance.rounding.large
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => {
                        if (root.player) root.player.volume = Math.min(1.5, (root.player.volume ?? 1) + 0.1)  
                    }
                    contentItem: MaterialSymbol {
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "volume_up"
                    }
                }
            }

            // ── Player selector ──
            StyledComboBox {
                id: playerSelector
                visible: Mpris.players.values.length > 1
                Layout.fillWidth: true
                Layout.topMargin: 12
                model: Mpris.players.values.map(p => p.identity ?? p.desktopEntry ?? "Unknown")
                currentIndex: 0
            }
        }
    }
}
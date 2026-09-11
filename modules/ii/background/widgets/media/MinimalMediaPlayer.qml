pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Desktop-only media presentation: no panel, shadow, controls, or visualizer.
Item {
    id: root

    required property MprisPlayer player
    property color textColor: Appearance.colors.colOnLayer0
    readonly property bool hasLyrics: LyricsService.status === "ok"
        && LyricsService.lyricsLines.length > 0
    readonly property bool lyricsSearching: LyricsService.status === "loading"

    readonly property string emptyLyricsText: {
        if (LyricsService.status === "no_info")
            return Translation.tr("No track info")
        if (LyricsService.instrumental)
            return Translation.tr("Instrumental")
        return Translation.tr("No lyrics found. Click to retry")
    }

    property var artUrl: MediaArt.urlFor(player)
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    readonly property string displayedArtFilePath: {
        if (!root.artDownloaded) return ""
        if (root.artUrl.startsWith("file://")) return root.artUrl
        return Qt.resolvedUrl(root.artFilePath)
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDownloaded = false
            return
        }
        if (root.artUrl.startsWith("file://")) {
            root.artDownloaded = true
            return
        }
        artDownloader.targetFile = root.artUrl
        artDownloader.artFilePath = root.artFilePath
        root.artDownloaded = false
        artDownloader.running = true
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c", `[ -f ${artFilePath} ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: root.artDownloaded = true
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 16

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 136
            Layout.maximumWidth: 156
            spacing: 8

            Item {
                Layout.fillWidth: true
                implicitHeight: emptyLyricsTextItem.implicitHeight
                visible: !root.hasLyrics && !root.lyricsSearching

                StyledText {
                    id: emptyLyricsTextItem
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: root.textColor
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.emptyLyricsText
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LyricsService.restartLyrics()
                }
            }

            // Host for the art plus the sync pill floating over it. The pill is a sibling rather
            // than a child of the art rectangle because its clip would cut the pill off at the
            // art's bounds as soon as it expands. Raised above the lyrics beside it so the expanded
            // pill draws over them instead of behind their clickable lines.
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 132
                Layout.preferredHeight: 132
                z: 1

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: 12
                    clip: true

                    StyledImage {
                        id: mediaArt
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        visible: status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        smooth: true
                        mipmap: true
                        sourceSize.width: 264
                        sourceSize.height: 264
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.displayedArtFilePath === "" || mediaArt.status !== Image.Ready
                        text: "music_note"
                        iconSize: 42
                        fill: 1
                        color: root.textColor
                    }

                    MouseArea {
                        id: artClickArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
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

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: root.textColor
                text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Untitled"
                animateChange: true
                animationDistanceX: 6
                animationDistanceY: 0
            }
        }

        Lyrics {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.hasLyrics || root.lyricsSearching
            player: root.player
            textColor: root.textColor
            activeColor: Appearance.colors.colPrimary
            dimColor: ColorUtils.transparentize(root.textColor, 0.45)
            indicatorColor: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
            indicatorShapeColor: Appearance.colors.colPrimary
        }
    }
}

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Circular cover art for the island's media context.
 *
 * MPRIS usually hands out a remote URL, which Image can't fetch, so it is curl'd into
 * Directories.coverArt once and read back from disk -- the same dance bar/Media.qml,
 * dock/DockMedia.qml and the others already do. Directories creates and wipes that folder on
 * startup, so nothing here has to manage it.
 */
Rectangle {
    id: root

    // The best art the player has offered for this track, not merely the latest one it published
    readonly property string artUrl: MediaArt.urlFor(MprisController.activePlayer)
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(root.artUrl)}`
    property bool artDownloaded: false

    readonly property string displayedArt: {
        if (root.artUrl.length === 0)
            return "";
        if (root.artUrl.startsWith("file://"))
            return root.artUrl;
        return root.artDownloaded ? Qt.resolvedUrl(root.artFilePath) : "";
    }

    implicitWidth: 24
    implicitHeight: 24
    radius: Appearance.rounding.full
    color: Appearance.colors.colSecondaryContainer

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }
    }

    function refreshArt(): void {
        root.artDownloaded = false;
        if (root.artUrl.length === 0 || root.artUrl.startsWith("file://"))
            return;
        artDownloader.running = false;
        artDownloader.running = true;
    }

    onArtUrlChanged: root.refreshArt()
    Component.onCompleted: root.refreshArt()

    Process {
        id: artDownloader
        command: ["bash", "-c", `[ -f '${root.artFilePath}' ] || curl -sSL '${root.artUrl}' -o '${root.artFilePath}'`]
        onExited: root.artDownloaded = true
    }

    StyledImage {
        anchors.fill: parent
        visible: root.displayedArt !== ""
        source: root.displayedArt
        fillMode: Image.PreserveAspectCrop
        cache: false
        antialiasing: true
        sourceSize.width: root.width
        sourceSize.height: root.height
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.displayedArt === ""
        fill: 1
        text: "music_note"
        iconSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colOnSecondaryContainer
    }
}

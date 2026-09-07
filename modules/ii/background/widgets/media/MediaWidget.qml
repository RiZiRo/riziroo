pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

/*
 * Desktop media card.
 *
 * This hosts a minimal desktop media view as a draggable, resizable widget.
 * The popup and sidebar keep their full controls; the desktop view shows only
 * cover art, the track title, and synced lyrics so it stays visually quiet.
 *
 * Data flow notes (why this file is small on purpose):
 * - Cover art comes from MediaArt.urlFor(player), which already copies,
 *   measures and keeps the largest picture per track. There is intentionally
 *   no downloader here: the old per-widget `curl` call could break on quotes
 *   in URLs and raced with Firefox's thumbnail replacement.
 * - Position polling, seek hold/verify and track-length guards live in
 *   Player / MediaProgressSlider / MediaSeeker / MediaUtils. Nothing here
 *   divides by a length or touches player.position directly.
 * - The audio wave comes from the shell's single shared cava process via
 *   GlobalStates.visualizerPoints. No second cava instance is started.
 */
AbstractBackgroundWidget {
    id: root

    // Kept for compatibility with Background.qml's mediaLoader hook.
    // Never emitted: track and player changes are handled internally.
    signal requestReset()

    configEntryName: "media"
    hoverEnabled: true

    // -- player selection (preferred player from bar settings) --
    readonly property var playerList: MprisController.players
    property MprisPlayer currentPlayer: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase();
        if (preferred.length === 0)
            return MprisController.activePlayer;
        // Touch .count so the binding re-evaluates when players come and go
        const _ = MprisController.players.count;
        for (const p of MprisController.players) {
            if ((p.identity ?? "").toLowerCase().includes(preferred)
                || (p.desktopEntry ?? "").toLowerCase().includes(preferred))
                return p;
        }
        return MprisController.activePlayer;
    }

    // -- card geometry (new Config API, with safe fallbacks) --
    // Live drag values override the saved config while resizing; they reset
    // to -1 on finish so the saved config becomes the source of truth again.
    property real dragWidth: -1
    property real dragHeight: -1
    readonly property real savedWidth: root.configEntry.cardWidth ?? 520
    readonly property real savedHeight: root.configEntry.cardHeight ?? 330
    readonly property real cardWidth: Math.max(420, Math.min(760,
        root.dragWidth > 0 ? root.dragWidth : root.savedWidth))
    readonly property real cardHeight: Math.max(300, Math.min(520,
        root.dragHeight > 0 ? root.dragHeight : root.savedHeight))
    readonly property real cardRadius: Appearance.rounding?.verylarge ?? 28

    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    visible: root.currentPlayer !== null && opacity > 0

    Item {
        id: card
        anchors.fill: parent

        // The desktop view is intentionally limited to cover art, title, and lyrics.
        Loader {
            id: playerLoader
            anchors.fill: parent
            active: root.currentPlayer !== null
            sourceComponent: MinimalMediaPlayer {
                player: root.currentPlayer
                // The desktop widget may sit on a dark wallpaper; use the shell's
                // high-contrast foreground instead of wallpaper-derived adaptive text.
                textColor: Appearance.colors.colOnLayer0
            }
        }

        ResizeHandler {
            anchorItem: card
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.cardWidth
            currentHeight: root.cardHeight
            resizeMode: "free"
            onResizedFree: (newWidth, newHeight) => {
                root.dragWidth = Math.max(420, Math.min(760, newWidth));
                root.dragHeight = Math.max(300, Math.min(520, newHeight));
            }
            onResizeFinished: {
                root.configEntry.cardWidth = root.cardWidth;
                root.configEntry.cardHeight = root.cardHeight;
                root.dragWidth = -1;
                root.dragHeight = -1;
            }
        }
    }
}

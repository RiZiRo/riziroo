pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

/**
 * Seeking that survives players which lie about their position.
 *
 * Writing `player.position` is a request, not a fact. Spotify and mpd apply it; Firefox/Zen
 * accepts it and then reports 0 until the page publishes media session state again. A requested
 * position is therefore remembered here and handed back by positionFor() for a moment, which is
 * what stops the seek bar and the time readout from snapping to the start the instant a player
 * answers with something bogus.
 *
 * If the position write doesn't take, the relative Seek() call is tried once -- quickshell notes
 * it can work where setting position doesn't -- before giving up and showing whatever the player
 * claims.
 */
Singleton {
    id: root

    // How long a requested position keeps overriding the player's own report
    readonly property int holdInterval: 1600
    // When to check whether the player actually moved
    readonly property int verifyInterval: 380
    // Reports this close to the request count as "the player did as it was told". Generous
    // because playback keeps running while we wait, so the player is legitimately ahead.
    readonly property real tolerance: 2.5

    property MprisPlayer target: null
    property real targetPosition: -1
    property bool triedRelative: false

    readonly property bool pending: root.targetPosition >= 0 && root.target !== null

    signal seeked(MprisPlayer player, real position)

    /**
     * Position to show for a player: the pending request while one is in flight, otherwise
     * whatever the player reports.
     * @param { MprisPlayer } player
     * @returns { number }
     */
    function positionFor(player) {
        if (root.pending && player === root.target)
            return root.targetPosition;
        return MediaUtils.trackPosition(player);
    }

    /**
     * Progress from 0 to 1 to show for a player, or 0 when its length is unknown.
     * @param { MprisPlayer } player
     * @returns { number }
     */
    function progressFor(player) {
        const length = MediaUtils.trackLength(player);
        if (!(length > 0))
            return 0;
        return Math.max(0, Math.min(1, root.positionFor(player) / length));
    }

    /**
     * Seeks to an absolute position in seconds. Returns false when the player can't seek at all,
     * so callers can put their control back where it was.
     * @param { MprisPlayer } player
     * @param { number } position
     * @returns { bool }
     */
    function seekTo(player, position) {
        if (!player || !(player.canSeek ?? false))
            return false;

        const wanted = root.__clamp(player, position);
        root.target = player;
        root.targetPosition = wanted;
        root.triedRelative = false;
        root.__request(player, wanted, false);
        verifyTimer.restart();
        holdTimer.restart();
        root.seeked(player, wanted);
        return true;
    }

    /**
     * Seeks by a signed number of seconds from where the player is now.
     * @param { MprisPlayer } player
     * @param { number } delta
     * @returns { bool }
     */
    function seekBy(player, delta) {
        return root.seekTo(player, root.positionFor(player) + delta);
    }

    function release() {
        verifyTimer.stop();
        holdTimer.stop();
        root.target = null;
        root.targetPosition = -1;
        root.triedRelative = false;
    }

    // Never ask for the very last instant of a track: several players treat that as "finished"
    // and skip to the next one.
    function __clamp(player, position) {
        const length = MediaUtils.trackLength(player);
        const wanted = Math.max(0, position);
        return length > 0 ? Math.min(wanted, Math.max(0, length - 0.5)) : wanted;
    }

    function __request(player, wanted, relative) {
        if (!player)
            return;
        if (relative || !player.positionSupported) {
            player.seek(wanted - MediaUtils.trackPosition(player));
        } else {
            player.position = wanted;
        }
        // Positions only reach bindings when this is emitted
        player.positionChanged();
    }

    Timer {
        id: verifyTimer
        interval: root.verifyInterval
        onTriggered: {
            const player = root.target;
            if (!root.pending || !player)
                return;
            player.positionChanged();
            if (Math.abs(MediaUtils.trackPosition(player) - root.targetPosition) <= root.tolerance) {
                root.release();
                return;
            }
            if (root.triedRelative)
                return; // Out of ideas; the hold expiring will show the truth
            root.triedRelative = true;
            root.__request(player, root.targetPosition, true);
            verifyTimer.restart();
            holdTimer.restart();
        }
    }

    Timer {
        id: holdTimer
        interval: root.holdInterval
        onTriggered: root.release()
    }

    // A new track invalidates any position we were waiting on
    Connections {
        target: root.target
        ignoreUnknownSignals: true
        function onPostTrackChanged() { root.release(); }
    }
}

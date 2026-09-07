pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions
import Quickshell
import Quickshell.Services.Mpris

/**
 * Track timing helpers for MPRIS players.
 *
 * `MprisPlayer.length` reports the current *position* for players that never
 * publish `mpris:length`, so plain `position / length` math quietly evaluates to
 * 1: the bar pins itself to the far end and the readout claims "0:28 / 0:28" for
 * a four minute song. Read lengths through here instead, where an unpublished
 * length comes back as 0, and gate anything that needs a real duration (seeking
 * to a point, a total time, a percentage) on `hasTrackLength`.
 */
Singleton {
    id: root

    /**
     * Length of the playing track in seconds, or 0 if the player doesn't publish one.
     * @param { MprisPlayer } player
     * @returns { number }
     */
    function trackLength(player) {
        if (!player?.lengthSupported)
            return 0;
        const length = player.length;
        return (isFinite(length) && length > 0) ? length : 0;
    }

    /**
     * Whether the player publishes a usable track length.
     * @param { MprisPlayer } player
     * @returns { bool }
     */
    function hasTrackLength(player) {
        return root.trackLength(player) > 0;
    }

    /**
     * Position within the playing track in seconds, never past its end.
     * @param { MprisPlayer } player
     * @returns { number }
     */
    function trackPosition(player) {
        const position = player?.position ?? 0;
        if (!isFinite(position) || position < 0)
            return 0;
        const length = root.trackLength(player);
        return length > 0 ? Math.min(position, length) : position;
    }

    /**
     * Progress through the playing track from 0 to 1, or 0 if the length is unknown.
     * @param { MprisPlayer } player
     * @returns { number }
     */
    function trackProgress(player) {
        const length = root.trackLength(player);
        if (length <= 0)
            return 0;
        return Math.max(0, Math.min(1, root.trackPosition(player) / length));
    }

    /**
     * Whether a specific point in the track can be seeked to, which needs a known
     * length to seek relative to on top of player support.
     * @param { MprisPlayer } player
     * @returns { bool }
     */
    function canSeekTo(player) {
        return (player?.canSeek ?? false) && root.hasTrackLength(player);
    }

    /**
     * The track length as "4:56", or "--:--" if the player doesn't publish one.
     * @param { MprisPlayer } player
     * @returns { string }
     */
    function friendlyTrackLength(player) {
        const length = root.trackLength(player);
        return length > 0 ? StringUtils.friendlyTimeForSeconds(length) : "--:--";
    }

    /**
     * A "1:23 / 4:56" readout, with "--:--" as the total while it is unknown.
     * @param { number } position
     * @param { MprisPlayer } player
     * @returns { string }
     */
    function friendlyProgress(position, player) {
        return `${StringUtils.friendlyTimeForSeconds(position)} / ${root.friendlyTrackLength(player)}`;
    }
}

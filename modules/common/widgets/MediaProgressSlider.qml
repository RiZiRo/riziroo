pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell.Services.Mpris

/**
 * Seek bar for an MPRIS player.
 *
 * `live: false` looked like the safe choice -- commit once on release instead of on every pixel of
 * the drag -- but a non-live Slider never writes the drag into `value`, so the commit sent the
 * position the handle had *before* the drag. Playback never moved and the bar sprang back. The
 * drag is live now and the seek is committed one event loop turn after the press ends, which is
 * late enough to be right for a click on the track as well as for a drag, whichever order Qt
 * settles `value` and `pressed` in.
 *
 * Requested positions are held by MediaSeeker instead of by a local settle timer, so every readout
 * that reads through it agrees with the handle while a player catches up -- or never does.
 *
 * A fraction of the track only means something when its length is known, so mount this on
 * `MediaUtils.canSeekTo(player)` rather than `player.canSeek` alone.
 */
StyledSlider {
    id: root

    property MprisPlayer player
    // Off by default: inside anything scrollable, seeking on wheel would eat the scroll
    property bool wheelSeek: false
    property real wheelSeconds: 5

    readonly property real trackLength: MediaUtils.trackLength(root.player)
    readonly property bool seekable: MediaUtils.canSeekTo(root.player)

    // Where the bar claims to be, including an in-flight drag. Derived from the handle rather than
    // from the player so a readout built on this can never disagree with what is on screen.
    readonly property real displayPosition: root.trackLength > 0
        ? root.visualPosition * root.trackLength
        : MediaSeeker.positionFor(root.player)
    readonly property real playerProgress: MediaSeeker.progressFor(root.player)

    signal seeked(real position)

    configuration: StyledSlider.Configuration.Wavy
    usePercentTooltip: false
    tooltipContent: StringUtils.friendlyTimeForSeconds(root.displayPosition)
    enabled: root.seekable
    // Wheel and arrow keys move in five second steps; NoSnap keeps dragging continuous
    stepSize: root.trackLength > 0 ? Math.min(0.5, root.wheelSeconds / root.trackLength) : 0
    snapMode: Slider.NoSnap
    wheelEnabled: root.wheelSeek && root.seekable

    function commit(): void {
        const length = root.trackLength;
        if (!(length > 0) || !root.player)
            return;
        const target = root.value * length;
        if (!MediaSeeker.seekTo(root.player, target)) {
            root.value = root.playerProgress;
            return;
        }
        root.seeked(target);
    }

    function follow(): void {
        const length = root.trackLength;
        if (length > 0)
            root.value = Math.max(0, Math.min(1, MediaSeeker.positionFor(root.player) / length));
    }

    Component.onCompleted: root.follow()
    onPlayerChanged: {
        commitTimer.stop();
        root.follow();
    }
    onPlayerProgressChanged: {
        if (!root.pressed && !commitTimer.running)
            root.value = root.playerProgress;
    }

    onPressedChanged: {
        if (root.pressed)
            commitTimer.stop();
        else
            commitTimer.restart();
    }

    // Wheel and keyboard changes arrive without any press, so they need committing too
    onMoved: if (!root.pressed) commitTimer.restart()

    Timer {
        id: commitTimer
        interval: 16
        onTriggered: root.commit()
    }

    // Follow playback per frame while it matters. MPRIS positions only reach bindings when
    // something emits positionChanged(), which the shell does about once a second: fine for a
    // "1:23" readout, visibly steppy for a bar. quickshell extrapolates position locally between
    // D-Bus reads, so sampling it every frame costs nothing and the bar actually glides.
    FrameAnimation {
        running: root.visible && !root.pressed && !commitTimer.running
            && (root.player?.isPlaying ?? false) && root.trackLength > 0
        onTriggered: root.follow()
    }
}

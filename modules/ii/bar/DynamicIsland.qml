import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.models
import qs.modules.ii.bar.island
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

/**
 * The bar's dynamic island: one pill that reshapes instead of several widgets swapping.
 *
 * Registered as "dynamicIsland" in Config.options.bar.layouts.middleLayout. It paints its own
 * shell -- BarContent excludes it from the BarGroup pill -- because the whole point is that this
 * Rectangle's geometry animates, and being wrapped in something that resizes on a different
 * curve breaks the illusion.
 *
 * Layout is deliberately anchor-based rather than a RowLayout: content is pinned to the shell's
 * own edges, so when the shell glides to a new width everything inside travels with it. Nesting
 * a layout that resizes independently makes the interior jump a frame ahead of the pill.
 *
 * The clock is permanent; only the context area to its left swaps between weather, media and the
 * volume/brightness burst. All state lives in IslandState.
 */
Item {
    id: root

    property bool vertical: false

    readonly property real horizontalPadding: 12
    readonly property real gap: 8
    readonly property bool expanded: IslandState.expanded
    readonly property bool weatherShown: Config.options.bar.weather.enable && Config.options.bar.island.showWeather

    // Whichever context is coming in -- the pill sizes to it immediately and glides, while the
    // outgoing one cross-fades underneath.
    readonly property Item contextContent: {
        if (IslandState.activity === "osd")
            return osdLoader.item;
        if (IslandState.activity === "media")
            return mediaLoader.item;
        return root.weatherShown ? weatherLoader.item : null;
    }
    readonly property real contextWidth: root.contextContent?.implicitWidth ?? 0
    readonly property bool hasContext: root.contextWidth > 0

    readonly property real collapsedWidth: root.horizontalPadding * 2
        + root.contextWidth
        + (root.hasContext ? root.gap * 2 + 1 : 0)
        + (clock.implicitWidth ?? 0)
    readonly property real targetWidth: IslandState.searchActive ? Config.options.bar.island.searchWidth : root.collapsedWidth

    // The layout width, animated here rather than on the shell. BarContent sizes the centre
    // material pill from this (+10 padding), so the outer pill glides along with the morph for
    // free -- and because the shell reads it instead of feeding it, the shell is free to overdraw
    // its own bounds on hover without any of it looping back.
    //
    // elementMoveSmall, not elementMoveFast: the fast preset is the 200ms *effects* curve, meant
    // for fades, and a 400px morph on it reads as a snap. This is the 350ms expressive spatial
    // curve, whose slight overshoot is what makes the pill land rather than stop. It also drops
    // alwaysRunToEnd, which the fast preset sets -- and this property is retargeted mid-flight
    // (a track change edits collapsedWidth while the pill is still moving), where two
    // run-to-completion animations on one property just judder.
    property real animatedWidth: root.targetWidth
    Behavior on animatedWidth {
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
    }

    // 0 at rest, 1 when hovered: closes the gap to the outer pill on all four sides at once.
    // Real geometry rather than a scale transform -- filling a 4px vertical gap on a 32px pill
    // needs yScale 1.25, which would stretch the text with it.
    // Held open through a drag as well: the pointer can leave a 32px-tall pill sideways without
    // meaning to let go, and having the shell shrink halfway through the gesture reads as a glitch.
    // Held open while expanded too, which is the important one: without it, clicking the pill open
    // dropped it from 40px tall to 32px at the same moment it started growing sideways, so the
    // morph began with a visible vertical squash. Expanded, the shell now fills its socket exactly
    // -- same width, same height as the outer material pill -- which is what makes the open island
    // read as one surface instead of a pill inside a pill.
    property real hoverGrow: (root.expanded || mouseArea.containsMouse || mouseArea.dragActive) ? 1 : 0
    Behavior on hoverGrow {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    readonly property real outerPadding: 10
    readonly property real restInset: 8

    // Swipe-to-skip. Armed only while a track is actually playing, so a drag on a pill
    // showing the weather -- or a paused player -- does nothing at all rather than leaning
    // for no reason. Drag left = next track, drag right = previous (unless swipeInvert).
    readonly property bool dragEnabled: !root.expanded
        && Config.options.bar.island.swipeToSkip
        && !!MprisController.activePlayer
        && MprisController.isPlaying

    // How far the pill leans out of its socket while dragged, how far the pointer travels per track,
    // and how much slop a click is allowed before it counts as a drag. The lean is asymptotic, so it
    // can never travel further than dragMaxOffset no matter how far the pointer goes.
    readonly property real dragMaxOffset: 14
    readonly property real dragSkipDistance: 30
    readonly property real dragStartDistance: 8

    property real dragOffset: 0

    // Deliberately not Appearance.animation.elementMoveFast: that preset sets alwaysRunToEnd, and
    // this property is reassigned on every mouse move, so two run-to-completion animations would
    // end up on it at once and the pill would judder. A short ease is also what makes the ratchet
    // read as a snap rather than a teleport.
    Behavior on dragOffset {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    // Covers the pill losing its player, pausing, or being expanded, mid-drag: without this
    // the lean would stay put until the button came back up.
    onDragEnabledChanged: {
        if (!root.dragEnabled) {
            mouseArea.dragActive = false;
            root.dragOffset = 0;
        }
    }

    implicitWidth: root.animatedWidth
    implicitHeight: Appearance.sizes.barHeight

    // Only used by the hover calendar popup; the pill's own clock comes from DateTime.
    property var today: new Date()

    // ---- Media-tinted pill background (matches the dock player card) ----
    // Same art cache and file naming as IslandArt/DockMedia, so the cover is
    // shared, never downloaded twice. The tint shows only while the media
    // context is up and its art is ready; otherwise the pill keeps its theme
    // colors exactly as before.
    readonly property var mediaArtUrl: MediaArt.urlFor(MprisController.activePlayer)
    readonly property string mediaArtFilePath: `${Directories.coverArt}/${Qt.md5(root.mediaArtUrl)}`
    property bool mediaArtDownloaded: false
    readonly property string mediaDisplayedArt: {
        if (!root.mediaArtDownloaded) return "";
        if (root.mediaArtUrl.startsWith("file://")) return root.mediaArtUrl;
        return Qt.resolvedUrl(root.mediaArtFilePath);
    }
    readonly property bool mediaBgActive: IslandState.activity === "media" && root.mediaDisplayedArt !== ""

    property color mediaArtDominant: ColorUtils.mix(
        mediaColorQuantizer?.colors[0] ?? Appearance.colors.colPrimary,
        Appearance.colors.colPrimaryContainer,
        0.8)

    property QtObject mediaBlended: AdaptedMaterialScheme {
        color: root.mediaArtDominant
    }

    // Effective pill color: blurred art (≈ dominant) under the veil.
    readonly property color mediaEffectiveBg: ColorUtils.mix(
        root.mediaArtDominant, root.mediaBlended.colLayer0, 0.55)

    // The pill's real background, whatever is painting it. The foreground
    // (label, meter, clock, separator) keys its contrast flip off this.
    readonly property color islandPillBg: root.mediaBgActive
        ? root.mediaEffectiveBg : Appearance.colors.colPrimaryContainer

    function refreshMediaArt(): void {
        root.mediaArtDownloaded = false;
        if (root.mediaArtUrl.length === 0)
            return;
        if (root.mediaArtUrl.startsWith("file://")) {
            root.mediaArtDownloaded = true;
            return;
        }
        mediaArtDownloader.running = false;
        mediaArtDownloader.running = true;
    }

    onMediaArtUrlChanged: root.refreshMediaArt()
    Component.onCompleted: root.refreshMediaArt()

    Process {
        id: mediaArtDownloader
        command: ["bash", "-c", `[ -f '${root.mediaArtFilePath}' ] || curl -sSL '${root.mediaArtUrl}' -o '${root.mediaArtFilePath}'`]
        onExited: root.mediaArtDownloaded = true
    }

    ColorQuantizer {
        id: mediaColorQuantizer
        source: root.mediaDisplayedArt
        depth: 0
        rescaleSize: 1
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.today = new Date()
    }

    Rectangle {
        id: shell
        anchors.centerIn: parent
        // The swipe gesture's lean. Real geometry again rather than a transform, so the whole pill
        // and everything anchored inside it travels together.
        anchors.horizontalCenterOffset: root.dragOffset
        // Overdraws the layout width by exactly the outer pill's padding when hovered, so the two
        // become flush. Neither dimension carries a Behavior of its own: both inputs are already
        // animated above, and easing an eased value just makes the pill lag.
        width: root.animatedWidth + root.hoverGrow * root.outerPadding
        height: Appearance.sizes.barHeight - root.restInset + root.hoverGrow * root.restInset
        radius: Appearance.rounding.full
        clip: true

        color: root.expanded
            ? Appearance.colors.colSurfaceContainerHigh
            : root.mediaBgActive
                ? root.mediaBlended.colLayer0
                : (mouseArea.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        border.width: root.expanded ? 1 : 0
        border.color: Appearance.colors.colPrimary

        // Blurred cover + veil, exactly like the dock player card. Under
        // everything (including the MouseArea, which paints nothing).
        // Masked to the pill shape: the blur renders as an offscreen layer,
        // which the shell's clip can't trim, so without this its square
        // corners would stick out over the rounded pill.
        Item {
            id: islandBg
            anchors.fill: parent
            visible: root.mediaBgActive && !root.expanded
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: islandBg.width
                    height: islandBg.height
                    radius: shell.radius
                }
            }

            Image {
                id: islandBlurredArt
                anchors.fill: parent
                source: root.mediaDisplayedArt
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true
                layer.enabled: true
                layer.effect: StyledBlurEffect {
                    source: islandBlurredArt
                }
            }

            Rectangle {
                id: islandVeil
                anchors.fill: parent
                color: ColorUtils.transparentize(root.mediaBlended.colLayer0,
                    (mouseArea.containsMouse && !root.expanded) ? 0.45 : 0.55)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        scale: mouseArea.pressed && !root.expanded ? 0.97 : 1
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // The attention pop when the context changes or a track advances. Driven through a Scale
        // transform rather than `scale` so it doesn't fight the hover Behavior above -- two
        // animations on one property just stutter.
        property real bounce: 1
        transform: Scale {
            origin.x: shell.width / 2
            origin.y: shell.height / 2
            xScale: shell.bounce
            yScale: shell.bounce
        }

        SequentialAnimation {
            id: bounceAnim
            NumberAnimation {
                target: shell
                property: "bounce"
                to: 1.05
                duration: 120
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: shell
                property: "bounce"
                to: 1
                duration: 280
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        Connections {
            target: IslandState
            function onActivityChanged() {
                bounceAnim.restart();
            }
        }

        Connections {
            target: MprisController
            enabled: IslandState.activity === "media"
            function onActiveTrackChanged() {
                bounceAnim.restart();
            }
        }

        // Declared before the content so it sits *under* it: the search field and mode chips get
        // their clicks first, while the non-interactive collapsed content lets clicks fall
        // through to here. Gating `enabled` on the mode instead would mean the click that opens
        // the island is also the last one it ever receives.
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

            // Scrolling over the pill moves the selection, and the results list follows via
            // positionViewAtIndex. The list lives in a different window, so the wheel can't reach
            // it from here -- but the selection is shared state, so this is the way across.
            // Collapsed, the same wheel is a volume dial instead: the change triggers the usual OSD
            // burst, which the pill is already absorbing, so it morphs to the slider on its own.
            property real wheelAccum: 0
            property real volumeAccum: 0
            onWheel: wheel => {
                const threshold = Config.options.interactions.scrolling.mouseScrollDeltaThreshold;
                if (!IslandState.searchActive) {
                    if (!Config.options.bar.island.scrollVolume) {
                        wheel.accepted = false;
                        return;
                    }
                    mouseArea.volumeAccum += wheel.angleDelta.y;
                    while (Math.abs(mouseArea.volumeAccum) >= threshold) {
                        const up = mouseArea.volumeAccum > 0;
                        Audio.stepVolume(up ? 1 : -1);
                        mouseArea.volumeAccum -= up ? threshold : -threshold;
                    }
                    wheel.accepted = true;
                    return;
                }
                console.log("[Island] pill wheel", wheel.angleDelta.y, "selected", IslandState.selectedIndex, "of", IslandState.resultCount);
                mouseArea.wheelAccum += wheel.angleDelta.y;
                while (Math.abs(mouseArea.wheelAccum) >= threshold) {
                    IslandState.moveSelection(mouseArea.wheelAccum > 0 ? -1 : 1);
                    mouseArea.wheelAccum -= (mouseArea.wheelAccum > 0 ? threshold : -threshold);
                }
                wheel.accepted = true;
            }

            // Swipe-to-skip. The pill can't actually move in the layout -- BarContent sizes the
            // outer material pill from root.animatedWidth -- so the gesture produces a capped lean
            // that springs back, and one dragSkipDistance of travel advances exactly one track.
            // Strictly one skip per press-drag-release: some players (notably YT Music's MPRIS
            // bridge) queue rapid Next/Previous calls and grind through them long after release,
            // so a ratchet that fires repeatedly walks to the end of the list unplayed.
            property real dragPressX: 0
            property real dragOriginX: 0
            property bool dragActive: false
            property bool dragSwiped: false
            property bool dragFired: false

            // Window coordinates, never this MouseArea's own. It fills the shell, and the shell both
            // leans (dragOffset) and scales (the press feedback) underneath the pointer, so a local x
            // would move even for a pointer standing still and the lean would chase itself.
            function pointerX(event) {
                return mouseArea.mapToItem(null, event.x, event.y).x;
            }

            function dragLean(delta) {
                const max = root.dragMaxOffset;
                const sign = delta < 0 ? -1 : 1;
                return sign * max * (1 - Math.exp(-Math.abs(delta) / max));
            }

            onPressed: event => {
                // Cleared for every button, not just the left one: a right-click landing after a
                // swipe must not be swallowed by the guard that swipe left behind.
                mouseArea.dragSwiped = false;
                if (event.button !== Qt.LeftButton)
                    return;
                const x = mouseArea.pointerX(event);
                mouseArea.dragPressX = x;
                mouseArea.dragOriginX = x;
                mouseArea.dragActive = false;
                mouseArea.dragFired = false;
            }

            onPositionChanged: event => {
                // hoverEnabled means this also fires with no button down.
                if (!(mouseArea.pressedButtons & Qt.LeftButton) || !root.dragEnabled)
                    return;
                const x = mouseArea.pointerX(event);
                if (!mouseArea.dragActive) {
                    if (Math.abs(x - mouseArea.dragPressX) < root.dragStartDistance)
                        return;
                    mouseArea.dragActive = true;
                    mouseArea.dragSwiped = true;
                }
                const delta = x - mouseArea.dragOriginX;
                // One skip per gesture, then the pill just leans: firing again while the pointer
                // keeps travelling is what queued up unplayed skips on slower players.
                if (!mouseArea.dragFired && Math.abs(delta) >= root.dragSkipDistance) {
                    const backwards = delta > 0;
                    // MprisController guards both on canGoNext/canGoPrevious, so a player that can't
                    // skip in that direction simply doesn't move.
                    if (backwards !== Config.options.bar.island.swipeInvert)
                        MprisController.previous();
                    else
                        MprisController.next();
                    mouseArea.dragFired = true;
                }
                root.dragOffset = mouseArea.dragLean(delta);
            }

            onReleased: event => {
                if (event.button !== Qt.LeftButton)
                    return;
                mouseArea.dragActive = false;
                root.dragOffset = 0;
                // dragSwiped deliberately survives: released fires before clicked, and it is what
                // stops the swipe from also opening the dashboard. The next press clears it.
            }

            onCanceled: {
                mouseArea.dragActive = false;
                mouseArea.dragSwiped = false;
                mouseArea.dragFired = false;
                root.dragOffset = 0;
            }

            onClicked: event => {
                if (event.button === Qt.MiddleButton) {
                    IslandState.toggle("search");
                    return;
                }
                if (event.button === Qt.RightButton) {
                    // Gated on the player, not on IslandState.activity: `activity` is only "media"
                    // while something is *playing*, so gating on it made right-click a pause-only
                    // button that could never resume. togglePlayer keeps that guard and routes
                    // Firefox-family players through the PlayPause method they actually honour.
                    MprisController.togglePlaying();
                    return;
                }
                // A drag that ends on the pill still emits clicked. Opening the dashboard on top of
                // a track change is not what the gesture asked for.
                if (mouseArea.dragSwiped)
                    return;
                // While the search surface is up its own controls own the left button.
                if (IslandState.searchActive)
                    return;
                IslandState.toggle("dashboard");
            }

            // Keeps the calendar-on-hover that clockWidget provided, so replacing it in the
            // middle layout doesn't cost anything. Suppressed while expanded -- a tooltip over
            // the search field would be in the way -- and while a swipe is in progress, where a
            // calendar hanging off the pill is just in the way of the gesture.
            // The collapse grace matters: the dashboard and the popup are separate layer
            // windows, and the compositor keeps fading the dashboard out for a moment after
            // the island collapses. An instant hover re-open stacks the two translucent
            // surfaces and ghosts them together on screen.
            ClockWidgetPopup {
                hoverTarget: mouseArea
                today: root.today
                active: mouseArea.containsMouse && !root.expanded && !mouseArea.dragActive
                    && !collapseGrace.running && !Config.options.bar.tooltips.clickToShow
            }

            Timer {
                id: collapseGrace
                interval: 450
            }

            Connections {
                target: root
                function onExpandedChanged() {
                    if (!root.expanded)
                        collapseGrace.restart();
                }
            }
        }

        Item {
            id: contextArea
            anchors.left: parent.left
            anchors.leftMargin: root.horizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: root.contextWidth
            implicitHeight: root.contextContent?.implicitHeight ?? 0
            width: implicitWidth
            height: implicitHeight
            opacity: root.expanded ? 0 : 1

            // Asymmetric on purpose, and the clock below matches. Opening, the collapsed content
            // has to be gone *before* the field arrives or the two overlap inside a pill that is
            // still narrow, which is the part that read as a jumble: 120ms out on an accel curve
            // clears it in the first third of the 350ms morph. Closing, it comes back slower and
            // on a decel curve, arriving as the pill finishes shrinking around it.
            Behavior on opacity {
                NumberAnimation {
                    duration: root.expanded ? 120 : 260
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.expanded
                        ? Appearance.animationCurves.emphasizedAccel
                        : Appearance.animationCurves.emphasizedDecel
                }
            }

            FadeLoader {
                id: weatherLoader
                anchors.centerIn: parent
                shown: root.weatherShown && IslandState.activity === "idle"
                sourceComponent: IslandWeather {}
            }

            FadeLoader {
                id: mediaLoader
                anchors.centerIn: parent
                shown: IslandState.activity === "media"
                sourceComponent: IslandMedia {}
                onLoaded: {
                    // Hand the pill's real background down so the label and
                    // meter flip against the cover tint, not the theme.
                    if (item && item.pillBg !== undefined)
                        item.pillBg = Qt.binding(() => root.islandPillBg);
                }
            }

            FadeLoader {
                id: osdLoader
                anchors.centerIn: parent
                shown: IslandState.activity === "osd"
                sourceComponent: IslandOsd {}
            }
        }

        Rectangle {
            id: separator
            visible: root.hasContext && !root.expanded
            opacity: contextArea.opacity
            anchors.left: contextArea.right
            anchors.leftMargin: root.gap
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            // Same readability flip as the island text: a light pill needs a
            // darker hairline, and vice versa.
            color: ColorUtils.pickReadable(
                Appearance.colors.colOutlineVariant,
                !ColorUtils.isDark(root.islandPillBg) ? "#71787E" : "#C1C7CE")
        }

        IslandClock {
            id: clock
            pillBg: root.islandPillBg
            anchors.right: parent.right
            anchors.rightMargin: root.horizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.expanded ? 0 : 1

            // Same asymmetry as contextArea above -- out fast, back slowly.
            Behavior on opacity {
                NumberAnimation {
                    duration: root.expanded ? 120 : 260
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.expanded
                        ? Appearance.animationCurves.emphasizedAccel
                        : Appearance.animationCurves.emphasizedDecel
                }
            }
        }

        // Fills the shell rather than centring, because the field has to stretch across it.
        //
        // The loader is never gated on the morph's progress, only the content's opacity is: the
        // field has to exist from the first frame so IslandSearchField's Component.onCompleted can
        // take focus, or the first keystrokes after Alt+Space land nowhere.
        FadeLoader {
            id: searchLoader
            anchors.fill: parent
            anchors.leftMargin: root.horizontalPadding
            anchors.rightMargin: root.horizontalPadding
            shown: IslandState.searchActive

            // What *is* gated is what you see. The field is laid out at the shell's current width,
            // so early in the morph its mode chips, hairline, input and close button are crushed
            // into a quarter of the room they need -- and clipped by the shell. Holding them back
            // until the pill has actually opened up skips that frame entirely. Clamped to the
            // pill's own final inner width, so a hand-lowered island.searchWidth still reveals it
            // rather than leaving the pill permanently blank.
            readonly property real revealWidth: Math.min(
                searchLoader.item?.naturalWidth ?? Infinity,
                Config.options.bar.island.searchWidth - root.horizontalPadding * 2)

            sourceComponent: IslandSearchField {
                opacity: searchLoader.width >= searchLoader.revealWidth ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}

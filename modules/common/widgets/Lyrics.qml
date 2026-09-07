pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Services.Mpris

/**
 * Synced lyrics with a word by word sweep.
 *
 * Every line is laid out once by an ordinary Text, which keeps Qt's own wrapping, alignment and
 * kerning. The line that is playing then draws a second time as one item per word, each placed at
 * the character rectangle that Text already laid out, so a word can lift and brighten on its own
 * without the line reflowing or the list shifting. Everything visual hangs off
 * LyricsService.position, which is sampled per frame while a view is open.
 *
 * All lines share one font size; the difference between the playing line and the rest is a
 * transform, never a size, so a line changing state can never move its neighbours.
 */
Item {
    id: root

    property MprisPlayer player: LyricsService.activePlayer
    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft
    property bool clickToSeek: true
    // Dragging the lines to scroll them. Off for consumers that need the drag themselves
    property bool dragScroll: true
    // Idle time before the view snaps back to the playing line
    property int followResumeDelay: 4000
    // True while the user is reading somewhere else in the song
    property bool browsing: false

    readonly property bool synced: LyricsService.synced
    readonly property bool canSeek: root.clickToSeek && root.synced && (root.player?.canSeek ?? false)

    // Which of the three views this is drawing, stepped through by clicking the cover art
    readonly property string mode: LyricsService.mode
    // A page to read rather than a view that follows the song: no highlight, no scaling of the line
    // playing, no auto scrolling, and none of the shader passes below
    readonly property bool raw: root.mode === "raw"

    // The sweep, the bloom and the depth blur are each a render pass or two, so each has a switch
    readonly property bool karaoke: root.mode === "karaoke" && root.synced
        && (Config?.options.media.lyricsKaraoke ?? true)
    // Lyrics with only line timings get no sweep unless this is on: a per word highlight there
    // would be invented, and a singer holding one syllable makes the invention obvious
    readonly property bool lineWipe: root.mode === "karaoke" && (Config?.options.media.lyricsLineWipe ?? false)
    readonly property bool glow: !root.raw && (Config?.options.media.lyricsGlow ?? true)
    readonly property bool depthBlur: !root.raw && root.synced && (Config?.options.media.lyricsBlur ?? true)

    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

    // One knob for lyric text size, read by every consumer of this widget (media controls popup,
    // left sidebar player, desktop media widget, island Media tab) so they stay in step.
    property real fontScale: Config?.options.media.lyricsFontScale ?? 1.25
    readonly property int activeFontSize: Math.round(Appearance.font.pixelSize.normal * root.fontScale)
    readonly property int inactiveFontSize: Math.round(Appearance.font.pixelSize.small * root.fontScale)
    // Idle lines shrink by transform rather than by font size, keeping the ratio the size knobs ask for
    readonly property real inactiveScale: Math.max(0.75, root.inactiveFontSize / root.activeFontSize)

    implicitWidth: 200
    implicitHeight: 150

    signal seeked(real position)

    function restartLyrics() {
        LyricsService.restartLyrics();
    }

    // For callers that only need the highlight to catch up, e.g. after seeking
    function syncNow() {
        root.stopBrowsing();
        LyricsService.syncNow();
    }

    // Routed through MediaSeeker so the seek bar, the time readout and this view all show the
    // requested position while a player takes its time about applying it
    function seekTo(position) {
        if (!root.canSeek)
            return;
        if (!MediaSeeker.seekTo(root.player, position))
            return;
        root.stopBrowsing();
        LyricsService.syncNow();
        root.seeked(position);
    }

    function markBrowsing() {
        root.browsing = true;
        resumeTimer.restart();
    }

    function stopBrowsing() {
        resumeTimer.stop();
        root.browsing = false;
        root.followActive(true);
    }

    function scrollTo(y, animated) {
        const target = Math.max(lyricsView.minContentY, Math.min(y, lyricsView.maxContentY));
        scrollAnimation.stop();
        // A jump of several screens is a seek, not a line change; animating that just smears
        const far = Math.abs(target - lyricsView.contentY) > lyricsView.height * 2.5;
        if (!animated || far || Math.abs(target - lyricsView.contentY) < 1) {
            lyricsView.contentY = target;
            return;
        }
        scrollAnimation.from = lyricsView.contentY;
        scrollAnimation.to = target;
        scrollAnimation.start();
    }

    function followActive(animated) {
        if (!root.visible || lyricsView.count === 0 || lyricsView.height <= 0)
            return;
        // Nothing chases the song in the raw view: the scroll stays where the reader left it
        if (root.raw)
            return;
        const idx = LyricsService.activeIndex;
        if (idx < 0 || idx >= lyricsView.count) {
            root.scrollTo(lyricsView.minContentY, animated);
            return;
        }
        // positionViewAtIndex snaps, so use it to measure and animate there ourselves
        const from = lyricsView.contentY;
        lyricsView.positionViewAtIndex(idx, ListView.Center);
        const target = lyricsView.contentY;
        lyricsView.contentY = from;
        root.scrollTo(target, animated);
    }

    function followActiveAnimated() {
        root.followActive(true);
    }

    function snapToActive() {
        root.followActive(false);
    }

    onVisibleChanged: {
        if (root.visible) {
            LyricsService.addViewer();
            Qt.callLater(root.snapToActive);
        } else {
            LyricsService.removeViewer();
            resumeTimer.stop();
            root.browsing = false;
        }
    }
    Component.onCompleted: if (root.visible) LyricsService.addViewer()
    Component.onDestruction: if (root.visible) LyricsService.removeViewer()

    onWidthChanged: if (!root.browsing) Qt.callLater(root.snapToActive)
    onHeightChanged: if (!root.browsing) Qt.callLater(root.snapToActive)

    // Switching view is a different way of reading the same song, so start each one where it makes
    // sense: the raw page at the beginning, the other two back on the line playing
    onModeChanged: {
        resumeTimer.stop();
        root.browsing = false;
        if (root.raw)
            Qt.callLater(root.scrollToTop);
        else
            Qt.callLater(root.snapToActive);
    }

    function scrollToTop() {
        root.scrollTo(lyricsView.minContentY, false);
    }

    Connections {
        target: LyricsService

        function onActiveIndexChanged() {
            if (root.browsing)
                return;
            Qt.callLater(root.followActiveAnimated);
        }

        function onLyricsLinesChanged() {
            resumeTimer.stop();
            root.browsing = false;
            Qt.callLater(root.raw ? root.scrollToTop : root.snapToActive);
        }
    }

    Timer {
        id: resumeTimer
        interval: root.followResumeDelay
        onTriggered: {
            root.browsing = false;
            root.followActive(true);
        }
    }

    // Overshoots slightly, which is what makes a line change read as the list settling rather
    // than as a jump
    NumberAnimation {
        id: scrollAnimation
        target: lyricsView
        property: "contentY"
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    // The single source of truth for lyric text metrics: the hidden layout pass, the per word
    // items and the width measurements all read this, so they can never disagree by a pixel
    FontMetrics {
        id: lyricMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: root.activeFontSize
        font.weight: Font.DemiBold
        font.hintingPreference: Font.PreferDefaultHinting
        font.variableAxes: ({
            "wght": 600,
            "wdth": 100
        })
    }

    readonly property bool hasLines: LyricsService.status === "ok" && LyricsService.lyricsLines.length > 0

    Item { // Loading, instrumental, retry and error states
        anchors.fill: parent
        visible: !root.hasLines

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10

            MaterialLoadingIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: LyricsService.status === "loading"
                loading: LyricsService.status === "loading"
                colBg: root.indicatorColor
                colShape: root.indicatorShapeColor
                implicitSize: 48
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: root.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: root.dimColor
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: {
                    if (LyricsService.status === "loading")
                        return Translation.tr("Looking for lyrics...");
                    if (LyricsService.status === "no_info")
                        return Translation.tr("No track info");
                    if (LyricsService.instrumental)
                        return Translation.tr("Instrumental");
                    return Translation.tr("No lyrics found. Click to retry");
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: LyricsService.status !== "loading"
            cursorShape: Qt.PointingHandCursor
            onClicked: LyricsService.restartLyrics()
        }
    }

    ListView {
        id: lyricsView
        anchors.fill: parent
        visible: root.hasLines
        clip: true
        // The desktop card turns this off while its widgets are unlocked, so a drag anywhere on the
        // card moves the card instead of scrolling the song. The wheel keeps working either way.
        interactive: root.dragScroll
        spacing: Math.round(root.activeFontSize * 0.22)
        cacheBuffer: 800
        boundsBehavior: Flickable.StopAtBounds
        maximumFlickVelocity: 2500
        model: LyricsService.lyricsLines
        // Enough slack for the first and last line to reach the middle. The raw view is read from
        // the top, so it gets ordinary padding instead of half a screen of it.
        topMargin: root.raw ? Math.round(root.activeFontSize * 0.5)
            : Math.max(0, height / 2 - lyricMetrics.lineSpacing / 2)
        bottomMargin: root.raw ? Math.round(root.activeFontSize * 0.5)
            : Math.max(0, height / 2 - lyricMetrics.lineSpacing / 2)

        readonly property real minContentY: -lyricsView.topMargin
        readonly property real maxContentY: Math.max(lyricsView.minContentY,
            lyricsView.contentHeight + lyricsView.bottomMargin - lyricsView.height)

        ScrollBar.vertical: StyledScrollBar {}

        onDragStarted: root.markBrowsing()
        onFlickStarted: root.markBrowsing()
        onMovementEnded: if (root.browsing) resumeTimer.restart()

        delegate: Item {
            id: lineDelegate
            required property int index
            required property var modelData

            readonly property bool interlude: (lineDelegate.modelData?.interlude ?? false) && root.synced
                && !root.raw
            readonly property bool current: lineDelegate.index === LyricsService.activeIndex
            readonly property bool past: LyricsService.activeIndex >= 0
                && lineDelegate.index < LyricsService.activeIndex
            readonly property int distance: LyricsService.activeIndex < 0
                ? 0 : Math.abs(lineDelegate.index - LyricsService.activeIndex)
            readonly property string lineText: lineDelegate.modelData?.text ?? ""
            // Only true when the source really timed the words. Nothing here invents timings.
            readonly property bool wordTimed: (lineDelegate.modelData?.words?.length ?? 0) > 0
            readonly property bool sweeping: root.karaoke && lineDelegate.current
                && !lineDelegate.interlude && lineDelegate.chunks.length > 0
                && (lineDelegate.wordTimed || root.lineWipe)

            // positionToRectangle() is a method call, so bindings built on it need something that
            // changes when the layout does
            property int layoutRevision: 0

            // One entry per drawn chunk: the text, where it starts inside the line (so it can be
            // drawn at the rectangle Qt already laid out for it) and, when the source timed it,
            // when it is sung. start < 0 means "no timing, wipe this one by position in the line".
            readonly property var chunks: {
                const text = lineDelegate.lineText;
                if (!text || !(lineDelegate.wordTimed || root.lineWipe))
                    return [];
                const result = [];
                const timed = lineDelegate.modelData?.words ?? [];
                if (timed.length > 0) {
                    let cursor = 0;
                    for (let i = 0; i < timed.length; i++) {
                        const word = timed[i]?.text ?? "";
                        const at = text.indexOf(word, cursor);
                        const offset = at >= 0 ? at : cursor;
                        result.push({
                            text: word,
                            offset: offset,
                            start: timed[i]?.start ?? 0,
                            end: timed[i]?.end ?? 0
                        });
                        cursor = offset + word.length;
                    }
                    return result;
                }
                // Line timings only: split the line here and let the wipe cross it at reading
                // pace. Handing each word a made up timestamp instead would claim to know when it
                // is sung, and any singer who holds or rushes a syllable makes that claim wrong.
                const parts = text.split(/(\s+)/);
                let offset = 0;
                for (let i = 0; i < parts.length; i++) {
                    if (parts[i].trim().length > 0)
                        result.push({ text: parts[i], offset: offset, start: -1, end: -1 });
                    offset += parts[i].length;
                }
                return result;
            }

            width: lyricsView.width
            height: (lineDelegate.interlude
                ? Math.round(lyricMetrics.lineSpacing * 0.85)
                : baseText.implicitHeight) + Math.round(root.activeFontSize * 0.45)

            Rectangle { // Click affordance
                anchors.fill: parent
                anchors.leftMargin: -4
                anchors.rightMargin: -4
                radius: Appearance.rounding.verysmall
                color: ColorUtils.transparentize(root.textColor, 0.92)
                opacity: (lineArea.containsMouse && root.canSeek) ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            // Fades lines towards the top and bottom edges. Done per line rather than by masking
            // the whole view, so it works over any background and stacks with the depth blur.
            Item {
                id: fader
                anchors.fill: parent
                opacity: {
                    if (root.raw)
                        return 1;
                    const half = lyricsView.height / 2;
                    if (!(half > 0))
                        return 1;
                    const center = lyricsView.contentY + half;
                    const offset = Math.abs(lineDelegate.y + lineDelegate.height / 2 - center) / half;
                    return Math.max(0, Math.min(1, 1.1 - Math.pow(Math.max(0, offset), 2.4)));
                }

                Item {
                    id: content
                    anchors.fill: parent
                    transformOrigin: root.textAlignment === Text.AlignHCenter
                        ? Item.Center
                        : (root.textAlignment === Text.AlignRight ? Item.Right : Item.Left)
                    scale: (root.raw || lineDelegate.current || root.browsing || !root.synced) ? 1 : root.inactiveScale
                    opacity: {
                        // Every line reads the same in the raw view, which is the point of it
                        if (root.raw)
                            return 0.9;
                        if (!root.synced)
                            return 0.85;
                        if (lineDelegate.current)
                            return 1;
                        if (root.browsing)
                            return 0.75;
                        const base = lineDelegate.distance === 1 ? 0.55
                            : (lineDelegate.distance === 2 ? 0.38 : 0.24);
                        return lineDelegate.past ? base * 0.75 : base;
                    }

                    // Depth: lines further from the one playing are softened as well as dimmed
                    layer.enabled: root.depthBlur && !root.browsing && lineDelegate.distance >= 2
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 16
                        blur: Math.min(1, (lineDelegate.distance - 1) * 0.4)
                    }

                    Behavior on scale {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    // Bloom behind the line being sung: one texture and one blur pass, and only
                    // ever for the single line that is actually playing
                    Loader {
                        anchors.fill: baseText
                        z: -1
                        active: root.glow && lineDelegate.current && !lineDelegate.interlude
                        sourceComponent: Component {
                            Item {
                                ShaderEffectSource {
                                    id: glowSource
                                    anchors.fill: parent
                                    visible: false
                                    live: true
                                    hideSource: false
                                    sourceItem: lineDelegate.sweeping ? sweep : baseText
                                }

                                // No brightness lift here: MultiEffect adds it to fully transparent
                                // pixels too, and premultiplied compositing turns that into a
                                // visible grey box the size of the line. Blur alone is the glow.
                                MultiEffect {
                                    anchors.fill: parent
                                    source: glowSource
                                    blurEnabled: true
                                    blurMax: 32
                                    blur: 1
                                    opacity: 0.5
                                }
                            }
                        }
                    }

                    // Lays the line out and draws it whenever the sweep isn't. TextEdit rather than
                    // Text because only TextEdit can report where a character ended up, which is
                    // what the per word items are placed by. QtRendering because these get scaled,
                    // and NativeRendering goes soft under a transform.
                    TextEdit {
                        id: baseText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !lineDelegate.interlude
                        // Read only isn't enough: this must not eat clicks or drags from the list
                        enabled: false
                        readOnly: true
                        selectByMouse: false
                        selectByKeyboard: false
                        activeFocusOnPress: false
                        cursorVisible: false
                        padding: 0
                        textMargin: 0
                        textFormat: TextEdit.PlainText
                        horizontalAlignment: root.textAlignment
                        wrapMode: TextEdit.WordWrap
                        renderType: TextEdit.QtRendering
                        font: lyricMetrics.font
                        text: lineDelegate.modelData?.text ?? ""
                        color: (lineDelegate.current && !root.raw) ? root.activeColor : root.textColor
                        // The sweep redraws the same glyphs word by word, so hand over to it
                        opacity: lineDelegate.sweeping ? 0 : 1

                        onWidthChanged: lineDelegate.layoutRevision++
                        onTextChanged: lineDelegate.layoutRevision++
                        onContentHeightChanged: lineDelegate.layoutRevision++

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }


                    // Draws the line being sung a chunk at a time. Word timed sources get a real
                    // per word sweep; line timed ones get one continuous edge crossing the line, at
                    // the same place a reader's eye would be.
                    Item {
                        id: sweep
                        anchors.fill: baseText
                        visible: lineDelegate.sweeping

                        Repeater {
                            model: lineDelegate.sweeping ? lineDelegate.chunks : []

                            delegate: Item {
                                id: wordItem
                                required property int index
                                required property var modelData

                                readonly property string word: wordItem.modelData?.text ?? ""
                                readonly property bool timed: (wordItem.modelData?.start ?? -1) >= 0
                                readonly property rect box: {
                                    lineDelegate.layoutRevision; // Recompute when the line relaid out
                                    // Delegates are recycled, so for a frame the offsets can belong
                                    // to a longer line than the one currently in baseText
                                    const at = Math.max(0, Math.min(wordItem.modelData?.offset ?? 0,
                                        baseText.length));
                                    return baseText.positionToRectangle(at);
                                }
                                // 0 before this chunk is sung, 1 once it has been
                                readonly property real progress: {
                                    if (wordItem.timed) {
                                        const start = wordItem.modelData.start;
                                        const end = Math.max(start + 0.08, wordItem.modelData.end);
                                        return Math.max(0, Math.min(1, (LyricsService.position - start) / (end - start)));
                                    }
                                    // Untimed: the edge advances through the line's characters as the
                                    // line plays, so it never lights a word out of order and never
                                    // stalls mid line
                                    const reached = LyricsService.lineProgress * lineDelegate.lineText.length;
                                    const offset = wordItem.modelData?.offset ?? 0;
                                    return Math.max(0, Math.min(1,
                                        (reached - offset) / Math.max(1, wordItem.word.length)));
                                }
                                // Rises fast and then holds, so a sung word stays lifted until the line
                                // changes. Only for real word timings: lifting a word the source never
                                // timed would be a guess drawn as a fact.
                                readonly property real lift: (wordItem.timed && wordItem.progress > 0)
                                    ? Math.pow(wordItem.progress, 0.4) : 0

                                x: wordItem.box.x
                                y: wordItem.box.y - 2 * wordItem.lift
                                width: wordMetrics.advanceWidth
                                height: wordItem.box.height
                                transformOrigin: Item.Bottom
                                scale: 1 + 0.04 * wordItem.lift

                                TextMetrics {
                                    id: wordMetrics
                                    font: lyricMetrics.font
                                    text: wordItem.word
                                }

                                Text { // Not sung yet
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    renderType: Text.QtRendering
                                    font: lyricMetrics.font
                                    text: wordItem.word
                                    color: root.textColor
                                    opacity: 0.45
                                }

                                Item { // Sung: wiped in across the word as it is sung
                                    width: Math.round(wordItem.width * wordItem.progress)
                                    height: wordItem.height
                                    clip: true

                                    Text {
                                        width: wordItem.width
                                        height: wordItem.height
                                        verticalAlignment: Text.AlignVCenter
                                        renderType: Text.QtRendering
                                        font: lyricMetrics.font
                                        text: wordItem.word
                                        color: root.activeColor
                                    }
                                }
                            }
                        }
                    }

                    // Instrumental breaks: three dots that fill as the gap runs out
                    Row {
                        id: interludeDots
                        visible: lineDelegate.interlude
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: root.textAlignment === Text.AlignLeft ? parent.left : undefined
                        anchors.right: root.textAlignment === Text.AlignRight ? parent.right : undefined
                        anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter
                            ? parent.horizontalCenter : undefined
                        spacing: Math.round(root.activeFontSize * 0.34)
                        opacity: lineDelegate.current ? 1 : 0.5
                        // Breathes while the gap runs. Driven by the sampled position rather than by
                        // an animation, so nothing is left stuck mid pulse when the line changes.
                        scale: lineDelegate.current
                            ? 1 + 0.05 * Math.sin(LyricsService.position * 2.2) : 0.8

                        Repeater {
                            model: 3

                            delegate: Rectangle {
                                id: dot
                                required property int index

                                readonly property real fill: lineDelegate.current
                                    ? Math.max(0, Math.min(1, LyricsService.lineProgress * 3 - dot.index))
                                    : 0

                                implicitWidth: Math.round(root.activeFontSize * 0.42)
                                implicitHeight: dot.implicitWidth
                                radius: dot.width / 2
                                color: root.activeColor
                                opacity: 0.28 + 0.72 * dot.fill
                                scale: 0.7 + 0.35 * dot.fill
                            }
                        }
                    }


                }

            }

            MouseArea {
                id: lineArea
                anchors.fill: parent
                enabled: root.canSeek
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.seekTo(lineDelegate.modelData?.time ?? 0)
            }
        }

    }

    // Wheel scrolling lives here so any scroll also pauses the auto following.
    // NoButton keeps clicks falling through to the lines underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        enabled: lyricsView.visible
        onWheel: wheel => {
            const threshold = root.mouseScrollDeltaThreshold;
            const steps = wheel.angleDelta.y / threshold;
            // Touchpads send small continuous deltas, wheels send multiples of ±120
            const factor = Math.abs(wheel.angleDelta.y) >= threshold
                ? root.mouseScrollFactor : root.touchpadScrollFactor;
            const base = scrollAnimation.running ? scrollAnimation.to : lyricsView.contentY;
            root.markBrowsing();
            root.scrollTo(base - steps * factor, true);
            wheel.accepted = true;
        }
    }
}

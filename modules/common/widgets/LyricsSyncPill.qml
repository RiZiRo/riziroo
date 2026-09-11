pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * The per-track lyrics sync adjustment, floating over a media view's cover art.
 *
 * A round timer chip appears at the cover's top-left corner while the cover is hovered -- the
 * consumer passes that state in as coverHovered. Clicking the chip opens a small panel below it
 * that stays within the cover: the offset can be nudged either way, reset, or the lyrics looked
 * up again when the match itself is wrong. The chip never moves, so the way in is also the way
 * out, and the panel folds itself away when the pointer leaves.
 *
 * The chip and panel own their palette instead of following the view's: they sit on album art,
 * where a tint of the text color vanishes on bright covers and smudges on dark ones, and a theme
 * accent can go dark on a light theme. A dark scrim with white content reads on any artwork.
 */
Item {
    id: root

    // The cover's hover state, supplied by whatever this is floating over
    property bool coverHovered: false
    property bool expanded: false

    // Nothing to adjust when the lyrics aren't following the song, and the raw view is a page to
    // read rather than a view that follows
    readonly property bool lyricsAdjustable: LyricsService.synced && LyricsService.status === "ok"
        && LyricsService.lyricsLines.length > 0 && LyricsService.mode !== "raw"

    // Hovering any part of the chip or panel must keep them alive, or they would blink out on the
    // way from the cover to a button: the buttons report their own hover, the backgrounds through
    // their hover catchers
    readonly property bool anyHover: root.coverHovered || chipHover.containsMouse || panelHover.containsMouse
        || timerButton.hovered || minusButton.hovered || plusButton.hovered
        || resetButton.hovered || lookupButton.hovered

    readonly property string offsetReadout: {
        const seconds = LyricsService.offsetMs / 1000;
        const sign = seconds > 0 ? "+" : seconds < 0 ? "-" : "";
        return sign + Math.abs(seconds).toFixed(2) + "s";
    }

    // The panel is only useful while the pointer is on it, so leaving puts the chip back the way
    // it was found instead of keeping an open panel around
    onAnyHoverChanged: {
        if (!root.anyHover)
            root.expanded = false;
    }

    component SyncPillButton: RippleButton {
        id: pillButton
        property string iconName
        implicitWidth: 24
        implicitHeight: 24
        buttonRadius: height / 2
        pointingHandCursor: true
        colBackground: "transparent"
        colBackgroundHover: Qt.rgba(1, 1, 1, 0.14)
        colRipple: Qt.rgba(1, 1, 1, 0.22)
        contentItem: MaterialSymbol {
            iconSize: 16
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: pillButton.toggled ? "#ffffff" : Qt.rgba(1, 1, 1, 0.8)
            text: pillButton.iconName
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    // The toggle. Expanding adds the panel below rather than moving this, so the button that
    // opened the panel is also the one that closes it.
    Rectangle {
        id: chip
        anchors.top: parent.top
        anchors.left: parent.left
        width: 30
        height: 30
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.55)
        border.width: 1
        border.color: ColorUtils.transparentize("#ffffff", 0.75)
        opacity: root.anyHover && root.lyricsAdjustable ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MouseArea {
            id: chipHover
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
        }

        SyncPillButton {
            id: timerButton
            anchors.centerIn: parent
            iconName: "timer"
            toggled: root.expanded
            downAction: () => { root.expanded = !root.expanded; }
            StyledToolTip { text: Translation.tr("Adjust lyrics sync") }
        }
    }

    // The adjustment panel. Two short rows rather than one long bar, so it never reaches past the
    // cover onto whatever is beside it.
    Rectangle {
        id: panel
        anchors.top: chip.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        width: panelContent.implicitWidth + 12
        height: panelContent.implicitHeight + 12
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.55)
        border.width: 1
        border.color: ColorUtils.transparentize("#ffffff", 0.75)
        opacity: root.expanded && root.anyHover && root.lyricsAdjustable ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MouseArea {
            id: panelHover
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
        }

        ColumnLayout {
            id: panelContent
            anchors.centerIn: parent
            spacing: 4

            RowLayout {
                spacing: 2

                SyncPillButton {
                    id: minusButton
                    iconName: "remove"
                    downAction: () => LyricsService.nudgeOffset(-100)
                    StyledToolTip { text: Translation.tr("Show lines later") }
                }

                StyledText {
                    // Keeps the row from twitching as the value crosses zero or changes sign
                    Layout.minimumWidth: 46
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: { "tnum": 1 }
                    color: LyricsService.offsetMs === 0 ? Qt.rgba(1, 1, 1, 0.55) : "#ffffff"
                    text: root.offsetReadout
                }

                SyncPillButton {
                    id: plusButton
                    iconName: "add"
                    downAction: () => LyricsService.nudgeOffset(100)
                    StyledToolTip { text: Translation.tr("Show lines earlier") }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2

                SyncPillButton {
                    id: resetButton
                    iconName: "restart_alt"
                    downAction: () => LyricsService.resetOffset()
                    StyledToolTip { text: Translation.tr("Reset offset") }
                }

                SyncPillButton {
                    id: lookupButton
                    iconName: "refresh"
                    downAction: () => LyricsService.restartLyrics()
                    StyledToolTip { text: Translation.tr("Look up lyrics again") }
                }
            }
        }
    }

    // Collapses when fresh lyrics for a new track start loading; a word-timed replacement of the
    // ones already showing can't, because the status is "ok" while that happens
    Connections {
        target: LyricsService
        function onLyricsLinesChanged() {
            if (LyricsService.status === "loading")
                root.expanded = false;
        }
    }
}

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

/**
 * Media context: cover art, "title • artist", and a small level meter.
 *
 * The meter is inlined rather than reusing bar/Visualizer.qml for two reasons: that widget is
 * sized for a whole bar slot (implicitHeight is the full bar height), and importing
 * qs.modules.ii.bar from inside qs.modules.ii.bar.island would make the two modules import each
 * other. The maths is the same -- read GlobalStates.visualizerPoints, scale against
 * maxVisualizerValue.
 */
RowLayout {
    id: root
    spacing: 7

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property string title: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Unknown track")
    readonly property string artist: root.player?.trackArtist ?? ""

    readonly property string label: {
        const full = root.artist.length > 0 ? `${root.title} • ${root.artist}` : root.title;
        const max = Config.options.bar.island.collapsedMaxTitleChars;
        return full.length > max ? `${full.slice(0, Math.max(1, max - 1))}…` : full;
    }

    // Readability flip: the pill background is theme-driven and can land
    // near-white (or near-black), where the theme foreground would wash out.
    // Theme colors are kept whenever they already contrast; otherwise an
    // absolute dark/light fallback takes over. Either direction works.
    // Bound by DynamicIsland to the pill's real background (cover-tinted
    // while media plays, theme container otherwise).
    property color pillBg: Appearance.colors.colPrimaryContainer
    readonly property bool lightBg: !ColorUtils.isDark(root.pillBg)
    readonly property color fgColor: ColorUtils.pickReadable(
        Appearance.colors.colOnPrimaryContainer,
        root.lightBg ? "#191C1E" : "#F2F4F5")
    readonly property color meterColor: ColorUtils.pickReadable(
        Appearance.colors.colPrimary,
        root.lightBg ? "#191C1E" : "#F2F4F5")

    IslandArt {
        Layout.alignment: Qt.AlignVCenter
    }

    StyledText {
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: root.fgColor
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignVCenter
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Row {
        id: meter
        visible: Config.options.bar.island.showVisualizer
        spacing: 2
        Layout.alignment: Qt.AlignVCenter

        readonly property list<real> points: GlobalStates.visualizerPoints
        readonly property int barCount: 12
        readonly property real dotSize: 2
        readonly property real maxBarHeight: 14
        readonly property real maxVisualizerValue: 1000

        // Pinned, not derived. A Row's implicitHeight is its tallest child, so letting it float
        // meant every level change resized the Row, which moved its vertical centre, which moved
        // every bar anchored to that centre -- the whole meter rocked up and down instead of the
        // bars just growing.
        height: meter.maxBarHeight
        Layout.preferredHeight: meter.maxBarHeight

        Repeater {
            model: meter.barCount

            Rectangle {
                required property int index

                width: meter.dotSize
                height: {
                    if (meter.points.length === 0)
                        return meter.dotSize;
                    const idx = Math.floor(index * meter.points.length / meter.barCount);
                    const value = meter.points[idx] ?? 0;
                    return Math.max(meter.dotSize, (value / meter.maxVisualizerValue) * meter.maxBarHeight);
                }
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.meterColor
                opacity: 0.85

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}

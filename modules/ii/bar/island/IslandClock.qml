import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The island's permanent right-hand content: date plus the time in a filled chip.
 *
 * Deliberately a near-copy of ClockWidget.qml's `rowMaterial` so swapping "clockWidget" for
 * "dynamicIsland" in the middle layout is not a visual regression. Unlike the context area to
 * its left, this never gets swapped out -- losing the clock because a track started playing
 * would be a downgrade.
 */
RowLayout {
    id: root
    spacing: 4

    readonly property var timeParts: DateTime.time.split(/[: ]/)
    readonly property string ampm: root.timeParts.find(part => /^(am|pm)$/i.test(part)) ?? ""
    readonly property string clockTime: root.timeParts.filter(part => !/^(am|pm)$/i.test(part)).join(":")

    // Bound by DynamicIsland to the pill's real background (cover-tinted
    // while media plays, theme container otherwise).
    property color pillBg: Appearance.colors.colPrimaryContainer
    readonly property bool lightBg: !ColorUtils.isDark(root.pillBg)

    StyledText {
        visible: Config.options.time.showDate
        text: DateTime.longDate
        font.pixelSize: Appearance.font.pixelSize.small
        color: ColorUtils.pickReadable(
            Appearance.colors.colOnPrimaryContainer,
            root.lightBg ? "#191C1E" : "#F2F4F5")
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: 2
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    Rectangle {
        implicitWidth: timeText.implicitWidth + 16
        implicitHeight: 24
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
        Layout.alignment: Qt.AlignVCenter

        StyledText {
            id: timeText
            anchors.centerIn: parent
            text: root.clockTime
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Bold
            font.letterSpacing: -0.4
            font.features: {
                "tnum": 1
            }
            color: Appearance.colors.colOnPrimary
        }
    }

    // Tucked under the time chip's right edge, same as the bar clock does it.
    Rectangle {
        visible: root.ampm !== ""
        z: 1
        implicitWidth: ampmText.implicitWidth + 8
        implicitHeight: 24
        radius: Appearance.rounding.full
        color: Appearance.colors.colTertiaryContainer
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: -10

        StyledText {
            id: ampmText
            anchors.centerIn: parent
            text: root.ampm
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colPrimary
        }
    }
}

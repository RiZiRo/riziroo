import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

/**
 * OSD context: the volume / brightness / gamma burst, rendered inside the pill instead of in the
 * floating panel below the bar. Values and icons are the same ones
 * modules/ii/onScreenDisplay/indicators/*.qml read, so the two stay in agreement; which of the
 * three is current comes from GlobalStates.osdIndicator.
 */
RowLayout {
    id: root
    spacing: 8

    readonly property string indicator: GlobalStates.osdIndicator

    // Resolved exactly the way indicators/BrightnessIndicator.qml does it. Reading this island's
    // own screen off QsWindow looked more correct on paper but came back null this deep inside a
    // Loader, so the value silently sat on its 0.5 fallback and the pill always read 50%.
    readonly property var focusedScreen: WM.compositor === "hyprland"
        ? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name)
        : Quickshell.screens.find(screen => screen.name === WM.focusedMonitor?.name)
    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(root.focusedScreen)

    readonly property real barValue: {
        switch (root.indicator) {
        case "brightness":
            return root.brightnessMonitor?.brightness ?? 0.5;
        case "gamma":
            return (Hyprsunset.gamma ?? 50) / 100;
        default:
            return Audio.sink?.audio.volume ?? 0;
        }
    }

    readonly property real barFrom: root.indicator === "gamma" ? (Hyprsunset.gammaLowerLimit / 100) : 0

    readonly property string icon: {
        switch (root.indicator) {
        case "brightness":
            return Hyprsunset.temperatureActive ? "routine" : "light_mode";
        case "gamma":
            return "wb_twilight";
        default:
            return (Audio.sink?.audio.muted ?? false) ? "volume_off" : "volume_up";
        }
    }

    MaterialSymbol {
        text: root.icon
        iconSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colOnPrimaryContainer
        Layout.alignment: Qt.AlignVCenter
    }

    StyledProgressBar {
        valueBarWidth: 84
        valueBarHeight: 9
        from: root.barFrom
        to: 1
        value: root.barValue
        // No end dot. At this thickness it is a 9px circle in the fill color sitting on the last
        // 9px of an 84px track, so from roughly 90% up it swallows what is left of the inactive
        // track and the slider reads as maxed out several notches before it is. Without it the
        // remaining track shrinks honestly all the way to 100%.
        showStopIndicator: false
        highlightColor: Appearance.colors.colPrimary
        trackColor: Appearance.colors.colSecondaryContainer
        Layout.alignment: Qt.AlignVCenter
    }

    StyledText {
        text: `${Math.round(root.barValue * 100)}%`
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        font.features: {
            "tnum": 1
        }
        color: Appearance.colors.colOnPrimaryContainer
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: 30
        horizontalAlignment: Text.AlignRight
    }
}

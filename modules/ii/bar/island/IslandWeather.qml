import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Idle context: current conditions. Only reached when bar.weather.enable is on -- otherwise the
 * island has no context at all and collapses to just the clock, which is what the bar looked
 * like before the island existed.
 */
RowLayout {
    id: root
    spacing: 5

    MaterialSymbol {
        text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
        iconSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colOnPrimaryContainer
        Layout.alignment: Qt.AlignVCenter
    }

    StyledText {
        text: Weather.data?.temp ?? "--°"
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnPrimaryContainer
        Layout.alignment: Qt.AlignVCenter
    }
}

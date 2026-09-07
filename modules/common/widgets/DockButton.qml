import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
    implicitWidth: implicitHeight - topInset - bottomInset
    buttonRadius: Appearance.rounding.normal
    hoverEnabled: true

    // Windows-like hover layer: transparent at rest, light pill on hover
    // so it's instantly clear what will be clicked.
    colBackground: "transparent"
    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.85)
    colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.75)

    background.implicitHeight: 50
}
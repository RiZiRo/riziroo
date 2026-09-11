import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property int currentIndex: 0
    property int totalCount: 0
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool paintMaterialPill: false
    property real padding: (root.isMaterial && !root.paintMaterialPill) ? 0 : 5
    property color bgColor: Appearance.colors.colPrimaryContainer

    readonly property color resolvedGroupColor: {
        const name = Config.options.bar.groupColor
        const key = `col${name.charAt(0).toUpperCase()}${name.slice(1)}`
        return Appearance.colors[key] ?? Appearance.colors.colLayer1
    }

    readonly property bool isSegmented: Config.options?.bar.borderless === "segmented"

    // What the group actually paints behind its widgets, before the color animation.
    readonly property color effectiveBgColor: (root.isMaterial && !root.paintMaterialPill)
        ? "transparent"
        : (root.isMaterial && root.paintMaterialPill)
            ? root.bgColor
            : (Config.options?.bar.borderless === "transparent"
                ? "transparent"
                : Config.options.bar.cornerStyle === 2 || (Config.options?.bar.borderless === "segmented" && !Config.options.bar.showBackground)
                    ? Appearance.colors.colLayer0
                    : root.resolvedGroupColor)

    // Bar widgets are written for a dark backdrop, but a palette is free to hand out a light
    // container role for the pill — scheme-monochrome does exactly that in dark mode, where
    // primaryContainer lands on tone 85 — and light-on-light is unreadable. Pick the side of
    // the palette that contrasts with whatever the group ended up painting.
    readonly property color contentColor: {
        if (root.effectiveBgColor.a < 0.1) return Appearance.colors.colOnLayer0;
        const surface = Appearance.m3colors.m3surface;
        const onSurface = Appearance.m3colors.m3onSurface;
        const lightSide = ColorUtils.isDark(onSurface) ? surface : onSurface;
        const darkSide = ColorUtils.isDark(onSurface) ? onSurface : surface;
        return ColorUtils.isDark(root.effectiveBgColor) ? lightSide : darkSide;
    }

    readonly property real fullRadius: height / 2
    readonly property real midRadius: root.isSegmented ? 0 : (Config.options.bar.cornerStyle === 2 ? Appearance.rounding.unsharpenmore + 2 : Appearance.rounding.unsharpenmore)
    property real startRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === 0) return fullRadius;
        return midRadius;
    }
    property real endRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === totalCount - 1) return fullRadius;
        return midRadius;
    }

    implicitWidth: vertical && root.isMaterial ? Appearance.sizes.baseVerticalBarWidth - 6 : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    default property alias items: gridLayout.children

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: root.effectiveBgColor

        border.width: root.isSegmented && !root.isMaterial ? 1 : 0
        border.color: Appearance.colors.colLayer0Border

        topLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.startRadius)
        bottomLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.vertical ? root.endRadius : root.startRadius)
        topRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.vertical ? root.startRadius : root.endRadius)
        bottomRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.endRadius)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
    }
}
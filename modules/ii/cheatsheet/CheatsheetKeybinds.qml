pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real padding: 4
    readonly property real scale: Config.options.cheatsheet.scale
    // Grows with `scale`, but stays small enough that the card around it — title,
    // padding and drop shadow — still fits on screen.
    readonly property real screenFraction: Math.min(0.7 * root.scale, 0.88)
    implicitWidth: (QsWindow?.window?.screen.width ?? 0) * root.screenFraction
    implicitHeight: (QsWindow?.window?.screen.height ?? 0) * root.screenFraction

    StyledFlickable {
        id: flickable
        clip: true
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
        contentHeight: height
        contentWidth: flow.implicitWidth
        Flow {
            id: flow
            height: flickable.height
            flow: Flow.TopToBottom
            spacing: 10 * root.scale
            Repeater {
                model: [...HyprlandKeybinds.keybindCategories, ""]
                delegate: CheatsheetKeybindsCategory {
                    required property var modelData
                    categoryName: modelData
                }
            }
        }
    }

    ScrollEdgeFade {
        target: flickable
        vertical: false
        color: Appearance.colors.colLayer0Base
    }
}

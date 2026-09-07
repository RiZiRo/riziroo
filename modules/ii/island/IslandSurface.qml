import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The island's expanded surface: search results or the dashboard.
 *
 * This is a plain Item, not a window. It is rendered inside the bar's own PanelWindow, because
 * that window demonstrably receives mouse input -- the pill's chips, field and buttons all work --
 * while a separate Overlay-layer window did not, through two different input-region attempts.
 *
 * Living in the bar window buys three things for free: the wheel and clicks reach it with no
 * cross-window routing, the search field and the list are finally in one focus scope, and text
 * fields inside the dashboard (the to-do list) actually accept typing, which they could not in a
 * keyboardFocus: None window.
 */
Item {
    id: root

    property real radius: Appearance.rounding.normal

    implicitWidth: contentLoader.implicitWidth
    implicitHeight: contentLoader.implicitHeight

    // Unfolds from the edge nearest the bar rather than appearing mid-screen.
    transformOrigin: Config.options.bar.bottom ? Item.Bottom : Item.Top
    opacity: IslandState.expanded ? 1 : 0
    scale: IslandState.expanded ? 1 : 0.94

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // The search field has its own Escape handler; this covers the dashboard, which has no field
    // to catch it.
    Shortcut {
        sequences: ["Escape"]
        enabled: IslandState.dashboardActive
        onActivated: IslandState.close()
    }

    StyledRectangularShadow {
        target: root
    }

    // Swallows presses that land on the surface but miss a control, so they don't reach the bar
    // underneath and toggle the island shut.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: event => event.accepted = true
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: IslandState.searchActive ? searchComponent : dashboardComponent
    }

    Component {
        id: searchComponent
        IslandResults {}
    }

    Component {
        id: dashboardComponent
        IslandDashboard {}
    }
}

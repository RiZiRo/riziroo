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

    // Driven by the Loader in Bar.qml instead of read straight off IslandState, for two reasons.
    // The loader now outlives the collapse by one animation, so the exit actually plays instead of
    // the card blinking out of existence. And `entered` gives the entrance a frame to start from:
    // a Behavior never runs on a property's *initial* binding, so binding opacity to
    // IslandState.expanded -- which is already true by the time the loader builds this -- meant the
    // card was created at opacity 1, scale 1 and simply appeared.
    property bool shown: false
    property bool entered: false
    readonly property bool open: root.shown && root.entered

    // Which surface is drawn. Fed by Bar.qml, which latches the last non-"collapsed" mode, because
    // this card now outlives the collapse by one animation: IslandState.mode goes to "collapsed"
    // the instant the island closes, and a live `searchActive ? results : dashboard` would tear
    // the results down and build the whole dashboard underneath the exit animation -- so closing a
    // search flashed the dashboard on the way out. "search" | "dashboard".
    property string frozenMode: "search"

    Component.onCompleted: Qt.callLater(() => root.entered = true)

    // Unfolds from the edge nearest the bar rather than appearing mid-screen.
    transformOrigin: Config.options.bar.bottom ? Item.Bottom : Item.Top
    opacity: root.open ? 1 : 0
    scale: root.open ? 1 : 0.92

    // Deliberately slower than the fade, and on a spatial curve while the fade is on a linear-ish
    // one: the card is fully legible about a third of the way through the unfold, so it reads as
    // one continuous motion out of the pill rather than a panel that arrives and then settles.
    // The pill's own morph (DynamicIsland.animatedWidth) runs on the same curve and duration, so
    // the two travel together. Exits are shorter than entrances, the usual asymmetry -- and both
    // are comfortably inside the 300ms the loader is held open for.
    Behavior on opacity {
        NumberAnimation {
            duration: root.open ? 200 : 150
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open
                ? Appearance.animationCurves.standardDecel
                : Appearance.animationCurves.standardAccel
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: root.open ? Appearance.animationCurves.expressiveFastSpatialDuration : 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open
                ? Appearance.animationCurves.expressiveFastSpatial
                : Appearance.animationCurves.emphasizedAccel
        }
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
        sourceComponent: root.frozenMode === "search" ? searchComponent : dashboardComponent
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

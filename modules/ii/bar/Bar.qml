pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.island

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            required property ShellScreen modelData
            readonly property bool wantsIsland: IslandState.enabled && IslandState.expanded
                && (barLoader.modelData?.name ?? "") === (Hyprland.focusedMonitor?.name ?? "")
            property bool keepIsland: false
            // Own the lifetime outside the loaded window: reading item from
            // active would feed the loader's creation back into its own binding.
            property Timer exitTimer: Timer {
                interval: 300
                onTriggered: barLoader.keepIsland = false
            }
            onWantsIslandChanged: {
                if (barLoader.wantsIsland) {
                    barLoader.exitTimer.stop();
                    barLoader.keepIsland = true;
                } else if (barLoader.keepIsland) {
                    barLoader.exitTimer.restart();
                }
            }
            Component.onCompleted: barLoader.keepIsland = barLoader.wantsIsland
            active: !GlobalStates.screenLocked && (GlobalStates.barOpen
                || (IslandState.enabled && (barLoader.wantsIsland || barLoader.keepIsland)))
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData
                readonly property bool islandOnly: !GlobalStates.barOpen

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }

                property bool showCorners: !barRoot.islandOnly && (!Config.options.bar.autoHide.enable || mustShow)

                Timer {
                    id: cornerRevealTimer
                    interval: 65
                    onTriggered: barRoot.showCorners = true
                }

                onMustShowChanged: {
                    if (!Config.options.bar.autoHide.enable) return;
                    if (mustShow) {
                        cornerRevealTimer.restart()
                    } else {
                        cornerRevealTimer.stop()
                        barRoot.showCorners = false
                    }
                }
                property bool superShow: false
                property bool mustShow: barRoot.islandExpanded || hoverRegion.containsMouse || superShow
                // The island's expanded surface lives in this window (see IslandSurface.qml), and
                // only on the bar the user is actually looking at -- IslandState is global, so
                // without this every monitor would grow a copy.
                readonly property bool isFocusedMonitor: (barRoot.screen?.name ?? "") === (Hyprland.focusedMonitor?.name ?? "")
                readonly property bool islandExpanded: IslandState.expanded && barRoot.isFocusedMonitor
                readonly property real islandSurfaceHeight: islandSurfaceLoader.item?.implicitHeight ?? 0
                readonly property real islandGap: 6

                // Kept true for one animation's worth after the island collapses, so the surface
                // gets to play its exit instead of being destroyed under it. `islandExpanded`
                // itself must stay instant -- the input mask and the layer both key off it.
                property bool islandSurfaceAlive: false
                onIslandExpandedChanged: {
                    if (barRoot.islandExpanded) {
                        islandSurfaceKeepAlive.stop();
                        barRoot.islandSurfaceAlive = true;
                    } else if (barRoot.islandSurfaceAlive) {
                        islandSurfaceKeepAlive.restart();
                    }
                }
                Timer {
                    id: islandSurfaceKeepAlive
                    interval: 300
                    onTriggered: barRoot.islandSurfaceAlive = false
                }

                // The last mode that was actually up. IslandState.mode goes to "collapsed" the
                // instant the island closes, but the surface is still on screen playing its exit
                // for another 300ms -- handing it the live mode would tear down the results and
                // build the dashboard underneath that animation, flashing the wrong surface on the
                // way out. Only ever read while collapsed (see frozenMode below), so by the time
                // it matters this handler has long since run.
                property string islandLastMode: "search"
                Connections {
                    target: IslandState
                    function onModeChanged() {
                        if (IslandState.mode !== "collapsed")
                            barRoot.islandLastMode = IslandState.mode;
                    }
                }
                property var thisMonitorData: HyprlandData.monitors.find(m => m.name === barRoot.screen?.name)
                property bool monitorHasFullscreen: HyprlandData.workspaceById[thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false
                property bool monitorHasSpecialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: barRoot.islandOnly || (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows)) ? 0 : Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) + (Config.options.bar.cornerStyle === 2 ? -6 : 0)
                WlrLayershell.namespace: "quickshell:bar"
                // The island's field and now its whole surface live in this window, so the bar has
                // to hold keyboard focus while it is open. Exclusive rather than OnDemand: under
                // Hyprland OnDemand only hands focus over on a click, and Super-tap opens the
                // island without one. Covers the dashboard too, so Escape and the to-do list's
                // text field both work.
                WlrLayershell.keyboardFocus: barRoot.islandExpanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                // Overlay layer while the island is expanded -- so Alt+Space brings it up over a
                // fullscreen window instead of leaving it buried -- and while a special workspace
                // sits on top of a fullscreen window. Else Top layer, so fullscreen apps cover the
                // bar as normal (Hyprland buries Top layer under fullscreen).
                WlrLayershell.layer: (barRoot.islandExpanded || (monitorHasFullscreen && monitorHasSpecialOpen)) ? WlrLayer.Overlay : WlrLayer.Top
                // NEVER resize this window. Hyprland animates a layer surface's geometry and
                // scales the client's texture to whatever the box is mid-animation, so growing the
                // bar to fullscreen on expand squashed the entire bar -- all three pills and the
                // island surface with them -- into the still-growing box for the length of the
                // layer animation, then snapped. `layerrule = noanim` does not fix it either
                // (hyprwm/Hyprland#7524). So the window is always the height it needs at its
                // largest: fullscreen, transparent everywhere but the bar strip.
                //
                // Fullscreen is what the expanded island wants anyway -- the input mask (bound to
                // hoverMaskRegion) then covers empty screen, so clicks outside the pill and its
                // surface reach islandDismissArea instead of falling to clients. Collapsed, the
                // mask shrinks back to the bar strip and every pixel below it passes clicks
                // through exactly as before.
                implicitHeight: IslandState.enabled
                    ? (barRoot.screen?.height ?? 800)
                    : Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                // The other half of never resizing: tell Hyprland which pixels are actually worth
                // rendering. Without this the compositor treats the whole fullscreen surface as
                // paintable and blurable, and the island's cava meter repaints it at the player's
                // frame rate. Collapsed this is exactly the rect the window used to be.
                HyprlandWindow.visibleMask: Region {
                    item: visibleMaskRegion
                }
                // When Overlay-layer, bar shares a layer with the screen-corner click zones (ScreenCorners.qml)
                // and same-layer overlap is resolved by stacking, not layer priority - bar was winning and
                // swallowing the tiny corner-open hit rects. Carve them out of the bar's own mask so clicks
                // reach the corners underneath. Only relevant on the edge the bar and corners share.
                property bool cutOutCornerOpenZones: (monitorHasFullscreen && monitorHasSpecialOpen) && (Config.options.bar.bottom === Config.options.sidebar.cornerOpen.bottom)
                property int cornerOpenCutWidth: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionWidth : 0
                property int cornerOpenCutHeight: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionHeight : 0
                mask: Region {
                    item: hoverMaskRegion
                    Region {
                        intersection: Intersection.Intersect
                        width: barRoot.width
                        height: barRoot.islandOnly && !barRoot.islandExpanded ? 0 : barRoot.height
                    }
                    Region {
                        intersection: Intersection.Subtract
                        x: 0
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                    Region {
                        intersection: Intersection.Subtract
                        x: barRoot.width - barRoot.cornerOpenCutWidth
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                }
                color: "transparent"

                // Positioning
                anchors {
                    top: !Config.options.bar.bottom
                    bottom: Config.options.bar.bottom
                    left: true
                    right: true
                }

                margins {
                    top: Config.options.bar.cornerStyle === 3 ? 5 : 0
                    right: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                    bottom: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1 || Config.options.bar.cornerStyle === 3 ? 5 : 0
                }

                // Include in focus grab
                Component.onCompleted: {
                    if (barRoot.islandExpanded)
                        barRoot.islandSurfaceAlive = true;
                    GlobalFocusGrab.addPersistent(barRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                }

                // Geometry for HyprlandWindow.visibleMask above. Collapsed it is the bar strip plus
                // the screen-rounding decorators -- i.e. the exact rect this window used to be, so
                // nothing that was drawn before can be clipped by it. Expanded it is the whole
                // window, which is what the surface, its shadow and the pill's overshoot need.
                // Follows islandSurfaceAlive rather than islandExpanded so the surface's exit
                // animation isn't cut off at the frame the island closes.
                //
                // x/y/width/height rather than anchors: this is read by the compositor, not laid
                // out, and explicit geometry is right on the very first frame instead of after a
                // layout pass. Paints nothing and has no MouseArea, so it is invisible to both the
                // screen and the pointer.
                Item {
                    id: visibleMaskRegion
                    readonly property real stripHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                    readonly property bool full: barRoot.islandExpanded || barRoot.islandSurfaceAlive
                    x: 0
                    width: barRoot.width
                    height: visibleMaskRegion.full ? barRoot.height : visibleMaskRegion.stripHeight
                    y: (!visibleMaskRegion.full && Config.options.bar.bottom)
                        ? Math.max(0, barRoot.height - visibleMaskRegion.stripHeight)
                        : 0
                }

                // NO GlobalFocusGrab registration for the island, deliberately. Registering this
                // window as a dismissable while it holds exclusive keyboard focus makes the grab
                // clear the instant it engages, which fires `dismissed` and closes the island
                // inside a frame -- the island then appears not to open at all. That happened with a
                // separate dismissable window in step 5, and again here when the bar itself was
                // registered. Twice is enough.
                //
                // Click-outside dismissal is instead done with geometry, not a grab: while expanded
                // this window goes fullscreen (transparent) and islandDismissArea below catches
                // presses landing outside the pill and its surface.
                //
                // Other ways to close: Escape, the pill, the keybind, or picking a result.

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            // While the island is expanded the mask item is the whole (fullscreen)
                            // window, so clicks landing on empty screen reach this window and hit
                            // islandDismissArea below. Collapsed, it is just the bar plus the hover
                            // strip, exactly as before.
                            fill: barRoot.islandExpanded ? hoverRegion : barContent
                            topMargin: barRoot.islandExpanded ? 0 : -Config.options.bar.autoHide.hoverRegionWidth - ((barRoot.islandExpanded && Config.options.bar.bottom) ? barRoot.islandSurfaceHeight + barRoot.islandGap * 2 : 0)
                            // Extended over the island surface so the mask -- which is bound to
                            // this Item -- covers it. Growing an already-working anchored Item was
                            // chosen over adding another Region to the mask, since Region geometry
                            // is exactly what failed twice in the standalone window.
                            bottomMargin: barRoot.islandExpanded ? 0 : -Config.options.bar.autoHide.hoverRegionWidth - ((barRoot.islandExpanded && !Config.options.bar.bottom) ? barRoot.islandSurfaceHeight + barRoot.islandGap * 2 : 0)
                        }
                    }

                    // Click-outside-to-close for the expanded island. Declared before the surface
                    // and the bar content so it sits *under* them: pill, search field, chips and
                    // results all get their presses first, and only a press landing on empty
                    // screen reaches here. Enabled only while expanded, so collapsed behavior --
                    // and every pixel of it -- is untouched. Any button dismisses.
                    MouseArea {
                        id: islandDismissArea
                        anchors.fill: hoverMaskRegion
                        enabled: barRoot.islandExpanded
                        acceptedButtons: Qt.AllButtons
                        onPressed: event => {
                            IslandState.close();
                            event.accepted = true;
                        }
                    }

                    Loader {
                        id: islandSurfaceLoader
                        // Outlives islandExpanded by one animation (see islandSurfaceKeepAlive), so
                        // the surface plays its exit rather than blinking out of existence.
                        active: barRoot.islandExpanded || barRoot.islandSurfaceAlive
                        visible: active
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            top: Config.options.bar.bottom ? undefined : barContent.bottom
                            bottom: Config.options.bar.bottom ? barContent.top : undefined
                            topMargin: barRoot.islandGap
                            bottomMargin: barRoot.islandGap
                        }
                        sourceComponent: IslandSurface {
                            shown: barRoot.islandExpanded
                            // Live while a mode is up -- so the loader builds the right card on its
                            // very first evaluation, whatever order this and the islandLastMode
                            // handler happen to run in -- and the latch only during the exit, where
                            // the live value is "collapsed" and would swap the card mid-animation.
                            frozenMode: IslandState.expanded ? IslandState.mode : barRoot.islandLastMode
                        }
                    }

                    RoundCorner {
                        id: leftPillCorner
                        visible: !barRoot.islandOnly && barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0 && barRoot.showCorners
                        x: barContent.centerPillX - implicitSize
                        implicitSize: Appearance.rounding.screenRounding
                        color: Config.options.bar.followFrameColor
                            ? Appearance.getColorFromName(Config.options.bar.frameColor)
                            : Appearance.colors.colLayer0
                        corner: RoundCorner.CornerEnum.TopRight

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: leftPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: leftPillCorner
                                corner: RoundCorner.CornerEnum.BottomRight
                            }
                        }
                        AnchorChanges {
                            target: leftPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }

                    BarContent {
                        id: barContent
                        islandOnly: barRoot.islandOnly
                        opacity: barRoot.islandOnly && !barRoot.islandExpanded ? 0 : 1
                        
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                        }
                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    RoundCorner {
                        id: rightPillCorner
                        visible: !barRoot.islandOnly && barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0 && barRoot.showCorners
                        x: barContent.centerPillX + barContent.centerPillWidth
                        implicitSize: Appearance.rounding.screenRounding
                        color: Config.options.bar.followFrameColor
                            ? Appearance.getColorFromName(Config.options.bar.frameColor)
                            : Appearance.colors.colLayer0
                        corner: RoundCorner.CornerEnum.TopLeft

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: rightPillCorner
                                anchors.top: undefined
                                anchors.bottom: barContent.bottom
                            }
                            PropertyChanges {
                                target: rightPillCorner
                                corner: RoundCorner.CornerEnum.BottomLeft
                            }
                        }
                        AnchorChanges {
                            target: rightPillCorner
                            anchors.top: barContent.top
                            anchors.bottom: undefined
                        }
                    }
                    
                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: !barRoot.islandOnly && showBarBackground && Config.options.bar.cornerStyle === 0 && !barContent.centerOnly// Hug

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding

                            readonly property color decoratorColor: showBarBackground
                                ? (Config.options.bar.followFrameColor && Config.options.bar.frameColor
                                    ? Appearance.getColorFromName(Config.options.bar.frameColor)
                                    : Appearance.colors.colLayer0)
                                : "transparent"

                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: parent.decoratorColor

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    right: parent.right
                                    top: !Config.options.bar.bottom ? parent.top : undefined
                                    bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: parent.decoratorColor

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    CompositorGlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    CompositorGlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    CompositorGlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}

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
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

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

                property bool showCorners: !Config.options.bar.autoHide.enable || mustShow

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
                property bool mustShow: hoverRegion.containsMouse || superShow
                // The island's expanded surface lives in this window (see IslandSurface.qml), and
                // only on the bar the user is actually looking at -- IslandState is global, so
                // without this every monitor would grow a copy.
                readonly property bool isFocusedMonitor: (barRoot.screen?.name ?? "") === (Hyprland.focusedMonitor?.name ?? "")
                readonly property bool islandExpanded: IslandState.expanded && barRoot.isFocusedMonitor
                readonly property real islandSurfaceHeight: islandSurfaceLoader.item?.implicitHeight ?? 0
                readonly property real islandGap: 6
                property var thisMonitorData: HyprlandData.monitors.find(m => m.name === barRoot.screen?.name)
                property bool monitorHasFullscreen: HyprlandData.workspaceById[thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false
                property bool monitorHasSpecialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows)) ? 0 : Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) + (Config.options.bar.cornerStyle === 2 ? -6 : 0)
                WlrLayershell.namespace: "quickshell:bar"
                // The island's field and now its whole surface live in this window, so the bar has
                // to hold keyboard focus while it is open. Exclusive rather than OnDemand: under
                // Hyprland OnDemand only hands focus over on a click, and Super-tap opens the
                // island without one. Covers the dashboard too, so Escape and the to-do list's
                // text field both work.
                WlrLayershell.keyboardFocus: barRoot.islandExpanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                // Overlay layer only while special workspace sits on top of a fullscreen window on this monitor,
                // else Top layer so fullscreen apps cover the bar as normal (Hyprland buries Top layer under fullscreen+special).
                WlrLayershell.layer: (monitorHasFullscreen && monitorHasSpecialOpen) ? WlrLayer.Overlay : WlrLayer.Top
                // Fullscreen while the island is expanded. Visually nothing changes -- the window
                // is transparent outside the bar -- but the input mask (bound to hoverMaskRegion,
                // which then fills this window) can cover empty screen, so clicks outside the pill
                // and its surface reach islandDismissArea instead of falling to clients.
                implicitHeight: barRoot.islandExpanded ? (barRoot.screen?.height ?? 800) : Appearance.sizes.barHeight + Appearance.rounding.screenRounding
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
                    GlobalFocusGrab.addPersistent(barRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
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
                        active: barRoot.islandExpanded
                        visible: active
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            top: Config.options.bar.bottom ? undefined : barContent.bottom
                            bottom: Config.options.bar.bottom ? barContent.top : undefined
                            topMargin: barRoot.islandGap
                            bottomMargin: barRoot.islandGap
                        }
                        sourceComponent: IslandSurface {}
                    }

                    RoundCorner {
                        id: leftPillCorner
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0 && barRoot.showCorners
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
                        visible: barContent.centerOnly && showBarBackground && Config.options.bar.cornerStyle === 0 && barRoot.showCorners
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
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 && !barContent.centerOnly// Hug

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

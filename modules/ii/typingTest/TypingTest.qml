pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    Loader {
        id: typingTestLoader
        // Keep the complete surface warm. Constructing the large word layout on
        // the Super+O path was responsible for the noticeable launch delay.
        active: true

        sourceComponent: PanelWindow {
            id: typingWindow
            visible: GlobalStates.typingTestOpen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:typingTest"
            WlrLayershell.layer: WlrLayer.Overlay
            // Exclusive, not OnDemand: Hyprland only gives keyboard focus to an
            // on-demand layer surface when the pointer enters it, so the test
            // would ignore typing until you hovered over the panel. Exclusive
            // grabs the keyboard the moment the overlay maps; closing (esc)
            // returns it. Pointer clicks still pass through outside the mask.
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // The layer surface covers the screen but is transparent and masked
            // to the floating panel, so everything outside the panel — clicks
            // included — belongs to whatever app is underneath.
            mask: Region {
                item: typingSurface.panelItem
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide(): void {
                GlobalStates.typingTestOpen = false;
            }

            // Exposed so the IpcHandler does not have to dig through contentItem children.
            function restartTest(): void {
                typingSurface.restartTest();
            }

            function previewResult(): void {
                typingSurface.previewResult();
            }

            function openSettings(): void {
                typingSurface.openSettings();
            }

            function openHistory(): void {
                typingSurface.openHistory();
            }

            function status(): string {
                return typingSurface.diagnosticStatus();
            }

            // Only joins the shared focus grab when the user asked for
            // click-outside-to-close; the grab is what closes sidebars.
            readonly property bool dismissOnClickOutside: typingSurface.settings.closeOnClickOutside

            function updateGrab(): void {
                if (visible && dismissOnClickOutside)
                    GlobalFocusGrab.addDismissable(typingWindow);
                else
                    GlobalFocusGrab.removeDismissable(typingWindow);
            }

            Component.onCompleted: {
                updateGrab();
                if (visible)
                    typingSurface.opened();
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(typingWindow)

            onVisibleChanged: {
                updateGrab();
                if (visible)
                    typingSurface.opened();
            }
            onDismissOnClickOutsideChanged: updateGrab()

            Connections {
                target: GlobalFocusGrab
                function onDismissed(): void {
                    if (typingWindow.dismissOnClickOutside)
                        typingWindow.hide();
                }
            }

            TypingTestSurface {
                id: typingSurface
                anchors.fill: parent
                onCloseRequested: typingWindow.hide()
            }
        }
    }

    IpcHandler {
        target: "typingTest"
        function toggle(): void { GlobalStates.typingTestOpen = !GlobalStates.typingTestOpen; }
        function open(): void { GlobalStates.typingTestOpen = true; }
        function close(): void { GlobalStates.typingTestOpen = false; }
        function restart(): void {
            GlobalStates.typingTestOpen = true;
            if (typingTestLoader.item)
                typingTestLoader.item.restartTest();
        }
        function previewResult(): void {
            GlobalStates.typingTestOpen = true;
            if (typingTestLoader.item)
                typingTestLoader.item.previewResult();
        }
        function settings(): void {
            GlobalStates.typingTestOpen = true;
            if (typingTestLoader.item)
                typingTestLoader.item.openSettings();
        }
        function history(): void {
            GlobalStates.typingTestOpen = true;
            if (typingTestLoader.item)
                typingTestLoader.item.openHistory();
        }
        function status(): string {
            return typingTestLoader.item ? typingTestLoader.item.status() : "{\"loaded\":false}";
        }
    }

    CompositorGlobalShortcut {
        name: "typingTestToggle"
        description: "Toggles the native typing test"
        onPressed: GlobalStates.typingTestOpen = !GlobalStates.typingTestOpen
    }
}

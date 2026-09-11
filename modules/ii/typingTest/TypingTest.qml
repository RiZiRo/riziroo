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
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Match the cheatsheet: the layer surface is transparent and only
            // the centered rounded panel participates in pointer input.
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

            function status(): string {
                return typingSurface.diagnosticStatus();
            }

            Component.onCompleted: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(typingWindow);
                    typingSurface.opened();
                }
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(typingWindow)

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(typingWindow);
                    typingSurface.opened();
                } else {
                    GlobalFocusGrab.removeDismissable(typingWindow);
                }
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed(): void { typingWindow.hide(); }
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

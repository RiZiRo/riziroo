import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Click-through overlay that draws AppLaunchFeedback's in-flight launches.
 *
 * One layer-shell window per screen, on the overlay layer so the bubbles survive
 * fullscreen windows. Each window only exists while something is actually launching
 * on that screen -- when nothing is, `visible` goes false and the wl_surface goes
 * away entirely, so this costs nothing at rest.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay

            required property var modelData
            readonly property var launches: Array.from(AppLaunchFeedback.pending).filter(item => item.placed && item.screenName === overlay.modelData.name)

            screen: overlay.modelData
            visible: overlay.launches.length > 0
            color: "transparent"

            WlrLayershell.namespace: "quickshell:launchFeedback"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // Empty region: every click goes straight through to whatever is underneath
            mask: Region {}

            Repeater {
                model: overlay.launches

                delegate: LaunchBubble {
                    required property var modelData
                    required property int index

                    launch: modelData
                    slot: index
                    screenName: overlay.modelData.name
                    boundsWidth: overlay.width
                    boundsHeight: overlay.height
                }
            }
        }
    }
}

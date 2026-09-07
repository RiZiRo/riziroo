pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.services

/**
 * Exposes the active Hyprland Xkb keyboard layout name and code for indicators.
 *
 * `switchxkblayout all next` advances every keyboard device separately, and each one
 * emits its own `activelayout` event. Devices that came up at a different group (keyd,
 * ydotoold, power buttons, hotkey pseudo-keyboards) never resync, so the last event of
 * the burst often reports the layout of a device nobody is typing on — which is what
 * made the bar show the wrong code. So event payloads are no longer trusted: a burst is
 * debounced into a single `hyprctl -j devices` query and the main keyboard (the one
 * Hyprland is actually routing input from) is the only source of truth.
 */
Singleton {
    id: root
    // You can read these
    property list<string> layoutCodes: []
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    property string currentLayoutCode: ""
    // For the service
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"
    property bool layoutTableReady: false

    // Update the layout code according to the layout name (Hyprland gives the name not the code)
    onCurrentLayoutNameChanged: {
        root.updateLayoutCode();
        if (root.currentLayoutName !== "") {
            Config.options.osk.layout = root.currentLayoutName.split(" (")[0];
        }
    }

    function updateLayoutCode() {
        if (WM.compositor !== "hyprland") return;
        if (root.currentLayoutName === "") return;
        if (root.cachedLayoutCodes.hasOwnProperty(root.currentLayoutName)) {
            root.currentLayoutCode = root.cachedLayoutCodes[root.currentLayoutName];
        } else if (root.layoutTableReady) {
            // Description missing from base.lst: show something rather than going blank
            root.currentLayoutCode = root.currentLayoutName.split(" (")[0].substring(0, 2).toLowerCase();
        }
        // Otherwise the table is still being parsed and will resolve this on completion
    }

    // Parse base.lst once into a description -> code table, so every later lookup is
    // synchronous. The old code re-read the file per switch and dropped requests that
    // landed while the previous read was still running, leaving a stale code on screen.
    Process {
        id: getLayoutProc
        running: WM.compositor === "hyprland"
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const table = {};
                let section = "";
                const lines = layoutCollector.text.split("\n");

                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line === "") continue;
                    if (line.startsWith("!")) {
                        section = line.substring(1).trim().split(/\s+/)[0];
                        continue;
                    }

                    if (section === "layout") {
                        // code + whitespace + description
                        const matchLayout = line.match(/^(\S+)\s+(.+)$/);
                        if (matchLayout && !table.hasOwnProperty(matchLayout[2])) {
                            table[matchLayout[2]] = matchLayout[1];
                        }
                    } else if (section === "variant") {
                        // variant + whitespace + "code:" + whitespace + description
                        const matchVariant = line.match(/^(\S+)\s+(\S+?):?\s+(.+)$/);
                        if (matchVariant && !table.hasOwnProperty(matchVariant[3])) {
                            table[matchVariant[3]] = matchVariant[2] + matchVariant[1];
                        }
                    }
                }

                root.cachedLayoutCodes = table;
                root.layoutTableReady = true;
                root.updateLayoutCode();
            }
        }
    }

    // Authoritative read of the available layouts and the layout currently in effect.
    Process {
        id: fetchLayoutsProc
        running: WM.compositor === "hyprland"
        command: ["hyprctl", "-j", "devices"]

        stdout: StdioCollector {
            id: devicesCollector

            onStreamFinished: {
                let keyboards = [];
                try {
                    const parsedOutput = JSON.parse(devicesCollector.text);
                    keyboards = parsedOutput["keyboards"] || [];
                } catch (e) {
                    return; // truncated or malformed output: keep the last known layout
                }

                let hyprlandKeyboard = keyboards.find(kb => kb.main === true);
                if (!hyprlandKeyboard) hyprlandKeyboard = keyboards[0];
                if (!hyprlandKeyboard) return;

                root.layoutCodes = String(hyprlandKeyboard["layout"] || "")
                    .split(",")
                    .map(code => code.trim())
                    .filter(code => code.length > 0);
                root.currentLayoutName = hyprlandKeyboard["active_keymap"] || "";
            }
        }
    }

    // One `activelayout` event arrives per keyboard device, so collapse the burst into
    // a single query once it has settled.
    Timer {
        id: refetchTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (fetchLayoutsProc.running) fetchLayoutsProc.running = false;
            fetchLayoutsProc.running = true;
        }
    }

    Connections {
        target: Hyprland
        enabled: WM.compositor === "hyprland"
        function onRawEvent(event) {
            if (event.name === "activelayout" || event.name === "configreloaded") {
                refetchTimer.restart();
            }
        }
    }
}

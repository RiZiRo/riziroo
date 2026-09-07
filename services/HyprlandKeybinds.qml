pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Uses the `get_keybinds.py` script to parse comments in config files in a certain format and convert to JSON.
 */
Singleton {
    id: root
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)
    property var defaultKeybinds: {"children": []}
    property var userKeybinds: {"children": []}
    property var keybinds: ({
        keybinds: [
            ...(defaultKeybinds.keybinds ?? []),
            ...(userKeybinds.keybinds ?? []),
        ],
        children: [
            ...(defaultKeybinds.children ?? []),
            ...(userKeybinds.children ?? []),
        ]
    })

    // Flat, hyprctl-shaped view of the above, for the cheatsheet.
    readonly property var cheatsheetData: root.buildCheatsheetData([root.defaultKeybinds, root.userKeybinds])
    readonly property var flatKeybinds: root.cheatsheetData.binds
    readonly property var keybindCategories: root.cheatsheetData.categories

    readonly property var modBits: ({
        "SHIFT": 1, "CAPS": 2, "CAPSLOCK": 2,
        "CTRL": 4, "CONTROL": 4,
        "ALT": 8, "MOD1": 8, "MOD2": 16, "MOD3": 32,
        "SUPER": 64, "META": 64, "MOD4": 64, "MOD5": 128,
    })

    /**
     * Flattens the parsed section tree into { modmask, key, description } entries.
     * Binds documented without a "Category: " prefix inherit their section name,
     * so loop-generated display binds land in the same column as the real ones.
     */
    function buildCheatsheetData(roots: var): var {
        const binds = [];
        const categories = [];

        function addBind(bind, sectionName) {
            const comment = bind.comment ?? "";
            if (comment.length === 0)
                return;
            // Undocumented binds get an auto-generated "Execute: <raw command>"
            // label. Useful in the launcher, too noisy for the cheatsheet.
            if (/^Execute:\s*"/.test(comment))
                return;

            const mods = bind.mods ?? [];
            let key = bind.key ?? "";
            // A lone Super press is parsed as a modifier; render it as the key instead.
            if (key.length === 0) {
                const loneSuper = mods.find(mod => mod.toUpperCase().startsWith("SUPER_"));
                if (loneSuper)
                    key = loneSuper.toUpperCase();
            }

            let modmask = 0;
            for (const mod of mods)
                modmask |= (root.modBits[mod.toUpperCase().replace(/_[LR]$/, "")] ?? 0);

            const description = (comment.includes(":") || sectionName.length === 0)
                ? comment
                : `${sectionName}: ${comment}`;
            const category = description.substring(0, description.indexOf(":"));
            if (category.length > 0 && !categories.includes(category))
                categories.push(category);

            binds.push({
                "modmask": modmask,
                "key": key,
                "description": description
            });
        }

        function walk(node, inheritedName) {
            const sectionName = (node.name?.length > 0) ? node.name : inheritedName;
            for (const bind of (node.keybinds ?? []))
                addBind(bind, sectionName);
            for (const child of (node.children ?? []))
                walk(child, sectionName);
        }

        for (const node of roots)
            walk(node ?? {}, "");
        return {
            "binds": binds,
            "categories": categories
        };
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getDefaultKeybinds.running = true
                getUserKeybinds.running = true
            }
        }
    }

    Process {
        id: getDefaultKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.defaultKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.defaultKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.userKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.userKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}


pragma Singleton

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string prefix: Config.options.search.prefix.files ?? "f "
    readonly property bool active: IslandState.searchActive && !GlobalStates.screenLocked
        && (LauncherSearch.query.startsWith(root.prefix) || LauncherSearch.query === root.prefix.trim())
    readonly property string query: root.active ? LauncherSearch.query.slice(root.prefix.length).trim() : ""
    property var results: []
    property bool searching: false
    property bool partial: false
    property string message: ""
    property string error: ""
    property int generation: 0
    property int runningGeneration: -1
    property bool pending: false
    property bool receivedFinal: false

    function replaceResults(rows) {
        const old = root.results;
        const byPath = {};
        for (const entry of old)
            byPath[entry.rawValue] = entry;
        const next = rows.map(row => {
            if (byPath[row.path]) {
                const existing = byPath[row.path];
                delete byPath[row.path];
                return existing;
            }
            // Closures capture this immutable reply, never the live query.
            const entry = resultComponent.createObject(root, {
                id: "file:" + row.path,
                rawValue: row.path,
                name: row.name,
                comment: row.parent,
                type: row.kind === "folder" ? Translation.tr("Folder") : Translation.tr("File"),
                category: "files",
                iconName: row.kind === "folder" ? "folder" : "description",
                iconType: LauncherSearchResult.IconType.Material,
                verb: Translation.tr("Open"),
                execute: () => Qt.openUrlExternally(row.url)
            });
            entry.actions = [
                resultComponent.createObject(entry, {
                    name: Translation.tr("Open containing folder"),
                    iconName: "folder_open",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        const url = row.parentUrl;
                        IslandState.close();
                        Qt.openUrlExternally(url);
                    }
                }),
                resultComponent.createObject(entry, {
                    name: Translation.tr("Copy path"),
                    iconName: "content_copy",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => Quickshell.clipboardText = row.path
                })
            ];
            return entry;
        });
        root.results = next;
        // destroy() is deferred by Qt; delegates see the replacement first.
        for (const entry of Object.values(byPath))
            entry.destroy();
    }

    function schedule() {
        root.generation++;
        debounce.stop();
        root.pending = false;
        worker.running = false;
        root.replaceResults([]);
        root.partial = false;
        root.message = "";
        root.error = "";
        root.searching = root.active && root.query.length > 0;
        if (root.searching)
            debounce.restart();
    }

    function startPending() {
        if (!root.pending || worker.running || !root.active || root.query.length === 0)
            return;
        root.pending = false;
        root.runningGeneration = root.generation;
        root.receivedFinal = false;
        worker.command = ["python3", Quickshell.shellPath("scripts/files/search.py"), "--request",
            JSON.stringify({requestId: root.generation, query: root.query,
                limit: Math.max(1, Config.options.bar.island.maxResults)})];
        worker.running = true;
    }

    onQueryChanged: root.schedule()
    onActiveChanged: root.schedule()

    Timer {
        id: debounce
        interval: 150
        onTriggered: {
            root.pending = true;
            root.startPending();
        }
    }

    Process {
        id: worker
        stdout: SplitParser {
            onRead: data => {
                try {
                    const reply = JSON.parse(data);
                    if (!root.active || reply.requestId !== root.generation)
                        return;
                    root.partial = reply.partial ?? false;
                    root.message = reply.message ?? "";
                    root.error = reply.error ?? "";
                    root.replaceResults(reply.results ?? []);
                    root.searching = reply.busy ?? false;
                    if (!root.searching)
                        root.receivedFinal = true;
                } catch (e) {
                    if (root.runningGeneration === root.generation) {
                        root.error = Translation.tr("Could not read file search results.");
                    }
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.runningGeneration === root.generation && root.active && !root.receivedFinal) {
                root.searching = false;
                root.error = Translation.tr("File search stopped. Try the query again.");
            }
            Qt.callLater(root.startPending);
        }
    }

    Component {
        id: resultComponent
        LauncherSearchResult {}
    }
}

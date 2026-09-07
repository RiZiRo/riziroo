pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * State machine for the bar's dynamic island.
 *
 * One enum (`mode`) instead of a boolean per surface: the reference shell this is modelled on
 * (zenith-shell) keeps three separate services that have to cross-call each other's close()
 * to stay mutually exclusive, which is how it ended up assigning `visible` imperatively and
 * destroying the bindings underneath. Here the surfaces bind to `mode` and nothing else.
 *
 * `searchMode` is deliberately NOT stored -- it is derived from LauncherSearch.query, so typing
 * a prefix by hand keeps the island's mode chips in sync, and there is only one source of truth.
 */
Singleton {
    id: root

    // The island's surface is drawn inside the bar window and takes exclusive keyboard focus, so it
    // must not be left expanded when that window goes away -- it would come back still open, still
    // holding focus. bar.vertical has no island at all (VerticalBar loads instead of Bar), so it
    // is treated as disabled rather than half-working.
    readonly property bool enabled: Config.options.bar.island.enable
        && !Config.options.bar.vertical
        && (Config.options.bar.layouts?.middleLayout ?? []).includes("dynamicIsland")

    // "collapsed" | "search" | "dashboard"
    property string mode: "collapsed"
    readonly property bool searchActive: root.mode === "search"
    readonly property bool dashboardActive: root.mode === "dashboard"
    readonly property bool expanded: root.mode !== "collapsed"

    // Timestamp of the last collapse -> expand transition. A client activation inside the
    // grace window is the opening click arriving late, not a click-outside dismiss.
    property double openedAtMs: 0
    readonly property int dismissGraceMs: 250

    onExpandedChanged: {
        if (root.expanded)
            root.openedAtMs = Date.now();
    }

    // Called whenever client activation changes. Closes an expanded island when the user
    // clicks into a normal window. Deliberately NOT GlobalFocusGrab: the bar holds exclusive
    // keyboard focus while expanded, so registering it as dismissable clears instantly and
    // the island never opens (see Bar.qml). Watching activation only fires on real changes,
    // so the island's own clicks -- all inside the layer-shell bar window, never a toplevel --
    // can never dismiss it.
    function closeOnClientActivation(): void {
        if (!root.expanded || !root.enabled)
            return;
        if (Date.now() - root.openedAtMs < root.dismissGraceMs)
            return;
        const t = ToplevelManager.activeToplevel;
        if (t && t.activated)
            root.close();
    }

    // "overview" | "focus" | "media"
    property string dashboardTab: "overview"

    /**
     * What the collapsed pill is currently showing. Derived, never assigned: an OSD burst wins
     * over playback so a volume nudge mid-track still shows the slider.
     */
    readonly property bool mediaAvailable: {
        const player = MprisController.activePlayer;
        if (!player)
            return false;
        return MprisController.isPlaying
            || (player.canTogglePlaying ?? false)
            || ((player.trackTitle ?? "").length > 0);
    }

    readonly property string activity: {
        if (GlobalStates.osdVolumeOpen && Config.options.bar.island.absorbOsd)
            return "osd";
        if (root.mediaAvailable)
            return "media";
        return "idle";
    }

    ////////////////////////// Search modes //////////////////////////
    // "all" carries no prefix, so it behaves exactly like the overview search does today:
    // apps, settings pages and actions, with math/command/web offered as fallbacks.
    readonly property list<string> searchModes: ["all", "apps", "clipboard", "emoji", "symbols", "ai", "keybinds", "translate"]

    function prefixFor(mode: string): string {
        const p = Config.options.search.prefix;
        switch (mode) {
        case "apps":      return p.app;
        case "clipboard": return p.clipboard;
        case "emoji":     return p.emojis;
        case "symbols":   return p.symbols;
        case "ai":        return p.ai ?? ".";
        case "keybinds":  return p.keybinds ?? "<";
        case "translate": return p.translate ?? "tr ";
        default:          return "";
        }
    }

    // Every prefix LauncherSearch knows about, longest first so a multi-character prefix is
    // stripped whole rather than leaving a fragment behind.
    readonly property list<string> knownPrefixes: {
        const p = Config.options.search.prefix;
        return [p.action, p.app, p.clipboard, p.emojis, p.keybinds ?? "<", p.ai ?? ".", p.symbols, p.math, p.shellCommand, p.webSearch, p.translate ?? "tr "].filter(prefix => (prefix?.length ?? 0) > 0).sort((a, b) => b.length - a.length);
    }

    readonly property string searchMode: {
        const q = LauncherSearch.query;
        const p = Config.options.search.prefix;
        // Longest first: "tr " has to be tested before the single-character prefixes.
        if (q.startsWith(p.translate ?? "tr ")) return "translate";
        if (q.startsWith(p.clipboard))        return "clipboard";
        if (q.startsWith(p.emojis))           return "emoji";
        if (q.startsWith(p.symbols))          return "symbols";
        if (q.startsWith(p.ai ?? "."))        return "ai";
        if (q.startsWith(p.keybinds ?? "<"))  return "keybinds";
        if (q.startsWith(p.app))              return "apps";
        return "all";
    }

    /**
     * Swaps the query's prefix, keeping whatever the user already typed.
     */
    function setSearchMode(mode: string): void {
        if (!root.searchModes.includes(mode))
            mode = "all";
        let rest = LauncherSearch.query;
        for (const prefix of root.knownPrefixes) {
            if (rest.startsWith(prefix)) {
                rest = rest.slice(prefix.length);
                break;
            }
        }
        LauncherSearch.query = root.prefixFor(mode) + rest;
    }

    function cycleSearchMode(backwards: bool): void {
        const modes = root.searchModes;
        const current = modes.indexOf(root.searchMode);
        const step = backwards ? -1 : 1;
        root.setSearchMode(modes[(current + step + modes.length) % modes.length]);
    }

    ////////////////////////// Frecency //////////////////////////
    // The one launcher feature the shell's search doesn't already have. A raw use counter -- which
    // is what the reference shell stores -- ranks something opened forty times last year above
    // what you opened yesterday, so each use is decayed by a configurable half-life instead.
    //
    // Stored as plain JSON through a FileView rather than in Persistent: its JsonAdapter has no
    // `property var` anywhere in this codebase, and a string-keyed map isn't something it models.
    // This follows services/Notes.qml, which does the same thing for the same reason.

    property var frecency: ({})

    FileView {
        id: frecencyFile
        path: Qt.resolvedUrl(Directories.islandFrecencyPath)
        onLoaded: {
            try {
                const parsed = JSON.parse(frecencyFile.text());
                root.frecency = (parsed && typeof parsed === "object") ? parsed : {};
            } catch (e) {
                root.frecency = {};
                frecencyFile.setText("{}");
            }
        }
        onLoadFailed: error => {
            root.frecency = {};
            if (error === FileViewError.FileNotFound)
                frecencyFile.setText("{}");
        }
    }

    function frecencyScore(id: string): real {
        const record = root.frecency[id];
        if (!id || !record)
            return 0;
        const ageDays = (Date.now() - (record.lastUsed ?? 0)) / 86400000;
        const halfLife = Math.max(1, Config.options.bar.island.frecencyHalfLifeDays);
        return (record.count ?? 0) * Math.pow(0.5, ageDays / halfLife);
    }

    function recordUse(id: string): void {
        if (!id || id.length === 0)
            return;
        const previous = root.frecency[id] ?? {};
        // Reassigned rather than mutated: QML compares by reference, so an in-place edit of the
        // same object never notifies anything bound to it.
        root.frecency = Object.assign({}, root.frecency, {
            [id]: {
                count: (previous.count ?? 0) + 1,
                lastUsed: Date.now()
            }
        });
        frecencyFile.setText(JSON.stringify(root.frecency));
    }

    /**
     * Reorders only the contiguous run of app results, leaving LauncherSearch's deliberate overall
     * ordering (math first, then apps, then settings pages, then actions, then the command/web
     * fallbacks) exactly as it built it.
     *
     * Frecency is blended with the existing fuzzy rank rather than replacing it, so one stale use
     * can't outrank a much better text match -- a single use is worth roughly three positions.
     */
    function byFrecency(list: var): var {
        const appType = Translation.tr("App");
        const start = list.findIndex(entry => entry.type === appType);
        if (start < 0)
            return list;
        let end = start;
        while (end < list.length && list[end].type === appType)
            end++;
        if (end - start < 2)
            return list;

        const fuzzyWeight = 0.35;
        const apps = list.slice(start, end);
        const ranked = apps.map((entry, index) => ({
            entry: entry,
            index: index,
            score: root.frecencyScore(entry.id) + (apps.length - index) * fuzzyWeight
        }));
        ranked.sort((a, b) => (b.score - a.score) || (a.index - b.index));
        return list.slice(0, start).concat(ranked.map(item => item.entry), list.slice(end));
    }

    ////////////////////////// Symbol availability //////////////////////////
    // assets/material_symbols_rounded.json indexes 3835 names, which is newer than the Material
    // Symbols font actually installed here. For a name the font has no ligature for, it substitutes
    // the longest prefix it *does* know and leaves the remainder as plain letters -- which is where
    // cells reading "STICKER" and "_2" next to a glyph came from.
    //
    // Every real symbol is one square glyph, so a name whose shaped advance is much wider than the
    // em box is a name this font cannot draw. advanceWidth() applies ligature substitution and has
    // no side effects, so it is safe to call from a binding.
    readonly property real symbolEm: 24

    FontMetrics {
        id: symbolFontMetrics
        font.family: Appearance.font.family.iconMaterial
        font.pixelSize: root.symbolEm
    }

    // Guards against the heuristic misfiring if the icon font is missing entirely, in which case
    // everything would measure wide and the symbol search would come back empty.
    readonly property bool symbolFilterUsable: {
        const probe = symbolFontMetrics.advanceWidth("search");
        return probe > 0 && probe <= root.symbolEm * 1.5;
    }

    function symbolRenders(name: string): bool {
        if (!root.symbolFilterUsable || !name)
            return true;
        return symbolFontMetrics.advanceWidth(name) <= root.symbolEm * 1.5;
    }

    ////////////////////////// Search results //////////////////////////


    // The field lives in the bar window and the list lives in the panel window, so neither can
    // reach into the other. Both read the results and the selection from here instead.

    property int selectedIndex: 0

    // Emoji is browsed, not read: a grid of glyphs beats a list of rows, and
    // it wants a far higher cap because you scan rather than read. The geometry lives here rather
    // than in the view so the search field's arrow keys can step by a whole row without having to
    // ask the view anything -- the two are in the same window now, but this keeps one owner.
    readonly property bool gridMode: root.searchMode === "emoji"
    readonly property real gridCellSize: 46
    readonly property int gridColumns: root.gridMode ? Math.max(1, Math.floor((Config.options.bar.island.panelWidth - 16) / root.gridCellSize)) : 0
    readonly property int resultLimit: root.gridMode
        ? 180
        : Math.max(1, Config.options.bar.island.maxResults)

    readonly property var searchResults: {
        if (!root.searchActive)
            return [];
        let list = root.byFrecency(LauncherSearch.results);
        return list.slice(0, root.resultLimit);
    }
    readonly property int resultCount: root.searchResults.length
    readonly property var selectedResult: root.searchResults[root.selectedIndex] ?? null

    // Every keystroke rebuilds the list, so the selection goes back to the top -- same as the
    // overview search's focusFirstItem().
    onSearchResultsChanged: root.selectedIndex = 0

    function moveSelection(delta: int): void {
        if (root.resultCount === 0)
            return;
        root.selectedIndex = Math.max(0, Math.min(root.resultCount - 1, root.selectedIndex + delta));
    }

    function activateSelected(): void {
        root.activateAt(root.selectedIndex);
    }

    function activateAt(index: int): void {
        const entry = root.searchResults[index];
        if (!entry)
            return;
        // Grab the callable first: close() clears the query, which rebuilds LauncherSearch.results
        // and can drop this entry before it ever runs. The stored `execute` is an arrow function,
        // so it keeps its own scope and survives being called detached.
        const run = entry.execute;
        const id = entry.id ?? "";
        root.close();
        if (id.length > 0)
            root.recordUse(id);
        if (run)
            run();
    }

    /**
     * Runs the selected result's Delete action if it has one -- the clipboard entries do.
     * Mirrors the Shift+Delete binding SearchItem already implements for the overview search.
     */
    function deleteSelected(): void {
        const action = root.searchResults[root.selectedIndex]?.actions?.find(candidate => candidate.name === Translation.tr("Delete"));
        if (action)
            action.execute();
    }

    ////////////////////////// Controls //////////////////////////
    // `arg` is a search mode for "search" and a tab name for "dashboard". Left untyped on
    // purpose: a typed `string` param coerces an omitted argument to "", which would make it
    // impossible to tell "no argument" from an explicit one, and that distinction is what
    // decides whether toggle() switches sub-mode or closes.

    function open(newMode, arg) {
        if (!root.enabled)
            return;
        // The island and the overview search are two front-ends over the same LauncherSearch
        // query, so they must never be up together.
        GlobalStates.overviewOpen = false;
        if (newMode === "search")
            LauncherSearch.query = root.prefixFor(arg ?? "all");
        else if (newMode === "dashboard" && arg)
            root.dashboardTab = arg;
        root.mode = newMode;
    }

    function close(): void {
        root.mode = "collapsed";
        root.selectedIndex = 0;
        LauncherSearch.query = "";
    }

    function toggle(newMode, arg) {
        if (!root.enabled)
            return;
        if (root.mode !== newMode) {
            root.open(newMode, arg);
            return;
        }
        // Already showing this surface. An explicit sub-mode switches to it instead of closing,
        // so hitting the clipboard bind while the app search is open does the useful thing.
        if (arg) {
            if (newMode === "search" && root.searchMode !== arg) {
                root.setSearchMode(arg);
                return;
            }
            if (newMode === "dashboard" && root.dashboardTab !== arg) {
                root.dashboardTab = arg;
                return;
            }
        }
        root.close();
    }

    // Collapse if the island is disabled at runtime, so it can't get stuck expanded.
    onEnabledChanged: {
        if (!root.enabled && root.expanded)
            root.close();
    }

    Connections {
        target: GlobalStates
        // Both of these tear down the window the surface is drawn in. Without collapsing here the
        // island would reappear expanded and still holding exclusive keyboard focus.
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked && root.expanded)
                root.close();
        }
        function onBarOpenChanged() {
            if (!GlobalStates.barOpen && root.expanded)
                root.close();
        }
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen && root.expanded)
                root.close();
        }
    }

    // Click-outside-to-close. A click into a client activates its toplevel; the island lives
    // in the bar's layer-shell window, so it can never be the activated toplevel itself.
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root.closeOnClientActivation();
        }
    }

    Connections {
        // Covers clicking back into the same window: activeToplevel stays the same object and
        // only flips activated back on. Retargets automatically when the toplevel changes.
        target: ToplevelManager.activeToplevel
        function onActivatedChanged() {
            root.closeOnClientActivation();
        }
    }

    ////////////////////////// External entry points //////////////////////////

    IpcHandler {
        target: "island"

        function toggle(): void {
            root.toggle("search");
        }
        function close(): void {
            root.close();
        }
        function search(mode: string): void {
            root.toggle("search", mode.length > 0 ? mode : undefined);
        }
        function clipboard(): void {
            root.toggle("search", "clipboard");
        }
        function emoji(): void {
            root.toggle("search", "emoji");
        }
        function ai(): void {
            root.toggle("search", "ai");
        }
        function symbols(): void {
            root.toggle("search", "symbols");
        }
        function keybinds(): void {
            root.toggle("search", "keybinds");
        }
        function dashboard(tab: string): void {
            root.toggle("dashboard", tab.length > 0 ? tab : undefined);
        }
    }

    CompositorGlobalShortcut {
        name: "islandToggle"
        description: "Toggles the dynamic island search"
        onPressed: root.toggle("search")
    }

    CompositorGlobalShortcut {
        name: "islandDashboardToggle"
        description: "Toggles the dynamic island dashboard"
        onPressed: root.toggle("dashboard")
    }

    CompositorGlobalShortcut {
        name: "islandClose"
        description: "Collapses the dynamic island"
        onPressed: root.close()
    }
}

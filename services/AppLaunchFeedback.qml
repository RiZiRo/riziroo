pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Launch feedback: the "yes, I heard your click" bounce.
 *
 * Cold-starting an app can take several seconds, during which nothing on screen
 * acknowledges the click. Everything that opens an app should call launch() here
 * instead of DesktopEntry.execute() -- this keeps a small list of in-flight
 * launches that modules/ii/launchFeedback draws as bouncing icons on the pointer,
 * and retires each one as soon as its window actually shows up.
 *
 * Windows are matched through ToplevelManager (so it works on any wl_shell
 * compositor); only the pointer tracking is Hyprland-specific, and it degrades to
 * a fixed spot on the focused screen elsewhere.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.launchFeedback?.enable ?? true
    readonly property bool followCursor: Config.options?.launchFeedback?.followCursor ?? true
    readonly property int giveUpDelay: Config.options?.launchFeedback?.timeout ?? 10000
    readonly property int slowAfter: Config.options?.launchFeedback?.slowAfter ?? 2500
    /** An app that already had a window is only being focused, so don't linger on it. */
    readonly property int refocusDelay: 1200
    readonly property int resolvedExitDuration: 280
    readonly property int expiredExitDuration: 320

    readonly property bool onHyprland: Hyprland.monitors.values.length > 0

    property list<var> pending: []
    readonly property bool active: root.pending.length > 0

    // Pointer in compositor-global logical coordinates.
    property real cursorX: 0
    property real cursorY: 0
    property bool cursorKnown: false

    ////////////////////////////// Public API //////////////////////////////

    /**
     * Runs a desktop entry and bounces its icon at the pointer until its window appears.
     */
    function launch(entry): void {
        if (!entry)
            return;
        root.track(entry.name, entry.icon, root.hintsFor(entry));
        entry.execute();
    }

    /**
     * Same, for one of an entry's desktop actions ("New Window", "New Private Window"...).
     */
    function launchAction(entry, action): void {
        if (!action)
            return;
        root.track(action.name || entry?.name, action.icon || entry?.icon, root.hintsFor(entry));
        action.execute();
    }

    /**
     * Feedback only, for callers that run their own command line -- terminal apps, mostly.
     * `extraHints` are window classes to also accept as "the app opened".
     */
    function trackEntry(entry, extraHints): void {
        if (!entry)
            return;
        root.track(entry.name, entry.icon, root.hintsFor(entry).concat(root.cleanHints(extraHints)));
    }

    /**
     * Lowest level entry point: a display name, an icon name and the window classes
     * whose appearance means the launch finished.
     */
    function track(name, iconName, hints): void {
        if (!root.enabled)
            return;
        const item = launchComponent.createObject(root, {
            name: String(name ?? ""),
            iconSource: Quickshell.iconPath(AppSearch.guessIcon(iconName || name), "application-x-executable"),
            hints: root.cleanHints(hints),
            startedAt: Date.now(),
            totalAtStart: root.openAppIds.length
        });
        if (!item)
            return;
        // Windows that are already open must not count as "the launch finished".
        item.matchedAtStart = root.openAppIds.filter(id => root.hintMatches(item, id)).length;
        root.applyPosition(item);
        root.pending = root.pending.concat([item]);
        root.probeCursor();
    }

    /** Drops every in-flight launch without waiting for its window or timeout. */
    function clear(): void {
        const doomed = root.pending;
        root.pending = [];
        Qt.callLater(() => doomed.forEach(item => item.destroy()));
    }

    ////////////////////////////// Window matching //////////////////////////////

    readonly property var openAppIds: Array.from(ToplevelManager.toplevels.values).map(toplevel => String(toplevel.appId ?? "").toLowerCase())
    readonly property string activeAppId: String(ToplevelManager.activeToplevel?.appId ?? "").toLowerCase()

    onOpenAppIdsChanged: root.reconcile()
    onActiveAppIdChanged: root.reconcile()

    function cleanHints(hints): var {
        const cleaned = [];
        for (const hint of (hints ?? [])) {
            const text = String(hint ?? "").trim().toLowerCase();
            if (text.length > 1 && !cleaned.includes(text))
                cleaned.push(text);
        }
        return cleaned;
    }

    /** Every string a .desktop file gives us that a window class might look like. */
    function hintsFor(entry): var {
        if (!entry)
            return [];
        const argv = entry.command ?? [];
        const executable = String(argv.length > 0 ? argv[0] : (entry.execString ?? "")).split(/\s+/)[0];
        return root.cleanHints([entry.startupClass, String(entry.id ?? "").replace(/\.desktop$/, ""), entry.name, executable.split("/").pop()]);
    }

    function hintMatches(item, appId): bool {
        const id = String(appId ?? "").toLowerCase();
        if (id.length === 0 || !item)
            return false;
        const idTail = id.split(".").pop();
        return item.hints.some(hint => {
            if (id === hint)
                return true;
            // org.gnome.Nautilus vs nautilus, and Electron's habit of picking one or the other
            const hintTail = hint.split(".").pop();
            if (idTail.length > 2 && idTail === hintTail)
                return true;
            if (id.length > 3 && hint.includes(id))
                return true;
            if (hint.length > 3 && id.includes(hint))
                return true;
            return false;
        });
    }

    function reconcile(): void {
        if (root.pending.length === 0)
            return;
        let resolvedAny = false;
        for (const item of root.pending) {
            if (item.phase !== "launching")
                continue;
            const matches = root.openAppIds.filter(id => root.hintMatches(item, id)).length;
            const gainedWindow = matches > item.matchedAtStart;
            const gotFocus = matches > 0 && root.hintMatches(item, root.activeAppId);
            if (gainedWindow || gotFocus) {
                root.setPhase(item, "resolved");
                resolvedAny = true;
            }
        }
        if (resolvedAny)
            return;
        // Nothing claimed the new window, but only one launch is in flight and the window
        // count went up: close enough. Covers apps whose class matches nothing in their
        // .desktop file, which is most Electron wrappers, Java apps and games.
        const only = root.pending.length === 1 ? root.pending[0] : null;
        if (only?.phase === "launching" && root.openAppIds.length > only.totalAtStart)
            root.setPhase(only, "resolved");
    }

    function setPhase(item, phase): void {
        item.phase = phase;
        item.phaseAt = Date.now();
        item.pinned = true; // Let the exit animation play where the user last saw it
    }

    ////////////////////////////// Placement //////////////////////////////

    /** Hyprland monitor rect, in the logical coordinates cursorpos reports. */
    function monitorAt(x, y): var {
        const monitors = Array.from(Hyprland.monitors.values);
        for (const monitor of monitors) {
            const scale = monitor.scale > 0 ? monitor.scale : 1;
            if (x >= monitor.x && x < monitor.x + monitor.width / scale && y >= monitor.y && y < monitor.y + monitor.height / scale)
                return monitor;
        }
        return Hyprland.focusedMonitor ?? monitors[0] ?? null;
    }

    /** Where to put the bubble when there is no pointer to put it on (niri, sway, ...). */
    function fallbackPoint(): var {
        const monitor = Hyprland.focusedMonitor;
        const screen = Quickshell.screens.find(candidate => candidate.name === monitor?.name) ?? Quickshell.screens[0];
        if (!screen)
            return Qt.point(0, 0);
        return Qt.point((monitor?.x ?? 0) + screen.width / 2, (monitor?.y ?? 0) + screen.height * 0.78);
    }

    function applyPosition(item): void {
        const usePointer = root.cursorKnown && root.onHyprland;
        const point = usePointer ? Qt.point(root.cursorX, root.cursorY) : root.fallbackPoint();
        const monitor = root.monitorAt(point.x, point.y);
        item.screenName = monitor?.name ?? (Quickshell.screens[0]?.name ?? "");
        item.screenX = monitor?.x ?? 0;
        item.screenY = monitor?.y ?? 0;
        item.x = point.x;
        item.y = point.y;
        item.centered = !usePointer;
        // Until this is true the bubble stays hidden, so it never flashes in a corner
        item.placed = usePointer || !root.onHyprland;
    }

    function syncPositions(): void {
        for (const item of root.pending) {
            if (!item.pinned)
                root.applyPosition(item);
        }
    }

    ////////////////////////////// Pointer tracking //////////////////////////////

    function acceptCursor(text): void {
        const parts = String(text ?? "").trim().split(/[\s,]+/);
        if (parts.length < 2)
            return;
        const x = parseInt(parts[0]);
        const y = parseInt(parts[1]);
        if (!isFinite(x) || !isFinite(y))
            return;
        root.cursorX = x;
        root.cursorY = y;
        root.cursorKnown = true;
        root.syncPositions();
    }

    function probeCursor(): void {
        if (!root.onHyprland || cursorProbe.running)
            return;
        cursorProbe.running = true;
    }

    // One shot, so the very first bubble of a session appears immediately instead of
    // waiting for the streamer below to start up.
    Process {
        id: cursorProbe
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: root.acceptCursor(this.text)
        }
    }

    // Keeps the bubble glued to the pointer. One long-lived process talking to Hyprland's
    // socket, rather than a dozen `hyprctl` forks a second, and only alive while something
    // is actually launching (plus a short grace period for rapid-fire launches).
    Process {
        id: cursorStream
        running: root.enabled && root.followCursor && root.onHyprland && (root.active || streamGrace.running)
        command: ["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/hyprland/cursorpos_stream.py`, String(Math.max(0.03, (Config.options?.launchFeedback?.followIntervalMs ?? 90) / 1000))]
        stdout: SplitParser {
            onRead: data => root.acceptCursor(data)
        }
    }

    Timer {
        id: streamGrace
        interval: 2500
    }

    onActiveChanged: {
        if (root.active)
            streamGrace.stop();
        else
            streamGrace.restart();
    }

    ////////////////////////////// Lifetime //////////////////////////////

    Timer {
        interval: 60
        repeat: true
        running: root.active
        onTriggered: {
            const now = Date.now();
            const survivors = [];
            const doomed = [];
            for (const item of root.pending) {
                if (item.phase === "launching") {
                    const age = now - item.startedAt;
                    if (!item.slow && age >= root.slowAfter)
                        item.slow = true;
                    if (age >= (item.matchedAtStart > 0 ? root.refocusDelay : root.giveUpDelay))
                        root.setPhase(item, "expired");
                }
                const exitDuration = item.phase === "resolved" ? root.resolvedExitDuration : root.expiredExitDuration;
                if (item.phase !== "launching" && now - item.phaseAt >= exitDuration)
                    doomed.push(item);
                else
                    survivors.push(item);
            }
            if (doomed.length === 0)
                return;
            root.pending = survivors;
            // Let the views drop their references before the objects go away
            Qt.callLater(() => doomed.forEach(item => item.destroy()));
        }
    }

    component PendingLaunch: QtObject {
        required property string name
        required property string iconSource
        /** Window classes whose appearance means this launch is done. */
        property var hints: []
        property real startedAt: 0
        property int totalAtStart: 0
        property int matchedAtStart: 0

        /** "launching" -> "resolved" (window showed up) or "expired" (gave up waiting). */
        property string phase: "launching"
        property real phaseAt: 0
        property bool slow: false

        // Compositor-global position, plus the origin of the screen it landed on.
        property real x: 0
        property real y: 0
        property real screenX: 0
        property real screenY: 0
        property string screenName: ""
        property bool placed: false
        property bool centered: false
        /** Stops following the pointer, so exit animations don't skate across the screen. */
        property bool pinned: false
        /**
         * Lives here rather than in the view: adding a second launch rebuilds the
         * Repeater's delegates, and without this the first bubble would pop in again.
         */
        property bool introPlayed: false
    }

    Component {
        id: launchComponent
        PendingLaunch {}
    }

    IpcHandler {
        target: "launchFeedback"

        /** Opens an app with feedback, the same way clicking it in the launcher does. */
        function launch(app: string): string {
            const entry = DesktopEntries.heuristicLookup(app);
            if (!entry)
                return `no desktop entry matches "${app}"`;
            root.launch(entry);
            return `launching ${entry.name}`;
        }

        /** Bounces an app's icon without launching anything, for tweaking the animation. */
        function demo(app: string): string {
            const wanted = app.length > 0 ? app : "kitty";
            const entry = DesktopEntries.heuristicLookup(wanted);
            root.track(entry?.name ?? wanted, entry?.icon ?? wanted, ["launchfeedback-demo-never-matches"]);
            return `bouncing ${entry?.name ?? wanted} for ${root.giveUpDelay}ms`;
        }

        function clear(): void {
            root.clear();
        }

        function status(): string {
            return JSON.stringify({
                enabled: root.enabled,
                onHyprland: root.onHyprland,
                following: cursorStream.running,
                cursorKnown: root.cursorKnown,
                cursor: [root.cursorX, root.cursorY],
                pending: root.pending.map(item => ({
                    name: item.name,
                    phase: item.phase,
                    hints: item.hints,
                    screen: item.screenName,
                    at: [item.x, item.y],
                    placed: item.placed
                }))
            });
        }
    }
}

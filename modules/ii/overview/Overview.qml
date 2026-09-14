import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    // Super is the workspace overview; Alt+Space is the launcher. Keep the old
    // search as a fallback only when no working island is configured.
    readonly property bool workspaceOnly: IslandState.enabled
    readonly property bool islandAbsorbs: IslandState.enabled

    PanelWindow {
        id: panelWindow
        readonly property string searchingText: overviewScope.workspaceOnly ? "" : LauncherSearch.query
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? columnLayout : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidgetLoader.item?.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    GlobalFocusGrab.dismiss();
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidgetLoader.item?.cancelSearch();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);
                    if (overviewScope.workspaceOnly)
                        Qt.callLater(() => columnLayout.forceActiveFocus());
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidgetLoader.item?.setSearchingText(text);
            searchWidgetLoader.item?.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: overviewScope.workspaceOnly ? 0 : -8
            focus: overviewScope.workspaceOnly && GlobalStates.overviewOpen

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                } else if (event.key === Qt.Key_Left) {
                    if (overviewScope.workspaceOnly || !panelWindow.searchingText)
                        Hyprland.dispatch('hl.dsp.focus({ workspace = "r-1" })');
                } else if (event.key === Qt.Key_Right) {
                    if (overviewScope.workspaceOnly || !panelWindow.searchingText)
                        Hyprland.dispatch('hl.dsp.focus({ workspace = "r+1" })');
                }
            }

            Loader {
                id: searchWidgetLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: !overviewScope.workspaceOnly
                visible: active
                sourceComponent: SearchWidget {}
            }

            Loader {
                id: overviewLoader
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                sourceComponent: (Config?.options.overview.style ?? "default") === "niri" ? niriComponent : defaultComponent

                Component {
                    id: defaultComponent
                    OverviewWidget {
                        screen: panelWindow.screen
                        visible: overviewScope.workspaceOnly || (panelWindow.searchingText == "")
                    }
                }

                Component {
                    id: niriComponent
                    NiriOverview {
                        screen: panelWindow.screen
                        panelWindow: panelWindow
                        visible: overviewScope.workspaceOnly || (panelWindow.searchingText == "")
                    }
                }
            }
        }
    }

    function toggleClipboard() {
        if (overviewScope.islandAbsorbs) {
            IslandState.toggle("search", "clipboard");
            return;
        }
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (overviewScope.islandAbsorbs) {
            IslandState.toggle("search", "emoji");
            return;
        }
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    function toggleAi() {
        if (overviewScope.islandAbsorbs) {
            IslandState.toggle("search", "ai");
            return;
        }
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.ai ?? ".");
        GlobalStates.overviewOpen = true;
    }

    function toggleSearch() {
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    CompositorGlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            overviewScope.toggleSearch();
        }
    }
    CompositorGlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    CompositorGlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    CompositorGlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            overviewScope.toggleSearch();
        }
    }
    CompositorGlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    CompositorGlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    CompositorGlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }

    CompositorGlobalShortcut {
        name: "overviewAiToggle"
        description: "Toggle AI search on overview widget"

        onPressed: {
            overviewScope.toggleAi();
        }
    }
}

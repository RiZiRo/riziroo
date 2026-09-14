pragma Singleton
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Island AI answers for the "." prefix.
 *
 * Explicit single-turn requests: typing never spends provider credits.
 * No tools or automatic desktop/file access. Full chat stays in Ai.qml.
 */
Singleton {
    id: root

    readonly property string prefix: Config.options.search.prefix.ai ?? "."
    readonly property bool active: !GlobalStates.screenLocked
        && (IslandState.searchActive || GlobalStates.overviewOpen)
        && LauncherSearch.query.startsWith(root.prefix)
    readonly property string rawText: root.active ? LauncherSearch.query.slice(root.prefix.length) : ""
    readonly property string text: root.rawText.trim()

    property string result: ""
    property string error: ""
    // "idle" | "loading" | "ok" | "failed" | "nokey"
    property string status: "idle"
    property int generation: 0
    property int runningGeneration: -1
    property bool pending: false
    property bool receivedFinal: false

    readonly property var model: Ai.models[Ai.currentModelId]
    readonly property string modelName: (root.model && root.model.name) ? root.model.name : "AI"

    function cancel() {
        root.generation++;
        root.pending = false;
        aiProc.running = false;
        root.status = "idle";
    }

    function reset() {
        root.cancel();
        root.result = "";
        root.error = "";
    }

    onTextChanged: root.reset()
    onActiveChanged: {
        if (!root.active)
            root.reset();
    }
    onModelChanged: root.reset()

    function submit() {
        if (!root.active || root.text.length === 0)
            return;
        root.cancel();
        root.result = "";
        root.error = "";
        if (!root.model) {
            root.status = "failed";
            root.error = Translation.tr("Choose an AI model in the sidebar first.");
            return;
        }
        if (root.model.requires_key && ((Ai.apiKeys[root.model.key_id] ?? "").length === 0)) {
            root.status = "nokey";
            root.error = Translation.tr("No API key is available for this model. Open the AI sidebar to configure it.");
            return;
        }
        root.status = "loading";
        root.pending = true;
        root.startPending();
    }

    function startPending() {
        if (!root.pending || aiProc.running || !root.active)
            return;
        const m = root.model;
        if (!m)
            return;
        root.pending = false;
        root.runningGeneration = root.generation;
        root.receivedFinal = false;
        aiProc.environment = {
            "ISLAND_AI_REQUEST_ID": String(root.generation),
            "ISLAND_AI_QUERY": root.text,
            "ISLAND_AI_ENDPOINT": m.endpoint ?? "",
            "ISLAND_AI_KEY": m.requires_key ? (Ai.apiKeys[m.key_id] ?? "") : "",
            "ISLAND_AI_FORMAT": m.api_format ?? "openai",
            "ISLAND_AI_MODEL": m.model ?? "",
            "ISLAND_AI_HEADERS": JSON.stringify(m.extraHeaders ?? {}),
            "ISLAND_AI_PARAMS": JSON.stringify(m.extraParams ?? {})
        };
        aiProc.running = true;
    }

    function openSidebar() {
        root.cancel();
        IslandState.close();
        GlobalStates.overviewOpen = false;
        GlobalStates.sidebarLeftOpen = true;
    }

    Process {
        id: aiProc
        command: ["python3", Quickshell.shellPath("scripts/ai/island_request.py")]

        stdout: SplitParser {
            onRead: data => {
                try {
                    const reply = JSON.parse(data);
                    if (!root.active || reply.requestId !== String(root.generation))
                        return;
                    root.receivedFinal = true;
                    root.result = reply.text ?? "";
                    root.error = reply.error ?? "";
                    root.status = reply.ok ? "ok" : "failed";
                } catch (e) {
                    if (root.runningGeneration === root.generation) {
                        root.receivedFinal = true;
                        root.error = Translation.tr("Could not read the provider response.");
                        root.status = "failed";
                    }
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.runningGeneration === root.generation && root.active && !root.receivedFinal) {
                root.status = "failed";
                root.error = Translation.tr("The request stopped before an answer arrived. Retry when ready.");
            }
            Qt.callLater(root.startPending);
        }
    }
}

pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Runs filesystem/search tools for the sidebar AI agent.
 *
 * All work is delegated to scripts/ai/agent_tool.py, which speaks JSON over
 * stdin/stdout. Doing the string handling in Python instead of assembling shell
 * commands here avoids quoting bugs and makes exact-string edits reliable.
 *
 * One tool runs at a time. A single Process is reused, so the next job may only
 * start after the previous one has fully exited, otherwise its output would be
 * attributed to the wrong caller.
 */
Singleton {
    id: root

    readonly property string scriptPath: CF.FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/agent_tool.py`)

    /** Tools that only observe the system, so they never need user approval. */
    readonly property var readOnlyTools: ["read_file", "list_directory", "glob_files", "search_files"]
    /** Tools that change files on disk. */
    readonly property var writeTools: ["write_file", "edit_file"]
    readonly property var knownTools: [...readOnlyTools, ...writeTools]

    property var queue: []
    property var activeJob: null
    /** Result parsed from stdout, resolved once the process exits. */
    property var pendingResult: null

    function isKnownTool(name: string): bool {
        return root.knownTools.indexOf(name) !== -1;
    }

    function needsApproval(name: string): bool {
        return root.writeTools.indexOf(name) !== -1;
    }

    /**
     * Runs a tool and invokes callback(result), where result is
     * { ok: bool, content: string, error: string, meta: var }.
     */
    function run(name: string, args: var, workingDirectory: string, callback: var) {
        root.queue = [...root.queue, {
            "name": name,
            "args": args ?? ({}),
            "cwd": workingDirectory,
            "callback": callback
        }];
        root.startNext();
    }

    function startNext() {
        if (root.activeJob || toolProcess.running || root.queue.length === 0) return;
        root.activeJob = root.queue[0];
        root.queue = root.queue.slice(1);
        root.pendingResult = null;
        toolProcess.stdinEnabled = true;
        toolProcess.running = true;
    }

    Process {
        id: toolProcess
        command: ["python3", root.scriptPath]

        onRunningChanged: {
            if (!toolProcess.running || !root.activeJob) return;
            toolProcess.write(JSON.stringify({
                "tool": root.activeJob.name,
                "args": root.activeJob.args,
                "cwd": root.activeJob.cwd
            }));
            toolProcess.stdinEnabled = false; // End of input
        }

        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                const raw = outputCollector.text.trim();
                if (raw.length === 0) return;
                try {
                    root.pendingResult = JSON.parse(raw);
                } catch (e) {
                    root.pendingResult = {
                        "ok": false,
                        "error": `Could not parse tool output: ${raw.slice(0, 500)}`
                    };
                }
            }
        }

        stderr: StdioCollector {
            id: errorCollector
        }

        onExited: (exitCode, exitStatus) => {
            const job = root.activeJob;
            const result = root.pendingResult ?? {
                "ok": false,
                "error": `Tool backend produced no output (exit ${exitCode}). ${errorCollector.text}`.trim()
            };
            root.activeJob = null;
            root.pendingResult = null;
            if (errorCollector.text.length > 0) {
                console.log("[AgentTools] stderr:", errorCollector.text);
            }
            if (job?.callback) job.callback(result);
            // Deferred so a callback that queues another tool doesn't race
            // against this process finishing its teardown.
            Qt.callLater(root.startNext);
        }
    }
}

pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Translation for the launcher's `tr ` prefix.
 *
 * Backed by translate-shell, invoked exactly the way modules/ii/sidebarLeft/Translator.qml already
 * does it -- the bing engine, which needs no API key. Nothing here duplicates that widget; this is
 * the same tool driven from the search query instead of a text area.
 *
 * The service owns its own trigger rather than being fed by LauncherSearch: writing into a service
 * from inside a `results` binding would be a side effect in a binding, and those are what leave QML
 * state subtly out of step.
 */
Singleton {
    id: root

    readonly property string prefix: Config.options.search.prefix.translate
    readonly property bool active: LauncherSearch.query.startsWith(root.prefix)
    readonly property string rawText: root.active ? LauncherSearch.query.slice(root.prefix.length) : ""

    // An explicit "en:fa " or ":fa " spec at the start wins; translate-shell takes the same shape.
    // Codes may carry a region variant, so zh-CN and pt-BR work as well as fa and de.
    readonly property var spec: /^([a-zA-Z]{2,3}(?:-[a-zA-Z]{2,4})?)?:([a-zA-Z]{2,3}(?:-[a-zA-Z]{2,4})?)\s+/.exec(root.rawText)
    readonly property string text: (root.spec ? root.rawText.slice(root.spec[0].length) : root.rawText).trim()

    readonly property string sourceLang: root.spec ? (root.spec[1] || "auto") : "auto"
    readonly property string targetLang: {
        if (root.spec)
            return root.spec[2];
        // Anything outside Basic Latin / Latin-1 / Latin Extended-A is treated as the foreign side.
        // Covers Persian and Arabic, and incidentally Cyrillic, Greek and CJK.
        return /[^\u0000-\u024F]/.test(root.text) ? Config.options.search.translate.secondary : Config.options.search.translate.primary;
    }

    property string result: ""
    // "idle" | "loading" | "ok" | "failed"
    property string status: "idle"

    onTextChanged: {
        root.result = "";
        if (root.text.length === 0) {
            root.status = "idle";
            debounce.stop();
            translateProc.running = false;
            return;
        }
        root.status = "loading";
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: Config.options.search.translate.delay
        repeat: false
        onTriggered: {
            translateProc.running = false;
            translateProc.buffer = "";
            translateProc.running = true;
        }
    }

    Process {
        id: translateProc
        property string buffer: ""

        // Engines are tried in order until one returns output, because translate-shell's scrapers
        // break independently of each other -- bing currently fails with "Failed to extract IG".
        readonly property string script: {
            const source = StringUtils.shellSingleQuoteEscape(root.sourceLang);
            const target = StringUtils.shellSingleQuoteEscape(root.targetLang);
            const payload = StringUtils.shellSingleQuoteEscape(root.text);
            const engines = Config.options.search.translate.engines.map(engine => `'${StringUtils.shellSingleQuoteEscape(engine)}'`).join(" ");
            return `for engine in ${engines}; do out=$(trans -e "$engine" -brief -no-bidi -source '${source}' -target '${target}' '${payload}' 2>/dev/null); if [ -n "$out" ]; then printf '%s' "$out"; exit 0; fi; done; exit 1`;
        }

        command: ["bash", "-c", translateProc.script]

        stdout: SplitParser {
            onRead: data => {
                translateProc.buffer += data + "\n";
            }
        }

        onExited: exitCode => {
            const output = translateProc.buffer.trim();
            if (exitCode !== 0 || output.length === 0) {
                root.result = "";
                root.status = "failed";
                return;
            }
            root.result = output;
            root.status = "ok";
        }
    }
}

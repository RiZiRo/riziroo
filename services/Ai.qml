pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    property Component claudeApiStrategy: ClaudeApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        if (root.currentTool === "functions") prompt += root.toolInstructions;
        return prompt;
    }

    /**
     * Appended to whatever system prompt is loaded, so the file tools behave
     * sanely even with a persona prompt that knows nothing about them.
     */
    readonly property string toolInstructions: `

## Tools (you have real filesystem access)

Working directory: \`${root.workingDirectory}\` — relative paths resolve against it.

- Read a file before claiming anything about it, and again immediately before editing it.
- Use \`search_files\` to find where something is defined and \`glob_files\` to find a file by name. Don't guess paths.
- Prefer \`edit_file\` over \`write_file\` for existing files. Copy \`old_string\` exactly as \`read_file\` showed it, including indentation, with enough context to appear only once.
- \`write_file\`, \`edit_file\` and \`run_shell_command\` ask the user to approve first. Say what you're about to do, make the call, then wait.
- If a call fails, read the error and fix the cause rather than retrying it unchanged. If the user rejects a call, don't retry it.
- After changing code, verify: re-read the edited region or run the project's build/test command. Report failures honestly with the output.
`
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    /**
     * The keyring loads asynchronously, and its contents can change while the
     * shell runs. Sending before the key is in hand puts an empty token on the
     * wire, which every provider answers with a confusing auth error, so a
     * request that needs a key it doesn't have waits for exactly one fetch.
     */
    property bool awaitingKey: false

    function ensureKeyForRequest(model): bool {
        if (!model?.requires_key) return true;
        if ((root.apiKeys[model.key_id]?.length ?? 0) > 0) {
            root.awaitingKey = false;
            return true;
        }
        if (root.awaitingKey) { // Fetch came back and the key still isn't there
            root.awaitingKey = false;
            root.addApiKeyAdvice(model);
            return false;
        }
        root.awaitingKey = true;
        KeyringStorage.fetchKeyringData();
        return false;
    }

    function resumeRequestWaitingForKey() {
        if (!root.awaitingKey) return;
        requester.makeRequest(); // ensureKeyForRequest now sends or advises
    }

    Connections {
        target: KeyringStorage
        function onFetchFinished() { root.resumeRequestWaitingForKey(); }
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`,
        "{CWD}": root.workingDirectory
    }

    /**
     * Directory that relative paths and shell commands resolve against.
     * Change it with /cwd so the model can work inside a project.
     */
    property string workingDirectory: Persistent.states?.ai?.workingDirectory || CF.FileUtils.trimFileProtocol(Directories.home)

    function setWorkingDirectory(path) {
        const trimmed = (path ?? "").trim();
        if (trimmed.length === 0) {
            root.addMessage(Translation.tr("Working directory: `%1`").arg(root.workingDirectory), root.interfaceRole);
            return;
        }
        workingDirectoryCheck.requestedPath = CF.FileUtils.trimFileProtocol(trimmed);
        workingDirectoryCheck.running = true;
    }

    /** Only accept a working directory that actually exists. */
    Process {
        id: workingDirectoryCheck
        property string requestedPath: ""
        command: ["bash", "-c", `cd -- "${requestedPath}" && pwd`]
        stdout: StdioCollector {
            id: workingDirectoryOutput
        }
        onExited: (exitCode, exitStatus) => {
            const resolved = workingDirectoryOutput.text.trim();
            if (exitCode !== 0 || resolved.length === 0) {
                root.addMessage(Translation.tr("Not a directory: `%1`").arg(workingDirectoryCheck.requestedPath), root.interfaceRole);
                return;
            }
            root.workingDirectory = resolved;
            if (Persistent.states?.ai) Persistent.states.ai.workingDirectory = resolved;
            root.addMessage(Translation.tr("Working directory set to `%1`").arg(resolved), root.interfaceRole);
        }
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"

    /**
     * File and search tools, in a neutral {name, description, parameters} form.
     * Each api_format wraps these differently in `tools` below.
     */
    function fileToolSchemas() {
        return [
            {
                "name": "read_file",
                "description": "Read a text file from disk and get it back with line numbers. Always read a file before editing it. Paths may be absolute or relative to the working directory.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File to read" },
                        "offset": { "type": "integer", "description": "1-based line to start from. Omit to read from the beginning." },
                        "limit": { "type": "integer", "description": "Maximum number of lines to read. Omit for the default of 2000." }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "list_directory",
                "description": "List the immediate contents of a directory. Directories are suffixed with a slash.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Directory to list. Defaults to the working directory." }
                    }
                }
            },
            {
                "name": "glob_files",
                "description": "Find files by name pattern, newest first. Use this when you know roughly what a file is called but not where it lives.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "pattern": { "type": "string", "description": "Glob such as **/*.qml or Config.*" },
                        "path": { "type": "string", "description": "Directory to search under. Defaults to the working directory." }
                    },
                    "required": ["pattern"]
                }
            },
            {
                "name": "search_files",
                "description": "Search file contents by regular expression and get back matching lines as path:line:text. Use this to locate code rather than guessing where it is.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "pattern": { "type": "string", "description": "Regular expression to search for" },
                        "path": { "type": "string", "description": "Directory to search under. Defaults to the working directory." },
                        "glob": { "type": "string", "description": "Restrict to file names matching this glob, e.g. *.py" }
                    },
                    "required": ["pattern"]
                }
            },
            {
                "name": "write_file",
                "description": "Create a new file or completely overwrite an existing one. Requires user approval. Prefer edit_file for changing part of an existing file.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File to write" },
                        "content": { "type": "string", "description": "Full contents of the file" }
                    },
                    "required": ["path", "content"]
                }
            },
            {
                "name": "edit_file",
                "description": "Replace an exact string in a file. Requires user approval. Read the file first and copy old_string byte for byte, including indentation. It must appear exactly once unless replace_all is set.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File to edit" },
                        "old_string": { "type": "string", "description": "Exact text to replace, with enough surrounding context to be unique" },
                        "new_string": { "type": "string", "description": "Replacement text" },
                        "replace_all": { "type": "boolean", "description": "Replace every occurrence instead of requiring a unique match" }
                    },
                    "required": ["path", "old_string", "new_string"]
                }
            }
        ];
    }

    /** Desktop shell and command tools, same neutral form as fileToolSchemas. */
    function shellToolSchemas() {
        return [
            {
                "name": "get_shell_config",
                "description": "Get the desktop shell config file contents",
                "parameters": { "type": "object", "properties": {} }
            },
            {
                "name": "set_shell_config",
                "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "key": {
                            "type": "string",
                            "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                        },
                        "value": {
                            "type": "string",
                            "description": "The value to set, e.g. `true`"
                        }
                    },
                    "required": ["key", "value"]
                }
            },
            {
                "name": "run_shell_command",
                "description": "Run a shell command in bash and get its output. Requires user approval. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": {
                            "type": "string",
                            "description": "The bash command to run",
                        },
                    },
                    "required": ["command"]
                }
            }
        ];
    }

    function agentToolSchemas() {
        return [...root.fileToolSchemas(), ...root.shellToolSchemas()];
    }

    // Shared by every api_format that speaks the OpenAI tool schema
    function openAiFormatTools() {
        return {
            "functions": root.agentToolSchemas().map(schema => ({
                "type": "function",
                "function": schema
            })),
            "search": [],
            "none": [],
        };
    }

    /**
     * Gemini rejects parameter objects with no properties, so drop `parameters`
     * entirely for tools that take no arguments.
     */
    function geminiFormatTools() {
        const declarations = root.agentToolSchemas().map(schema => {
            const takesArgs = Object.keys(schema.parameters?.properties ?? {}).length > 0;
            return takesArgs ? schema : {
                "name": schema.name,
                "description": schema.description
            };
        });
        return {
            "functions": [{
                "functionDeclarations": [
                    {
                        "name": "switch_to_search_mode",
                        "description": "Search the web",
                    },
                    ...declarations
                ]
            }],
            "search": [{ "google_search": {} }],
            "none": []
        };
    }

    property var tools: {
        "gemini": root.geminiFormatTools(),
        "openai": root.openAiFormatTools(),
        "claude": root.openAiFormatTools(),
        "mistral": root.openAiFormatTools()
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format])
    property var toolDescriptions: {
        "functions": Translation.tr("Read, search and edit files, run commands, change shell config.\nWrites and commands ask for your approval first"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    // - extraHeaders: Extra HTTP headers for endpoints that need more than the key. JSON object.
    property var models: Config.options.policies.ai === 2 ? {} : {
        "gemini-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nNewer model that's slower than its predecessor but should deliver higher quality answers"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "gemini-3-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 3 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nPro-level intelligence at the speed and pricing of Flash."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent",
            "model": "gemini-3-flash-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training.\n\n**Instructions**: Log into Google account, allow AI Studio to create Google Cloud project or whatever it asks, go back and click Get API key"),
            "api_format": "gemini",
        }),
        "mistral-medium-3": aiModelComponent.createObject(this, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | %1's model | Delivers fast, responsive and well-formatted answers. Disadvantages: not very eager to do stuff; might make up unknown function calls").arg("Mistral"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
        "claude-opus-5": aiModelComponent.createObject(this, {
            "name": "Claude Opus 5",
            "icon": "claude-symbolic",
            "description": Translation.tr("Online | %1's model | Strong at coding, reasoning and following instructions closely").arg("Anthropic"),
            "homepage": "https://www.anthropic.com/claude",
            "endpoint": "https://api.justwoker.icu/v1/chat/completions",
            "model": "claude-opus-5",
            "requires_key": true,
            "key_id": "justwoker",
            "key_get_link": "https://api.justwoker.icu",
            "key_get_description": Translation.tr("**Instructions**: Use the API key issued for your justwoker.icu account. The same key works for every Claude model in this list."),
            "api_format": "claude",
        }),
        "claude-opus-5-thinking": aiModelComponent.createObject(this, {
            "name": "Claude Opus 5 Thinking",
            "icon": "claude-symbolic",
            "description": Translation.tr("Online | %1's model | Same model with extended reasoning shown before the answer. Slower, better on hard problems").arg("Anthropic"),
            "homepage": "https://www.anthropic.com/claude",
            "endpoint": "https://api.justwoker.icu/v1/chat/completions",
            "model": "claude-opus-5-thinking",
            "requires_key": true,
            "key_id": "justwoker",
            "key_get_link": "https://api.justwoker.icu",
            "key_get_description": Translation.tr("**Instructions**: Use the API key issued for your justwoker.icu account. The same key works for every Claude model in this list."),
            "api_format": "claude",
        }),
        "glm-5.3": aiModelComponent.createObject(this, {
            "name": "GLM 5.3",
            "icon": "spark-symbolic",
            "description": Translation.tr("Online | %1's model | Fast and cheap for long sessions, solid at coding and tool use").arg("Z.ai"),
            "homepage": "https://agentrouter.org",
            "endpoint": "https://agentrouter.org/v1/chat/completions",
            "model": "glm-5.3",
            "requires_key": true,
            "key_id": "agentrouter",
            "key_get_link": "https://agentrouter.org",
            "key_get_description": Translation.tr("**Instructions**: Use the API key issued for your agentrouter.org account. The same key works for every AgentRouter model in this list."),
            "api_format": "openai",
            // AgentRouter answers 401 "unauthorized client detected" unless the
            // request looks like it comes from a CLI client it supports
            "extraHeaders": ({ "User-Agent": "claude-cli/1.0.0 (external, cli)" }),
        }),
        "deepseek-v4-flash": aiModelComponent.createObject(this, {
            "name": "DeepSeek V4 Flash",
            "icon": "deepseek-symbolic",
            "description": Translation.tr("Online | %1's model | Lightweight and quick, shows its reasoning before answering").arg("DeepSeek"),
            "homepage": "https://agentrouter.org",
            "endpoint": "https://agentrouter.org/v1/chat/completions",
            "model": "deepseek-v4-flash",
            "requires_key": true,
            "key_id": "agentrouter",
            "key_get_link": "https://agentrouter.org",
            "key_get_description": Translation.tr("**Instructions**: Use the API key issued for your agentrouter.org account. The same key works for every AgentRouter model in this list."),
            "api_format": "openai",
            // Same client check as the other AgentRouter models
            "extraHeaders": ({ "User-Agent": "claude-cli/1.0.0 (external, cli)" }),
        }),
        "agnes-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Agnes 2.5 Flash",
            "icon": "spark-symbolic",
            "description": Translation.tr("Online | %1's free model | Fast, streams its reasoning and calls tools, so it works as a coding agent").arg("Agnes AI"),
            "homepage": "https://agnes-ai.com",
            "endpoint": "https://apihub.agnes-ai.com/v1/chat/completions",
            "model": "agnes-2.5-flash",
            "requires_key": true,
            "key_id": "agnes",
            "key_get_link": "https://agnes-ai.com",
            "key_get_description": Translation.tr("**Pricing**: free tier.\n\n**Instructions**: Use the API key issued for your Agnes AI account. The same key works for every Agnes model in this list."),
            "api_format": "openai",
        }),
        "agnes-2.5-pro": aiModelComponent.createObject(this, {
            "name": "Agnes 2.5 Pro",
            "icon": "spark-symbolic",
            "description": Translation.tr("Online | %1's model | Slower sibling of Flash, better on hard problems").arg("Agnes AI"),
            "homepage": "https://agnes-ai.com",
            "endpoint": "https://apihub.agnes-ai.com/v1/chat/completions",
            "model": "agnes-2.5-pro",
            "requires_key": true,
            "key_id": "agnes",
            "key_get_link": "https://agnes-ai.com",
            "key_get_description": Translation.tr("**Pricing**: free tier.\n\n**Instructions**: Use the API key issued for your Agnes AI account. The same key works for every Agnes model in this list."),
            "api_format": "openai",
        }),
        "genspark-gemini-3.7-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 3.7 Flash (Genspark)",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google via Genspark Proxy | Fast, advanced multimodal reasoning"),
            "homepage": "https://www.genspark.ai",
            "endpoint": "https://www.genspark.ai/api/llm_proxy/gemini/v1beta/models/gemini-3.7-flash:streamGenerateContent",
            "model": "gemini-3.7-flash",
            "requires_key": true,
            "key_id": "genspark",
            "key_get_link": "https://www.genspark.ai",
            "key_get_description": Translation.tr("**Instructions**: Uses your Genspark login API key (~/.genspark-tool-cli/config.json)."),
            "api_format": "gemini",
        }),
        "genspark-claude-opus-5": aiModelComponent.createObject(this, {
            "name": "Claude Opus 5 (Genspark)",
            "icon": "claude-symbolic",
            "description": Translation.tr("Online | Anthropic via Genspark Proxy | Premium reasoning and coding"),
            "homepage": "https://www.genspark.ai",
            "endpoint": "https://www.genspark.ai/api/llm_proxy/v1/chat/completions",
            "model": "claude-opus-5",
            "requires_key": true,
            "key_id": "genspark",
            "key_get_link": "https://www.genspark.ai",
            "key_get_description": Translation.tr("**Instructions**: Uses your Genspark login API key (~/.genspark-tool-cli/config.json)."),
            "api_format": "openai",
        }),
        "genspark-claude-sonnet-4-5": aiModelComponent.createObject(this, {
            "name": "Claude Sonnet 4.5 (Genspark)",
            "icon": "claude-symbolic",
            "description": Translation.tr("Online | Anthropic via Genspark Proxy | Fast, balanced model"),
            "homepage": "https://www.genspark.ai",
            "endpoint": "https://www.genspark.ai/api/llm_proxy/v1/chat/completions",
            "model": "claude-sonnet-4-5",
            "requires_key": true,
            "key_id": "genspark",
            "key_get_link": "https://www.genspark.ai",
            "key_get_description": Translation.tr("**Instructions**: Uses your Genspark login API key (~/.genspark-tool-cli/config.json)."),
            "api_format": "openai",
        }),
        "genspark-gpt-5-codex": aiModelComponent.createObject(this, {
            "name": "GPT 5 Codex (Genspark)",
            "icon": "spark-symbolic",
            "description": Translation.tr("Online | OpenAI via Genspark Proxy | Codex model for coding and reasoning"),
            "homepage": "https://www.genspark.ai",
            "endpoint": "https://www.genspark.ai/api/llm_proxy/v1/chat/completions",
            "model": "gpt-5-codex",
            "requires_key": true,
            "key_id": "genspark",
            "key_get_link": "https://www.genspark.ai",
            "key_get_description": Translation.tr("**Instructions**: Uses your Genspark login API key (~/.genspark-tool-cli/config.json)."),
            "api_format": "openai",
        }),
        "genspark-deepseek-v4-flash": aiModelComponent.createObject(this, {
            "name": "DeepSeek V4 Flash (Genspark)",
            "icon": "deepseek-symbolic",
            "description": Translation.tr("Online | DeepSeek via Genspark Proxy | Ultra-fast reasoning and code"),
            "homepage": "https://www.genspark.ai",
            "endpoint": "https://www.genspark.ai/api/llm_proxy/v1/chat/completions",
            "model": "deep-seek-v4-flash",
            "requires_key": true,
            "key_id": "genspark",
            "key_get_link": "https://www.genspark.ai",
            "key_get_description": Translation.tr("**Instructions**: Uses your Genspark login API key (~/.genspark-tool-cli/config.json)."),
            "api_format": "openai",
        }),
        "genspark-minimax-m3": aiModelComponent.createObject(this, {
            "name": "MiniMax M3 (Genspark)",
            "icon": "spark-symbolic",
            "description": Translation.tr("Online | MiniMax via Genspark Proxy | Multilingual large context reasoning"),
            "homepage": "https://www.genspark.ai",
            "endpoint": "https://www.genspark.ai/api/llm_proxy/v1/chat/completions",
            "model": "minimax-m3",
            "requires_key": true,
            "key_id": "genspark",
            "key_get_link": "https://www.genspark.ai",
            "key_get_description": Translation.tr("**Instructions**: Uses your Genspark login API key (~/.genspark-tool-cli/config.json)."),
            "api_format": "openai",
        }),
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
        "claude": claudeApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, model)
        });
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string pendingFilePath: ""

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
        root.addUserModels() // Config onReadyChanged above might not fire if config is loaded before this service
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n"), Ai.interfaceRole) + "\n```"
        }
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    FileView {
        id: requesterScriptFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.saveChat("lastSession")
            root.responseFinished()
        }

        function makeRequest() {
            const model = models[currentModelId];

            // Don't send until the key for this model is actually loaded
            if (!root.ensureKeyForRequest(model)) return;

            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format][root.currentTool], root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = Object.assign({
                "Content-Type": "application/json",
            }, model.extraHeaders ?? {})
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);

            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }

            // A stream that ends without a finish reason can still leave a
            // complete tool call buffered in the strategy.
            if (result.functionCall) {
                requester.message.functionCall = result.functionCall;
                root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                return;
            }

            // A tool finished while this request was still streaming
            if (root.continuationQueued) {
                root.continuationQueued = false;
                requester.makeRequest();
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.toolTurnCount = 0; // Fresh budget for each user turn
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true, toolCallId = "") {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "toolCallId": toolCallId,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output, toolCallId = "") {
        const aiMessage = createFunctionOutputMessage(name, output, true, toolCallId);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    /**
     * Number of consecutive tool round-trips since the user last spoke.
     * Prevents a model that keeps calling tools from looping forever.
     */
    property int toolTurnCount: 0
    readonly property int maxToolTurns: 25
    /** Set when a tool finished before the streaming request process exited. */
    property bool continuationQueued: false

    /**
     * Starts the next model request, waiting for the in-flight one to exit first.
     * Read-only tools can finish faster than curl closes its stream, and starting
     * a second request on the same Process would clobber it.
     */
    function requestContinuation() {
        if (requester.running) {
            root.continuationQueued = true;
            return;
        }
        requester.makeRequest();
    }

    /**
     * Feeds a tool result back to the model and lets it continue.
     * toolCallId links the result to the call the model made, which providers
     * require before they will accept the next turn.
     * Stops and tells the user if the model has been looping too long.
     */
    function continueWithToolOutput(name, output, toolCallId = "") {
        root.addFunctionOutputMessage(name, output, toolCallId);
        root.toolTurnCount += 1;
        if (root.toolTurnCount > root.maxToolTurns) {
            root.addMessage(
                Translation.tr("Stopped after %1 tool calls in a row. Send another message to continue.").arg(root.maxToolTurns),
                root.interfaceRole
            );
            return;
        }
        root.requestContinuation();
    }

    /** One-line description of a pending tool call, shown in the approval prompt. */
    function describeToolCall(name, args) {
        if (name === "run_shell_command") return args?.command ?? "";
        if (name === "write_file") {
            const lineCount = (args?.content ?? "").split("\n").length;
            return Translation.tr("Write %1 (%2 lines)").arg(args?.path ?? "?").arg(lineCount);
        }
        if (name === "edit_file") {
            return Translation.tr("Edit %1").arg(args?.path ?? "?");
        }
        return `${name}(${JSON.stringify(args ?? {})})`;
    }

    /** Markdown preview of what a pending tool call would do. */
    function previewToolCall(name, args) {
        if (name === "run_shell_command") {
            return `\n\n**${Translation.tr("Command execution request")}**\n\n\`\`\`command\n${args.command}\n\`\`\``;
        }
        if (name === "write_file") {
            return `\n\n**${Translation.tr("Wants to write")} \`${args.path}\`**\n\n\`\`\`command\n${args.content ?? ""}\n\`\`\``;
        }
        if (name === "edit_file") {
            const before = (args.old_string ?? "").split("\n").map(line => `- ${line}`).join("\n");
            const after = (args.new_string ?? "").split("\n").map(line => `+ ${line}`).join("\n");
            return `\n\n**${Translation.tr("Wants to edit")} \`${args.path}\`**\n\n\`\`\`command\n${before}\n${after}\n\`\`\``;
        }
        return `\n\n\`\`\`command\n${name}(${JSON.stringify(args, null, 2)})\n\`\`\``;
    }

    /**
     * Parks a tool call until the user approves or rejects it.
     * The message shows a preview plus Approve/Reject buttons.
     */
    function requestToolApproval(name, args, message: AiMessageData) {
        message.pendingToolName = name;
        message.pendingToolArgs = args;
        message.pendingToolSummary = root.describeToolCall(name, args);
        const preview = root.previewToolCall(name, args);
        message.rawContent += preview;
        message.content += preview;
        message.functionPending = true; // Marks the message as awaiting a decision
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        const name = message.pendingToolName || message.functionName;
        message.pendingToolName = "";
        root.continueWithToolOutput(
            name,
            Translation.tr("Rejected by user. Do not retry this; ask what they'd prefer instead."),
            message.toolCallId
        );
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        const name = message.pendingToolName || message.functionName;
        const args = message.pendingToolArgs ?? message.functionCall?.args ?? {};
        message.pendingToolName = "";

        if (name === "run_shell_command") {
            root.runApprovedShellCommand(name, args, message);
            return;
        }
        root.runAgentTool(name, args, message.toolCallId);
    }

    /** Streams an approved shell command's output into a new message. */
    function runApprovedShellCommand(name, args, message: AiMessageData) {
        const responseMessage = createFunctionOutputMessage(name, "", false, message.toolCallId);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    /** Runs a file/search tool through AgentTools and continues the conversation. */
    function runAgentTool(name, args, toolCallId = "") {
        AgentTools.run(name, args, root.workingDirectory, result => {
            const output = result.ok
                ? (result.content ?? "")
                : `Error: ${result.error ?? "unknown failure"}`;
            root.continueWithToolOutput(name, output, toolCallId);
        });
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        workingDirectory: root.workingDirectory
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        stderr: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            root.toolTurnCount += 1;
            if (root.toolTurnCount > root.maxToolTurns) {
                root.addMessage(
                    Translation.tr("Stopped after %1 tool calls in a row. Send another message to continue.").arg(root.maxToolTurns),
                    root.interfaceRole
                );
                return;
            }
            root.requestContinuation(); // Continue
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        const callId = message.toolCallId ?? "";
        if (name === "switch_to_search_mode") {
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            root.continueWithToolOutput(name, Translation.tr("Switched to search mode. Continue with the user's request."), callId);
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            root.continueWithToolOutput(name, JSON.stringify(configJson), callId);
        } else if (name === "set_shell_config") {
            if (!args.key || args.value === undefined) {
                root.continueWithToolOutput(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."), callId);
                return;
            }
            Config.setNestedValue(args.key, args.value);
            root.continueWithToolOutput(name, Translation.tr("Set %1 to %2").arg(args.key).arg(args.value), callId);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                root.continueWithToolOutput(name, Translation.tr("Invalid arguments. Must provide `command`."), callId);
                return;
            }
            root.requestToolApproval(name, args, message);
        } else if (AgentTools.isKnownTool(name)) {
            if (AgentTools.needsApproval(name)) {
                root.requestToolApproval(name, args, message);
            } else {
                root.runAgentTool(name, args, callId);
            }
        }
        else root.continueWithToolOutput(name, Translation.tr("Unknown tool: %1").arg(name), callId);
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "toolCallId": message.toolCallId,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "toolCallId": message.toolCallId ?? "",
                    "visibleToUser": message.visibleToUser,
                });
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}

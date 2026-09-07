import QtQuick

/**
 * Base strategy for every endpoint that speaks the OpenAI chat-completions
 * format: OpenAI itself, Mistral, and OpenAI-compatible Anthropic proxies.
 *
 * Handles the three things all of them get wrong if done naively:
 * - tool call arguments arrive as fragments across many deltas, so they are
 *   accumulated and only emitted once a finish reason arrives
 * - reasoning deltas (`reasoning` / `reasoning_content`) are wrapped in <think>
 *   blocks for display, then stripped before being replayed to the model
 * - tool results are replayed as ordinary user turns, which every provider
 *   accepts, instead of a `tool` role that needs matching call ids
 */
ApiStrategy {
    property bool isReasoning: false
    property var pendingToolCalls: ({})

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    /**
     * Reasoning text is only useful while it streams; replaying it wastes
     * context and some endpoints reject it outright. The `[[ Function: ... ]]`
     * marker is display-only too — the real call is replayed as tool_calls.
     */
    function stripThinkBlocks(text: string): string {
        return String(text ?? "")
            .replace(/<think>[\s\S]*?<\/think>/g, "")
            .replace(/\[\[ Function: [\s\S]*?\]\]/g, "")
            .replace(/\[\[ Ignored \d+ parallel tool call\(s\)[^\]]*\]\]/g, "")
            .trim();
    }

    /**
     * Converts one stored message into a wire message. Tool calls and their
     * results are replayed using the real assistant/tool_calls + tool-role
     * protocol, so the model sees its own calls rather than prose about them.
     */
    function buildMessage(message) {
        const isToolResult = message.functionResponse?.length > 0 && message.functionName?.length > 0;
        if (isToolResult) {
            if (message.toolCallId?.length > 0) {
                return {
                    "role": "tool",
                    "tool_call_id": message.toolCallId,
                    "content": message.functionResponse
                };
            }
            // No call id (loaded from an older chat): fall back to a user turn
            return {
                "role": "user",
                "content": `[[ Result of ${message.functionName} ]]\n${message.functionResponse}`
            };
        }

        const isToolCall = message.role === "assistant"
            && message.functionName?.length > 0
            && message.toolCallId?.length > 0;
        if (isToolCall) {
            const args = message.functionCall?.args ?? {};
            return {
                "role": "assistant",
                "content": stripThinkBlocks(message.rawContent),
                "tool_calls": [{
                    "id": message.toolCallId,
                    "type": "function",
                    "function": {
                        "name": message.functionName,
                        "arguments": JSON.stringify(args)
                    }
                }]
            };
        }

        const content = message.role === "assistant"
            ? stripThinkBlocks(message.rawContent)
            : message.rawContent;
        return {
            "role": message.role,
            "content": content.length > 0 ? content : "(no content)"
        };
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let baseData = {
            "model": model.model,
            "messages": [
                { role: "system", content: systemPrompt },
                ...messages.map(message => buildMessage(message))
            ],
            "stream": true,
            "temperature": temperature,
        };
        // Some OpenAI-compatible proxies reject an empty tools array
        if (tools && tools.length > 0) baseData.tools = tools;
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function endThinkBlock(message) {
        if (!isReasoning) return;
        isReasoning = false;
        const endBlock = "\n\n</think>\n\n";
        message.content += endBlock;
        message.rawContent += endBlock;
    }

    function collectToolCallDeltas(deltaToolCalls) {
        deltaToolCalls.forEach(toolCall => {
            const index = toolCall.index ?? 0;
            if (!pendingToolCalls[index]) {
                pendingToolCalls[index] = { id: "", name: "", arguments: "" };
            }
            const entry = pendingToolCalls[index];
            if (toolCall.id) entry.id = toolCall.id;
            if (toolCall.function?.name) entry.name = toolCall.function.name;
            if (toolCall.function?.arguments) entry.arguments += toolCall.function.arguments;
        });
    }

    function emitToolCall(message) {
        const indices = Object.keys(pendingToolCalls).sort((a, b) => Number(a) - Number(b));
        if (indices.length === 0) return {};
        const entry = pendingToolCalls[indices[0]];
        const droppedCount = indices.length - 1;
        pendingToolCalls = ({});
        if (!entry.name || entry.name.length === 0) return {};

        let args = {};
        try {
            if (entry.arguments.trim().length > 0) args = JSON.parse(entry.arguments);
        } catch (e) {
            console.log("[AI] Could not parse tool call arguments: ", entry.arguments);
        }

        endThinkBlock(message);
        let newContent = `\n\n[[ Function: ${entry.name}(${JSON.stringify(args, null, 2)}) ]]\n`;
        if (droppedCount > 0) {
            // The chat runs one tool at a time, so extra parallel calls are dropped
            newContent += `\n[[ Ignored ${droppedCount} parallel tool call(s); tools run one at a time ]]\n`;
        }
        message.rawContent += newContent;
        message.content += newContent;
        message.functionName = entry.name;
        message.functionCall = entry.name;
        message.toolCallId = entry.id ?? "";
        return { functionCall: { name: entry.name, args: args, id: entry.id } };
    }

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            const toolCallResult = emitToolCall(message);
            endThinkBlock(message);
            if (toolCallResult.functionCall) return Object.assign({ finished: true }, toolCallResult);
            return { finished: true };
        }

        try {
            const dataJson = JSON.parse(cleanData);

            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            const delta = dataJson.choices?.[0]?.delta;
            const finishReason = dataJson.choices?.[0]?.finish_reason;

            if (delta?.tool_calls) {
                collectToolCallDeltas(delta.tool_calls);
            }

            const responseContent = delta?.content || dataJson.message?.content;
            const responseReasoning = delta?.reasoning || delta?.reasoning_content;

            let newContent = "";
            if (responseContent && responseContent.length > 0) {
                endThinkBlock(message);
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }
            message.content += newContent;
            message.rawContent += newContent;

            if (finishReason) {
                const toolCallResult = emitToolCall(message);
                endThinkBlock(message);
                if (toolCallResult.functionCall) return toolCallResult;
            }

            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                return { finished: true };
            }

        } catch (e) {
            console.log("[AI] Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }

        return {};
    }

    function onRequestFinished(message) {
        const toolCallResult = emitToolCall(message);
        endThinkBlock(message);
        return toolCallResult;
    }

    function reset() {
        isReasoning = false;
        pendingToolCalls = ({});
    }
}

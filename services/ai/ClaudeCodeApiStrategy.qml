import qs.modules.common.functions as CF
import QtQuick

// Runs prompts through the local `claude` CLI (Claude Code) instead of a
// metered HTTP API, so usage comes out of a Claude Pro/Max subscription
// rather than API billing. Ai.qml always builds a curl-based script for the
// other strategies; finalizeScriptContent() below throws that script away
// entirely and substitutes one that shells out to `claude` instead, which is
// the only hook in the ApiStrategy interface that can replace the request
// mechanism wholesale rather than just its endpoint/headers/body.
//
// parseResponseLine() below is verified against a real captured trace of
// `claude -p "hi" --verbose --output-format stream-json --include-partial-messages`
// (Claude Code CLI 2.1.278). Re-check against a fresh trace if this stops
// working after a CLI update - the event shapes aren't a documented contract.
//
// After turn one, later turns pass --resume <session-id> and send only the
// new message instead of replaying the whole conversation. Verified against a
// captured two-turn trace: --resume reports back the same session_id it was
// given, and the resumed turn's "assistant" event recaps only that turn's
// text (not the full session), so the no-op on "assistant" above still holds.
// The trace also confirms the payoff: turn one built a cache
// (cache_creation_input_tokens: 9461), the resumed turn read from it
// (cache_read_input_tokens: 26249) and paid input_tokens: 2 - not a re-send
// of the whole conversation.
ApiStrategy {
    // The Claude Code CLI's own session id, captured from event.session_id in
    // parseResponseLine() (present on nearly every stream-json line). Kept
    // across turns deliberately - reset() runs before every single request
    // (see makeRequest() in Ai.qml), not just on a new chat, so clearing this
    // there would defeat --resume entirely. It's naturally invalidated by the
    // messages.length check in buildRequestData() below when a chat is
    // cleared, since that drops back to a single message with no history.
    property string claudeSessionId: ""

    // Per-turn scratch, stashed by buildRequestData() and read back by
    // finalizeScriptContent(). Ai.qml calls the two back-to-back within the
    // same makeRequest(), so passing data between them via strategy-instance
    // state (cleared in reset(), unlike claudeSessionId above) is safe.
    property string pendingPrompt: ""
    property string pendingResumeSessionId: ""

    function buildEndpoint(model: AiModel): string {
        return model.endpoint; // unused - finalizeScriptContent() never runs curl
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        // sendUserMessage() appends the new user message to messageIDs before
        // calling makeRequest(), so `messages` here always ends with it. Resume
        // only when we both have a session to resume AND there's prior history
        // in front of it - a fresh/cleared chat is exactly one message long
        // (see clearMessages() in Ai.qml, which doesn't touch claudeSessionId,
        // so this length check is what actually invalidates a stale session).
        const latest = messages[messages.length - 1];
        const canResume = claudeSessionId.length > 0 && messages.length > 1 && latest?.role === "user";

        if (canResume) {
            // Claude Code already has everything earlier in its own session
            // state - send only the new turn, not the system prompt or history.
            pendingResumeSessionId = claudeSessionId;
            pendingPrompt = latest.rawContent;
        } else {
            // No session to resume: replay the whole conversation as one flat
            // prompt, same as before --resume existed.
            pendingResumeSessionId = "";
            let parts = [];
            if (systemPrompt && systemPrompt.length > 0) {
                parts.push(systemPrompt);
            }
            for (const message of messages) {
                const speaker = message.role === "user" ? "User" : "Assistant";
                parts.push(`${speaker}: ${message.rawContent}`);
            }
            pendingPrompt = parts.join("\n\n");
        }

        return {}; // discarded - finalizeScriptContent() ignores the curl line entirely
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return ""; // no API key - `claude` auth is whatever `claude login` already set up
    }

    function buildScriptFileSetup(filePath) {
        return ""; // TODO: file attachments, once needed - `claude -p` has its own file-reading tools
    }

    function finalizeScriptContent(scriptContent: string): string {
        // --verbose is mandatory: `--print --output-format=stream-json` refuses
        // to run without it ("Error: When using --print, --output-format=
        // stream-json requires --verbose") and exits before emitting any JSON.
        const resumeFlag = pendingResumeSessionId.length > 0
            ? ` --resume '${CF.StringUtils.shellSingleQuoteEscape(pendingResumeSessionId)}'`
            : "";
        return "#!/usr/bin/env bash\n"
            + `claude -p '${CF.StringUtils.shellSingleQuoteEscape(pendingPrompt)}'${resumeFlag} --verbose --output-format stream-json --include-partial-messages\n`;
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        if (!line || line.length === 0) return {};

        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            console.log("[AI] ClaudeCode: could not parse line: ", e);
            return {};
        }

        // Present on nearly every line. Always take the freshest value Claude
        // Code reports, rather than only what we passed via --resume - this
        // is also how a brand-new session (no --resume on this turn) ends up
        // with a claudeSessionId ready for the *next* turn to resume.
        if (event.session_id) {
            claudeSessionId = event.session_id;
        }

        switch (event.type) {
        case "stream_event": {
            // --include-partial-messages: incremental Anthropic-style content_block_delta events
            const delta = event.event?.delta;
            if (delta?.type === "text_delta" && delta.text) {
                message.content += delta.text;
                message.rawContent += delta.text;
            }
            return {};
        }
        case "assistant":
            // Deliberately ignored: with --include-partial-messages, this
            // event is a full recap of text already streamed via
            // "stream_event"/content_block_delta above (confirmed in the
            // captured trace - identical text, delta-by-delta). Appending it
            // here would duplicate every response.
            return {};
        case "result": {
            if (event.is_error) {
                const errorMsg = `**Error**: ${event.result ?? "claude exited with an error"}`;
                message.content += errorMsg;
                message.rawContent += errorMsg;
            }
            return {
                finished: true,
                tokenUsage: event.usage ? {
                    input: event.usage.input_tokens ?? -1,
                    output: event.usage.output_tokens ?? -1,
                    total: (event.usage.input_tokens ?? 0) + (event.usage.output_tokens ?? 0),
                } : undefined,
            };
        }
        default:
            return {};
        }
    }

    function onRequestFinished(message: AiMessageData): var {
        // Belt-and-braces: if the process exited without a "result" event
        // (e.g. `claude` crashed or was killed), still mark the turn done.
        if (!message.done) return { finished: true };
        return {};
    }

    function reset() {
        // Per-turn scratch only. claudeSessionId deliberately survives this -
        // see the comment on its declaration above.
        pendingPrompt = "";
        pendingResumeSessionId = "";
    }
}

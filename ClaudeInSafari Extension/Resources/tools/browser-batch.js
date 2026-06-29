/**
 * browser_batch — execute a sequence of browser tool calls in one round trip.
 * See Spec 033 (browser-batch).
 *
 * Sub-actions run SEQUENTIALLY and the batch STOPS on the first error. Outputs
 * are concatenated (interleaved) into a single MCP content array, each preceded
 * by a "[i/N] <tool>" marker. Each sub-action is dispatched through
 * globalThis.executeTool — the same entry point background.js uses for a normal
 * single tool call — so per-tool behavior is identical to calling it standalone.
 *
 * MVP scope (Safari): only extension-handled tools are supported. The tools
 * below are handled NATIVELY in the Swift ToolRouter before/without forwarding
 * to the extension, so they cannot run inside an extension-side batch. They are
 * rejected during validation with a message directing the caller to invoke them
 * standalone. Nesting browser_batch is also not allowed. See Spec 033.
 */

"use strict";

// Tools handled natively in the Swift ToolRouter (not registered, or requiring
// Swift-side arg enrichment) — unsupported inside an extension-side batch.
const NATIVE_ONLY_TOOLS = new Set(["file_upload", "upload_image", "gif_creator"]);
// computer actions captured natively via ScreenCaptureKit.
const NATIVE_COMPUTER_ACTIONS = new Set(["screenshot", "zoom"]);

/**
 * Validate the entire batch before executing anything, so a statically-invalid
 * batch never runs a partial prefix of actions.
 * @param {Array<{name:string, input?:object}>} actions
 * @throws {Error} on an empty/malformed batch or an unsupported (native) tool.
 */
function validateBatch(actions) {
    if (!Array.isArray(actions) || actions.length === 0) {
        throw new Error("browser_batch requires a non-empty 'actions' array");
    }
    actions.forEach((action, i) => {
        const n = i + 1;
        if (!action || typeof action !== "object" || typeof action.name !== "string") {
            throw new Error(
                `browser_batch action ${n} is malformed: each action must be { name, input }`
            );
        }
        const name = action.name;
        if (name === "browser_batch") {
            throw new Error(`browser_batch cannot be nested (action ${n})`);
        }
        if (NATIVE_ONLY_TOOLS.has(name)) {
            throw new Error(
                `browser_batch does not support '${name}' (action ${n}) — it is handled natively. ` +
                `Call ${name} as a standalone tool instead.`
            );
        }
        if (name === "computer") {
            const act = action.input && action.input.action;
            if (NATIVE_COMPUTER_ACTIONS.has(act)) {
                throw new Error(
                    `browser_batch does not support computer '${act}' (action ${n}) — screenshots and ` +
                    `zoom are captured natively. Call computer '${act}' as a standalone tool instead.`
                );
            }
        }
    });
}

/**
 * Extract a human-readable message from an executeTool error envelope.
 * @param {{error?:{content?:Array<{text?:string}>}}} outcome
 * @returns {string}
 */
function errorText(outcome) {
    const blocks = outcome && outcome.error && outcome.error.content;
    if (Array.isArray(blocks)) {
        const joined = blocks.map((b) => b && b.text).filter(Boolean).join(" ");
        if (joined) return joined;
    }
    return "unknown error";
}

/**
 * @param {{actions: Array<{name:string, input?:object}>}} args
 * @param {object} [context] — forwarded verbatim to each sub-action.
 * @returns {Promise<{content: Array<object>}>} aggregated, interleaved content.
 */
async function handleBrowserBatch(args, context) {
    const actions = args && args.actions;
    validateBatch(actions);

    const content = [];
    const total = actions.length;
    let completed = 0;

    for (let i = 0; i < total; i++) {
        const { name, input } = actions[i];
        content.push({ type: "text", text: `[${i + 1}/${total}] ${name}` });

        const outcome = await globalThis.executeTool(name, input || {}, context);

        if (outcome && outcome.result && Array.isArray(outcome.result.content)) {
            content.push(...outcome.result.content);
            completed++;
        } else {
            // Error envelope (handler threw, or unknown tool). Stop the batch but
            // keep everything produced so far so prior outputs aren't lost.
            content.push({
                type: "text",
                text:
                    `ERROR: action ${i + 1}/${total} (${name}) failed: ${errorText(outcome)}\n` +
                    `Batch stopped — ${completed} of ${total} action(s) completed.`,
            });
            return { content };
        }
    }

    content.push({
        type: "text",
        text: `Batch complete: ${completed}/${total} action(s) succeeded.`,
    });
    return { content };
}

registerTool("browser_batch", handleBrowserBatch);

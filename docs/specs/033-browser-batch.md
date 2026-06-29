# Spec 033 — browser_batch

## Overview

`browser_batch` executes a sequence of browser tool calls in a single MCP round
trip. Each item is `{ name, input }`, where `input` is exactly what you would
pass to that tool standalone. Actions execute **sequentially** and the batch
**stops on the first error**. Outputs are concatenated (interleaved) into one
MCP content array, each preceded by a `[i/N] <tool>` marker.

It is a port of the Claude in Chrome `browser_batch` tool, scoped to what the
Safari architecture can support extension-side (see **Unsupported tools**).

## Scope

- Background: `ClaudeInSafari Extension/Resources/tools/browser-batch.js`
- Tool name: `"browser_batch"`
- Runs **in the extension background script**, dispatching each sub-action via
  `globalThis.executeTool(name, input, context)` — the same entry point
  `background.js` uses for a normal single tool call.
- MCP tool definition added to `ToolRouter.swift` `toolDefinitions`, and
  `"browser_batch"` added to `ToolRouter.executeScriptTools` so Safari is
  brought frontmost before the batch is forwarded (its sub-actions use
  `executeScript`, which fails silently when Safari is in the background).

## Arguments

```ts
{
  actions: Array<{
    name: string;     // tool name, e.g. "navigate", "find", "computer"
    input?: object;   // same shape you'd pass that tool standalone
  }>;
}
```

## Behavior

1. **Validate the whole batch up front** (before executing anything):
   - `actions` must be a non-empty array → else throw.
   - Each item must be an object with a string `name` → else throw
     (`action <i> is malformed`).
   - `name === "browser_batch"` → throw (no nesting).
   - An **unsupported (native) tool** → throw, naming the tool and the index
     (nothing is executed; see below).
2. **Execute sequentially.** For each action, push a `[i/N] <name>` text marker,
   then `await globalThis.executeTool(name, input || {}, context)`.
   - Success (`{ result: { content } }`) → append its content blocks; continue.
   - Error (`{ error: { content } }`, e.g. the handler threw or the tool is
     unknown) → append an `ERROR: action i/N (<name>) failed: …` block noting how
     many actions completed, then **stop** (remaining actions are not run).
3. **Return** the aggregated content array (success-shape). Prior successful
   outputs are preserved even when a later action fails, matching Chrome's
   "interleaved outputs, stop on first error" contract. A fully-successful batch
   appends a `Batch complete: N/N` summary.

Returning the aggregated content (rather than throwing) on a mid-batch error is
deliberate: it preserves the text output of the steps that did run, which is the
whole point of batching. The failure is made explicit in the content text.

## Unsupported tools (Safari MVP)

These are handled **natively in the Swift `ToolRouter`** before/without
forwarding to the extension, so they cannot run inside an extension-side batch.
They are rejected during validation with a message directing the caller to
invoke them standalone:

- `file_upload` — Swift reads the files and enriches the args with base64.
- `upload_image` — Swift attaches the captured image bytes by `imageId`.
- `gif_creator` — fully native; not registered in the extension.
- `computer` with `action` of `screenshot` or `zoom` — captured natively via
  ScreenCaptureKit.

All other tools (`navigate`, `find`, `read_page`, `form_input`,
`get_page_text`, `javascript_tool`, `read_console_messages`,
`read_network_requests`, `computer` clicks/type/scroll/key/hover/drag,
`tabs_context_mcp`, `tabs_create_mcp`) are supported.

> A faithful port that also batches native steps would require refactoring
> `ToolRouter`'s response-delivery path to aggregate results Swift-side. That is
> deferred; this MVP covers the common no-screenshot sequences.

## Return Value (example)

```
[1/3] navigate
Navigated to https://example.com
[2/3] find
Found 1 element: ref_2 (link) "More information"
[3/3] computer
Clicked ref_2
Batch complete: 3/3 action(s) succeeded.
```

On a mid-batch failure:

```
[1/2] navigate
Navigated to https://example.com
[2/2] form_input
ERROR: action 2/2 (form_input) failed: Tab not found: 7
Batch stopped — 1 of 2 action(s) completed.
```

## Out of Scope

- Nesting `browser_batch` inside itself.
- Parallel execution (actions are strictly sequential).
- Per-action permission prompts beyond what each sub-tool already enforces.
- Batching native tools (deferred — would need a Swift-side response refactor).

# Spec 032 — tabs_close_mcp

## Overview

`tabs_close_mcp` closes a tab that belongs to the current MCP tab group, by its
**virtual tab ID** (the `Tab N` value shown by `tabs_context_mcp`). It is the
lifecycle counterpart to `tabs_create_mcp` and a port of the Claude in Chrome
tool of the same name.

Only tabs in the session's virtual group are closable. Closing a tab that is not
tracked by the group is rejected — the tool never closes arbitrary Safari tabs
the user opened themselves.

## Scope

- Background: `ClaudeInSafari Extension/Resources/tools/tabs-manager.js`
  (added alongside `tabs_context_mcp` / `tabs_create_mcp` — it requires the
  module-private `withTabGroupLock` and the `__claudeTabGroups` state shape,
  which are not exported via `globalThis`).
- Tool name: `"tabs_close_mcp"`
- No content script injection required (does not use `executeScript`, so it does
  not require Safari to be frontmost).
- MCP tool definition added to `ToolRouter.swift` `toolDefinitions`.

## Arguments

```ts
{
  tabId: number;  // Virtual tab ID from tabs_context_mcp. Required.
}
```

Unlike page-acting tools, `tabId` has **no active-tab fallback** — a close
operation must always name an explicit target. A missing, null, or non-numeric
`tabId` is an error.

## Behavior

All state access runs inside `withTabGroupLock` so the find → close → delete
sequence is atomic with respect to concurrent `tabs_create_mcp`,
`tabs_context_mcp`, `resolveTab`, and `pruneStaleGroups` calls. The lock is held
across the `browser.tabs.remove` IPC call, matching the existing precedent in
`tabs_create_mcp` (which holds the lock across `browser.tabs.create`).

1. **Validate input.** If `tabId` is missing/null or not a number → throw
   `"tabs_close_mcp requires a numeric 'tabId' (the virtual tab ID from tabs_context_mcp)"`.
2. **Locate the entry.** Search every group for `group.tabs[tabId]`.
   - Not found → throw
     `"Tab <tabId> is not in the MCP tab group. Use tabs_context_mcp to list valid tab IDs."`
3. **Close the real tab.** Call `browser.tabs.remove(entry.realTabId)`.
   - Rejection matching `TAB_GONE_PATTERN` ("no tab with id" / "invalid tab") →
     the tab is already gone. This is **not** an error: fall through and remove
     the now-orphaned virtual entry as cleanup.
   - Any other (transient) rejection → do **not** delete the entry; rethrow with
     context so a momentarily-unreachable tab is not silently dropped from the
     group.
4. **Delete the virtual entry.** Remove `group.tabs[tabId]`.
5. **Cascade empty group.** If the group has no remaining tabs, delete the group
   (mirrors `applyStaleRemovals` and Chrome's "group auto-removed when its last
   tab closes" behavior).
6. **Persist** the mutated state (the non-skipWrite return triggers `writeState`).

## Return Value

A confirmation string, e.g.:

```
Closed Tab 2 (Group 1). 1 tab(s) remain in the group.
```

When the closed tab was the last in its group:

```
Closed Tab 2. The MCP tab group is now empty and has been removed.
```

When the real tab was already gone (cleanup path):

```
Tab 2 was already closed; removed its stale entry from the MCP tab group.
```

## Edge Cases

| Case | Behavior |
|---|---|
| `tabId` missing / null / non-number | Throw input-validation error |
| `tabId` not tracked by any group | Throw "not in the MCP tab group" |
| Real tab already closed (`TAB_GONE_PATTERN`) | Remove stale entry, return cleanup message (success) |
| `browser.tabs.remove` transient failure | Preserve entry, rethrow with context |
| Closing the last tab in a group | Delete the group |
| Already-stale entry (`isStale: true`) | Still closable — `remove` likely hits the gone path, entry removed |

## Out of Scope

- Closing tabs outside the MCP group (never permitted).
- Bulk close / close-by-pattern (single `tabId` per call, matching Chrome).

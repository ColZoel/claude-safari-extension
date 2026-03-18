# Claude in Safari

A macOS Safari Web Extension that brings the [Claude in Chrome](https://claude.ai) browser automation features to Safari. It lets Claude Code CLI control Safari via the Model Context Protocol (MCP) — reading pages, clicking elements, filling forms, taking screenshots, and more.

## How It Works

```
Claude Code CLI
    ↕  Unix domain socket  (newline-delimited JSON)
    ↕  /tmp/claude-mcp-browser-bridge-<username>/<pid>.sock
Native Swift App  (MCP server · screenshots · window management · file I/O)
    ↕  browser.runtime.sendNativeMessage()
Safari Web Extension  (background script · content scripts · tool handlers)
    ↕  browser.scripting.executeScript
Web Pages
```

The native app exposes the same socket path and protocol as the Chrome extension's native messaging host, so Claude Code works with it out of the box.

## Requirements

- macOS 13 Ventura or later
- Safari 16.4 or later
- Xcode 16 or later (to build)

## Building

```sh
git clone https://github.com/chriscantu/claude-safari-extension.git
cd claude-safari-extension

# Build, launch, and health-check in one step
make dev

# Or build without launching
make build
```

## Running Tests

```sh
# JavaScript tests (852 tests)
npm test

# Swift tests (224 tests)
make test-swift
```

## Setup

1. Run `make dev` — builds the app, launches it, and creates a stable socket symlink.
2. The onboarding wizard guides you through three permissions:
   - **Safari extension** — enable in Safari → Settings → Extensions
   - **Screen Recording** — for screenshots (ScreenCaptureKit)
   - **Accessibility** — for window resize (AppleScript)
3. The menu bar icon shows connection status (green = connected, yellow = needs attention).

The MCP socket server starts automatically on launch.

## Project Layout

See [STRUCTURE.md](STRUCTURE.md) for the full canonical directory layout.

```
ClaudeInSafari/            # macOS app — MCP server, screenshots, AppleScript
ClaudeInSafari Extension/  # Safari Web Extension — tool handlers, content scripts
Shared/                    # Constants shared between both targets
docs/specs/                # Feature specifications (written before code)
Tests/                     # Swift unit tests
```

## Development Workflow

This project follows the principles in [PRINCIPLES.md](PRINCIPLES.md):

1. **Spec first** — write a spec in `docs/specs/` before any implementation.
2. **Test first** — write a passing test before marking a feature complete.
3. **Iterative commits** — commit each small batch of working code.
4. **Structure compliance** — all files must be placed per `STRUCTURE.md`.

### Adding a New Tool

1. Write a spec: `docs/specs/<NNN>-<tool-name>.md`
2. Write tests: `Tests/Swift/` or `Tests/JS/`
3. Implement in the matching file from `STRUCTURE.md`
4. Register the tool in `tool-registry.js`
5. Run tests, commit

## Features

### MCP Tools (20 tools — all complete)

| Tool | Description |
|------|-------------|
| `read_page` | Accessibility tree snapshot |
| `navigate` | URL navigation and history traversal |
| `find` | Find elements by natural language |
| `form_input` | Fill inputs, checkboxes, selects |
| `get_page_text` | Extract article/main text |
| `javascript_tool` | Run JS in page context (sync + async) |
| `read_console_messages` | Captured console logs |
| `read_network_requests` | Captured network log |
| `computer` | Mouse, keyboard, scroll, screenshot (ScreenCaptureKit) |
| `resize_window` | AppleScript window management |
| `tabs_context_mcp` / `tabs_create_mcp` | Tab listing and creation |
| `gif_creator` | Screen recording to GIF |
| `upload_image` | Inject image into page |
| `file_upload` | Inject files into file inputs |
| `agent_visual_indicator` | Show/hide/stop agent activity indicator |

### Infrastructure

| Component | Description |
|-----------|-------------|
| MCP socket server | GCD-based Unix domain socket with newline-delimited JSON framing |
| Native ↔ extension bridge | `browser.runtime.sendNativeMessage()` message routing |
| Tool registry | Centralized tool registration and dispatch |
| Tabs manager | Virtual tab groups via `browser.storage.session` |
| Onboarding wizard | First-run setup for Safari extension, Screen Recording, and Accessibility permissions |
| Menu bar presence | Status icon with connection state and permission monitoring |
| macOS notifications | Native Notification Center integration for agent activity |

## License

MIT

# Claude in Safari

<!-- TODO: Add screenshot or demo GIF here -->

A macOS Safari Web Extension that brings [Claude Code's](https://claude.ai) browser automation to Safari. Read pages, click elements, fill forms, take screenshots, and more — all controlled from the Claude Code CLI.

## Install

1. Download **ClaudeInSafari.dmg** from the [latest release](https://github.com/chriscantu/claude-safari-extension/releases/latest)
2. Open the DMG and drag **Claude in Safari** to Applications
3. Launch the app — the onboarding wizard walks you through:
   - Enabling the Safari extension (Safari → Settings → Extensions)
   - Granting Screen Recording permission (for screenshots)
4. The menu bar icon shows connection status

The MCP server starts automatically on launch. Claude Code detects it and gains Safari control tools.

## Requirements

- macOS 13 Ventura or later
- Safari 16.4 or later
- [Claude Code CLI](https://claude.ai)

## Tools

| Tool | What it does |
|------|-------------|
| `read_page` | Accessibility tree snapshot of the current page |
| `navigate` | Go to a URL or traverse browser history |
| `find` | Find elements by natural language description |
| `form_input` | Fill inputs, checkboxes, selects, and other form controls |
| `get_page_text` | Extract the main text content from a page |
| `javascript_tool` | Run JavaScript in the page context (sync + async) |
| `computer` | Mouse clicks, keyboard input, scroll, and screenshots |
| `read_console_messages` | Read captured browser console logs |
| `read_network_requests` | Read captured network request log |
| `tabs_context_mcp` / `tabs_create_mcp` | List open tabs or create new ones |
| `gif_creator` | Record a screen region to GIF |
| `upload_image` | Inject an image into the page |
| `file_upload` | Attach files to file input elements |
| `agent_visual_indicator` | Show/hide agent activity indicator |

## How It Works

```
Claude Code CLI
    ↕  Unix domain socket (newline-delimited JSON)
Native Swift App  (MCP server · screenshots · file I/O)
    ↕  browser.runtime.sendNativeMessage()
Safari Web Extension  (background page · content scripts · tool handlers)
    ↕  browser.scripting.executeScript
Web Pages
```

## Setup

1. Install the DMG or download from the Mac App Store
2. Launch Claude in Safari and complete the onboarding steps
3. When prompted, install the Claude integration:
   - **DMG**: Click "Install" — automatic
   - **App Store**: Click "Install", paste in Terminal, press Enter
4. Restart Claude Code or Claude Desktop

Manual install (if needed):
```bash
"/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge" --install --verify
```

## Building from Source

See [CONTRIBUTING.md](CONTRIBUTING.md) for full development setup, testing, and contribution guidelines.

```sh
git clone https://github.com/chriscantu/claude-safari-extension.git
cd claude-safari-extension
make dev
```

## License

MIT

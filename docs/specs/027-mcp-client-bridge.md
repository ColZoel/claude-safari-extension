# Spec 027 — MCP Client Bridge & Auto-Install

## Goal
Enable Claude Code CLI and Claude Desktop to connect to the running Claude in Safari app by shipping a compiled stdio-to-socket bridge binary inside the app bundle, with an `--install` flag that writes MCP configuration to both clients. Maximize UX by auto-installing for DMG users and providing a guided two-step flow for App Store users.

## Motivation
The native app creates an MCP socket server in the App Group container (`~/Library/Group Containers/group.com.chriscantu.claudeinsafari/sockets/<pid>.sock`). During development, the Makefile `run` target creates a symlink at `/tmp/claude-mcp-browser-bridge-<username>/dev.sock` that test scripts use. But when users install the DMG, no symlink is created and no MCP client configuration exists — Claude Code and Claude Desktop have zero knowledge of the socket. This is a complete connection failure for all production users.

## Decisions
- **Swift compiled binary, not Python.** macOS no longer ships Python (removed in 12.3). A native binary has zero external dependencies and gets code-signed + notarized with the app.
- **Binary lives inside the app bundle** at `Contents/MacOS/safari-mcp-bridge`. MCP configs reference it by absolute path (auto-detected from the binary's own bundle location).
- **Dual-path UX based on sandbox detection.** DMG builds are unsandboxed and can auto-install config directly from the app. App Store builds are sandboxed and use a "Copy command + open Terminal" flow. The app detects which path to take at runtime.
- **Install logic lives in the bridge binary.** Whether invoked directly by the unsandboxed app (`Process`) or by the user in Terminal, the same `--install` code runs. Single source of truth.
- **Merge, don't overwrite.** When writing MCP config, read the existing file, parse JSON, insert/update only the `claude-in-safari` key under `mcpServers`, and write back. Never clobber other MCP servers the user has configured.
- **Graceful degradation.** If the config file doesn't exist, create it. If the directory doesn't exist, create it. If the file has invalid JSON, warn the user rather than overwriting.
- **Bridge discovers socket automatically.** It scans the App Group container socket directory for the newest `.sock` file. No hardcoded PID.
- **Install success signaled via App Group marker.** The bridge writes a marker file to the App Group container after successful install. The sandboxed app can read this to update its UI with confirmation — no entitlements needed.

## Scope

### 1. New Xcode Target: `safari-mcp-bridge`
**Type:** Command Line Tool (Swift)
**Product location:** Built into `Contents/MacOS/safari-mcp-bridge` inside the app bundle.
**No sandbox entitlements.** This binary runs unsandboxed as a subprocess of Claude Code/Desktop, the user's shell, or (for DMG builds) the unsandboxed main app.

#### A. Bridge mode (default — no flags)
Stdio-to-socket relay for MCP communication:

1. Resolve socket directory: `~/Library/Group Containers/group.com.chriscantu.claudeinsafari/sockets/`
2. Find the newest `*.sock` file (by mtime). If none found, print a JSON-RPC error to stderr and exit with code 1.
3. Connect to the Unix domain socket.
4. Relay: read lines from stdin → write to socket; read lines from socket → write to stdout.
5. On EOF from either side (stdin closed, socket closed), close the other side and exit 0.
6. Flush stdout after every line (critical — MCP clients expect unbuffered output).

Error cases:
- No socket found → stderr: `{"error": "Claude in Safari is not running. Launch the app and try again."}`, exit 1
- Socket connection refused → stderr: `{"error": "Socket exists but connection failed. Restart Claude in Safari."}`, exit 1
- Socket disconnects mid-session → close stdin/stdout, exit 0 (Claude Code will retry)

#### B. `--install` flag
Writes MCP server config to detected Claude clients:

| Client | Config path | Key |
|--------|-------------|-----|
| Claude Code CLI | `~/.claude.json` | `mcpServers.claude-in-safari` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers.claude-in-safari` |

Config payload (auto-detects bridge path from its own executable location):
```json
{
  "command": "/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge",
  "args": []
}
```

Algorithm:
1. Resolve the bridge binary's own absolute path via `CommandLine.arguments[0]` or `ProcessInfo.processInfo.arguments[0]` (handles symlinks).
2. Detect which clients are installed:
   - Claude Code: check if `~/.claude/` directory exists
   - Claude Desktop: check if `~/Library/Application Support/Claude/` directory exists
3. For each detected client's config file:
   a. Read existing file (or start with empty `{}`).
   b. Parse as JSON dictionary. If parse fails, print warning and skip that file.
   c. Get or create `mcpServers` dictionary.
   d. Set `mcpServers["claude-in-safari"]` to `{"command": "<bridge-path>", "args": []}`.
   e. Serialize with sorted keys and 2-space indent.
   f. Write atomically to the file path.
   g. Create parent directories if needed.
4. Write a marker file to the App Group container: `~/Library/Group Containers/group.com.chriscantu.claudeinsafari/mcp_config_installed.json` containing `{"installed_at": "<ISO8601>", "bridge_path": "<path>", "clients": ["claude-code", "claude-desktop"]}`.
5. Print a summary to stdout:
   ```
   ✓ Claude Code CLI  — configured (~/.claude.json)
   ✓ Claude Desktop   — configured
   ✗ Claude Desktop   — not installed, skipped

   Done! Restart Claude Code or Claude Desktop to connect.
   ```

#### C. `--install --verify`
After writing config, also tests the connection:
1. Check if a socket exists in the App Group container.
2. If yes, connect and send an MCP `initialize` handshake + `tools/list` request.
3. Print the number of tools discovered:
   ```
   ✓ Connection verified — 19 tools available
   ```
4. If the socket doesn't exist or connection fails, print a warning (config was still installed successfully):
   ```
   ⚠ Config installed, but Claude in Safari is not running. Launch the app to activate.
   ```

#### D. `--uninstall` flag
Removes the `claude-in-safari` key from both config files. Same merge logic — read, parse, delete key, write back. Removes the App Group marker file.

#### E. `--status` flag
Prints diagnostic info:
- Bridge binary path
- Socket directory path
- Socket exists? (which PID?)
- Config installed in Claude Code? (path + bridge path in config)
- Config installed in Claude Desktop? (path + bridge path in config)
- Config bridge path matches current binary path? (detects stale config after app move)

### 2. Sandbox Detection
**Where:** `AppDelegate.swift` or a shared utility

The app detects at runtime whether it's running inside the App Sandbox:
```swift
let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
```

This determines which install flow to use:

| Distribution | Sandboxed? | Install flow |
|-------------|------------|--------------|
| DMG | No | Auto-install: app launches bridge binary via `Process` with `--install --verify` |
| App Store | Yes | Guided: copy command + open Terminal |

### 3. App UI Integration — DMG Flow (Unsandboxed)
**Where:** Onboarding UI + `AppDelegate.swift`

When `isSandboxed == false`, the app can launch the bridge binary directly via `Process`:

**A. Onboarding (new final step — "Connect to Claude"):**
- Shows which clients are detected (Claude Code? Desktop? Both?)
- Single **"Install"** button
- On click: launches `Contents/MacOS/safari-mcp-bridge --install --verify` via `Process`, captures stdout
- Displays results inline (checkmarks per client, tool count from verify)
- Advances automatically on success

**B. Menu bar item:**
- "Install Claude Integration" — runs `--install --verify` via `Process`, shows result in an alert
- "Uninstall Claude Integration" — runs `--uninstall` via `Process`
- Both report success/failure via `NSAlert`

### 4. App UI Integration — App Store Flow (Sandboxed)
**Where:** Onboarding UI + `AppDelegate.swift`

When `isSandboxed == true`, the app cannot launch the bridge unsandboxed. Instead:

**A. Onboarding (new final step — "Connect to Claude"):**
- Explains what the install command does (one sentence)
- Single **"Install"** button that does TWO things simultaneously:
  1. Copies the install command to the clipboard via `NSPasteboard`:
     `"/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge" --install --verify`
     (uses the actual bundle path, not hardcoded `/Applications/`)
  2. Opens Terminal.app via `NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))`
- Shows instruction: **"Paste ⌘V and press Enter"**
- Polls the App Group marker file (`mcp_config_installed.json`) every 2 seconds
- When marker is detected, automatically shows success state with checkmarks and advances

**B. Menu bar item:**
- "Copy Install Command" — copies to clipboard, opens Terminal
- "Copy Uninstall Command" — copies uninstall command to clipboard, opens Terminal

### 5. Install Success Detection (Both Flows)
**Where:** Onboarding UI

The bridge binary writes `mcp_config_installed.json` to the App Group container on successful install. The onboarding screen:
1. Starts a 2-second polling timer when the "Connect to Claude" step is shown
2. Reads `~/Library/Group Containers/group.com.chriscantu.claudeinsafari/mcp_config_installed.json`
3. When found, parses the JSON to display which clients were configured
4. Shows green checkmarks and a "Continue" or auto-advance

This works for BOTH flows — DMG (instant, since `Process` completes synchronously) and App Store (detected within 2 seconds of the user running the command in Terminal).

### 6. Path Resilience
The bridge auto-detects its own path when `--install` is run, so the config always points to the correct location — even if the app is in `/Applications/`, `~/Applications/`, or a custom path.

If the user moves the app after installing, the config will point to the old path. Mitigations:
- `--status` detects path mismatch and reports it.
- On app launch, read the marker file from App Group container. If `bridge_path` doesn't match the current bundle's bridge path, show a notification suggesting re-install.
- The menu bar "Install" action lets users re-install with one click (DMG) or one copy-paste (App Store).
- The bridge binary prints a clear error if it can't find the socket, so the failure mode is diagnosable.

## App Store Compatibility
This design is fully App Store compatible:
- **Bridge binary:** Helper tools inside app bundles are standard practice (Docker, VS Code, Homebrew all do this). The binary has no sandbox entitlements — it runs as a child process of Claude Code/Desktop or the user's shell, not of the sandboxed app.
- **Config writing (App Store flow):** Done entirely by the unsandboxed bridge binary via `--install` in the user's Terminal session, never by the sandboxed main app.
- **Config writing (DMG flow):** The app is unsandboxed, so direct `Process` launch is allowed.
- **Clipboard access:** `NSPasteboard` is allowed under App Sandbox without additional entitlements.
- **Opening Terminal:** `NSWorkspace.shared.open` for system apps is allowed under App Sandbox.
- **App Group marker file:** Both the sandboxed app and unsandboxed bridge can read/write the App Group container.
- **No temporary exception entitlements** required.

## Safari Degradations
None — this feature is entirely native-side (Swift CLI + config files). No extension APIs involved.

## Test Plan
1. **Bridge relay test:** Mock a Unix domain socket server, launch `safari-mcp-bridge`, send MCP initialize handshake via stdin, verify response on stdout.
2. **Install test:** Run `--install` with temp `HOME`, verify JSON merge preserves existing keys, verify creation from scratch, verify invalid-JSON is skipped with warning. Verify marker file is written to App Group container.
3. **Install with verify test:** Run `--install --verify` with a mock socket server, verify tools/list handshake completes and tool count is printed.
4. **Client detection test:** Verify `--install` skips Claude Desktop when its directory doesn't exist, and skips Claude Code when `~/.claude/` doesn't exist.
5. **Uninstall test:** Run `--uninstall`, verify key is removed, verify other keys preserved, verify marker file removed.
6. **Status test:** Run `--status` with and without socket, with and without config installed, with path mismatch.
7. **Path detection test:** Run `--install` from different app locations, verify config points to correct path each time.
8. **Sandbox detection test:** Verify `isSandboxed` returns correct value for both build types.
9. **Integration test (DMG):** With app running unsandboxed, click "Install" in onboarding, verify config is written and connection verified automatically.
10. **Integration test (App Store):** With app running sandboxed, click "Install", verify command is copied + Terminal opens, run command in Terminal, verify onboarding detects marker and shows success.
11. **Path mismatch test:** Install config, move app to different location, launch, verify app detects mismatch and prompts re-install.

## Files

### New
| File | Purpose |
|------|---------|
| `safari-mcp-bridge/main.swift` | CLI bridge binary — relay, install, uninstall, status, verify |

### Modified
| File | Change |
|------|--------|
| `ClaudeInSafari.xcodeproj` | Add `safari-mcp-bridge` CLI target, embed in app bundle |
| `ClaudeInSafari/App/AppDelegate.swift` | Menu bar "Claude Integration" items, sandbox detection |
| Onboarding UI files | New "Connect to Claude" step with dual-path flow |
| `Shared/Constants.swift` | Add `mcpConfigInstalledURL` for App Group marker file path |
| `STRUCTURE.md` | Document new target and files |
| `README.md` | Update setup instructions with install command |

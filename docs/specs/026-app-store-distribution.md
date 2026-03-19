# Spec 026 — App Store Distribution

## Goal
Make Claude in Safari distributable via the Mac App Store and as a notarized DMG, by removing App Store-incompatible entitlements, migrating `file_upload` to a sandbox-compatible native bridge, and building a signing/packaging pipeline.

## Motivation
All 20 MCP tools are implemented and production-hardened (Specs 022–025). The app currently ships as an unsigned `.zip` via GitHub Releases, requiring `xattr -cr` to bypass Gatekeeper. Two temporary exception entitlements (`apple-events` for `resize_window`, `files.absolute-path.read-only` for `file_upload`) block App Store submission. Additionally, the main app is not sandboxed — App Store requires `com.apple.security.app-sandbox` on both the app and extension targets. This spec resolves all blockers, adds a proper DMG installer, and prepares the CI/CD pipeline for signed distribution.

## Decisions
- **App Store is the primary target.** A notarized DMG is a parallel distribution channel using the same build.
- **`resize_window` is removed** (uses AppleScript temporary exception). Deferred to future roadmap — will explore `browser.windows.update()` or other App Store-compatible approaches.
- **`file_upload` is migrated** to read files in the native Swift app (before sandbox enforcement) and pass data to the extension via the existing native messaging bridge. Uses `com.apple.security.files.user-selected.read-write` entitlement with security-scoped bookmarks for sandbox-compatible file access.
- **App Sandbox is added** to the main app target (extension already has it).
- **Branding is configurable** — display name, accent color, and icon are centralized constants so a rebrand is a single-PR change (pending Anthropic brand permission).
- **Sparkle auto-updates deferred to v1.1.** A "Check for Updates" menu item ships in v1.0.
- **Apple Developer Program enrollment is a prerequisite**, not engineering work. The pipeline is gated on secrets — unsigned builds work without enrollment.
- **Bundle ID stays `com.chriscantu.claudeinsafari`** — personal project, personal identity.

## Scope

### 1. Remove `resize_window` Tool
**Where:** `ClaudeInSafari/MCP/ToolRouter.swift`, `ClaudeInSafari/Services/AppleScriptBridge.swift`, `ClaudeInSafari/ClaudeInSafari.entitlements`, `ClaudeInSafari/Info.plist`, onboarding UI, tests

The `resize_window` tool is implemented entirely in Swift (no JS file exists). Remove all touchpoints:

- **Keep** `ClaudeInSafari/Services/AppleScriptBridge.swift` in the project (preserved for future re-enablement)
- **Keep** `Tests/Swift/AppleScriptBridgeTests.swift` (tests validation logic, compiles without entitlement)
- Disconnect `resize_window` from `ToolRouter.swift`: remove case dispatch, remove tool definition from schema, remove `AppleScriptBridge` property instantiation
- Remove `com.apple.security.temporary-exception.apple-events` from `ClaudeInSafari/ClaudeInSafari.entitlements`
- Remove `NSAppleEventsUsageDescription` from `ClaudeInSafari/Info.plist`
- Remove Accessibility permission from onboarding:
  - Remove `.accessibility` case from `OnboardingStep` enum in `PermissionMonitor.swift`
  - Remove `accessibility` field from `PermissionStatus` struct
  - Update `allGranted` and `firstIncompleteStep` to exclude accessibility
  - Remove `isAccessibilityGranted()`, `registerAccessibility()`, and `requestAccessibility()` from `PermissionChecking` protocol
  - Remove Accessibility screen from `OnboardingWindowController.swift`
  - Onboarding becomes 4 screens: Welcome → Safari Extension → Screen Recording → Done
- Remove `resize_window` from MCP tool schema in `ToolRouter.swift` (tool should no longer be advertised to clients)
- Update `STRUCTURE.md` to mark `AppleScriptBridge.swift` as disabled and update onboarding comment from "5-screen setup wizard: Welcome -> 3 permission steps -> Done" to "4-screen setup wizard: Welcome -> 2 permission steps -> Done"
- Update `CLAUDE.md` to remove AppleScript references from Key Technical Decisions

### 2. Add App Sandbox to Main App
**Where:** `ClaudeInSafari/ClaudeInSafari.entitlements`

The App Store requires `com.apple.security.app-sandbox` on both the app and extension. The extension already has it (`ClaudeInSafari Extension/ClaudeInSafariExtension.entitlements` — sandbox + app group only, no changes needed); the main app does not.

Add to `ClaudeInSafari/ClaudeInSafari.entitlements`:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

Rationale for each:
- `app-sandbox` — required for App Store
- `network.server` — the app hosts a Unix domain socket (MCP server)
- `network.client` — needed for outbound connections (update checks)
- `files.user-selected.read-write` — needed for `file_upload` (see §3)

**Impact on socket path:** Under sandbox, the app cannot create sockets in `/tmp/`. The socket path must move to the App Group container: `~/Library/Group Containers/group.com.chriscantu.claudeinsafari/<pid>.sock`. Update `MCPSocketServer.swift` and `Shared/Constants.swift` accordingly. This is a **breaking change** for CLI integration — the CLI must be updated to look for the socket in the new location, or a symlink in `/tmp/` must be maintained (investigate whether sandbox allows creating symlinks in `/tmp/`).

**Fallback:** If the sandbox socket restriction blocks CLI integration, document this as a known issue and investigate:
1. A non-sandboxed XPC helper that manages the socket in `/tmp/`
2. An App Group-based discovery mechanism
3. Requesting a `com.apple.security.temporary-exception.files.absolute-path.read-write` for `/tmp/` only (narrower than current exception, may be accepted)

### 3. Migrate `file_upload` to Native Bridge
**Where:** `ToolRouter.swift`, `file-upload.js`, `ClaudeInSafari/Services/FileService.swift`

Current flow:
```
CLI → socket → ToolRouter → extension (file-upload.js reads file via entitlement) → page
```

New flow:
```
CLI → socket → ToolRouter (reads file bytes in Swift via FileService) → base64 data in native message → extension (file-upload.js receives data, injects into page)
```

**Sandbox file access strategy:**
Under App Sandbox, `FileManager` cannot read arbitrary paths. The `com.apple.security.files.user-selected.read-write` entitlement only covers paths the user has selected via `NSOpenPanel`. Since `file_upload` receives paths from the CLI (not user-selected), we need one of:

1. **Preferred: Bookmark a broad directory at first launch.** During onboarding or first `file_upload` use, present an `NSOpenPanel` asking the user to grant access to their home directory (or `/`). Store a security-scoped bookmark. On subsequent file reads, resolve the bookmark to get access. This is a one-time UX step.
2. **Alternative: Per-file open panel.** On each `file_upload`, present an `NSOpenPanel` pre-seeded with the requested path. User confirms. Poor UX for automation.
3. **Fallback: If Apple rejects broad bookmarks**, restrict `file_upload` to files within the App Group container and document the limitation.

Implementation (using approach 1):
1. Add a `FileAccessManager` class that:
   - Stores security-scoped bookmarks in `UserDefaults` (or the App Group container)
   - On first `file_upload`, presents `NSOpenPanel` for the user to grant access to a directory
   - Resolves bookmarks with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
   - Caches resolved bookmarks for the session
2. In `ToolRouter.swift`, when handling `file_upload`:
   - Call `FileAccessManager` to get read access to the file path
   - Read the file via `FileService` (existing, has `maxFileSizeBytes = 100 MB`)
   - Base64-encode the contents
   - Include the base64 data and filename in the message payload to the extension
3. In `file-upload.js`:
   - Instead of reading the file from disk, receive base64 data from the native message
   - Decode base64 → `Blob` → `File` object
   - Inject into the page's file input (existing logic)
4. Remove `com.apple.security.temporary-exception.files.absolute-path.read-only` from `ClaudeInSafari/ClaudeInSafari.entitlements`

**File size limit:** Keep existing `FileService.maxFileSizeBytes` of 100 MB. Base64 overhead makes this ~133 MB in transit, which is acceptable for native messaging.

### 4. Configurable Branding
**Where:** `Shared/Constants.swift`, `tools/constants.js`, `scripts/generate-app-icon.swift`, Info.plist files

Centralize brand-touchable values:

**Swift (`Shared/Constants.swift` — extend existing file):**
```swift
// MARK: - Branding
static let appDisplayName = "Claude in Safari"
static let brandColorHex = "#D97757"
```

**JavaScript (`tools/constants.js` — extend existing file):**
```javascript
const APP_DISPLAY_NAME = 'Claude in Safari';
```

**Icon script (`scripts/generate-app-icon.swift`):**
- Parameterize the fill color (currently hardcoded `#D97757`)
- Read from a constant or CLI argument

**Info.plist:**
- `CFBundleDisplayName` already set; ensure usage description strings reference the configurable name pattern rather than hardcoding it

**Touchpoints to centralize** (grep for "Claude in Safari" and "Claude"):
- `Shared/Constants.swift` — display name, color
- `tools/constants.js` — display name
- `scripts/generate-app-icon.swift` — icon color
- `ClaudeInSafari/Info.plist` — `CFBundleDisplayName`, usage descriptions
- `ClaudeInSafari Extension/Info.plist` — `CFBundleDisplayName`
- Menu bar title in `MenuBarController.swift` (if present)
- Onboarding window title/text in `OnboardingWindowController.swift`

**Scope boundary:** This is not a white-label system. It's centralizing touchpoints so a rebrand is a small, focused PR — not a grep-and-replace across dozens of files.

### 5. DMG Packaging
**Where:** `scripts/create-dmg.sh` (new, bash script), `Makefile`

Create a branded drag-to-Applications DMG:
- Background image: Claude orange gradient with app name and arrow (generated or static PNG)
- Window size: ~600×400
- App icon positioned left, Applications alias positioned right
- Volume name: "Claude in Safari <version>"

**Script:** `scripts/create-dmg.sh`
- Input: path to signed `.app` bundle
- Output: `ClaudeInSafari-<version>.dmg`
- Uses `create-dmg` CLI tool (Homebrew: `brew install create-dmg`) or `hdiutil` directly
- Bash script (shebang `#!/bin/bash`) — intentionally bash, not fish, for CI portability. Existing scripts in `scripts/` are Python/JS/Swift; these are the first shell scripts.

**Makefile target:**
```makefile
dmg: build
	scripts/create-dmg.sh $(BUILD_DIR)/ClaudeInSafari.app
```

### 6. CI/CD Pipeline Updates
**Where:** `.github/workflows/release.yml`

Update the existing release workflow:

**Signing (gated on `APPLE_CERTIFICATE` secret):**
1. Import Developer ID Application certificate from secrets
2. Sign the `.app` bundle with `codesign --deep --force --options runtime`
3. Sign the embedded extension

**Notarization (gated on `APPLE_ID` + `APP_PASSWORD` + `TEAM_ID` secrets):**
1. `xcrun notarytool submit` the signed `.app`
2. Wait for Apple's approval (~2-5 min)
3. `xcrun stapler staple` the approved `.app`

**DMG creation:**
1. Run `scripts/create-dmg.sh` on the stapled `.app`
2. Notarize and staple the DMG itself

**App Store upload (gated on `APP_STORE_CONNECT_KEY` secret):**
1. Archive with `ExportOptions.plist` (`method: app-store-connect`)
2. Upload via `xcodebuild -exportArchive` or Transporter

**Release artifacts:**
- `ClaudeInSafari-<version>.dmg` — primary download
- `ClaudeInSafari-<version>.zip` — for Sparkle compatibility (future)
- Remove prerelease flag for `v1.0.0+`
- Update release notes template (remove Gatekeeper bypass instructions when signed)

**Unsigned fallback:** When secrets are not configured, the workflow produces unsigned artifacts as it does today. This allows contributors to fork and build without Apple credentials.

### 7. Version Management
**Where:** `scripts/bump-version.sh` (new, bash script), Info.plist files

**Script:** `scripts/bump-version.sh <major|minor|patch>`
- Reads current version from `ClaudeInSafari/Info.plist`
- Bumps the specified component (semver)
- Increments `CFBundleVersion` (integer build number)
- Updates both `ClaudeInSafari/Info.plist` and `ClaudeInSafari Extension/Info.plist` in sync
- Outputs the new version string for use in CI

### 8. Menu Bar Additions
**Where:** `ClaudeInSafari/App/MenuBarController.swift` (or equivalent)

Add two menu items:
- **"Check for Updates"** — opens the GitHub Releases page (or App Store page once live) in the default browser via `NSWorkspace.shared.open(url)`
- **"About Claude in Safari"** — shows a standard `NSAlert` with app name (from `Constants.appDisplayName`), version, and a brief description

### 9. Onboarding Updates
**Where:** `ClaudeInSafari/App/OnboardingWindowController.swift`, `ClaudeInSafari/App/PermissionMonitor.swift`

- Remove the Accessibility permission screen
- Onboarding becomes 4 screens: Welcome → Safari Extension → Screen Recording → Done
- No new screen for Files & Folders — the security-scoped bookmark prompt (§3) is presented on first `file_upload` use, not during onboarding

## Files Modified

### Disabled (preserved for future re-enablement)
- `ClaudeInSafari/Services/AppleScriptBridge.swift` — disconnected from ToolRouter, not deleted
- `Tests/Swift/AppleScriptBridgeTests.swift` — still compiles and runs (tests validation logic)

### New
- `ClaudeInSafari/Services/FileAccessManager.swift` — security-scoped bookmark management
- `Tests/Swift/FileAccessManagerTests.swift`
- `scripts/create-dmg.sh`
- `scripts/bump-version.sh`
- DMG background image asset

### Modified
- `ClaudeInSafari/ClaudeInSafari.entitlements` — add sandbox, remove temporary exceptions
- `ClaudeInSafari/MCP/ToolRouter.swift` — remove `resize_window`, update `file_upload` to native bridge
- `ClaudeInSafari/Services/FileService.swift` — integrate with `FileAccessManager` for sandbox access
- `ClaudeInSafari Extension/Resources/tools/file-upload.js` — receive base64 data instead of reading files
- `ClaudeInSafari/App/PermissionMonitor.swift` — remove accessibility step
- `ClaudeInSafari/App/OnboardingWindowController.swift` — remove accessibility screen
- `ClaudeInSafari/App/MenuBarController.swift` — add "Check for Updates" and "About" items
- `ClaudeInSafari/MCP/MCPSocketServer.swift` — update socket path for sandbox
- `Shared/Constants.swift` — add branding constants, update socket path
- `ClaudeInSafari Extension/Resources/tools/constants.js` — add branding constant
- `scripts/generate-app-icon.swift` — parameterize color
- `ClaudeInSafari/Info.plist` — remove AppleEvents usage description
- `.github/workflows/release.yml` — signing, notarization, DMG, App Store upload
- `Makefile` — add `dmg` target
- `STRUCTURE.md` — mark `AppleScriptBridge.swift` as disabled, add new files, update onboarding screen count
- `CLAUDE.md` — remove AppleScript references, update Key Technical Decisions
- `Tests/Swift/ToolRouterTests.swift` — remove `resize_window` tests, add `file_upload` bridge tests
- `Tests/Swift/PermissionMonitorTests.swift` — remove accessibility-related test cases
- `Tests/Swift/OnboardingWindowControllerTests.swift` — remove accessibility screen tests

## Out of Scope
- Bundle ID changes (staying with `com.chriscantu.claudeinsafari`)
- Apple Developer Program enrollment (prerequisite, not engineering)
- Actual App Store review submission (manual step after pipeline is ready)
- Sparkle auto-updates (deferred to v1.1)
- `resize_window` restoration (future roadmap)
- Rebrand execution (depends on Anthropic permission; architecture supports it)

## Future Roadmap
- **v1.1:** Sparkle auto-updates
- **Future:** Restore `resize_window` via `browser.windows.update()` or other App Store-compatible API
- **If needed:** Rebrand (configurable constants make this a single PR)

## Testing
- Verify `file_upload` works end-to-end with native bridge (base64 round-trip, security-scoped bookmark)
- Verify `resize_window` tool is fully removed (no schema advertised, no code remaining)
- Verify `AppleScriptBridge.swift` and its tests still compile (preserved but disconnected from ToolRouter)
- Verify entitlements: `app-sandbox` present, no temporary exceptions
- Verify DMG mounts, drag-to-Applications works, app launches from `/Applications`
- Verify onboarding shows exactly 4 screens (Welcome → Extension → Screen Recording → Done)
- Verify unsigned build still works (CI without secrets)
- Verify "Check for Updates" and "About" menu items function
- Verify MCP socket works under sandbox (or document fallback)
- Run full existing test suite — no regressions (minus removed AppleScriptBridge tests)

## Risks
- **Socket path under sandbox:** Moving from `/tmp/` to App Group container is a breaking change for CLI integration. Mitigation: investigate symlink or XPC helper; document fallback options in §2.
- **Security-scoped bookmarks for broad directory access:** Apple may reject apps that request access to `/` or `$HOME` via `NSOpenPanel`. Mitigation: request the narrowest useful directory; fall back to per-file prompts or App Group-only access.
- **Branding / trademark:** "Claude" is Anthropic's trademark. Mitigation: reach out to Anthropic for permission before App Store submission; branding is configurable for a quick rebrand if needed.

## Safari Degradations
- `resize_window` is no longer available — clients calling it will receive a "tool not found" error
- `file_upload` requires a one-time directory access grant on first use (security-scoped bookmark prompt)

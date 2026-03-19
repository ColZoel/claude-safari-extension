# App Store Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude in Safari distributable via Mac App Store and notarized DMG by removing App Store-incompatible entitlements, adding App Sandbox, and building a signing/packaging pipeline.

**Architecture:** Remove `resize_window` tool entirely (AppleScript dependency). Keep `file_upload` working by adding `FileAccessManager` for security-scoped bookmarks under sandbox. Add App Sandbox to the main app. Build DMG packaging and CI/CD signing pipeline.

**Tech Stack:** Swift 5, Xcode 16, `create-dmg`, GitHub Actions, `xcrun notarytool`, security-scoped bookmarks

**Spec:** `docs/specs/026-app-store-distribution.md`

---

## File Structure

### Disabled (kept for future re-enablement)
- `ClaudeInSafari/Services/AppleScriptBridge.swift` — AppleScript bridge, disconnected from ToolRouter but preserved
- `Tests/Swift/AppleScriptBridgeTests.swift` — tests preserved, will still compile and run

### New
- `ClaudeInSafari/Services/FileAccessManager.swift` — security-scoped bookmark management for sandbox file access
- `Tests/Swift/FileAccessManagerTests.swift` — tests for above
- `scripts/create-dmg.sh` — DMG packaging script
- `scripts/bump-version.sh` — version bumping for both Info.plists
- `assets/dmg-background.png` — DMG installer background image

### Modified
- `ClaudeInSafari/ClaudeInSafari.entitlements` — add sandbox, remove temporary exceptions
- `ClaudeInSafari/MCP/ToolRouter.swift` — remove resize_window, integrate FileAccessManager for file_upload
- `ClaudeInSafari/Services/FileService.swift` — no changes needed (already reads files and returns base64)
- `ClaudeInSafari Extension/Resources/tools/file-upload.js` — **no changes needed** (already receives base64 from native app via ToolRouter; the spec §3 JS changes are a no-op)
- `ClaudeInSafari/App/PermissionMonitor.swift` — remove accessibility step
- `ClaudeInSafari/App/OnboardingWindowController.swift` — remove accessibility screen
- `ClaudeInSafari/App/MenuBarController.swift` — add Check for Updates and About items
- `ClaudeInSafari/MCP/MCPSocketServer.swift` — update socket path for sandbox
- `Shared/Constants.swift` — add branding constants, update socket path
- `ClaudeInSafari Extension/Resources/tools/constants.js` — add branding constant
- `scripts/generate-app-icon.swift` — parameterize color
- `ClaudeInSafari/Info.plist` — remove NSAppleEventsUsageDescription
- `.github/workflows/release.yml` — signing, notarization, DMG, App Store upload
- `Makefile` — add dmg target, update socket path references
- `STRUCTURE.md` — remove AppleScriptBridge, update onboarding screen count
- `CLAUDE.md` — remove AppleScript references
- `Tests/Swift/ToolRouterTests.swift` — remove resize_window tests
- `Tests/Swift/PermissionMonitorTests.swift` — remove accessibility tests
- `Tests/Swift/OnboardingWindowControllerTests.swift` — remove accessibility screen tests (if they exist)

---

## Task 1: Disable `resize_window` Tool (preserve code for future re-enablement)

**Files:**
- Modify: `ClaudeInSafari/MCP/ToolRouter.swift:206-215,358-365,600-635,1021-1093`
- Modify: `ClaudeInSafari/ClaudeInSafari.entitlements:9-12`
- Modify: `ClaudeInSafari/Info.plist` (NSAppleEventsUsageDescription)
- Keep: `ClaudeInSafari/Services/AppleScriptBridge.swift` (unchanged)
- Keep: `Tests/Swift/AppleScriptBridgeTests.swift` (unchanged)

- [x] **Step 1: Disconnect resize_window from ToolRouter.swift**
- [x] **Step 2: Remove AppleScript entitlement and usage description** (already done in prior work)
- [x] **Step 3: Remove resize_window tests from ToolRouterTests.swift**
- [x] **Step 4: Build and run tests** — 269 tests, 0 failures
- [ ] **Step 5: Commit**

```
git add -A
git commit -m "feat: disable resize_window for App Store compatibility, preserve code (Spec 026 §1)"
```

---

## Task 2: Remove Accessibility from Onboarding

**Files:**
- Modify: `ClaudeInSafari/App/PermissionMonitor.swift:10-58,122-131,139-174`
- Modify: `ClaudeInSafari/App/OnboardingWindowController.swift:94-115,186-194,390-436`
- Modify: `ClaudeInSafari/App/MenuBarController.swift:55-64`
- Modify: `Tests/Swift/PermissionMonitorTests.swift`

- [ ] **Step 1: Update PermissionMonitor.swift**

1. Remove `.accessibility` from `OnboardingStep` enum (line 13):
```swift
enum OnboardingStep: Equatable {
    case safariExtension
    case screenRecording
}
```

2. Remove `accessibility` from `PermissionStatus` struct (lines 18-34):
```swift
struct PermissionStatus {
    let extensionEnabled: Bool
    let screenRecording: Bool

    var allGranted: Bool {
        extensionEnabled && screenRecording
    }

    var firstIncompleteStep: OnboardingStep? {
        if !extensionEnabled { return .safariExtension }
        if !screenRecording  { return .screenRecording }
        return nil
    }
}
```

3. Remove from `PermissionChecking` protocol (lines 38-58):
   - Remove `func isAccessibilityGranted() -> Bool`
   - Remove `func registerAccessibility()`
   - Remove `func requestAccessibility()`

4. Remove from `SystemPermissionChecker` implementation (lines 63-103):
   - Remove `isAccessibilityGranted()` method (uses `AXIsProcessTrusted()`)
   - Remove `registerAccessibility()` method
   - Remove `requestAccessibility()` method

5. Remove pass-through methods from `PermissionMonitor` class (lines 122-131):
   - Remove `registerAccessibility()` (lines 124-126)
   - Remove `requestAccessibility()` (lines 129-131)

6. Update `PermissionMonitor.checkAll()` (lines 139-174) to remove `accessibility` from the status construction — remove the `checker.isAccessibilityGranted()` call and its use in `PermissionStatus(...)`.

- [ ] **Step 1.5: Update MenuBarController.swift**

In `MenuBarController.swift`, update `menuBarState(from:)` (~line 55-64) to remove the `status.accessibility` check. The function derives menu bar state from `PermissionStatus` — after removing the `accessibility` field, this will fail to compile unless updated.

- [ ] **Step 2: Update OnboardingWindowController.swift**

1. In `show()` (~line 94-115): Remove the `case .accessibility` from registerAccessibility/registerScreenRecording dispatch
2. In `buildView()` (~line 186-194): Remove the `.accessibility` case that calls `buildAccessibilityView()`
3. Delete `buildAccessibilityView()` (~lines 390-423)
4. Delete `openAccessibilitySettings()` (~lines 425-436)
5. Delete `accessibilityIconImage()` (~line 738)
6. Update timeline `activeIndex` values: Safari Extension = 0, Screen Recording = 1 (was 0, 1, 2)

- [ ] **Step 3: Update PermissionMonitorTests.swift**

Remove or update:
- `MockPermissionChecker`: remove `accessibilityGranted` property, `isAccessibilityGranted()`, `registerAccessibility()`, `requestAccessibility()`, `requestAccessibilityCalled`
- Update `allGranted` tests to only check extensionEnabled + screenRecording
- Update `firstIncompleteStep` tests to remove accessibility cases

- [ ] **Step 4: Build and run tests**

Run: `make build && make test-swift`
Expected: Build succeeds. All tests pass.

- [ ] **Step 5: Commit**

```
git add -A
git commit -m "feat: remove accessibility from onboarding (Spec 026 §1, §9)"
```

---

## Task 3: Add App Sandbox to Main App

**Files:**
- Modify: `ClaudeInSafari/ClaudeInSafari.entitlements`
- Modify: `ClaudeInSafari/MCP/MCPSocketServer.swift:38-42`
- Modify: `Shared/Constants.swift`

- [ ] **Step 1: Update entitlements**

Replace `ClaudeInSafari/ClaudeInSafari.entitlements` contents with:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.chriscantu.claudeinsafari</string>
    </array>
</dict>
</plist>
```

This adds sandbox + network server/client + user-selected file access, and removes both temporary exceptions.

- [ ] **Step 2: Update socket path to App Group container**

In `Shared/Constants.swift`, add a socket directory URL:
```swift
/// Socket directory for MCP server (inside App Group container for sandbox compatibility).
static var socketDirectoryURL: URL {
    appGroupContainerURL.appendingPathComponent("sockets")
}
```

In `MCPSocketServer.swift` (~line 38-42), replace the `/tmp/` socket path:
```swift
// Old: /tmp/claude-mcp-browser-bridge-<username>/<pid>.sock
// New: ~/Library/Group Containers/group.com.chriscantu.claudeinsafari/sockets/<pid>.sock
let socketDir = AppConstants.socketDirectoryURL.path
```

Also create a symlink at the old `/tmp/` path pointing to the new socket, for backward compatibility with the CLI. If symlink creation fails under sandbox, log a warning but don't fail — the App Group path is the primary.

- [ ] **Step 3: Update Makefile socket references**

Update `SOCK_DIR` and `APP_GROUP` variables in Makefile to match the new socket path. Update `dev.sock` symlink creation in the `run` target.

- [ ] **Step 4: Build and test**

Run: `make build && make test-swift`
Expected: Build succeeds. Tests pass.

Then test manually:
Run: `make dev`
Expected: App launches, socket is created in App Group container. Check with `ls ~/Library/Group\ Containers/group.com.chriscantu.claudeinsafari/sockets/`.

- [ ] **Step 5: Commit**

```
git add -A
git commit -m "feat: add App Sandbox to main app, move socket to App Group (Spec 026 §2)"
```

---

## Task 4: Add FileAccessManager for Sandbox File Access

**Files:**
- Create: `ClaudeInSafari/Services/FileAccessManager.swift`
- Create: `Tests/Swift/FileAccessManagerTests.swift`
- Modify: `ClaudeInSafari/MCP/ToolRouter.swift:738-779`

- [ ] **Step 1: Write FileAccessManager tests**

Create `Tests/Swift/FileAccessManagerTests.swift`:
```swift
// Tests/Swift/FileAccessManagerTests.swift
import XCTest
@testable import ClaudeInSafari

final class FileAccessManagerTests: XCTestCase {

    func testHasAccessReturnsFalseWithNoBookmarks() {
        let manager = FileAccessManager(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        XCTAssertFalse(manager.hasAccess(to: "/Users/test/file.txt"))
    }

    func testBookmarkDataPersistsInUserDefaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let manager = FileAccessManager(defaults: defaults)

        // Simulate storing a bookmark (can't create real security-scoped bookmark in tests)
        let fakeBookmark = Data([0x01, 0x02, 0x03])
        manager.storeBookmark(fakeBookmark, for: "/Users/test")

        XCTAssertNotNil(defaults.data(forKey: "FileAccessBookmark:/Users/test"))
    }

    func testNeedsAccessPromptReturnsTrueForUnbookmarkedPath() {
        let manager = FileAccessManager(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        XCTAssertTrue(manager.needsAccessPrompt(for: "/Users/test/file.txt"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-swift`
Expected: FAIL — `FileAccessManager` not found.

- [ ] **Step 3: Implement FileAccessManager**

Create `ClaudeInSafari/Services/FileAccessManager.swift`:
```swift
// ClaudeInSafari/Services/FileAccessManager.swift
import Foundation
import AppKit

/// Manages security-scoped bookmarks for sandbox-compatible file access.
/// On first file_upload, presents NSOpenPanel for directory access grant.
/// Stores bookmarks in UserDefaults for persistence across launches.
final class FileAccessManager {

    private let defaults: UserDefaults
    private static let bookmarkKeyPrefix = "FileAccessBookmark:"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Check if we have a stored bookmark covering the given path.
    func hasAccess(to path: String) -> Bool {
        return findBookmarkDirectory(for: path) != nil
    }

    /// Returns true if we need to show NSOpenPanel for this path.
    func needsAccessPrompt(for path: String) -> Bool {
        return !hasAccess(to: path)
    }

    /// Store a security-scoped bookmark for a directory.
    func storeBookmark(_ data: Data, for directory: String) {
        defaults.set(data, forKey: Self.bookmarkKeyPrefix + directory)
    }

    /// Present NSOpenPanel to grant access to a directory containing the file.
    /// Returns true if user granted access, false if cancelled.
    @MainActor
    func requestAccess(for filePath: String) -> Bool {
        let directory = (filePath as NSString).deletingLastPathComponent

        let panel = NSOpenPanel()
        panel.message = "Claude in Safari needs access to read files for upload. Please select the folder containing your files."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: directory)

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            storeBookmark(bookmark, for: url.path)
            return true
        } catch {
            return false
        }
    }

    /// Resolve bookmark and start accessing the security-scoped resource.
    /// Returns the resolved URL, or nil if bookmark is stale.
    func resolveAccess(for path: String) -> URL? {
        guard let directory = findBookmarkDirectory(for: path) else { return nil }
        guard let bookmarkData = defaults.data(forKey: Self.bookmarkKeyPrefix + directory) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-create bookmark
                if let newData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    storeBookmark(newData, for: directory)
                }
            }

            guard url.startAccessingSecurityScopedResource() else { return nil }
            return url
        } catch {
            return nil
        }
    }

    /// Stop accessing a security-scoped resource. Call when done reading.
    func stopAccess(for url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: - Private

    private func findBookmarkDirectory(for path: String) -> String? {
        // Check if any stored bookmark directory is a prefix of the path
        for key in defaults.dictionaryRepresentation().keys {
            guard key.hasPrefix(Self.bookmarkKeyPrefix) else { continue }
            let dir = String(key.dropFirst(Self.bookmarkKeyPrefix.count))
            if path.hasPrefix(dir) { return dir }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-swift`
Expected: All tests pass, including FileAccessManager tests.

- [ ] **Step 5: Integrate FileAccessManager into ToolRouter**

In `ToolRouter.swift`:
1. Add `private let fileAccessManager = FileAccessManager()` property
2. In `handleFileUpload()` (~line 738), before calling `FileService.readFiles()`, add:
```swift
// Check sandbox access for each file path
for path in filePaths {
    if fileAccessManager.needsAccessPrompt(for: path) {
        // Dispatch to main thread for NSOpenPanel
        let granted = await MainActor.run {
            fileAccessManager.requestAccess(for: path)
        }
        if !granted {
            // Return error to client
            sendError("File access denied: user cancelled directory access grant for \(path)")
            return
        }
    }
}
```

3. After reading files, resolve and stop security-scoped access:
```swift
// Resolve security-scoped access before reading
if let scopedURL = fileAccessManager.resolveAccess(for: path) {
    defer { fileAccessManager.stopAccess(for: scopedURL) }
    // ... existing FileService.readFiles() call ...
}
```

- [ ] **Step 6: Add FileAccessManager to Xcode project**

Add `FileAccessManager.swift` and `FileAccessManagerTests.swift` to the Xcode project via `project.pbxproj`.

- [ ] **Step 7: Build and run tests**

Run: `make build && make test-swift`
Expected: Build succeeds. All tests pass.

- [ ] **Step 8: Commit**

```
git add -A
git commit -m "feat: add FileAccessManager for sandbox file access (Spec 026 §3)"
```

---

## Task 5: Configurable Branding

**Files:**
- Modify: `Shared/Constants.swift:1-42`
- Modify: `ClaudeInSafari Extension/Resources/tools/constants.js`
- Modify: `scripts/generate-app-icon.swift:8`
- Modify: `ClaudeInSafari/App/MenuBarController.swift`
- Modify: `ClaudeInSafari/App/OnboardingWindowController.swift`

- [ ] **Step 1: Add branding constants to Swift**

In `Shared/Constants.swift`, add after existing constants:
```swift
// MARK: - Branding
static let appDisplayName = "Claude in Safari"
static let brandColorHex = "#D97757"
static let updateURL = URL(string: "https://github.com/anthropics/claude-safari-extension/releases")!
```

- [ ] **Step 2: Add branding constant to JavaScript**

In `ClaudeInSafari Extension/Resources/tools/constants.js`, add:
```javascript
const APP_DISPLAY_NAME = 'Claude in Safari';
```

- [ ] **Step 3: Parameterize icon color**

In `scripts/generate-app-icon.swift` (~line 8), replace the hardcoded color with a CLI argument:
```swift
// Read color from CLI arg or use default
let brandHex = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "D97757"
let r = Double(Int(brandHex.prefix(2), radix: 16)!) / 255.0
let g = Double(Int(brandHex.dropFirst(2).prefix(2), radix: 16)!) / 255.0
let b = Double(Int(brandHex.dropFirst(4).prefix(2), radix: 16)!) / 255.0
let brandOrange = NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
```

- [ ] **Step 4: Use AppConstants.appDisplayName in UI code**

In `MenuBarController.swift`, replace any hardcoded "Claude in Safari" strings with `AppConstants.appDisplayName`.

In `OnboardingWindowController.swift`, replace hardcoded app name strings with `AppConstants.appDisplayName`.

- [ ] **Step 5: Build and test**

Run: `make build && make test`
Expected: Build succeeds. All tests pass. Icon generation still works: `swift scripts/generate-app-icon.swift`

- [ ] **Step 6: Commit**

```
git add -A
git commit -m "feat: centralize branding constants for rebrand flexibility (Spec 026 §4)"
```

---

## Task 6: Menu Bar Additions

**Files:**
- Modify: `ClaudeInSafari/App/MenuBarController.swift:132-175`

- [ ] **Step 1: Add Check for Updates and About menu items**

In `MenuBarController.swift`, in `buildMenu()` (~line 132), add to all three menu state branches:

```swift
menu.addItem(.separator())
menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
menu.addItem(withTitle: "About \(AppConstants.appDisplayName)", action: #selector(showAbout), keyEquivalent: "")
menu.addItem(.separator())
menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
```

Add the action methods:
```swift
@objc private func checkForUpdates() {
    NSWorkspace.shared.open(AppConstants.updateURL)
}

@objc private func showAbout() {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

    let alert = NSAlert()
    alert.messageText = AppConstants.appDisplayName
    alert.informativeText = "Version \(version) (\(build))\n\nA Safari extension that enables Claude Code CLI to control Safari via MCP."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
```

- [ ] **Step 2: Build and test manually**

Run: `make build && make dev`
Expected: Menu bar shows new items. "Check for Updates" opens browser. "About" shows alert.

- [ ] **Step 3: Commit**

```
git add -A
git commit -m "feat: add Check for Updates and About menu items (Spec 026 §8)"
```

---

## Task 7: DMG Packaging

**Files:**
- Create: `scripts/create-dmg.sh`
- Create: `assets/dmg-background.png` (or generate inline)
- Modify: `Makefile`

- [ ] **Step 1: Create DMG script**

Create `scripts/create-dmg.sh`:
```bash
#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh <path-to-app>}"
APP_NAME=$(basename "$APP_PATH" .app)
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_DIR=$(mktemp -d)

echo "Creating DMG: $DMG_NAME"

# Copy app to temp directory
cp -R "$APP_PATH" "$DMG_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-size 600 400 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 150 200 \
        --app-drop-link 450 200 \
        "$DMG_NAME" \
        "$DMG_DIR"
else
    echo "create-dmg not found, using hdiutil fallback"
    hdiutil create -volname "$APP_NAME $VERSION" \
        -srcfolder "$DMG_DIR" \
        -ov -format UDZO \
        "$DMG_NAME"
fi

# Cleanup
rm -rf "$DMG_DIR"

echo "Created: $DMG_NAME"
```

- [ ] **Step 2: Make script executable**

Run: `chmod +x scripts/create-dmg.sh`

- [ ] **Step 3: Add Makefile target**

Add to `Makefile`:
```makefile
dmg: build
	scripts/create-dmg.sh "$(BUILD_DIR)/Build/Products/Release/ClaudeInSafari.app"
```

- [ ] **Step 4: Test DMG creation**

Run: `make build && scripts/create-dmg.sh "$(find ~/Library/Developer/Xcode/DerivedData/ClaudeInSafari-* -path '*/Build/Products/Debug/ClaudeInSafari.app' -maxdepth 5 | head -1)"`
Expected: Creates `ClaudeInSafari-1.0.0.dmg` in current directory. Mount it, verify app icon and Applications link appear.

- [ ] **Step 5: Commit**

```
git add -A
git commit -m "feat: add DMG packaging script and Makefile target (Spec 026 §5)"
```

---

## Task 8: Version Management Script

**Files:**
- Create: `scripts/bump-version.sh`

- [ ] **Step 1: Create bump-version script**

Create `scripts/bump-version.sh`:
```bash
#!/bin/bash
set -euo pipefail

BUMP="${1:?Usage: bump-version.sh <major|minor|patch>}"
APP_PLIST="ClaudeInSafari/Info.plist"
EXT_PLIST="ClaudeInSafari Extension/Info.plist"

# Read current version
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo "Error: argument must be major, minor, or patch"; exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((BUILD + 1))

# Update both plists
for PLIST in "$APP_PLIST" "$EXT_PLIST"; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"
done

echo "$NEW_VERSION"
```

- [ ] **Step 2: Make executable and test**

Run: `chmod +x scripts/bump-version.sh`

Test (dry run — don't commit the version change):
Run: `scripts/bump-version.sh patch`
Expected: Outputs `1.0.1`. Check plists updated. Then revert: `git checkout -- ClaudeInSafari/Info.plist "ClaudeInSafari Extension/Info.plist"`

- [ ] **Step 3: Commit**

```
git add scripts/bump-version.sh
git commit -m "feat: add version bump script for synced plist updates (Spec 026 §7)"
```

---

## Task 9: CI/CD Pipeline Updates

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Update release workflow with signing and DMG**

Replace `.github/workflows/release.yml` with updated workflow that:
1. Keeps existing trigger (tag `v*`) and test step
2. Adds conditional signing step (gated on `APPLE_CERTIFICATE` secret)
3. Adds conditional notarization step (gated on `APPLE_ID` + `APP_PASSWORD` + `TEAM_ID`)
4. Adds DMG creation step using `scripts/create-dmg.sh`
5. Adds conditional App Store upload step (gated on `APP_STORE_CONNECT_KEY`)
6. Updates release artifacts to include `.dmg`
7. Updates release notes — removes Gatekeeper bypass instructions when signed
8. Keeps unsigned fallback when secrets are not configured

Key additions to the workflow:
```yaml
    - name: Import signing certificate
      if: env.APPLE_CERTIFICATE != ''
      env:
        APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE }}
        APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
      run: |
        echo "$APPLE_CERTIFICATE" | base64 --decode > cert.p12
        security create-keychain -p "" build.keychain
        security import cert.p12 -k build.keychain -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain
        security list-keychains -d user -s build.keychain

    - name: Sign app
      if: env.APPLE_CERTIFICATE != ''
      run: codesign --deep --force --options runtime --sign "Developer ID Application" "$APP_PATH"

    - name: Notarize
      if: env.APPLE_ID != ''
      env:
        APPLE_ID: ${{ secrets.APPLE_ID }}
        APP_PASSWORD: ${{ secrets.APP_PASSWORD }}
        TEAM_ID: ${{ secrets.TEAM_ID }}
      run: |
        xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$TEAM_ID" --wait
        xcrun stapler staple "$DMG_PATH"

    - name: Create DMG
      run: scripts/create-dmg.sh "$APP_PATH"
```

- [ ] **Step 2: Test workflow syntax**

Run: `act -n` (if `act` is installed) or manually review YAML syntax.
Alternatively, just validate the YAML parses: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"`

- [ ] **Step 3: Commit**

```
git add .github/workflows/release.yml
git commit -m "feat: update CI/CD with signing, notarization, DMG pipeline (Spec 026 §6)"
```

---

## Task 10: Update Project Documentation

**Files:**
- Modify: `STRUCTURE.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update STRUCTURE.md**

1. Add a `(disabled — Spec 026)` note next to `AppleScriptBridge.swift` in the Services section
2. Add `FileAccessManager.swift` to the Services section
4. Add `FileAccessManagerTests.swift` to the Tests section
5. Add `scripts/create-dmg.sh` and `scripts/bump-version.sh` to the scripts section
6. Update onboarding comment from "5-screen setup wizard: Welcome -> 3 permission steps -> Done" to "4-screen setup wizard: Welcome -> 2 permission steps -> Done"

- [ ] **Step 2: Update CLAUDE.md**

1. In "Key Technical Decisions": remove "**AppleScript** for window management (Safari's `browser.windows` API is limited)"
2. In "Architecture": update if it references AppleScript or resize_window
3. Add note about App Sandbox and security-scoped bookmarks for file access

- [ ] **Step 3: Commit**

```
git add STRUCTURE.md CLAUDE.md
git commit -m "docs: update project docs for Spec 026 changes"
```

---

## Task 11: Final Verification

- [ ] **Step 1: Full test suite**

Run: `make test-all`
Expected: All JS tests pass. All Swift tests pass (minus removed tests).

- [ ] **Step 2: Build verification**

Run: `make clean && make build`
Expected: Clean build succeeds with no warnings related to removed code.

- [ ] **Step 3: Manual smoke test**

Run: `make dev`
Expected:
- App launches in menu bar
- Menu shows "Check for Updates" and "About" items
- Onboarding shows 4 screens (Welcome → Extension → Screen Recording → Done)
- No accessibility screen
- Socket created in App Group container

Run: `make health`
Expected: Health check passes.

Run: `make send TOOL=file_upload ARGS='{"paths":["/tmp/test.txt"],"ref":"input[type=file]"}'`
Expected: If no bookmark exists, should prompt for directory access (NSOpenPanel). After granting, file upload works.

Run: `make send TOOL=resize_window ARGS='{"width":800,"height":600}'`
Expected: Error response — tool not found.

- [ ] **Step 4: DMG verification**

Run: `make dmg` (or `scripts/create-dmg.sh` with built app path)
Expected: DMG created. Mount it. App icon and Applications link visible. Drag to Applications works. Launch from Applications works.

- [ ] **Step 5: Entitlements verification**

Run: `codesign -d --entitlements - "$(find ~/Library/Developer/Xcode/DerivedData/ClaudeInSafari-* -path '*/Debug/ClaudeInSafari.app' -maxdepth 5 | head -1)" 2>/dev/null | grep -E "app-sandbox|temporary-exception"`
Expected: `app-sandbox` = true. No `temporary-exception` entries.

- [ ] **Step 6: Final commit (if any fixes needed)**

```
git add -A
git commit -m "fix: final verification fixes for Spec 026"
```

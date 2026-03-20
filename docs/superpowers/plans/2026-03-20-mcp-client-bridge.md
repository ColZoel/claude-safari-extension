# MCP Client Bridge & Auto-Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Claude Code CLI and Claude Desktop to connect to the running Claude in Safari app by shipping a stdio-to-socket bridge binary and auto-installing MCP configuration.

**Architecture:** New `safari-mcp-bridge` CLI target compiled into the app bundle at `Contents/MacOS/safari-mcp-bridge`. The bridge discovers the MCP socket in the App Group container and relays stdin↔socket. An `--install` flag writes MCP config to Claude Code and Desktop. The sandboxed app provides a UI button that either runs the bridge directly (DMG, unsandboxed) or copies the install command + opens Terminal (App Store, sandboxed). Install success is communicated via an App Group marker file.

**Tech Stack:** Swift 5, Xcode 16, Unix domain sockets (POSIX), GCD DispatchSource, NSPasteboard, NSWorkspace

**Spec:** `docs/specs/027-mcp-client-bridge.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `safari-mcp-bridge/main.swift` | CLI entry point — argument parsing, dispatches to bridge/install/uninstall/status modes |
| `safari-mcp-bridge/BridgeRelay.swift` | Socket discovery + stdin↔socket relay logic |
| `safari-mcp-bridge/ConfigInstaller.swift` | Read/merge/write MCP config JSON for Claude Code + Desktop |
| `safari-mcp-bridge/StatusReporter.swift` | `--status` diagnostic output |
| `Tests/Swift/ConstantsTests.swift` | Unit tests for new AppConstants properties |
| `Tests/Swift/ConfigInstallerTests.swift` | Unit tests for JSON merge/create/invalid-JSON handling, marker file |
| `Tests/Swift/BridgeRelayTests.swift` | Unit tests for socket discovery and relay integration |

### Modified Files
| File | Change |
|------|--------|
| `ClaudeInSafari.xcodeproj/project.pbxproj` | Add `safari-mcp-bridge` CLI target, embed in app bundle |
| `Shared/Constants.swift` | Add `mcpConfigInstalledURL` for App Group marker file |
| `ClaudeInSafari/App/OnboardingWindowController.swift` | Add "Connect to Claude" step between screenRecording and done |
| `ClaudeInSafari/App/AppDelegate.swift` | Add sandbox detection, wire new onboarding step, menu bar integration |
| `ClaudeInSafari/App/MenuBarController.swift` | Add "Install Claude Integration" / "Uninstall" menu items |
| `ClaudeInSafari/App/PermissionMonitor.swift` | No changes needed (onboarding step doesn't use permission polling) |
| `Tests/Swift/OnboardingWindowControllerTests.swift` | Add tests for new Connect step |
| `Tests/Swift/MenuBarControllerTests.swift` | Add tests for new menu items |
| `STRUCTURE.md` | Document `safari-mcp-bridge/` target |
| `README.md` | Update setup instructions with install command |
| `Makefile` | Add `bridge` target for building the CLI tool |

---

## Task 1: Add `mcpConfigInstalledURL` to Constants.swift

**Files:**
- Modify: `Shared/Constants.swift:16-19`

- [ ] **Step 1: Write the failing test**

Create `Tests/Swift/ConstantsTests.swift` (if it doesn't already exist) or add to an existing test:

```swift
import XCTest
@testable import ClaudeInSafari

final class ConstantsTests: XCTestCase {
    func testMcpConfigInstalledURL_isInAppGroupContainer() {
        let url = AppConstants.mcpConfigInstalledURL
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.contains("group.com.chriscantu.claudeinsafari"))
        XCTAssertTrue(url!.lastPathComponent == "mcp_config_installed.json")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: FAIL — `mcpConfigInstalledURL` does not exist

- [ ] **Step 3: Write minimal implementation**

Add to `Shared/Constants.swift` inside `enum AppConstants`, after `extensionGenerationURL`:

```swift
/// URL for the MCP config install marker file (written by safari-mcp-bridge --install,
/// read by the main app to detect successful config installation).
static var mcpConfigInstalledURL: URL? {
    appGroupContainerURL?.appendingPathComponent("mcp_config_installed.json")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```
git add Shared/Constants.swift Tests/Swift/ConstantsTests.swift
git commit -m "feat(027): add mcpConfigInstalledURL to AppConstants"
```

---

## Task 2: Create `safari-mcp-bridge` Xcode Target (scaffold)

This task creates the new CLI target in Xcode and gets a minimal "hello world" binary building. The actual logic is added in subsequent tasks.

**Files:**
- Create: `safari-mcp-bridge/main.swift`
- Modify: `ClaudeInSafari.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the target directory and minimal main.swift**

```swift
// safari-mcp-bridge/main.swift
import Foundation

// CLI entry point for safari-mcp-bridge.
// Modes:
//   (no flags)   — stdio-to-socket relay for MCP communication
//   --install    — write MCP config to Claude Code + Desktop
//   --uninstall  — remove MCP config from Claude Code + Desktop
//   --status     — print diagnostic info

let args = CommandLine.arguments.dropFirst() // skip executable name
let command = args.first

switch command {
case "--install":
    // TODO: Task 4
    print("--install not yet implemented")
    exit(1)
case "--uninstall":
    // TODO: Task 4
    print("--uninstall not yet implemented")
    exit(1)
case "--status":
    // TODO: Task 5
    print("--status not yet implemented")
    exit(1)
case nil:
    // Default: bridge relay mode
    // TODO: Task 3
    print("bridge relay not yet implemented")
    exit(1)
default:
    fputs("Unknown flag: \(command!)\nUsage: safari-mcp-bridge [--install | --uninstall | --status]\n", stderr)
    exit(1)
}
```

- [ ] **Step 2: Add the CLI target to the Xcode project**

Use Xcode's "Add Target" (File → New → Target → macOS → Command Line Tool) or `xcodebuild` scripting. The target must:
- Name: `safari-mcp-bridge`
- Type: Command Line Tool
- Language: Swift
- Sources: `safari-mcp-bridge/main.swift`
- No sandbox entitlements (do NOT add `com.apple.security.app-sandbox`)
- Deployment target: macOS 13.0 (same as main app)
- Build product: `safari-mcp-bridge` binary

The binary must be embedded in the main app bundle. Add a "Copy Files" build phase to the main `ClaudeInSafari` target:
- Destination: Executables (`Contents/MacOS/`)
- Files: `safari-mcp-bridge` product

Also add a target dependency: `ClaudeInSafari` depends on `safari-mcp-bridge` (so it builds before the copy phase).

- [ ] **Step 3: Verify the binary builds and is embedded**

Run: `xcodebuild build -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafari -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Then verify the binary exists in the app bundle:
```bash
APP_PATH=$(xcodebuild -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafari -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')
ls -la "$APP_PATH/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge"
```

Expected: binary exists, is executable

- [ ] **Step 4: Test the binary runs**

```bash
"$APP_PATH/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge" --status
```

Expected: prints "--status not yet implemented", exits 1

- [ ] **Step 5: Commit**

```
git add safari-mcp-bridge/ ClaudeInSafari.xcodeproj/
git commit -m "feat(027): add safari-mcp-bridge CLI target scaffold"
```

---

## Task 3: Implement Bridge Relay (stdin↔socket)

**Files:**
- Create: `safari-mcp-bridge/BridgeRelay.swift`
- Modify: `safari-mcp-bridge/main.swift` (wire up default case)
- Create: `Tests/Swift/BridgeRelayTests.swift`

- [ ] **Step 1: Write the failing test — socket discovery**

Create `Tests/Swift/BridgeRelayTests.swift`:

```swift
import XCTest
@testable import ClaudeInSafari

final class BridgeRelayTests: XCTestCase {

    func testFindNewestSocket_returnsNewestByMtime() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create two fake socket files with different mtimes
        let older = tmpDir.appendingPathComponent("111.sock")
        let newer = tmpDir.appendingPathComponent("222.sock")
        FileManager.default.createFile(atPath: older.path, contents: nil)
        sleep(1) // ensure different mtime
        FileManager.default.createFile(atPath: newer.path, contents: nil)

        let result = BridgeRelay.findNewestSocket(in: tmpDir.path)
        XCTAssertEqual(result, newer.path)
    }

    func testFindNewestSocket_returnsNilWhenEmpty() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let result = BridgeRelay.findNewestSocket(in: tmpDir.path)
        XCTAssertNil(result)
    }
}
```

**Important — test target access:** `BridgeRelay.swift` and `ConfigInstaller.swift` live in the `safari-mcp-bridge/` directory but must also be compiled by the main app target so that tests can reach them via `@testable import ClaudeInSafari`. Both files depend only on Foundation (no AppKit), so dual-compilation is safe. In Xcode: select each `.swift` file → File Inspector → Target Membership → check both `ClaudeInSafari` and `safari-mcp-bridge`. This applies to all bridge source files except `main.swift` (which must only be in the CLI target).

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: FAIL — `BridgeRelay` type not found

- [ ] **Step 3: Implement BridgeRelay.swift**

Create `safari-mcp-bridge/BridgeRelay.swift` (also add to main app test target's compile sources):

```swift
// safari-mcp-bridge/BridgeRelay.swift
import Foundation

/// Discovers the MCP socket and relays stdin↔socket using newline-delimited JSON.
enum BridgeRelay {

    /// App Group container socket directory path.
    /// Hardcoded rather than using FileManager.containerURL(forSecurityApplicationGroupIdentifier:)
    /// because that API requires the app group entitlement, which the bridge binary intentionally
    /// does not have (it runs unsandboxed as a subprocess of Claude Code/Desktop).
    static let socketDirectory: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Group Containers/group.com.chriscantu.claudeinsafari/sockets"
    }()

    /// Finds the newest *.sock file in the given directory by modification time.
    /// Returns nil if no socket files exist.
    static func findNewestSocket(in directory: String) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return nil }
        let socks = entries.filter { $0.hasSuffix(".sock") }
        guard !socks.isEmpty else { return nil }

        return socks
            .map { (directory as NSString).appendingPathComponent($0) }
            .max { path1, path2 in
                let m1 = (try? fm.attributesOfItem(atPath: path1)[.modificationDate] as? Date) ?? .distantPast
                let m2 = (try? fm.attributesOfItem(atPath: path2)[.modificationDate] as? Date) ?? .distantPast
                return m1 < m2
            }
    }

    /// Connects to the Unix domain socket at the given path.
    /// Returns the file descriptor, or throws on failure.
    static func connectToSocket(at path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BridgeError.socketCreationFailed(errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                _ = strcpy(ptr, cstr)
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw BridgeError.connectionFailed(errno)
        }
        return fd
    }

    /// Runs the stdio↔socket relay loop. Blocks until either side closes.
    static func run() -> Never {
        guard let socketPath = findNewestSocket(in: socketDirectory) else {
            fputs("{\"error\": \"Claude in Safari is not running. Launch the app and try again.\"}\n", stderr)
            exit(1)
        }

        let fd: Int32
        do {
            fd = try connectToSocket(at: socketPath)
        } catch {
            fputs("{\"error\": \"Socket exists but connection failed. Restart Claude in Safari.\"}\n", stderr)
            exit(1)
        }

        // Disable stdout buffering so MCP clients see responses immediately
        setbuf(stdout, nil)

        let group = DispatchGroup()

        // stdin → socket
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let bufSize = 65536
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }

            while true {
                let n = fread(buf, 1, bufSize, stdin)
                if n <= 0 { break } // EOF or error
                var written = 0
                while written < n {
                    let w = Darwin.write(fd, buf.advanced(by: written), n - written)
                    if w <= 0 { group.leave(); return }
                    written += w
                }
            }
            shutdown(fd, SHUT_WR)
            group.leave()
        }

        // socket → stdout
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let bufSize = 65536
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }

            while true {
                let n = Darwin.read(fd, buf, bufSize)
                if n <= 0 { break } // EOF or error
                var written = 0
                while written < n {
                    let w = fwrite(buf.advanced(by: written), 1, n - written, stdout)
                    if w <= 0 { group.leave(); return }
                    written += w
                    fflush(stdout)
                }
            }
            group.leave()
        }

        group.wait()
        close(fd)
        exit(0)
    }
}

    /// Performs a full MCP handshake (initialize + tools/list) and returns the tool count.
    /// Returns nil on failure. Used by --install --verify.
    static func verifyConnection(socketPath: String) -> Int? {
        guard let fd = try? connectToSocket(at: socketPath) else { return nil }
        defer { close(fd) }

        // Set 5s read timeout
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        func sendLine(_ json: String) {
            let data = (json + "\n").data(using: .utf8)!
            data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                _ = Darwin.write(fd, base, data.count)
            }
        }

        func readLine() -> [String: Any]? {
            var buffer = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
            defer { buf.deallocate() }
            while true {
                let n = Darwin.read(fd, buf, 65536)
                if n <= 0 { return nil }
                buffer.append(buf, count: n)
                if let idx = buffer.firstIndex(of: 0x0A) {
                    let msgData = buffer[buffer.startIndex..<idx]
                    return try? JSONSerialization.jsonObject(with: msgData) as? [String: Any]
                }
            }
        }

        // Step 1: initialize
        sendLine("{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"safari-mcp-bridge\",\"version\":\"1.0.0\"}}}")
        guard readLine() != nil else { return nil }

        // Step 2: initialized notification
        sendLine("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")
        usleep(50_000)

        // Step 3: tools/list
        sendLine("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}")
        guard let response = readLine(),
              let result = response["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]] else { return nil }

        return tools.count
    }
}

enum BridgeError: Error {
    case socketCreationFailed(Int32)
    case connectionFailed(Int32)
}
```

- [ ] **Step 4: Wire up main.swift default case**

In `safari-mcp-bridge/main.swift`, replace the `case nil:` TODO:

```swift
case nil:
    BridgeRelay.run()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Manual integration test with running app**

```bash
# Build
xcodebuild build -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafari -destination 'platform=macOS' -quiet

# Find the built binary
BRIDGE=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeInSafari-*/Build/Products/Release -name safari-mcp-bridge -type f 2>/dev/null | head -1)

# Send an MCP initialize + tools/list via the bridge (pipe stdin)
echo '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"bridge-test","version":"1.0.0"}}}' | "$BRIDGE"
```

Expected: JSON response on stdout containing server capabilities

- [ ] **Step 7: Commit**

```
git add safari-mcp-bridge/BridgeRelay.swift safari-mcp-bridge/main.swift Tests/Swift/BridgeRelayTests.swift
git commit -m "feat(027): implement bridge relay — stdin↔socket for MCP"
```

---

## Task 4: Implement `--install` and `--uninstall` (ConfigInstaller)

**Files:**
- Create: `safari-mcp-bridge/ConfigInstaller.swift`
- Create: `Tests/Swift/ConfigInstallerTests.swift`
- Modify: `safari-mcp-bridge/main.swift` (wire up --install and --uninstall)

- [ ] **Step 1: Write failing tests**

Create `Tests/Swift/ConfigInstallerTests.swift`:

```swift
import XCTest
@testable import ClaudeInSafari

final class ConfigInstallerTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("config-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // T1: creates config from scratch when file doesn't exist
    func testInstall_createsNewFile() throws {
        let configPath = tmpDir.appendingPathComponent("claude.json").path
        let result = ConfigInstaller.installConfig(
            bridgePath: "/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge",
            configPath: configPath
        )
        XCTAssertTrue(result.success)

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = json["mcpServers"] as! [String: Any]
        let safari = servers["claude-in-safari"] as! [String: Any]
        XCTAssertEqual(safari["command"] as? String, "/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge")
    }

    // T2: merges into existing config without clobbering other servers
    func testInstall_mergesWithExisting() throws {
        let configPath = tmpDir.appendingPathComponent("claude.json").path
        let existing = """
        {
          "mcpServers": {
            "other-server": {
              "command": "other-binary",
              "args": ["--flag"]
            }
          },
          "otherKey": true
        }
        """
        try existing.write(toFile: configPath, atomically: true, encoding: .utf8)

        let result = ConfigInstaller.installConfig(
            bridgePath: "/test/bridge",
            configPath: configPath
        )
        XCTAssertTrue(result.success)

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Other server preserved
        let servers = json["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other-server"])
        XCTAssertNotNil(servers["claude-in-safari"])
        // Other top-level key preserved
        XCTAssertEqual(json["otherKey"] as? Bool, true)
    }

    // T3: skips file with invalid JSON
    func testInstall_skipsInvalidJSON() throws {
        let configPath = tmpDir.appendingPathComponent("claude.json").path
        try "not valid json {{{".write(toFile: configPath, atomically: true, encoding: .utf8)

        let result = ConfigInstaller.installConfig(
            bridgePath: "/test/bridge",
            configPath: configPath
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("invalid JSON"))
    }

    // T4: uninstall removes the key
    func testUninstall_removesKey() throws {
        let configPath = tmpDir.appendingPathComponent("claude.json").path
        // First install
        _ = ConfigInstaller.installConfig(bridgePath: "/test/bridge", configPath: configPath)
        // Then uninstall
        let result = ConfigInstaller.uninstallConfig(configPath: configPath)
        XCTAssertTrue(result.success)

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = json["mcpServers"] as? [String: Any] ?? [:]
        XCTAssertNil(servers["claude-in-safari"])
    }

    // T5: uninstall preserves other servers
    func testUninstall_preservesOtherServers() throws {
        let configPath = tmpDir.appendingPathComponent("claude.json").path
        let existing = """
        {
          "mcpServers": {
            "other-server": {"command": "other"},
            "claude-in-safari": {"command": "/old/path"}
          }
        }
        """
        try existing.write(toFile: configPath, atomically: true, encoding: .utf8)

        _ = ConfigInstaller.uninstallConfig(configPath: configPath)

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = json["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other-server"])
        XCTAssertNil(servers["claude-in-safari"])
    }

    // T6: creates parent directories if needed
    func testInstall_createsParentDirectories() throws {
        let configPath = tmpDir
            .appendingPathComponent("nested/dir/claude.json").path

        let result = ConfigInstaller.installConfig(
            bridgePath: "/test/bridge",
            configPath: configPath
        )
        XCTAssertTrue(result.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))
    }

    // T7: marker file is written with correct contents
    func testWriteMarkerFile_writesJSON() throws {
        // Use a temp App Group path for testing (override in test)
        let markerPath = tmpDir.appendingPathComponent("mcp_config_installed.json").path
        ConfigInstaller.writeMarkerFile(bridgePath: "/test/bridge", clients: ["Claude Code CLI"], markerPath: markerPath)

        let data = try Data(contentsOf: URL(fileURLWithPath: markerPath))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["bridge_path"] as? String, "/test/bridge")
        XCTAssertEqual(json["clients"] as? [String], ["Claude Code CLI"])
        XCTAssertNotNil(json["installed_at"] as? String)
    }

    // T8: removeMarkerFile deletes the file
    func testRemoveMarkerFile_deletesFile() throws {
        let markerPath = tmpDir.appendingPathComponent("mcp_config_installed.json").path
        ConfigInstaller.writeMarkerFile(bridgePath: "/test/bridge", clients: [], markerPath: markerPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerPath))

        ConfigInstaller.removeMarkerFile(markerPath: markerPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerPath))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: FAIL — `ConfigInstaller` not found

- [ ] **Step 3: Implement ConfigInstaller.swift**

Create `safari-mcp-bridge/ConfigInstaller.swift` (also add to test target compile sources):

```swift
// safari-mcp-bridge/ConfigInstaller.swift
import Foundation

struct InstallResult {
    let success: Bool
    let message: String
}

/// Reads, merges, and writes MCP server config for Claude Code and Desktop.
enum ConfigInstaller {

    static let serverKey = "claude-in-safari"

    /// Well-known config file paths.
    static var claudeCodeConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude.json"
    }

    static var claudeDesktopConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Claude/claude_desktop_config.json"
    }

    /// Detects which Claude clients are installed.
    static func detectClients() -> [(name: String, configPath: String)] {
        var clients: [(String, String)] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Claude Code: check if ~/.claude/ directory exists
        if FileManager.default.fileExists(atPath: "\(home)/.claude") {
            clients.append(("Claude Code CLI", claudeCodeConfigPath))
        }

        // Claude Desktop: check if ~/Library/Application Support/Claude/ exists
        let desktopDir = "\(home)/Library/Application Support/Claude"
        if FileManager.default.fileExists(atPath: desktopDir) {
            clients.append(("Claude Desktop", claudeDesktopConfigPath))
        }

        return clients
    }

    /// Writes the MCP server config entry for safari-mcp-bridge to the given config file.
    /// Merges with existing config — never overwrites other keys.
    static func installConfig(bridgePath: String, configPath: String) -> InstallResult {
        let fm = FileManager.default

        // Create parent directories if needed
        let parentDir = (configPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: parentDir) {
            do {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            } catch {
                return InstallResult(success: false, message: "Failed to create directory: \(error.localizedDescription)")
            }
        }

        // Read existing file or start with empty dict
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: configPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return InstallResult(success: false, message: "Config file contains invalid JSON (not a dictionary): \(configPath)")
                }
                root = parsed
            } catch {
                return InstallResult(success: false, message: "Config file contains invalid JSON: \(configPath) — \(error.localizedDescription)")
            }
        }

        // Get or create mcpServers
        var servers = root["mcpServers"] as? [String: Any] ?? [:]

        // Set our entry
        servers[serverKey] = [
            "command": bridgePath,
            "args": [String]()
        ] as [String: Any]

        root["mcpServers"] = servers

        // Write back
        do {
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            return InstallResult(success: true, message: "Configured: \(configPath)")
        } catch {
            return InstallResult(success: false, message: "Failed to write config: \(error.localizedDescription)")
        }
    }

    /// Removes the safari-mcp-bridge entry from the given config file.
    static func uninstallConfig(configPath: String) -> InstallResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configPath) else {
            return InstallResult(success: true, message: "Config file does not exist, nothing to remove: \(configPath)")
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return InstallResult(success: false, message: "Config file contains invalid JSON: \(configPath)")
            }

            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            servers.removeValue(forKey: serverKey)
            root["mcpServers"] = servers

            let updated = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try updated.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            return InstallResult(success: true, message: "Removed from: \(configPath)")
        } catch {
            return InstallResult(success: false, message: "Failed to update config: \(error.localizedDescription)")
        }
    }

    /// Default marker file path in the App Group container.
    static var defaultMarkerPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Group Containers/group.com.chriscantu.claudeinsafari/mcp_config_installed.json"
    }

    /// Writes a marker file so the main app can detect successful installation.
    /// `markerPath` is overridable for testing.
    static func writeMarkerFile(bridgePath: String, clients: [String], markerPath: String? = nil) {
        let path = markerPath ?? defaultMarkerPath

        let formatter = ISO8601DateFormatter()
        let marker: [String: Any] = [
            "installed_at": formatter.string(from: Date()),
            "bridge_path": bridgePath,
            "clients": clients
        ]

        if let data = try? JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    /// Removes the marker file. `markerPath` is overridable for testing.
    static func removeMarkerFile(markerPath: String? = nil) {
        let path = markerPath ?? defaultMarkerPath
        try? FileManager.default.removeItem(atPath: path)
    }
}
```

- [ ] **Step 4: Wire up main.swift --install and --uninstall**

Replace the `--install` case in `main.swift`:

```swift
case "--install":
    // Resolve our own path (the bridge binary)
    let bridgePath = ProcessInfo.processInfo.arguments[0]
    let resolvedPath: String
    if let realPath = realpath(bridgePath, nil) {
        resolvedPath = String(cString: realPath)
        free(realPath)
    } else {
        resolvedPath = bridgePath
    }

    let verify = args.contains("--verify")
    let clients = ConfigInstaller.detectClients()

    if clients.isEmpty {
        print("⚠ No Claude clients detected.")
        print("  Install Claude Code (https://claude.ai/download) or Claude Desktop first.")
        // Still install to the default paths in case detection failed
    }

    var configuredClients: [String] = []
    let targets = clients.isEmpty
        ? [("Claude Code CLI", ConfigInstaller.claudeCodeConfigPath)]  // fallback: always write Claude Code config
        : clients

    for (name, path) in targets {
        let result = ConfigInstaller.installConfig(bridgePath: resolvedPath, configPath: path)
        if result.success {
            print("✓ \(name) — configured")
            configuredClients.append(name)
        } else {
            print("✗ \(name) — \(result.message)")
        }
    }

    ConfigInstaller.writeMarkerFile(bridgePath: resolvedPath, clients: configuredClients)

    if verify {
        // Full MCP handshake: connect, initialize, tools/list, report tool count
        if let socketPath = BridgeRelay.findNewestSocket(in: BridgeRelay.socketDirectory) {
            let toolCount = BridgeRelay.verifyConnection(socketPath: socketPath)
            if let count = toolCount {
                print("\n✓ Connection verified — \(count) tools available")
            } else {
                print("\n⚠ Socket exists but verification failed. Restart Claude in Safari.")
            }
        } else {
            print("\n⚠ Config installed, but Claude in Safari is not running. Launch the app to activate.")
        }
    }

    print("\nDone! Restart Claude Code or Claude Desktop to connect.")
    exit(0)
```

Replace the `--uninstall` case:

```swift
case "--uninstall":
    let paths = [
        ("Claude Code CLI", ConfigInstaller.claudeCodeConfigPath),
        ("Claude Desktop", ConfigInstaller.claudeDesktopConfigPath)
    ]
    for (name, path) in paths {
        let result = ConfigInstaller.uninstallConfig(configPath: path)
        print("\(result.success ? "✓" : "✗") \(name) — \(result.message)")
    }
    ConfigInstaller.removeMarkerFile()
    print("\nDone! MCP config removed.")
    exit(0)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: All ConfigInstallerTests pass

- [ ] **Step 6: Manual test**

```bash
BRIDGE=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeInSafari-*/Build/Products -name safari-mcp-bridge -type f 2>/dev/null | head -1)
"$BRIDGE" --install --verify
"$BRIDGE" --status
"$BRIDGE" --uninstall
```

- [ ] **Step 7: Commit**

```
git add safari-mcp-bridge/ConfigInstaller.swift safari-mcp-bridge/main.swift Tests/Swift/ConfigInstallerTests.swift
git commit -m "feat(027): implement --install and --uninstall for MCP config"
```

---

## Task 5: Implement `--status` (StatusReporter)

**Files:**
- Create: `safari-mcp-bridge/StatusReporter.swift`
- Modify: `safari-mcp-bridge/main.swift` (wire up --status)

- [ ] **Step 1: Implement StatusReporter.swift**

```swift
// safari-mcp-bridge/StatusReporter.swift
import Foundation

enum StatusReporter {

    static func printStatus() {
        let bridgePath = {
            if let realPath = realpath(ProcessInfo.processInfo.arguments[0], nil) {
                defer { free(realPath) }
                return String(cString: realPath)
            }
            return ProcessInfo.processInfo.arguments[0]
        }()

        print("Safari MCP Bridge Status")
        print("========================")
        print("")

        // Bridge binary
        print("Bridge: \(bridgePath)")

        // Socket
        let socketDir = BridgeRelay.socketDirectory
        print("Socket dir: \(socketDir)")
        if let socketPath = BridgeRelay.findNewestSocket(in: socketDir) {
            let pid = (socketPath as NSString).lastPathComponent.replacingOccurrences(of: ".sock", with: "")
            print("Socket: \(socketPath) (PID \(pid))")

            // Test connection
            if let fd = try? BridgeRelay.connectToSocket(at: socketPath) {
                close(fd)
                print("Connection: ✓ reachable")
            } else {
                print("Connection: ✗ exists but unreachable")
            }
        } else {
            print("Socket: ✗ not found (is Claude in Safari running?)")
        }

        print("")

        // Config files
        let configs: [(String, String)] = [
            ("Claude Code CLI", ConfigInstaller.claudeCodeConfigPath),
            ("Claude Desktop", ConfigInstaller.claudeDesktopConfigPath)
        ]

        for (name, path) in configs {
            let fm = FileManager.default
            if fm.fileExists(atPath: path) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let servers = json["mcpServers"] as? [String: Any],
                   let safari = servers["claude-in-safari"] as? [String: Any],
                   let command = safari["command"] as? String {
                    let pathMatch = command == bridgePath
                    print("\(name): ✓ configured → \(command)")
                    if !pathMatch {
                        print("  ⚠ Path mismatch! Config points to \(command) but this binary is \(bridgePath)")
                        print("  Run --install to update.")
                    }
                } else {
                    print("\(name): ✗ config exists but no claude-in-safari entry")
                }
            } else {
                print("\(name): — config file not found (\(path))")
            }
        }
    }
}
```

- [ ] **Step 2: Wire up main.swift --status**

Replace the `--status` case:

```swift
case "--status":
    StatusReporter.printStatus()
    exit(0)
```

- [ ] **Step 3: Build and test manually**

```bash
xcodebuild build -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafari -destination 'platform=macOS' -quiet
BRIDGE=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeInSafari-*/Build/Products -name safari-mcp-bridge -type f 2>/dev/null | head -1)
"$BRIDGE" --status
```

Expected: Prints bridge path, socket status, config status for both clients

- [ ] **Step 4: Commit**

```
git add safari-mcp-bridge/StatusReporter.swift safari-mcp-bridge/main.swift
git commit -m "feat(027): implement --status diagnostic output"
```

---

## Task 6: Add Sandbox Detection Utility

**Files:**
- Modify: `ClaudeInSafari/App/AppDelegate.swift`

- [ ] **Step 1: Add sandbox detection property to AppDelegate**

Add at the top of `AppDelegate`, after the private state properties:

```swift
/// True when running inside App Sandbox (App Store build).
/// DMG builds are unsandboxed and can launch the bridge binary directly.
private var isSandboxed: Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafari -destination 'platform=macOS' -quiet`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```
git add ClaudeInSafari/App/AppDelegate.swift
git commit -m "feat(027): add sandbox detection to AppDelegate"
```

---

## Task 7: Add "Connect to Claude" Onboarding Step

This is the most complex UI task. It adds a new screen to the onboarding flow between Screen Recording and Done.

**Files:**
- Modify: `ClaudeInSafari/App/OnboardingWindowController.swift`
- Modify: `Tests/Swift/OnboardingWindowControllerTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `Tests/Swift/OnboardingWindowControllerTests.swift`:

```swift
// T-new: advance from screenRecording goes to connectClaude, not done
func testAdvance_fromScreenRecording_goesToConnectClaude() {
    let wc = OnboardingWindowController(monitor: mockMonitor())
    wc.showOnboarding()
    // Navigate: welcome → safariExtension → screenRecording → connectClaude
    wc.advance() // → safariExtension
    wc.advance() // → screenRecording
    wc.advance() // → connectClaude (NEW — previously went to done)
    XCTAssertEqual(wc.currentScreen, .connectClaude)
}

func testAdvance_fromConnectClaude_goesToDone() {
    let wc = OnboardingWindowController(monitor: mockMonitor())
    wc.showOnboarding()
    wc.advance() // → safariExtension
    wc.advance() // → screenRecording
    wc.advance() // → connectClaude
    wc.advance() // → done
    XCTAssertEqual(wc.currentScreen, .done)
}
```

Note: you'll need to check what the existing test helper `mockMonitor()` looks like and adapt accordingly. The `OnboardingScreen` enum needs a `.connectClaude` case.

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `.connectClaude` doesn't exist on `OnboardingScreen`

- [ ] **Step 3: Add `.connectClaude` to OnboardingScreen enum**

In `OnboardingWindowController.swift`, update the enum:

```swift
enum OnboardingScreen: Equatable {
    case welcome
    case step(OnboardingStep)
    case connectClaude   // NEW — "Connect to Claude" step
    case done
}
```

- [ ] **Step 4: Update `advance()` method**

```swift
func advance() {
    switch currentScreen {
    case .welcome:
        show(screen: .step(.safariExtension))
    case .step(.safariExtension):
        show(screen: .step(.screenRecording))
    case .step(.screenRecording):
        show(screen: .connectClaude)
    case .connectClaude:
        show(screen: .done)
    case .done:
        dismiss()
    }
}
```

- [ ] **Step 5: Update `show(screen:)` to handle `.connectClaude`**

The Connect step doesn't use permission polling. Instead, it polls the App Group marker file.

- [ ] **Step 6: Update `buildView(for:)` to include `.connectClaude`**

```swift
private func buildView(for screen: OnboardingScreen) -> NSView {
    switch screen {
    case .welcome:                return buildWelcomeView()
    case .step(.safariExtension): return buildSafariExtensionView()
    case .step(.screenRecording): return buildScreenRecordingView()
    case .connectClaude:          return buildConnectClaudeView()
    case .done:                   return buildDoneView()
    }
}
```

- [ ] **Step 7: Implement `buildConnectClaudeView()`**

This is the key UI piece. It needs two modes based on sandbox detection:

```swift
private func buildConnectClaudeView() -> NSView {
    let root = paddedRoot()

    // Icon: link/chain symbol
    let iconView = makeIconView(size: Layout.iconSizeSm, corner: Layout.cornerSm,
                                content: sfSymbolImage("link", size: Layout.iconSizeSm * 0.55))
    iconView.frame.origin = CGPoint(x: Layout.padding, y: Layout.windowHeight - Layout.padding - Layout.iconSizeSm)
    root.addSubview(iconView)

    let title = makeLabel("Connect to Claude", size: 20, weight: .bold)
    title.frame = NSRect(x: Layout.padding, y: iconView.frame.minY - 36,
                         width: Layout.windowWidth - Layout.padding * 2, height: 26)
    root.addSubview(title)

    let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    if isSandboxed {
        // App Store flow: copy command + open Terminal
        let body = makeLabel(
            "One more step — connect this app to Claude Code and Claude Desktop so they can use Safari.",
            size: 13, weight: .regular, color: .secondaryLabelColor, wraps: true)
        body.frame = NSRect(x: Layout.padding, y: title.frame.minY - 44,
                            width: Layout.windowWidth - Layout.padding * 2, height: 36)
        root.addSubview(body)

        // Command box
        let commandBox = makeInstructionBox("Click Install, then paste (⌘V) in Terminal and press Enter.")
        commandBox.frame = NSRect(x: Layout.padding, y: body.frame.minY - 68,
                                  width: Layout.windowWidth - Layout.padding * 2, height: 56)
        root.addSubview(commandBox)

        let primary = makeButton("Install (Copy & Open Terminal)", action: #selector(copyAndOpenTerminal), primary: true)
        primary.frame = NSRect(x: Layout.padding, y: 100, width: Layout.windowWidth - Layout.padding * 2, height: 36)
        root.addSubview(primary)
    } else {
        // DMG flow: auto-install
        let body = makeLabel(
            "Connect this app to Claude Code and Claude Desktop so they can use Safari.",
            size: 13, weight: .regular, color: .secondaryLabelColor, wraps: true)
        body.frame = NSRect(x: Layout.padding, y: title.frame.minY - 36,
                            width: Layout.windowWidth - Layout.padding * 2, height: 28)
        root.addSubview(body)

        let primary = makeButton("Install", action: #selector(runInstallDirectly), primary: true)
        primary.frame = NSRect(x: Layout.padding, y: 100, width: Layout.windowWidth - Layout.padding * 2, height: 36)
        root.addSubview(primary)
    }

    // Detecting row — polls for marker file
    let detecting = makeDetectingRow("Waiting for installation…")
    detecting.frame = NSRect(x: Layout.padding, y: 64, width: Layout.windowWidth - Layout.padding * 2, height: 32)
    detecting.isHidden = true
    detecting.identifier = NSUserInterfaceItemIdentifier("connectDetecting")
    root.addSubview(detecting)

    let skip = makeButton("I'll do this later →", action: #selector(skipConnect), primary: false)
    skip.frame = NSRect(x: Layout.padding, y: 30, width: Layout.windowWidth - Layout.padding * 2, height: 24)
    root.addSubview(skip)

    addTimeline(to: root, activeIndex: 2)  // 3rd segment for Connect
    return root
}
```

- [ ] **Step 8: Implement action methods**

```swift
@objc private func copyAndOpenTerminal() {
    let bridgePath = Bundle.main.bundlePath + "/Contents/MacOS/safari-mcp-bridge"
    let command = "\"\(bridgePath)\" --install --verify"

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)

    // Open Terminal
    let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }

    // Start polling for marker file
    startMarkerPolling()
}

@objc private func runInstallDirectly() {
    let bridgePath = Bundle.main.bundlePath + "/Contents/MacOS/safari-mcp-bridge"

    // Run on background queue to avoid blocking UI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bridgePath)
        process.arguments = ["--install", "--verify"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog("safari-mcp-bridge --install output: %@", output)

            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    // Success — advance after brief delay for user to see result
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.advance()
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Installation failed"
                    alert.informativeText = output
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        } catch {
            NSLog("Failed to run safari-mcp-bridge: %@", error.localizedDescription)
        }
    }
}

@objc private func skipConnect() { advance() }

private func startMarkerPolling() {
    // Show detecting row
    if let detectingRow = window?.contentView?.subviews.first(where: {
        $0.identifier == NSUserInterfaceItemIdentifier("connectDetecting")
    }) {
        detectingRow.isHidden = false
    }

    // Poll the marker file every 2 seconds
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
        guard let self, !self.dismissed else { return }
        guard case .connectClaude = self.currentScreen else { return }

        if let url = AppConstants.mcpConfigInstalledURL,
           FileManager.default.fileExists(atPath: url.path) {
            self.stopPolling()
            self.advance()
        }
    }
}
```

- [ ] **Step 9: Update the timeline to show 3 segments**

The current `addTimeline(to:root:activeIndex:)` draws 2 segments. Update it to handle the Connect step. Change the labels array and segment count:

```swift
private func addTimeline(to root: NSView, activeIndex: Int) {
    let labels = ["Safari Extension", "Screen Recording", "Connect"]
    let segCount = labels.count
    let segWidth = (Layout.windowWidth - Layout.padding * 2 - CGFloat(segCount - 1) * 5) / CGFloat(segCount)
    let barY: CGFloat = 14
    let labelY: CGFloat = 2

    for i in 0..<segCount {
        let x = Layout.padding + CGFloat(i) * (segWidth + 5)

        let bar = NSView(frame: NSRect(x: x, y: barY, width: segWidth, height: 3))
        bar.wantsLayer = true
        if i < activeIndex {
            bar.layer?.backgroundColor = NSColor.systemGreen.cgColor
        } else if i == activeIndex {
            bar.layer?.backgroundColor = NSColor.claudeOrange.cgColor
        } else {
            bar.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
        bar.layer?.cornerRadius = 1.5
        root.addSubview(bar)

        let lbl = NSTextField(labelWithString: i < activeIndex ? "✓ \(labels[i])" : labels[i])
        lbl.font = NSFont.systemFont(ofSize: 9, weight: i == activeIndex ? .semibold : .regular)
        lbl.textColor = i < activeIndex ? NSColor.systemGreen
                      : i == activeIndex ? .claudeOrange
                      : .tertiaryLabelColor
        lbl.frame = NSRect(x: x, y: labelY, width: segWidth, height: 11)
        root.addSubview(lbl)
    }
}
```

- [ ] **Step 10: Update `show(screen:)` for the `.connectClaude` case**

The connect step doesn't use permission polling — it uses marker file polling (started by the button action). Update the `show(screen:)` method to handle it:

```swift
private func show(screen: OnboardingScreen) {
    stopPolling()
    guard window != nil else {
        NSLog("OnboardingWindowController: show(screen:) called with nil window — content view not updated")
        return
    }
    currentScreen = screen
    window?.contentView = buildView(for: screen)
    if case .step(let step) = screen {
        if step == .screenRecording {
            monitor.registerScreenRecording()
        }
        startPolling(for: step)
    }
    // Note: .connectClaude polling starts when user clicks Install button, not on screen show
}
```

- [ ] **Step 11: Run tests to verify they pass**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: All tests pass, including the new onboarding tests

- [ ] **Step 12: Commit**

```
git add ClaudeInSafari/App/OnboardingWindowController.swift Tests/Swift/OnboardingWindowControllerTests.swift
git commit -m "feat(027): add 'Connect to Claude' onboarding step with dual-path install"
```

---

## Task 8: Add Menu Bar Integration

**Files:**
- Modify: `ClaudeInSafari/App/MenuBarController.swift`
- Modify: `ClaudeInSafari/App/AppDelegate.swift`
- Modify: `Tests/Swift/MenuBarControllerTests.swift`

- [ ] **Step 1: Add callbacks to MenuBarController**

Add new callback properties after the existing ones:

```swift
/// Callback invoked when user taps "Install Claude Integration".
var onInstallIntegration: (() -> Void)?

/// Callback invoked when user taps "Uninstall Claude Integration".
var onUninstallIntegration: (() -> Void)?
```

- [ ] **Step 2: Add menu items to `buildMenu()`**

In the `.connected` case of `buildMenu()`, after the "Open Safari" item, add:

```swift
menu.addItem(.separator())
menu.addItem(makeItem("Install Claude Integration", action: #selector(installIntegration), symbol: "🔗"))
menu.addItem(makeItem("Uninstall Claude Integration", action: #selector(uninstallIntegration), symbol: nil))
```

- [ ] **Step 3: Add action methods**

```swift
@objc private func installIntegration()   { onInstallIntegration?() }
@objc private func uninstallIntegration()  { onUninstallIntegration?() }
```

- [ ] **Step 4: Wire up callbacks in AppDelegate.setupMenuBar()**

Add to `setupMenuBar()` in AppDelegate:

```swift
controller.onInstallIntegration = { [weak self] in
    self?.runBridgeInstall()
}
controller.onUninstallIntegration = { [weak self] in
    self?.runBridgeUninstall()
}
```

- [ ] **Step 5: Implement bridge runner methods in AppDelegate**

```swift
// MARK: - Claude Integration

private func runBridgeInstall() {
    let bridgePath = Bundle.main.bundlePath + "/Contents/MacOS/safari-mcp-bridge"

    if isSandboxed {
        // Copy command to clipboard + open Terminal
        let command = "\"\(bridgePath)\" --install --verify"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error {
                NSLog("AppDelegate: failed to open Terminal — %@", error.localizedDescription)
            }
        }

        let alert = NSAlert()
        alert.messageText = "Install command copied"
        alert.informativeText = "Paste (⌘V) in Terminal and press Enter to configure Claude Code and Desktop."
        alert.alertStyle = .informational
        alert.runModal()
    } else {
        // Run directly — on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: bridgePath)
            process.arguments = ["--install", "--verify"]
            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    if process.terminationStatus == 0 {
                        alert.messageText = "Claude Integration installed"
                        alert.informativeText = output
                        alert.alertStyle = .informational
                    } else {
                        alert.messageText = "Installation failed"
                        alert.informativeText = output
                        alert.alertStyle = .warning
                    }
                    alert.runModal()
                }
            } catch {
                NSLog("AppDelegate: failed to run bridge — %@", error.localizedDescription)
            }
        }
    }
}

private func runBridgeUninstall() {
    let bridgePath = Bundle.main.bundlePath + "/Contents/MacOS/safari-mcp-bridge"

    if isSandboxed {
        let command = "\"\(bridgePath)\" --uninstall"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }

        let alert = NSAlert()
        alert.messageText = "Uninstall command copied"
        alert.informativeText = "Paste (⌘V) in Terminal and press Enter."
        alert.alertStyle = .informational
        alert.runModal()
    } else {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: bridgePath)
            process.arguments = ["--uninstall"]
            let pipe = Pipe()
            process.standardOutput = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Claude Integration removed"
                    alert.informativeText = output
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            } catch {
                NSLog("AppDelegate: failed to run bridge uninstall — %@", error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 6: Add path mismatch detection on app launch**

In `AppDelegate.applicationDidFinishLaunching`, after `checkAndShowOnboardingIfNeeded()`, add:

```swift
checkBridgePathMismatch()
```

And implement:

```swift
/// Checks if the installed MCP config points to a stale bridge path (e.g., user moved the app).
private func checkBridgePathMismatch() {
    guard let markerURL = AppConstants.mcpConfigInstalledURL,
          FileManager.default.fileExists(atPath: markerURL.path),
          let data = try? Data(contentsOf: markerURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let installedPath = json["bridge_path"] as? String else { return }

    let currentPath = Bundle.main.bundlePath + "/Contents/MacOS/safari-mcp-bridge"
    guard installedPath != currentPath else { return }

    // Path mismatch — app was moved since last install
    DispatchQueue.main.async { [weak self] in
        let alert = NSAlert()
        alert.messageText = "Claude Integration needs update"
        alert.informativeText = "The app was moved since the MCP config was installed. Update the config to keep Claude Code connected."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            self?.runBridgeInstall()
        }
    }
}
```

- [ ] **Step 7: Add menu bar test for new callbacks**

Add to `Tests/Swift/MenuBarControllerTests.swift`:

```swift
// T7 — onInstallIntegration callback is settable
func testOnInstallIntegration_callback() {
    let controller = MenuBarController()
    var called = false
    controller.onInstallIntegration = { called = true }
    controller.onInstallIntegration?()
    XCTAssertTrue(called)
}

// T8 — onUninstallIntegration callback is settable
func testOnUninstallIntegration_callback() {
    let controller = MenuBarController()
    var called = false
    controller.onUninstallIntegration = { called = true }
    controller.onUninstallIntegration?()
    XCTAssertTrue(called)
}
```

- [ ] **Step 8: Run tests**

Run: `xcodebuild test -project ClaudeInSafari.xcodeproj -scheme ClaudeInSafariTests -destination 'platform=macOS' -quiet 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 9: Commit**

```
git add ClaudeInSafari/App/MenuBarController.swift ClaudeInSafari/App/AppDelegate.swift Tests/Swift/MenuBarControllerTests.swift
git commit -m "feat(027): add Install/Uninstall Claude Integration to menu bar + path mismatch detection"
```

---

## Task 9: Add Makefile Targets and Update Docs

**Files:**
- Modify: `Makefile`
- Modify: `STRUCTURE.md`
- Modify: `README.md`

- [ ] **Step 1: Add Makefile targets**

Add after the existing `dmg` target:

```makefile
bridge: ## Build the safari-mcp-bridge CLI tool
	@xcodebuild build \
		-project $(PROJECT) \
		-scheme safari-mcp-bridge \
		-destination "$(DEST)" \
		-quiet
	@echo "Bridge built successfully"

bridge-install: bridge ## Build and run --install
	@BRIDGE=$$(find ~/Library/Developer/Xcode/DerivedData/ClaudeInSafari-*/Build/Products -name safari-mcp-bridge -type f 2>/dev/null | head -1); \
	if [ -n "$$BRIDGE" ]; then \
		"$$BRIDGE" --install --verify; \
	else \
		echo "ERROR: safari-mcp-bridge not found. Run 'make bridge' first."; \
		exit 1; \
	fi

bridge-status: ## Show bridge status
	@BRIDGE=$$(find ~/Library/Developer/Xcode/DerivedData/ClaudeInSafari-*/Build/Products -name safari-mcp-bridge -type f 2>/dev/null | head -1); \
	if [ -n "$$BRIDGE" ]; then \
		"$$BRIDGE" --status; \
	else \
		echo "ERROR: safari-mcp-bridge not found. Run 'make bridge' first."; \
		exit 1; \
	fi
```

- [ ] **Step 2: Update STRUCTURE.md**

Add the new target section after the existing Shared section:

```markdown
│   ├── safari-mcp-bridge/                  # CLI Bridge Target (embedded in app bundle)
│   │   ├── main.swift                     # Entry point: argument parsing, mode dispatch
│   │   ├── BridgeRelay.swift              # Socket discovery + stdin↔socket relay
│   │   ├── ConfigInstaller.swift          # MCP config read/merge/write for Claude Code + Desktop
│   │   └── StatusReporter.swift           # --status diagnostic output
```

- [ ] **Step 3: Update README.md setup instructions**

Add a "Setup" section that documents the install command:

```markdown
## Setup

1. Install the DMG or download from the Mac App Store
2. Launch Claude in Safari and complete the onboarding steps
3. When prompted, install the Claude integration:
   - **DMG**: Click "Install" — automatic
   - **App Store**: Click "Install", paste in Terminal, press Enter
4. Restart Claude Code or Claude Desktop

Manual install (if needed):
\`\`\`bash
"/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge" --install --verify
\`\`\`
```

- [ ] **Step 4: Commit**

```
git add Makefile STRUCTURE.md README.md
git commit -m "docs(027): update Makefile, STRUCTURE.md, and README with bridge setup"
```

---

## Task 10: End-to-End Verification

- [ ] **Step 1: Full build**

```bash
make clean
make build
```

Expected: Both main app and bridge binary build successfully

- [ ] **Step 2: Run all tests**

```bash
make test-all
```

Expected: All Swift and JS tests pass

- [ ] **Step 3: Launch app and test install flow**

```bash
make run
```

Then use the onboarding or menu bar to install. Verify:
- Config written to `~/.claude.json`
- Marker file exists in App Group container
- `make bridge-status` shows correct status

- [ ] **Step 4: Test bridge relay with running app**

```bash
make bridge-install
# Then in a new terminal:
echo '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}' | "/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge"
```

Expected: JSON response with server capabilities

- [ ] **Step 5: Test from Claude Code**

Open a new Claude Code session and verify that the Safari tools appear in the tool list. Try a simple command like navigating to a URL.

- [ ] **Step 6: Test uninstall**

```bash
"/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge" --uninstall
"/Applications/Claude in Safari.app/Contents/MacOS/safari-mcp-bridge" --status
```

Expected: Config entries removed, status shows no config installed

- [ ] **Step 7: Final commit**

```
git commit --allow-empty -m "feat(027): MCP client bridge complete — verified end-to-end"
```

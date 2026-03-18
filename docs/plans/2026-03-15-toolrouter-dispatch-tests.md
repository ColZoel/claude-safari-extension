# ToolRouter Dispatch Tests Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 7 missing tests that cover `ToolRouter`'s MCP protocol dispatch layer (`initialize`, `notifications/initialized`, `tools/list`, unknown method routing, non-JSON input, and client disconnect cleanup).

**Architecture:** All 7 tests live in a new `ToolRouterDispatchTests` class appended to `Tests/Swift/ToolRouterTests.swift`. They reuse the `MockMCPSocketServer` already defined at the top of that file. No new mocks, imports, or files required. These tests cover existing behavior — they should pass on first run.

**Tech Stack:** Swift / XCTest

---

## Chunk 1: ToolRouterDispatchTests class

### Task 1: Add `ToolRouterDispatchTests` to `ToolRouterTests.swift`

**Files:**
- Modify: `Tests/Swift/ToolRouterTests.swift` (append after the final `}` of `MockCaptureProviderForGif`)

- [ ] **Step 1: Append the new test class**

  Add the following block at the very end of `Tests/Swift/ToolRouterTests.swift`:

  ```swift
  // MARK: - ToolRouterDispatchTests

  /// Tests for ToolRouter's MCP protocol dispatch layer.
  /// Covers initialize, notifications/initialized, tools/list,
  /// unknown method routing, non-JSON input, and client disconnect cleanup.
  final class ToolRouterDispatchTests: XCTestCase {

      private var router: ToolRouter!
      private var server: MockMCPSocketServer!

      override func setUp() {
          super.setUp()
          server = MockMCPSocketServer()
          router = ToolRouter(
              screenshotService: ScreenshotService(),
              gifService: GifService(),
              fileService: FileService()
          )
          router.setServer(server)
      }

      // T_dispatch1 — initialize returns correct MCP handshake fields
      func testInitialize_returnsProtocolVersionAndServerInfo() {
          let data = try! JSONSerialization.data(withJSONObject: [
              "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]
          ])
          router.socketServer(server, didReceiveMessage: data, from: "client-1")

          let json = server.lastSentJSON()
          let result = json?["result"] as? [String: Any]
          XCTAssertNotNil(result, "initialize must return a result")
          XCTAssertEqual(result?["protocolVersion"] as? String, "2025-11-25")
          let serverInfo = result?["serverInfo"] as? [String: Any]
          XCTAssertEqual(serverInfo?["name"] as? String, "claude-safari")
          XCTAssertNotNil(result?["capabilities"], "capabilities key must be present")
      }

      // T_dispatch2 — notifications/initialized is a no-op (no response sent)
      func testNotificationsInitialized_sendsNoResponse() {
          let data = try! JSONSerialization.data(withJSONObject: [
              "jsonrpc": "2.0", "method": "notifications/initialized"
          ])
          router.socketServer(server, didReceiveMessage: data, from: "client-1")

          XCTAssertTrue(server.sentData.isEmpty,
                        "notifications/initialized is a notification — no response should be sent")
      }

      // T_dispatch3 — tools/list returns a non-empty tools array
      func testToolsList_returnsNonEmptyToolsArray() {
          let data = try! JSONSerialization.data(withJSONObject: [
              "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:]
          ])
          router.socketServer(server, didReceiveMessage: data, from: "client-1")

          let json = server.lastSentJSON()
          let result = json?["result"] as? [String: Any]
          let tools = result?["tools"] as? [[String: Any]]
          XCTAssertNotNil(tools, "tools/list must return a result.tools array")
          XCTAssertFalse(tools!.isEmpty, "tools array must not be empty")
      }

      // T_dispatch4 — unknown method with id sends -32601 Method Not Found
      func testUnknownMethod_withId_sendsMethodNotFoundError() {
          let data = try! JSONSerialization.data(withJSONObject: [
              "jsonrpc": "2.0", "id": 3, "method": "widgets/frobnicate", "params": [:]
          ])
          router.socketServer(server, didReceiveMessage: data, from: "client-1")

          let json = server.lastSentJSON()
          let error = json?["error"] as? [String: Any]
          XCTAssertNotNil(error, "Unknown method with id must produce an error response")
          XCTAssertEqual(error?["code"] as? Int, -32601)
          let message = error?["message"] as? String ?? ""
          XCTAssertTrue(message.contains("widgets/frobnicate"),
                        "Error message must include the unknown method name: \(message)")
      }

      // T_dispatch5 — unknown method without id is silent (JSON-RPC notification)
      func testUnknownMethod_withoutId_sendsNoResponse() {
          let data = try! JSONSerialization.data(withJSONObject: [
              "jsonrpc": "2.0", "method": "widgets/frobnicate"
              // no "id" key — this is a JSON-RPC notification, must not be responded to
          ])
          router.socketServer(server, didReceiveMessage: data, from: "client-1")

          XCTAssertTrue(server.sentData.isEmpty,
                        "Unknown method without id must not send any response")
      }

      // T_dispatch6 — non-JSON-RPC data is silently dropped (no crash, no response)
      func testNonJSONData_noCrashNoResponse() {
          let data = "not json at all".data(using: .utf8)!
          router.socketServer(server, didReceiveMessage: data, from: "client-1")

          XCTAssertTrue(server.sentData.isEmpty,
                        "Malformed non-JSON data must be silently dropped")
      }

      // T_disconnect1 — didDisconnect cleans up pending requests for the disconnected client
      // and leaves pending requests for other clients untouched.
      func testDidDisconnect_cleansPendingRequestsForClient() {
          // req-A belongs to the client that will disconnect; req-B belongs to another client.
          router.injectPendingRequest(requestId: "req-A", clientId: "client-disc", jsonrpcId: 10)
          router.injectPendingRequest(requestId: "req-B", clientId: "client-other", jsonrpcId: 11)

          // Simulate client-disc disconnecting — req-A is removed silently (client already gone).
          router.socketServer(server, didDisconnect: "client-disc")

          // req-A is no longer in pendingRequests; cancelCurrentRequest only sees req-B.
          router.cancelCurrentRequest()

          // Exactly one error response is sent: for req-B (client-other). req-A produced no send.
          XCTAssertEqual(server.sentData.count, 1,
                         "Only req-B cancellation response should be sent — req-A was cleaned up silently by didDisconnect")
          let json = server.lastSentJSON()
          let error = json?["error"] as? [String: Any]
          let message = error?["message"] as? String ?? ""
          XCTAssertTrue(message.contains("Cancelled"),
                        "req-B (client-other) should still be pending and cancellable: \(message)")
      }
  }
  ```

- [ ] **Step 2: Run the Swift test suite**

  ```fish
  make test-swift
  ```

  Expected: all existing tests pass plus 7 new ones. No implementation changes are needed — these tests cover existing behavior.

- [ ] **Step 3: Commit**

  ```fish
  echo "test(router): add ToolRouterDispatchTests — MCP protocol dispatch coverage

  Covers initialize handshake, notifications/initialized no-op, tools/list,
  unknown method routing (-32601), non-JSON input, and client disconnect
  cleanup. Seven new tests, all exercise existing behavior.

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" > /tmp/commitmsg
  git add "Tests/Swift/ToolRouterTests.swift"
  git commit -F /tmp/commitmsg
  ```

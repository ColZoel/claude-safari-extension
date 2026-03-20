import XCTest
@testable import ClaudeInSafari

final class BridgeRelayTests: XCTestCase {

    func testFindNewestSocket_returnsNewestByMtime() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let older = tmpDir.appendingPathComponent("111.sock")
        let newer = tmpDir.appendingPathComponent("222.sock")
        FileManager.default.createFile(atPath: older.path, contents: nil)
        sleep(1)
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

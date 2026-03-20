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

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
        let fakeBookmark = Data([0x01, 0x02, 0x03])
        manager.storeBookmark(fakeBookmark, for: "/Users/test")
        XCTAssertNotNil(defaults.data(forKey: "FileAccessBookmark:/Users/test"))
    }

    func testNeedsAccessPromptReturnsTrueForUnbookmarkedPath() {
        let manager = FileAccessManager(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        XCTAssertTrue(manager.needsAccessPrompt(for: "/Users/test/file.txt"))
    }

    func testHasAccessReturnsTrueAfterStoringBookmark() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let manager = FileAccessManager(defaults: defaults)
        manager.storeBookmark(Data([0x01]), for: "/Users/test")
        XCTAssertTrue(manager.hasAccess(to: "/Users/test/file.txt"))
    }

    func testHasAccessReturnsFalseForDifferentDirectory() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let manager = FileAccessManager(defaults: defaults)
        manager.storeBookmark(Data([0x01]), for: "/Users/test")
        XCTAssertFalse(manager.hasAccess(to: "/Users/other/file.txt"))
    }

    func testBookmarkDirectoryMatchesSubdirectories() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let manager = FileAccessManager(defaults: defaults)
        manager.storeBookmark(Data([0x01]), for: "/Users/test")
        XCTAssertTrue(manager.hasAccess(to: "/Users/test/deep/nested/file.txt"))
    }

    func testHasAccessReturnsFalseForPrefixCollision() {
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let manager = FileAccessManager(defaults: defaults)
        manager.storeBookmark(Data([0x01]), for: "/Users/test")
        XCTAssertFalse(manager.hasAccess(to: "/Users/testing/secret.txt"))
    }

    func testResolveAccessReturnsNilWithNoBookmark() {
        let manager = FileAccessManager(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        XCTAssertNil(manager.resolveAccess(for: "/Users/test/file.txt"))
    }
}

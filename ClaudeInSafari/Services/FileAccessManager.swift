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
        panel.message = "\(AppConstants.appDisplayName) needs access to read files for upload. Please select the folder containing your files."
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
    /// Returns the resolved URL, or nil if resolution fails.
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
        for key in defaults.dictionaryRepresentation().keys {
            guard key.hasPrefix(Self.bookmarkKeyPrefix) else { continue }
            let dir = String(key.dropFirst(Self.bookmarkKeyPrefix.count))
            let normalizedDir = dir.hasSuffix("/") ? dir : dir + "/"
            if path.hasPrefix(normalizedDir) || path == dir { return dir }
        }
        return nil
    }
}

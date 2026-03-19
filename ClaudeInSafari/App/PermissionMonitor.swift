// ClaudeInSafari/App/PermissionMonitor.swift
import Foundation
import CoreGraphics
import SafariServices

// MARK: - OnboardingStep

/// The two permission steps in setup order.
enum OnboardingStep: Equatable {
    case safariExtension
    case screenRecording
}

// MARK: - PermissionStatus

struct PermissionStatus {
    let extensionEnabled: Bool
    let screenRecording: Bool

    var allGranted: Bool {
        extensionEnabled && screenRecording
    }

    /// Returns the first step not yet complete, in setup order.
    var firstIncompleteStep: OnboardingStep? {
        if !extensionEnabled { return .safariExtension }
        if !screenRecording  { return .screenRecording }
        return nil
    }
}

// MARK: - PermissionChecking protocol

protocol PermissionChecking {
    func isScreenRecordingGranted() -> Bool
    /// Completion may be called on any queue.
    /// `PermissionMonitor.checkAll` re-dispatches to the main queue before invoking its own
    /// completion, so callers of `checkAll` do not need to add their own dispatch.
    /// Direct callers of this protocol method are responsible for their own queue management.
    func getExtensionEnabled(completion: @escaping (Bool) -> Void)

    /// Silently registers the app in TCC for Screen Recording (no dialog on macOS 14+).
    /// Call on step entry so the app appears in System Settings before the user navigates there.
    func registerScreenRecording()
}

// MARK: - SystemPermissionChecker

/// Production implementation that calls real macOS APIs.
struct SystemPermissionChecker: PermissionChecking {
    private static let extensionBundleID = "com.chriscantu.claudeinsafari.extension"

    func isScreenRecordingGranted() -> Bool {
        // Silent check — no UI, no side effects. Used for the 0.5 s polling loop.
        CGPreflightScreenCaptureAccess()
    }

    func getExtensionEnabled(completion: @escaping (Bool) -> Void) {
        SFSafariExtensionManager.getStateOfSafariExtension(
            withIdentifier: Self.extensionBundleID
        ) { state, error in
            if let error = error {
                NSLog("PermissionMonitor: SFSafariExtensionManager query failed: %@", error.localizedDescription)
            }
            completion(state?.isEnabled ?? false)
        }
    }

    func registerScreenRecording() {
        // Registers in TCC so the app appears in System Settings → Screen Recording.
        // No dialog on macOS 14+; returns Bool (ignored here).
        CGRequestScreenCaptureAccess()
    }
}

// MARK: - PermissionMonitor

/// Checks permission state and delivers `PermissionStatus` on the main queue.
/// Must be called from the main thread. Not thread-safe for concurrent callers.
final class PermissionMonitor {
    private let checker: PermissionChecking

    /// Debounce state for `extensionEnabled`. SFSafariExtensionManager can flicker
    /// between true/false on rapid polls; we require two consecutive identical results
    /// before changing the reported value.
    private var lastExtensionEnabled: Bool?
    private var pendingExtensionEnabled: Bool?

    init(checker: PermissionChecking = SystemPermissionChecker()) {
        self.checker = checker
    }

    /// Silently registers the app in TCC for Screen Recording (no dialog).
    /// Call on step entry so the app appears in System Settings.
    func registerScreenRecording() {
        checker.registerScreenRecording()
    }

    /// One-shot check of all permissions. Delivers `PermissionStatus` on the main queue.
    func checkAll(completion: @escaping (PermissionStatus) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let screenRecording = checker.isScreenRecordingGranted()
        checker.getExtensionEnabled { [weak self] extensionEnabled in
            DispatchQueue.main.async {
                guard let self else {
                    // Self deallocated — deliver a safe default so callers are never left hanging.
                    NSLog("PermissionMonitor: deallocated during checkAll — delivering empty status")
                    completion(PermissionStatus(extensionEnabled: false, screenRecording: false))
                    return
                }
                // Debounce: only adopt a new value after two consecutive identical reads.
                let stable: Bool
                if extensionEnabled == self.pendingExtensionEnabled {
                    // Two consecutive reads agree — adopt this value.
                    self.lastExtensionEnabled = extensionEnabled
                    stable = extensionEnabled
                } else {
                    // First read of a new value — buffer it but keep the old value.
                    self.pendingExtensionEnabled = extensionEnabled
                    stable = self.lastExtensionEnabled ?? extensionEnabled
                }

                let status = PermissionStatus(
                    extensionEnabled: stable,
                    screenRecording: screenRecording
                )
                completion(status)
            }
        }
    }
}

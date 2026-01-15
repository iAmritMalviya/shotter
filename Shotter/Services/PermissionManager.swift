import Foundation
import ScreenCaptureKit
import Combine
import AppKit

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var authorizationStatus: AuthorizationStatus = .unknown

    enum AuthorizationStatus {
        case unknown
        case authorized
        case denied
        case restricted
    }

    private init() {
        Task {
            await checkPermission()
        }
    }

    /// Checks current screen recording permission status
    func checkPermission() async {
        do {
            // Attempting to get shareable content will prompt for permission if needed
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            // If we get here without error, we have permission
            isAuthorized = !content.displays.isEmpty
            authorizationStatus = isAuthorized ? .authorized : .denied
        } catch {
            // Error usually means permission denied
            isAuthorized = false
            authorizationStatus = .denied
            print("PermissionManager: Screen capture permission check failed - \(error)")
        }
    }

    /// Requests screen recording permission
    /// On modern macOS, this triggers the system permission dialog
    func requestPermission() async {
        // Trigger permission prompt by attempting to access content
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // Permission was denied or error occurred
        }

        // Re-check permission status
        await checkPermission()
    }

    /// Opens System Settings to the Screen Recording privacy pane
    func openSystemSettings() {
        let url: URL
        if #available(macOS 13.0, *) {
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        } else {
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording")!
        }
        NSWorkspace.shared.open(url)
    }
}

import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var hotkeyManager: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Initialize managers
        hotkeyManager = HotkeyManager()
        menuBarController = MenuBarController()

        // Register global hotkeys
        registerHotkeys()

        // Check permissions on launch
        Task {
            await PermissionManager.shared.checkPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unregister hotkeys
        hotkeyManager.unregisterAll()
    }

    private func registerHotkeys() {
        // Register full screen hotkey
        hotkeyManager.register(
            config: hotkeyManager.fullScreenHotkey,
            for: .fullScreen
        ) { [weak self] in
            self?.menuBarController.captureFullScreen()
        }

        // Register region hotkey
        hotkeyManager.register(
            config: hotkeyManager.regionHotkey,
            for: .region
        ) { [weak self] in
            self?.menuBarController.captureRegion()
        }

        // Register window hotkey
        hotkeyManager.register(
            config: hotkeyManager.windowHotkey,
            for: .window
        ) { [weak self] in
            self?.menuBarController.captureWindowMenu()
        }
    }
}

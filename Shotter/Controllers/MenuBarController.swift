import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private let captureService = ScreenCaptureService.shared
    private let clipboardManager = ClipboardManager.shared
    private let permissionManager = PermissionManager.shared

    private var regionSelectionWindow: RegionSelectionWindow?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupStatusItem()
        setupMenu()
        observePermissions()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use SF Symbol for menu bar icon
            if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotter") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "S"
            }
        }

        statusItem.menu = menu
    }

    private func setupMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        // Capture options
        let fullScreenItem = NSMenuItem(
            title: "Capture Full Screen",
            action: #selector(captureFullScreen),
            keyEquivalent: "3"
        )
        fullScreenItem.target = self
        fullScreenItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(fullScreenItem)

        let regionItem = NSMenuItem(
            title: "Capture Region",
            action: #selector(captureRegion),
            keyEquivalent: "4"
        )
        regionItem.target = self
        regionItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(regionItem)

        let windowItem = NSMenuItem(
            title: "Capture Window",
            action: #selector(captureWindowMenu),
            keyEquivalent: "5"
        )
        windowItem.target = self
        windowItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // Permission status item (hidden when authorized)
        let permissionItem = NSMenuItem(
            title: "Grant Screen Recording Permission",
            action: #selector(openPermissions),
            keyEquivalent: ""
        )
        permissionItem.target = self
        permissionItem.tag = 100
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Shotter",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func observePermissions() {
        permissionManager.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthorized in
                self?.updateMenuForPermissionStatus(isAuthorized)
            }
            .store(in: &cancellables)
    }

    private func updateMenuForPermissionStatus(_ isAuthorized: Bool) {
        guard let permissionItem = menu.item(withTag: 100) else { return }
        permissionItem.isHidden = isAuthorized

        // Enable/disable capture items
        for item in menu.items {
            if item.action == #selector(captureFullScreen) ||
               item.action == #selector(captureRegion) ||
               item.action == #selector(captureWindowMenu) {
                item.isEnabled = isAuthorized
            }
        }
    }

    // MARK: - Actions

    @objc func captureFullScreen() {
        Task {
            do {
                let image = try await captureService.captureFullScreen()
                clipboardManager.copy(image: image)
                showSuccessFeedback()
            } catch {
                showErrorAlert(error)
            }
        }
    }

    @objc func captureRegion() {
        regionSelectionWindow = RegionSelectionWindow()
        regionSelectionWindow?.beginSelection { [weak self] rect in
            guard let self = self, let rect = rect else { return }

            Task {
                do {
                    let image = try await self.captureService.captureRegion(rect)
                    self.clipboardManager.copy(image: image)
                    self.showSuccessFeedback()
                } catch {
                    self.showErrorAlert(error)
                }
            }
        }
    }

    @objc func captureWindowMenu() {
        Task {
            let windows = await captureService.getWindowList()

            await MainActor.run {
                let windowMenu = NSMenu()

                if windows.isEmpty {
                    let noWindowsItem = NSMenuItem(title: "No windows available", action: nil, keyEquivalent: "")
                    noWindowsItem.isEnabled = false
                    windowMenu.addItem(noWindowsItem)
                } else {
                    for (id, title, app) in windows {
                        let displayTitle = title.isEmpty ? app : "\(app): \(title)"
                        let item = NSMenuItem(
                            title: displayTitle,
                            action: #selector(captureSelectedWindow(_:)),
                            keyEquivalent: ""
                        )
                        item.target = self
                        item.representedObject = id
                        windowMenu.addItem(item)
                    }
                }

                // Show as popup
                if let button = statusItem.button {
                    windowMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
                }
            }
        }
    }

    @objc private func captureSelectedWindow(_ sender: NSMenuItem) {
        guard let windowID = sender.representedObject as? CGWindowID else { return }

        Task {
            do {
                let image = try await captureService.captureWindow(windowID)
                clipboardManager.copy(image: image)
                showSuccessFeedback()
            } catch {
                showErrorAlert(error)
            }
        }
    }

    @objc private func openPermissions() {
        permissionManager.openSystemSettings()
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Feedback

    private func showSuccessFeedback() {
        // Play sound
        if UserDefaults.standard.bool(forKey: "playSoundOnCapture") != false {
            NSSound(named: "Pop")?.play()
        }

        // Show notification
        if UserDefaults.standard.bool(forKey: "showNotification") != false {
            let content = UNMutableNotificationContent()
            content.title = "Screenshot Captured"
            content.body = "Image copied to clipboard"

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    private func showErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if let captureError = error as? CaptureError,
           captureError == .permissionDenied {
            alert.addButton(withTitle: "Open Settings")
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            permissionManager.openSystemSettings()
        }
    }
}

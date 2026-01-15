import Foundation
import Carbon.HIToolbox
import AppKit

// MARK: - Global Callback Context

private var hotkeyManagerInstance: HotkeyManager?

enum HotkeyAction: Int {
    case fullScreen = 1
    case region = 2
    case window = 3
}

@MainActor
final class HotkeyManager: ObservableObject {
    // Published properties for UI binding
    @Published var fullScreenHotkey: HotkeyConfiguration
    @Published var regionHotkey: HotkeyConfiguration
    @Published var windowHotkey: HotkeyConfiguration

    // Carbon hotkey references
    private var fullScreenHotKeyRef: EventHotKeyRef?
    private var regionHotKeyRef: EventHotKeyRef?
    private var windowHotKeyRef: EventHotKeyRef?

    // Action callbacks
    private var actions: [HotkeyAction: () -> Void] = [:]

    // Event handler reference
    private var eventHandlerRef: EventHandlerRef?

    init() {
        // Load saved or use defaults
        fullScreenHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.fullScreenKey,
            default: .fullScreen
        )
        regionHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.regionKey,
            default: .region
        )
        windowHotkey = HotkeyConfiguration.load(
            for: HotkeyConfiguration.windowKey,
            default: .window
        )

        // Store instance for C callback
        hotkeyManagerInstance = self

        // Install event handler
        installEventHandler()
    }

    deinit {
        hotkeyManagerInstance = nil
    }

    // MARK: - Event Handler Installation

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let error = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard error == noErr else { return error }

                // Dispatch to main thread
                DispatchQueue.main.async {
                    hotkeyManagerInstance?.handleHotkey(id: Int(hotKeyID.id))
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            print("HotkeyManager: Failed to install event handler, error: \(status)")
        }
    }

    private func removeEventHandler() {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    // MARK: - Hotkey Handling

    private func handleHotkey(id: Int) {
        guard let action = HotkeyAction(rawValue: id),
              let callback = actions[action] else {
            return
        }
        callback()
    }

    // MARK: - Registration

    func register(
        config: HotkeyConfiguration,
        for action: HotkeyAction,
        handler: @escaping () -> Void
    ) {
        // Store callback
        actions[action] = handler

        // Create hotkey ID
        var hotKeyID = EventHotKeyID(
            signature: OSType(0x5348_5452), // 'SHTR' in hex
            id: UInt32(action.rawValue)
        )

        // Register the hotkey
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            print("HotkeyManager: Failed to register \(action), error: \(status)")
            return
        }

        // Store reference for unregistration
        switch action {
        case .fullScreen:
            fullScreenHotKeyRef = hotKeyRef
        case .region:
            regionHotKeyRef = hotKeyRef
        case .window:
            windowHotKeyRef = hotKeyRef
        }

        print("HotkeyManager: Registered \(action) with \(config.displayString)")
    }

    func unregister(_ action: HotkeyAction) {
        let ref: EventHotKeyRef?

        switch action {
        case .fullScreen:
            ref = fullScreenHotKeyRef
            fullScreenHotKeyRef = nil
        case .region:
            ref = regionHotKeyRef
            regionHotKeyRef = nil
        case .window:
            ref = windowHotKeyRef
            windowHotKeyRef = nil
        }

        if let ref = ref {
            UnregisterEventHotKey(ref)
        }

        actions[action] = nil
    }

    func unregisterAll() {
        unregister(.fullScreen)
        unregister(.region)
        unregister(.window)
        removeEventHandler()
    }

    // MARK: - Update Hotkeys

    func updateHotkey(for action: HotkeyAction, config: HotkeyConfiguration) {
        // Store current callback
        let callback = actions[action]

        // Unregister current
        unregister(action)

        // Save new config
        switch action {
        case .fullScreen:
            config.save(for: HotkeyConfiguration.fullScreenKey)
            fullScreenHotkey = config
        case .region:
            config.save(for: HotkeyConfiguration.regionKey)
            regionHotkey = config
        case .window:
            config.save(for: HotkeyConfiguration.windowKey)
            windowHotkey = config
        }

        // Re-register with new config
        if let callback = callback {
            register(config: config, for: action, handler: callback)
        }
    }
}

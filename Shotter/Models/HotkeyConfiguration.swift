import Foundation
import Carbon.HIToolbox

struct HotkeyConfiguration: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    // Default hotkeys
    static let fullScreen = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_3),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let region = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_4),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let window = HotkeyConfiguration(
        keyCode: UInt32(kVK_ANSI_5),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }

        let keyChar = Self.keyCodeToString(keyCode)
        parts.append(keyChar)

        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Z): "Z",
        ]
        return keyMap[keyCode] ?? "?"
    }
}

// MARK: - UserDefaults Storage

extension HotkeyConfiguration {
    static let fullScreenKey = "hotkey.fullScreen"
    static let regionKey = "hotkey.region"
    static let windowKey = "hotkey.window"

    static func load(for key: String, default defaultValue: HotkeyConfiguration) -> HotkeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
            return defaultValue
        }
        return config
    }

    func save(for key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

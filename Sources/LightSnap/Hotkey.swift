import AppKit
import Carbon.HIToolbox

/// A user-configurable global shortcut: Carbon virtual key code + modifiers,
/// plus the display character captured when it was recorded.
struct Hotkey: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var character: String

    static let defaultArea = Hotkey(
        keyCode: UInt32(kVK_ANSI_9),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        character: "9"
    )
    static let defaultFullScreen = Hotkey(
        keyCode: UInt32(kVK_ANSI_9),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey),
        character: "9"
    )

    func hasSameCombo(as other: Hotkey) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + character
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// Lowercase single-character key equivalent for menu display, when the
    /// key is representable there (letters, digits, punctuation).
    var menuKeyEquivalent: String? {
        guard character.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.isASCII
        else { return nil }
        return character.lowercased()
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
             kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
             kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            return true
        default:
            return false
        }
    }

    static func specialKeyName(for keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_ANSI_KeypadEnter: return "⌤"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return nil
        }
    }
}

/// Owns the app's global hotkey registrations and re-registers them whenever
/// the configured shortcuts change. `suspend()` frees the combos while the
/// Settings recorder is capturing keystrokes.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private let manager = HotkeyManager()
    private(set) var areaRegistered = true
    private(set) var fullScreenRegistered = true

    private init() {}

    func reload() {
        manager.unregisterAll()

        let area = Prefs.areaHotkey
        areaRegistered = manager.register(keyCode: area.keyCode, modifiers: area.carbonModifiers) {
            Task { @MainActor in
                CaptureController.shared.beginCapture(mode: .area)
            }
        }

        let fullScreen = Prefs.fullScreenHotkey
        fullScreenRegistered = manager.register(keyCode: fullScreen.keyCode, modifiers: fullScreen.carbonModifiers) {
            Task { @MainActor in
                CaptureController.shared.beginCapture(mode: .fullScreen)
            }
        }
    }

    func suspend() {
        manager.unregisterAll()
    }

    func resume() {
        reload()
    }
}

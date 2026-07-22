import AppKit

enum ImageFormat: String, CaseIterable {
    case png
    case jpeg

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }
}

/// What happens right after an area is selected.
enum PostSelectionAction: String, CaseIterable {
    case edit
    case copy
    case save

    var displayName: String {
        switch self {
        case .edit: return "Show editing tools"
        case .copy: return "Copy to clipboard immediately"
        case .save: return "Save to folder immediately"
        }
    }
}

enum Prefs {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let saveDirectory = "saveDirectory"
        static let showsCursor = "showsCursor"
        static let imageFormat = "imageFormat"
        static let areaHotkey = "areaHotkey"
        static let fullScreenHotkey = "fullScreenHotkey"
        static let postSelectionAction = "postSelectionAction"
    }

    static var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.saveDirectory) {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set {
            defaults.set(newValue.path, forKey: Key.saveDirectory)
        }
    }

    static var showsCursor: Bool {
        get { defaults.bool(forKey: Key.showsCursor) }
        set { defaults.set(newValue, forKey: Key.showsCursor) }
    }

    static var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: Key.imageFormat) ?? "") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: Key.imageFormat) }
    }

    static var postSelectionAction: PostSelectionAction {
        get { PostSelectionAction(rawValue: defaults.string(forKey: Key.postSelectionAction) ?? "") ?? .edit }
        set { defaults.set(newValue.rawValue, forKey: Key.postSelectionAction) }
    }

    static var areaHotkey: Hotkey {
        get { hotkey(forKey: Key.areaHotkey) ?? .defaultArea }
        set { setHotkey(newValue, forKey: Key.areaHotkey) }
    }

    static var fullScreenHotkey: Hotkey {
        get { hotkey(forKey: Key.fullScreenHotkey) ?? .defaultFullScreen }
        set { setHotkey(newValue, forKey: Key.fullScreenHotkey) }
    }

    private static func hotkey(forKey key: String) -> Hotkey? {
        guard let dict = defaults.dictionary(forKey: key),
              let keyCode = dict["keyCode"] as? Int,
              let modifiers = dict["modifiers"] as? Int,
              let character = dict["character"] as? String
        else { return nil }
        return Hotkey(
            keyCode: UInt32(truncatingIfNeeded: keyCode),
            carbonModifiers: UInt32(truncatingIfNeeded: modifiers),
            character: character
        )
    }

    private static func setHotkey(_ hotkey: Hotkey, forKey key: String) {
        let dict: [String: Any] = [
            "keyCode": Int(hotkey.keyCode),
            "modifiers": Int(hotkey.carbonModifiers),
            "character": hotkey.character,
        ]
        defaults.set(dict, forKey: key)
    }
}

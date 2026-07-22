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

enum Prefs {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let saveDirectory = "saveDirectory"
        static let showsCursor = "showsCursor"
        static let imageFormat = "imageFormat"
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
}

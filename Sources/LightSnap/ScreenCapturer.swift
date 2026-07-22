import AppKit
import ScreenCaptureKit

struct DisplayCapture {
    let screen: NSScreen
    let image: CGImage
}

enum CaptureError: LocalizedError {
    case noDisplays

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            return "No displays could be captured."
        }
    }
}

enum ScreenCapturer {
    /// Takes a full-resolution screenshot of every connected display using
    /// ScreenCaptureKit (SCScreenshotManager, macOS 14+).
    @MainActor
    static func captureAllDisplays() async throws -> [DisplayCapture] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var captures: [DisplayCapture] = []

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let scDisplay = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            let scale = screen.backingScaleFactor
            let configuration = SCStreamConfiguration()
            configuration.width = Int(CGFloat(scDisplay.width) * scale)
            configuration.height = Int(CGFloat(scDisplay.height) * scale)
            configuration.showsCursor = Prefs.showsCursor
            configuration.captureResolution = .best

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            captures.append(DisplayCapture(screen: screen, image: image))
        }

        guard !captures.isEmpty else { throw CaptureError.noDisplays }
        return captures
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}

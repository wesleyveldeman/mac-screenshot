import AppKit
import UniformTypeIdentifiers

@MainActor
enum OutputActions {
    static func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    /// Save with a file dialog (⌘S / toolbar save button).
    static func promptAndSave(_ image: NSImage) {
        let format = Prefs.imageFormat
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFilename(fileExtension: format.fileExtension)
        panel.allowedContentTypes = [format == .png ? UTType.png : UTType.jpeg]
        panel.directoryURL = Prefs.saveDirectory
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            write(image, to: url, format: format)
            Prefs.saveDirectory = url.deletingLastPathComponent()
        }
    }

    /// Save straight into the configured screenshots folder (⇧⌘S).
    @discardableResult
    static func quickSave(_ image: NSImage) -> URL? {
        let format = Prefs.imageFormat
        let directory = Prefs.saveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(defaultFilename(fileExtension: format.fileExtension))
        write(image, to: url, format: format)
        return url
    }

    static func printImage(_ image: NSImage) {
        let view = NSImageView(frame: CGRect(origin: .zero, size: image.size))
        view.image = image
        view.imageScaling = .scaleProportionallyDown

        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.orientation = image.size.width > image.size.height ? .landscape : .portrait

        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        NSApp.activate(ignoringOtherApps: true)
        operation.run()
    }

    static func defaultFilename(fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).\(fileExtension)"
    }

    static func encode(_ image: NSImage, format: ImageFormat) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        // Preserve the point size so Retina captures carry 144 dpi metadata.
        rep.size = image.size
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }

    private static func write(_ image: NSImage, to url: URL, format: ImageFormat) {
        guard let data = encode(image, format: format) else { return }
        do {
            try data.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save screenshot"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

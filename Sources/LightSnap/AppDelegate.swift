import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var preferencesWindow: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        HotkeyCenter.shared.reload()

        // Prime the Screen Recording permission prompt on first launch so the
        // app shows up in System Settings before the user tries to capture.
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "LightSnap")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "LightSnap — click to capture an area, right-click for menu"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            showMenu()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            CaptureController.shared.beginCapture(mode: .area)
        }
    }

    private func showMenu() {
        guard let item = statusItem else { return }
        item.menu = buildMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let area = NSMenuItem(title: "Capture Area", action: #selector(captureArea), keyEquivalent: "")
        applyKeyEquivalent(Prefs.areaHotkey, to: area)
        area.target = self
        menu.addItem(area)

        let full = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        applyKeyEquivalent(Prefs.fullScreenHotkey, to: full)
        full.target = self
        menu.addItem(full)

        menu.addItem(.separator())

        let folder = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        let prefs = NSMenuItem(title: "Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About LightSnap", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem(title: "Quit LightSnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    // MARK: - Actions

    @objc private func captureArea() {
        CaptureController.shared.beginCapture(mode: .area)
    }

    @objc private func captureFullScreen() {
        CaptureController.shared.beginCapture(mode: .fullScreen)
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(Prefs.saveDirectory)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
        }
        preferencesWindow?.show()
    }

    private func applyKeyEquivalent(_ hotkey: Hotkey, to item: NSMenuItem) {
        guard let keyEquivalent = hotkey.menuKeyEquivalent else { return }
        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = hotkey.cocoaModifiers
    }
}

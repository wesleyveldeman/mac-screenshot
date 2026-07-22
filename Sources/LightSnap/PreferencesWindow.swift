import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController {
    private var pathLabel: NSTextField!
    private var formatPopup: NSPopUpButton!
    private var cursorCheckbox: NSButton!
    private var loginCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LightSnap Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildContent()
        window.center()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        pathLabel = NSTextField(labelWithString: "")
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.preferredMaxLayoutWidth = 240
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))

        let pathRow = NSStackView(views: [pathLabel, chooseButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8

        formatPopup = NSPopUpButton()
        for format in ImageFormat.allCases {
            formatPopup.addItem(withTitle: format.displayName)
        }
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)

        cursorCheckbox = NSButton(
            checkboxWithTitle: "Include mouse cursor in screenshots",
            target: self,
            action: #selector(cursorToggled)
        )
        loginCheckbox = NSButton(
            checkboxWithTitle: "Launch LightSnap at login",
            target: self,
            action: #selector(loginToggled)
        )

        let hotkeyLabel = NSTextField(labelWithString: "⇧⌘9  capture area        ⌥⇧⌘9  capture full screen")
        hotkeyLabel.textColor = .secondaryLabelColor
        hotkeyLabel.font = .systemFont(ofSize: 12)

        let grid = NSGridView(views: [
            [label("Save to:"), pathRow],
            [label("Format:"), formatPopup],
            [NSGridCell.emptyContentView, cursorCheckbox],
            [NSGridCell.emptyContentView, loginCheckbox],
            [label("Shortcuts:"), hotkeyLabel],
        ])
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    private func label(_ string: String) -> NSTextField {
        NSTextField(labelWithString: string)
    }

    private func refresh() {
        pathLabel.stringValue = Prefs.saveDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        formatPopup.selectItem(at: ImageFormat.allCases.firstIndex(of: Prefs.imageFormat) ?? 0)
        cursorCheckbox.state = Prefs.showsCursor ? .on : .off
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Prefs.saveDirectory
        panel.prompt = "Choose"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Prefs.saveDirectory = url
            self?.refresh()
        }
    }

    @objc private func formatChanged() {
        let index = max(0, formatPopup.indexOfSelectedItem)
        Prefs.imageFormat = ImageFormat.allCases[index]
    }

    @objc private func cursorToggled() {
        Prefs.showsCursor = cursorCheckbox.state == .on
    }

    @objc private func loginToggled() {
        do {
            if loginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update login item"
            alert.informativeText = "\(error.localizedDescription)\n\nNote: launch at login requires running LightSnap from the built app bundle (make app)."
            alert.runModal()
            loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

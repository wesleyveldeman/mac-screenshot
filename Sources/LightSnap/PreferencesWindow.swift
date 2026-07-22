import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private var pathLabel: NSTextField!
    private var formatPopup: NSPopUpButton!
    private var actionPopup: NSPopUpButton!
    private var cursorCheckbox: NSButton!
    private var loginCheckbox: NSButton!
    private var areaRecorder: HotkeyRecorderField!
    private var fullScreenRecorder: HotkeyRecorderField!
    private var hotkeyWarningLabel: NSTextField!
    private var hotkeyWarningRow: NSGridRow?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LightSnap Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Ending recording re-registers the global hotkeys, so never leave a
    // recorder focused when the window goes away.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
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

        actionPopup = NSPopUpButton()
        for action in PostSelectionAction.allCases {
            actionPopup.addItem(withTitle: action.displayName)
        }
        actionPopup.target = self
        actionPopup.action = #selector(actionChanged)

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

        areaRecorder = HotkeyRecorderField(hotkey: Prefs.areaHotkey)
        areaRecorder.onChange = { [weak self] hotkey in
            guard let self else { return }
            if hotkey.hasSameCombo(as: Prefs.fullScreenHotkey) {
                NSSound.beep()
                self.areaRecorder.hotkey = Prefs.areaHotkey
                return
            }
            Prefs.areaHotkey = hotkey
        }
        fullScreenRecorder = HotkeyRecorderField(hotkey: Prefs.fullScreenHotkey)
        fullScreenRecorder.onChange = { [weak self] hotkey in
            guard let self else { return }
            if hotkey.hasSameCombo(as: Prefs.areaHotkey) {
                NSSound.beep()
                self.fullScreenRecorder.hotkey = Prefs.fullScreenHotkey
                return
            }
            Prefs.fullScreenHotkey = hotkey
        }
        for recorder in [areaRecorder!, fullScreenRecorder!] {
            recorder.onRecordingChange = { [weak self] recording in
                if recording {
                    HotkeyCenter.shared.suspend()
                } else {
                    HotkeyCenter.shared.resume()
                    self?.updateHotkeyWarning()
                }
            }
        }

        hotkeyWarningLabel = NSTextField(wrappingLabelWithString: "")
        hotkeyWarningLabel.textColor = .systemRed
        hotkeyWarningLabel.font = .systemFont(ofSize: 11)
        hotkeyWarningLabel.preferredMaxLayoutWidth = 280

        let grid = NSGridView(views: [
            [label("Save to:"), pathRow],
            [label("Format:"), formatPopup],
            [label("After selection:"), actionPopup],
            [NSGridCell.emptyContentView, cursorCheckbox],
            [NSGridCell.emptyContentView, loginCheckbox],
            [label("Capture area:"), areaRecorder],
            [label("Full screen:"), fullScreenRecorder],
            [NSGridCell.emptyContentView, hotkeyWarningLabel],
        ])
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        hotkeyWarningRow = grid.row(at: 7)
        hotkeyWarningRow?.isHidden = true
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
        actionPopup.selectItem(at: PostSelectionAction.allCases.firstIndex(of: Prefs.postSelectionAction) ?? 0)
        cursorCheckbox.state = Prefs.showsCursor ? .on : .off
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        areaRecorder.hotkey = Prefs.areaHotkey
        fullScreenRecorder.hotkey = Prefs.fullScreenHotkey
        updateHotkeyWarning()
    }

    private func updateHotkeyWarning() {
        let center = HotkeyCenter.shared
        let failed = !center.areaRegistered || !center.fullScreenRegistered
        hotkeyWarningLabel.stringValue = failed
            ? "A shortcut could not be registered — the combination may already be in use by another app."
            : ""
        hotkeyWarningRow?.isHidden = !failed
    }

    // MARK: - Actions

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

    @objc private func actionChanged() {
        let index = max(0, actionPopup.indexOfSelectedItem)
        Prefs.postSelectionAction = PostSelectionAction.allCases[index]
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

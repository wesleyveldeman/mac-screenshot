import AppKit

/// Click-to-record shortcut field for the Settings window. Click it, press a
/// combination, and it commits via `onChange`. Esc or clicking again cancels.
final class HotkeyRecorderField: NSView {
    var hotkey: Hotkey {
        didSet { needsDisplay = true }
    }

    /// Called with the newly recorded hotkey; fires before recording ends so
    /// the owner can persist it ahead of global re-registration.
    var onChange: ((Hotkey) -> Void)?

    /// Called when recording starts (true) and ends (false). The owner should
    /// suspend global hotkeys during recording so they can be re-captured.
    var onRecordingChange: ((Bool) -> Void)?

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            needsDisplay = true
            onRecordingChange?(isRecording)
        }
    }

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 140).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    // Command-key combinations arrive as key equivalents first; claim them
    // while recording so they reach keyDown instead of being swallowed.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Escape cancels recording
            window?.makeFirstResponder(nil)
            return
        }

        let keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = Hotkey.carbonModifiers(from: flags)

        // Require ⌘, ⌃, or ⌥ unless it's a function key, so ordinary typing
        // can't become a global shortcut.
        let hasPrimaryModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        guard hasPrimaryModifier || Hotkey.isFunctionKey(keyCode) else {
            NSSound.beep()
            return
        }

        let character = Hotkey.specialKeyName(for: keyCode)
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? ""
        guard !character.isEmpty else {
            NSSound.beep()
            return
        }

        let recorded = Hotkey(keyCode: keyCode, carbonModifiers: modifiers, character: character)
        hotkey = recorded
        onChange?(recorded)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        path.lineWidth = isRecording ? 2 : 1
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text = isRecording ? "Type shortcut…" : hotkey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        ))
    }
}

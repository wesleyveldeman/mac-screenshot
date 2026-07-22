import AppKit

/// Lightshot-style floating toolbar shown next to the selection: annotation
/// tools, color swatches, undo/redo, and output actions.
final class EditorToolbar: NSView {
    private unowned let owner: SelectionView

    private var toolButtons: [Int: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var undoButton: NSButton!
    private var redoButton: NSButton!

    init(owner: SelectionView) {
        self.owner = owner
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        for tool in Tool.allCases {
            let button = makeButton(symbol: tool.symbolName, tooltip: tool.help, action: #selector(toolClicked(_:)))
            button.tag = tool.rawValue
            toolButtons[tool.rawValue] = button
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(makeSeparator())

        for (index, color) in SelectionView.palette.enumerated() {
            let button = NSButton(image: Self.swatchImage(color: color, selected: false), target: self, action: #selector(colorClicked(_:)))
            button.tag = index
            button.isBordered = false
            button.toolTip = "Color"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            colorButtons.append(button)
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(makeSeparator())

        undoButton = makeButton(symbol: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", action: #selector(undoClicked))
        redoButton = makeButton(symbol: "arrow.uturn.forward", tooltip: "Redo (⇧⌘Z)", action: #selector(redoClicked))
        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)

        stack.addArrangedSubview(makeSeparator())

        stack.addArrangedSubview(makeButton(symbol: "doc.on.doc", tooltip: "Copy to clipboard (⌘C or Enter)", action: #selector(copyClicked)))
        stack.addArrangedSubview(makeButton(symbol: "square.and.arrow.down", tooltip: "Save… (⌘S) — ⇧⌘S saves instantly", action: #selector(saveClicked)))
        stack.addArrangedSubview(makeButton(symbol: "printer", tooltip: "Print (⌘P)", action: #selector(printClicked)))

        stack.addArrangedSubview(makeSeparator())

        stack.addArrangedSubview(makeButton(symbol: "xmark", tooltip: "Cancel (Esc)", action: #selector(cancelClicked)))

        addSubview(stack)
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        stack.frame = CGRect(origin: .zero, size: size)
        stack.autoresizingMask = [.width, .height]
        setFrameSize(size)

        refreshTools()
        refreshColors()
        refreshUndoRedo()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Swallow clicks on the toolbar background so they don't fall through to
    // the selection view and start a new selection.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    // MARK: - State refresh

    func refreshTools() {
        for (raw, button) in toolButtons {
            let selected = raw == owner.currentTool.rawValue
            button.layer?.backgroundColor = selected
                ? NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
                : NSColor.clear.cgColor
        }
    }

    func refreshColors() {
        for (index, button) in colorButtons.enumerated() {
            let color = SelectionView.palette[index]
            button.image = Self.swatchImage(color: color, selected: color == owner.currentColor)
        }
    }

    func refreshUndoRedo() {
        undoButton.isEnabled = owner.canUndo
        redoButton.isEnabled = owner.canRedo
    }

    // MARK: - Actions

    @objc private func toolClicked(_ sender: NSButton) {
        guard let tool = Tool(rawValue: sender.tag) else { return }
        owner.selectTool(tool)
    }

    @objc private func colorClicked(_ sender: NSButton) {
        owner.selectColor(SelectionView.palette[sender.tag])
    }

    @objc private func undoClicked() { owner.undo() }
    @objc private func redoClicked() { owner.redo() }
    @objc private func copyClicked() { owner.performCopy() }
    @objc private func saveClicked() { owner.performSave() }
    @objc private func printClicked() { owner.performPrint() }
    @objc private func cancelClicked() { owner.performCancel() }

    // MARK: - Construction helpers

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .white
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private func makeSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private static func swatchImage(color: NSColor, selected: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let circle = rect.insetBy(dx: 4, dy: 4)
            color.setFill()
            NSBezierPath(ovalIn: circle).fill()

            let outline = NSBezierPath(ovalIn: circle)
            outline.lineWidth = 1
            NSColor.white.withAlphaComponent(0.35).setStroke()
            outline.stroke()

            if selected {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
                ring.lineWidth = 1.5
                NSColor.white.setStroke()
                ring.stroke()
            }
            return true
        }
    }
}

import AppKit

/// Full-screen view shown over a frozen screenshot of one display.
/// Handles area selection (drag, move, resize), in-place annotation with the
/// current tool, and produces the final cropped + annotated image.
final class SelectionView: NSView {
    private enum State {
        case idle
        case selecting
        case selected
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum DragMode {
        case none
        case move
        case resize(Handle)
        case draw
    }

    static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .white, .black,
    ]

    let capture: DisplayCapture
    private unowned let controller: CaptureController
    private let backgroundImage: NSImage
    private let scale: CGFloat

    private var state: State = .idle
    private(set) var selectionRect: CGRect = .zero
    private var dragMode: DragMode = .none
    private var dragOrigin: CGPoint = .zero
    private var dragOriginalRect: CGRect = .zero

    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var activeAnnotation: Annotation?
    private var textField: NSTextField?
    private var toolbar: EditorToolbar!

    private(set) var currentTool: Tool = .select
    private(set) var currentColor: NSColor = .systemRed
    private let strokeWidth: CGFloat = 3
    private let textFontSize: CGFloat = 18

    private let accentColor = NSColor(calibratedRed: 0.22, green: 0.55, blue: 0.98, alpha: 1)

    // MARK: - Setup

    init(capture: DisplayCapture, controller: CaptureController) {
        self.capture = capture
        self.controller = controller
        self.scale = capture.screen.backingScaleFactor
        self.backgroundImage = NSImage(cgImage: capture.image, size: capture.screen.frame.size)
        super.init(frame: CGRect(origin: .zero, size: capture.screen.frame.size))
        toolbar = EditorToolbar(owner: self)
        toolbar.isHidden = true
        addSubview(toolbar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func teardown() {
        discardTextField()
    }

    // MARK: - Public state changes

    func selectTool(_ tool: Tool) {
        commitTextField()
        currentTool = tool
        toolbar.refreshTools()
        window?.invalidateCursorRects(for: self)
    }

    func selectColor(_ color: NSColor) {
        currentColor = color
        textField?.textColor = color
        toolbar.refreshColors()
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        commitTextField()
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
        toolbar.refreshUndoRedo()
        needsDisplay = true
    }

    func redo() {
        guard let annotation = redoStack.popLast() else { return }
        annotations.append(annotation)
        toolbar.refreshUndoRedo()
        needsDisplay = true
    }

    func selectEntireScreen() {
        controller.selectionWillBegin(on: self)
        commitTextField()
        // ⌘A inside an active editing session only expands the selection —
        // re-applying the post-selection action here would instantly
        // copy/save and kill the session mid-edit.
        let alreadyEditing = state == .selected && !toolbar.isHidden
        state = .selected
        selectionRect = bounds
        dragMode = .none
        let action: PostSelectionAction = alreadyEditing ? .edit : Prefs.postSelectionAction
        switch action {
        case .edit:
            layoutToolbar()
            toolbar.isHidden = false
            toolbar.refreshUndoRedo()
        case .copy:
            performCopy()
            return
        case .save:
            performQuickSave()
            return
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func clearSelection() {
        discardTextField()
        state = .idle
        selectionRect = .zero
        annotations.removeAll()
        redoStack.removeAll()
        activeAnnotation = nil
        dragMode = .none
        toolbar.isHidden = true
        toolbar.refreshUndoRedo()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        backgroundImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        let hasSelection = state != .idle && selectionRect.width > 0 && selectionRect.height > 0

        let dimPath = NSBezierPath(rect: bounds)
        if hasSelection {
            dimPath.append(NSBezierPath(rect: selectionRect))
            dimPath.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.4).setFill()
        dimPath.fill()

        if hasSelection {
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: selectionRect).addClip()
            AnnotationRenderer.draw(annotations)
            if let activeAnnotation {
                AnnotationRenderer.draw(activeAnnotation)
            }
            NSGraphicsContext.current?.restoreGraphicsState()

            drawSelectionChrome()
        }

        if state == .idle {
            drawHint()
        }
    }

    private func drawSelectionChrome() {
        let border = NSBezierPath(rect: selectionRect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        accentColor.setStroke()
        border.stroke()

        if state == .selected {
            for handle in Handle.allCases {
                let center = point(for: handle, in: selectionRect)
                let rect = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
                let path = NSBezierPath(ovalIn: rect)
                NSColor.white.setFill()
                path.fill()
                path.lineWidth = 1
                accentColor.setStroke()
                path.stroke()
            }
        }

        drawSizeLabel()
    }

    private func drawSizeLabel() {
        let text = "\(Int(selectionRect.width.rounded())) × \(Int(selectionRect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let padding: CGFloat = 5

        var origin = CGPoint(x: selectionRect.minX, y: selectionRect.minY - size.height - padding * 2 - 4)
        if origin.y < 0 {
            origin.y = selectionRect.minY + 4
        }
        origin.x = min(max(0, origin.x), bounds.maxX - size.width - padding * 2)

        let background = CGRect(
            x: origin.x,
            y: origin.y,
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        string.draw(at: CGPoint(x: background.minX + padding, y: background.minY + padding))
    }

    private func drawHint() {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
        ]
        let title = NSAttributedString(string: "Drag to select an area", attributes: titleAttrs)
        let subtitle = NSAttributedString(string: "⌘A whole screen   ·   Esc cancel", attributes: subtitleAttrs)

        let titleSize = title.size()
        let subtitleSize = subtitle.size()
        let width = max(titleSize.width, subtitleSize.width) + 48
        let height = titleSize.height + subtitleSize.height + 36
        let rect = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)

        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        title.draw(at: CGPoint(x: rect.midX - titleSize.width / 2, y: rect.minY + 12))
        subtitle.draw(at: CGPoint(x: rect.midX - subtitleSize.width / 2, y: rect.minY + 12 + titleSize.height + 6))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        commitTextField()

        switch state {
        case .idle:
            beginSelection(at: point)

        case .selecting:
            dragOrigin = point

        case .selected:
            if let handle = handle(at: point) {
                dragMode = .resize(handle)
                dragOrigin = point
                dragOriginalRect = selectionRect
            } else if selectionRect.contains(point) {
                switch currentTool {
                case .select:
                    dragMode = .move
                    dragOrigin = point
                    dragOriginalRect = selectionRect
                case .text:
                    beginTextEditing(at: point)
                default:
                    dragMode = .draw
                    beginAnnotation(at: point)
                }
            } else {
                // Clicking outside the selection starts a fresh one.
                annotations.removeAll()
                redoStack.removeAll()
                activeAnnotation = nil
                toolbar.isHidden = true
                toolbar.refreshUndoRedo()
                beginSelection(at: point)
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampToBounds(convert(event.locationInWindow, from: nil))

        switch state {
        case .idle:
            break

        case .selecting:
            selectionRect = rect(from: dragOrigin, to: point)

        case .selected:
            switch dragMode {
            case .none:
                break
            case .move:
                var moved = dragOriginalRect.offsetBy(dx: point.x - dragOrigin.x, dy: point.y - dragOrigin.y)
                moved.origin.x = min(max(0, moved.origin.x), bounds.width - moved.width)
                moved.origin.y = min(max(0, moved.origin.y), bounds.height - moved.height)
                selectionRect = moved
                layoutToolbar()
            case .resize(let handle):
                selectionRect = resized(dragOriginalRect, handle: handle, to: point)
                layoutToolbar()
            case .draw:
                extendAnnotation(to: point)
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch state {
        case .idle:
            break

        case .selecting:
            if selectionRect.width < 4 || selectionRect.height < 4 {
                state = .idle
                selectionRect = .zero
            } else {
                state = .selected
                // Holding ⌥ on release always opens the editor, so annotating
                // stays available even with auto-copy/save enabled.
                var action = Prefs.postSelectionAction
                if event.modifierFlags.contains(.option) {
                    action = .edit
                }
                switch action {
                case .edit:
                    layoutToolbar()
                    toolbar.isHidden = false
                case .copy:
                    performCopy()
                    return
                case .save:
                    performQuickSave()
                    return
                }
            }
            window?.invalidateCursorRects(for: self)

        case .selected:
            if case .draw = dragMode {
                commitActiveAnnotation()
            }
            dragMode = .none
            // A move/resize drag relocates the selection and toolbar; their
            // cursor rects must follow.
            window?.invalidateCursorRects(for: self)
        }
        needsDisplay = true
    }

    private func beginSelection(at point: CGPoint) {
        controller.selectionWillBegin(on: self)
        state = .selecting
        dragOrigin = point
        selectionRect = CGRect(origin: point, size: .zero)
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            controller.cancelCapture()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad Enter
            if state == .selected {
                performCopy()
            }
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            switch key {
            case "c":
                performCopy()
                return
            case "s":
                if flags.contains(.shift) {
                    performQuickSave()
                } else {
                    performSave()
                }
                return
            case "z":
                if flags.contains(.shift) {
                    redo()
                } else {
                    undo()
                }
                return
            case "a":
                selectEntireScreen()
                return
            case "p":
                performPrint()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        switch state {
        case .idle, .selecting:
            addCursorRect(bounds, cursor: .crosshair)
        case .selected:
            addCursorRect(bounds, cursor: .crosshair)
            let inner = selectionRect.intersection(bounds)
            if !inner.isEmpty {
                switch currentTool {
                case .select:
                    addCursorRect(inner, cursor: .openHand)
                case .text:
                    addCursorRect(inner, cursor: .iBeam)
                default:
                    addCursorRect(inner, cursor: .crosshair)
                }
            }
            if !toolbar.isHidden {
                addCursorRect(toolbar.frame, cursor: .arrow)
            }
        }
    }

    // MARK: - Geometry helpers

    private func clampToBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), bounds.width),
            y: min(max(0, point.y), bounds.height)
        )
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private func point(for handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handle(at point: CGPoint) -> Handle? {
        guard state == .selected else { return nil }
        return Handle.allCases.first { handle in
            let center = self.point(for: handle, in: selectionRect)
            return hypot(center.x - point.x, center.y - point.y) <= 8
        }
    }

    private func resized(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        }

        var result = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: max(abs(maxX - minX), 1),
            height: max(abs(maxY - minY), 1)
        )
        result = result.intersection(bounds)
        return result
    }

    // MARK: - Annotations

    private func beginAnnotation(at point: CGPoint) {
        redoStack.removeAll()
        switch currentTool {
        case .pen:
            activeAnnotation = Annotation(shape: .pen([point]), color: currentColor, lineWidth: strokeWidth)
        case .highlight:
            activeAnnotation = Annotation(shape: .highlight([point]), color: currentColor, lineWidth: strokeWidth)
        case .line:
            activeAnnotation = Annotation(shape: .line(from: point, to: point), color: currentColor, lineWidth: strokeWidth)
        case .arrow:
            activeAnnotation = Annotation(shape: .arrow(from: point, to: point), color: currentColor, lineWidth: strokeWidth)
        case .rect:
            dragOrigin = point
            activeAnnotation = Annotation(shape: .rect(CGRect(origin: point, size: .zero)), color: currentColor, lineWidth: strokeWidth)
        case .select, .text:
            break
        }
    }

    private func extendAnnotation(to point: CGPoint) {
        guard var annotation = activeAnnotation else { return }
        switch annotation.shape {
        case .pen(var points):
            points.append(point)
            annotation.shape = .pen(points)
        case .highlight(var points):
            points.append(point)
            annotation.shape = .highlight(points)
        case .line(let from, _):
            annotation.shape = .line(from: from, to: point)
        case .arrow(let from, _):
            annotation.shape = .arrow(from: from, to: point)
        case .rect:
            annotation.shape = .rect(rect(from: dragOrigin, to: point))
        case .text:
            break
        }
        activeAnnotation = annotation
    }

    private func commitActiveAnnotation() {
        if let annotation = activeAnnotation {
            annotations.append(annotation)
            toolbar.refreshUndoRedo()
        }
        activeAnnotation = nil
    }

    // MARK: - Text tool

    private func beginTextEditing(at point: CGPoint) {
        commitTextField()
        let width = max(80, selectionRect.maxX - point.x)
        let field = NSTextField(frame: CGRect(x: point.x, y: point.y - textFontSize / 2, width: width, height: textFontSize + 8))
        field.font = .systemFont(ofSize: textFontSize, weight: .semibold)
        field.textColor = currentColor
        field.drawsBackground = false
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        field.layer?.borderWidth = 1
        field.layer?.cornerRadius = 2
        field.placeholderString = "Text"
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func commitTextField() {
        guard let field = textField else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.isEmpty {
            // Match the text field's internal padding so the committed text
            // lands where it was typed.
            let origin = CGPoint(x: field.frame.origin.x + 2, y: field.frame.origin.y + 2)
            annotations.append(Annotation(
                shape: .text(string, origin: origin, fontSize: textFontSize),
                color: currentColor,
                lineWidth: 1
            ))
            redoStack.removeAll()
            toolbar.refreshUndoRedo()
        }
        discardTextField()
    }

    private func discardTextField() {
        guard let field = textField else { return }
        textField = nil
        window?.makeFirstResponder(self)
        field.removeFromSuperview()
        needsDisplay = true
    }

    // MARK: - Toolbar layout

    private func layoutToolbar() {
        let size = toolbar.frame.size
        let margin: CGFloat = 8

        var x = selectionRect.maxX - size.width
        x = min(max(margin, x), bounds.width - size.width - margin)

        var y = selectionRect.maxY + margin
        if y + size.height > bounds.height - margin {
            y = selectionRect.minY - size.height - margin
            if y < margin {
                // Selection covers (almost) the whole screen: put it inside.
                y = selectionRect.maxY - size.height - margin
                x = min(max(margin, selectionRect.maxX - size.width - margin), bounds.width - size.width - margin)
            }
        }
        toolbar.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: - Output

    func renderFinalImage() -> NSImage? {
        commitTextField()
        guard selectionRect.width >= 1, selectionRect.height >= 1 else { return nil }

        let imageRect = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        let pixelRect = CGRect(
            x: selectionRect.origin.x * scale,
            y: selectionRect.origin.y * scale,
            width: selectionRect.width * scale,
            height: selectionRect.height * scale
        ).integral.intersection(imageRect)
        guard !pixelRect.isEmpty, let cropped = capture.image.cropping(to: pixelRect) else { return nil }

        let pixelWidth = Int(pixelRect.width)
        let pixelHeight = Int(pixelRect.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        if !annotations.isEmpty {
            context.saveGState()
            // Map the context to the view's flipped point coordinates so the
            // exact same renderer used on screen draws the export.
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: 1, y: -1)
            context.scaleBy(x: scale, y: scale)
            // Translate by the integral crop origin, not the fractional
            // selection origin, so annotations land on the exact pixels they
            // covered on screen.
            context.translateBy(x: -(pixelRect.origin.x / scale), y: -(pixelRect.origin.y / scale))

            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = graphics
            AnnotationRenderer.draw(annotations)
            NSGraphicsContext.current = previous
            context.restoreGState()
        }

        guard let output = context.makeImage() else { return nil }
        return NSImage(cgImage: output, size: CGSize(width: pixelRect.width / scale, height: pixelRect.height / scale))
    }

    func performCopy() {
        guard state == .selected, let image = renderFinalImage() else { return }
        OutputActions.copyToClipboard(image)
        controller.finishCapture()
    }

    func performSave() {
        guard state == .selected, let image = renderFinalImage() else { return }
        controller.finishCapture()
        OutputActions.promptAndSave(image)
    }

    func performQuickSave() {
        guard state == .selected, let image = renderFinalImage() else { return }
        controller.finishCapture()
        OutputActions.quickSave(image)
    }

    func performPrint() {
        guard state == .selected, let image = renderFinalImage() else { return }
        controller.finishCapture()
        OutputActions.printImage(image)
    }

    func performCancel() {
        controller.cancelCapture()
    }
}

// MARK: - NSTextFieldDelegate (text tool)

extension SelectionView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextField()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            discardTextField()
            return true
        }
        return false
    }
}

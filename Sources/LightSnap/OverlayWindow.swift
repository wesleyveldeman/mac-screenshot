import AppKit

/// Borderless full-screen window that displays the frozen screenshot of one
/// display and hosts the selection/annotation view on top of it.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

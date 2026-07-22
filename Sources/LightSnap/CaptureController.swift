import AppKit

enum CaptureMode {
    case area
    case fullScreen
}

/// Orchestrates a capture session: freezes every display into an image,
/// shows a full-screen overlay per display for selection + annotation,
/// and tears everything down when the user copies/saves/cancels.
@MainActor
final class CaptureController {
    static let shared = CaptureController()

    private struct Session {
        let window: OverlayWindow
        let view: SelectionView
    }

    private var sessions: [Session] = []
    private var isCapturing = false

    private init() {}

    func beginCapture(mode: CaptureMode) {
        guard !isCapturing else { return }
        // Claim the flag before the permission alert runs modally, or a
        // second hotkey press during the alert stacks another one.
        isCapturing = true
        guard ensurePermission() else {
            isCapturing = false
            return
        }
        Task { @MainActor in
            do {
                let captures = try await ScreenCapturer.captureAllDisplays()
                presentOverlays(for: captures, mode: mode)
            } catch {
                isCapturing = false
                presentError(error)
            }
        }
    }

    /// Only one display can host the active selection; clear the others.
    func selectionWillBegin(on view: SelectionView) {
        for session in sessions where session.view !== view {
            session.view.clearSelection()
        }
    }

    func cancelCapture() {
        dismissOverlays()
    }

    func finishCapture() {
        dismissOverlays()
    }

    // MARK: - Private

    private func presentOverlays(for captures: [DisplayCapture], mode: CaptureMode) {
        guard isCapturing, sessions.isEmpty else { return }

        let mouseLocation = NSEvent.mouseLocation
        var activeView: SelectionView?

        for capture in captures {
            let window = OverlayWindow(screen: capture.screen)
            let view = SelectionView(capture: capture, controller: self)
            window.contentView = view
            sessions.append(Session(window: window, view: view))
            window.orderFrontRegardless()
            if NSMouseInRect(mouseLocation, capture.screen.frame, false) {
                activeView = view
            }
        }
        if activeView == nil {
            activeView = sessions.first?.view
        }

        NSApp.activate(ignoringOtherApps: true)
        if let activeView, let window = activeView.window {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(activeView)
            if mode == .fullScreen {
                activeView.selectEntireScreen()
            }
        }
    }

    private func dismissOverlays() {
        let dismissed = sessions
        sessions.removeAll()
        isCapturing = false
        for session in dismissed {
            session.view.teardown()
            session.window.makeFirstResponder(nil)
            session.window.orderOut(nil)
        }
        // A toolbar button action or key handler inside one of these views may
        // still be on the call stack; release the view hierarchy on the next
        // runloop turn instead of out from under it.
        DispatchQueue.main.async {
            for session in dismissed {
                session.window.contentView = nil
            }
        }
    }

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        _ = CGRequestScreenCaptureAccess()

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        LightSnap needs Screen Recording access to take screenshots.

        Enable LightSnap in System Settings → Privacy & Security → Screen Recording, then try again.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not capture the screen"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

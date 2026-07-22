import AppKit

@main
enum LightSnapApp {
    static func main() {
        // The process entry point always starts on the main thread, so this
        // runtime-checked hop onto the main actor is safe.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}

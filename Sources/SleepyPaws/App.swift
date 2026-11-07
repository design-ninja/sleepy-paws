import AppKit

@main
struct SleepyPawsApp {
    @MainActor
    static func main() {
        guard BackgroundAgent.shouldLaunch() else { return }
        let app = NSApplication.shared
        let controller = SleepyPawsController()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) { app.run() }
    }
}

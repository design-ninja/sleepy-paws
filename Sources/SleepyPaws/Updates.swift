import AppKit
import Sparkle

/// Sparkle updates from the GitHub releases feed (SUFeedURL in Info.plist), checked once a day
/// and on demand from the menu.
@MainActor
final class Updates: NSObject, SPUUpdaterDelegate {
    /// Called when Sparkle is about to quit the app to install an update, which the app would
    /// otherwise refuse without the parent PIN.
    var willRelaunch: () -> Void = {}

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: !BackgroundAgent.isTestInstance, updaterDelegate: self, userDriverDelegate: nil
    )

    func start() { _ = controller }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { willRelaunch() }
    }
}

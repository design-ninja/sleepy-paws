import AppKit
import CoreServices
import OSLog
import SleepyPawsCore
import SwiftUI

@MainActor
final class SleepyPawsController: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "app")
    private let stateURL = URL.applicationSupportDirectoryCompat
        .appendingPathComponent("SleepyPaws", isDirectory: true)
        .appendingPathComponent("state.json")
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let saveWarning = NSMenuItem(title: "Couldn’t save timer progress", action: nil, keyEquivalent: "")
    private let agentWarning = NSMenuItem(title: "Background protection is off", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
    private var aboutWindow: NSWindow?
    private let pauseItem = NSMenuItem(title: "Pause Timer…", action: #selector(togglePause), keyEquivalent: "")
    private let cover = BreakWindows()
    private var settingsWindow: NSWindow?
    private var parentWindow: NSWindow?
    private var sound: NSSound?
    private var state = LocalState()
    private var timer: Timer?
    private var sessionActive = true
    private var displayAwake = true
    private let macUsage = MacUsageState()
    private let audioGuard = AudioGuard(defaults: BackgroundAgent.defaults)
    private let updates = Updates()
    private var usageClock = UsageClock()
    private var approvedQuit = false
    private var lastSave = ProcessInfo.processInfo.systemUptime
    private var hadExpired = false
    private var stateIsDirty = false
    private var saveFailed = false
    /// When the PIN, or an administrator via "Forgot PIN?", last approved on the break screen.
    private var approvedAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = LocalState.load(from: stateURL, mirror: BackgroundAgent.defaults)
        // Rewrite both copies, in case one was deleted, edited or damaged.
        if state.pin != nil { _ = replace(with: state) }

        audioGuard.restore() // in case the app ended while the break screen had muted the Mac
        if let url = Bundle.main.url(forResource: "TimeIsUp", withExtension: "wav") {
            sound = NSSound(contentsOf: url, byReference: true)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        saveWarning.isEnabled = false
        saveWarning.isHidden = true
        menu.addItem(saveWarning)
        agentWarning.isEnabled = false
        agentWarning.isHidden = true
        menu.addItem(agentWarning)
        menu.addItem(pauseItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(Updates.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updates
        menu.addItem(updateItem)
        menu.addItem(withTitle: "About Sleepy Paws", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(askToQuit), keyEquivalent: "")
        menu.items.filter { $0.action != nil && $0.target == nil }.forEach { $0.target = self }
        // Installing an update quits and relaunches the app, which a PIN-less quit can't do.
        updates.willRelaunch = { [weak self] in self?.approvedQuit = true }
        updates.start()
        status.menu = menu
        status.button?.image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: nil)
        status.button?.imagePosition = .imageLeading
        status.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        status.button?.image?.isTemplate = true
        switch BackgroundAgent.install() {
        case .handOver:
            // launchd is starting the copy it keeps alive; let it take over.
            approvedQuit = true
            NSApp.terminate(nil)
            return
        case .unavailable:
            agentWarning.isHidden = false
        case .running:
            break
        }
        cover.forgotPIN = { [weak self] done in self?.checkAdministrator(done) }
        cover.rememberExtra = { BackgroundAgent.defaults.set($0, forKey: Self.extraKey) }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(pauseDisplay), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(pauseDisplay), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resumeDisplay), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(pauseSession), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resumeSession), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 0.25, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.05
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        hadExpired = state.budget.expired
        tick()
        if state.pin == nil { showSettings() }
        #if DEBUG
        // Test copies can open Settings straight away, to check its layout without the PIN.
        if BackgroundAgent.isTestInstance, ProcessInfo.processInfo.environment["SLEEPYPAWS_TEST_SHOW"] == "settings" {
            showSettings()
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if cover.isShowing { cover.focus() }
        else if let settingsWindow, settingsWindow.isVisible { present(settingsWindow) }
        else { openSettings() }
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        if cover.isShowing {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.desktopAvailable else { return }
                self.cover.focus()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if approvedQuit || state.pin == nil || isSystemQuit { return .terminateNow }
        if !cover.isShowing {
            DispatchQueue.main.async { [weak self] in
                self?.askToQuit()
            }
        }
        return .terminateCancel
    }

    private var isSystemQuit: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let reason = event?.paramDescriptor(forKeyword: 0x7768793f /* keyAEQuitReason (why?) */)?.enumCodeValue
        return [kAEReallyLogOut, kAEShutDown, kAERestart].contains { reason == OSType($0) }
    }

    private var desktopAvailable: Bool {
        sessionActive && displayAwake && macUsage.sessionIsUnlocked
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        audioGuard.restore()
        persist()
    }

    @objc private func tick() {
        let uptime = ProcessInfo.processInfo.systemUptime
        let desktopAvailable = self.desktopAvailable
        let counts = state.pin != nil && desktopAvailable && !macUsage.lidIsClosed
        let elapsed = usageClock.sample(at: uptime, counts: counts)
        if state.pin != nil {
            let before = state.budget.remaining
            state.budget.record(elapsed, at: Date())
            stateIsDirty = stateIsDirty || before != state.budget.remaining
            if state.budget.expired && !hadExpired {
                stateIsDirty = true
                persist()
            }
            hadExpired = state.budget.expired
            if uptime - lastSave >= 5 { persist() }
            updateCover(desktopAvailable: desktopAvailable)
        }
        // Keep the Mac silent behind the break screen, after the yawn has finished.
        if cover.isShowing {
            if sound?.isPlaying != true { audioGuard.enforce() }
        } else {
            audioGuard.restore()
        }
        updateStatus()
    }

    private func updateCover(desktopAvailable: Bool) {
        if state.budget.blocks {
            guard desktopAvailable, !cover.isShowing else { return }
            [settingsWindow, parentWindow, aboutWindow].forEach { $0?.orderOut(nil) }
            settingsWindow = nil
            parentWindow = nil
            let initial = extraChoice
            cover.show(extraOptions: Array(Set(Self.extraOptions + [state.budget.minutes, initial])).sorted(),
                       initialExtra: initial,
                       verify: { [weak self] pin in
                           guard let self else { return "Try again" }
                           return self.verifyPIN(pin)
                       },
                       unlock: { [weak self] action in
                           guard let self else { return "Try again" }
                           return self.unlock(action: action)
                       })
            playSound() // the sleepy yawn, every time the break screen comes up
        } else if cover.isShowing {
            cover.hide()
        }
    }

    private func updateStatus() {
        let title: String
        if state.pin == nil {
            title = "Set Up"
        } else if state.budget.isPaused {
            title = "Paused"
        } else if state.budget.expired {
            title = "Time’s Up"
        } else {
            title = DurationText.countdown(seconds: Int(ceil(state.budget.remaining)))
        }
        // Called four times a second: only touch AppKit when something actually changed.
        if status.button?.title != title {
            status.button?.title = title
            status.button?.setAccessibilityLabel("Sleepy Paws • \(title)")
        }
        if saveWarning.isHidden == saveFailed { saveWarning.isHidden = !saveFailed }
        let settingsTitle = state.pin == nil ? "Set Up…" : "Settings…"
        if settingsItem.title != settingsTitle { settingsItem.title = settingsTitle }
        let pauseTitle = state.budget.isPaused ? "Resume Timer" : "Pause Timer…"
        if pauseItem.title != pauseTitle { pauseItem.title = pauseTitle }
        if pauseItem.isHidden != (state.pin == nil) { pauseItem.isHidden = state.pin == nil }
    }

    @objc private func pauseDisplay() {
        displayAwake = false
        tick()
        persist()
    }

    @objc private func resumeDisplay() {
        displayAwake = true
        tick()
        if desktopAvailable { cover.focus() }
    }

    @objc private func pauseSession() {
        sessionActive = false
        tick()
        persist()
    }

    @objc private func resumeSession() {
        sessionActive = true
        tick()
        if desktopAvailable { cover.focus() }
    }

    @objc private func screensChanged() {
        cover.screensChanged()
    }

    private static let extraKey = "BreakScreen.extraMinutes"
    private static let extraOptions = [5, 10, 15, 30] + (1...8).map { $0 * 60 }

    /// The amount picked on the break screen last time, or else the daily limit.
    private var extraChoice: Int {
        let saved = BackgroundAgent.defaults.integer(forKey: Self.extraKey)
        return DailyBudget.limits.contains(saved) ? saved : state.budget.minutes
    }

    private func verifyPIN(_ pin: String) -> String? {
        if let error = authenticate(pin) { return error }
        approvedAt = Date()
        return nil
    }

    private func unlock(action: BreakAction) -> String? {
        guard let approved = approvedAt, Date().timeIntervalSince(approved) < 120 else {
            return "Enter the PIN again"
        }
        approvedAt = nil
        var edited = state
        switch action {
        case .addTime(let minutes): edited.budget.grantExtraTime(minutes: minutes)
        case .pause: edited.budget.pause()
        }
        guard replace(with: edited) else { return "Couldn’t save. Try again." }
        MediaPauser.requestPermission() // a parent just entered the PIN
        tick()
        return nil
    }

    /// Pausing needs the parent PIN; resuming only makes things stricter, so it doesn't.
    @objc private func togglePause() {
        guard !cover.isShowing else { return }
        if state.budget.isPaused {
            var edited = state
            edited.budget.resume()
            _ = replace(with: edited)
            tick()
        } else {
            askParent("Pause Timer", purpose: "to pause the timer until midnight") { [weak self] in
                guard let self else { return }
                var edited = self.state
                edited.budget.pause()
                _ = self.replace(with: edited)
                self.tick()
            }
        }
    }

    /// "Forgot PIN?": an administrator of this Mac approves instead of the PIN.
    private func checkAdministrator(_ done: @escaping @MainActor (Bool) -> Void) {
        cover.isAuthorizing = true
        parentWindow?.level = .normal // let the system dialog come in front
        AdminAuth.request("Sleepy Paws needs an administrator to continue without the parent PIN.") { [weak self] approved in
            guard let self else { return }
            self.cover.isAuthorizing = false
            self.parentWindow?.level = .floating
            if approved {
                self.approvedAt = Date()
                var reset = self.state
                reset.attempts.reset()
                _ = self.replace(with: reset)
                MediaPauser.requestPermission()
            }
            self.cover.focus()
            done(approved)
        }
    }

    @objc private func showAbout() {
        guard !cover.isShowing else { return }
        let window = aboutWindow ?? makeWindow(title: "About Sleepy Paws", view: AboutView())
        aboutWindow = window
        present(window)
    }

    @objc private func openSettings() {
        guard !cover.isShowing else { return }
        if let settingsWindow, settingsWindow.isVisible { present(settingsWindow); return }
        if state.pin == nil { showSettings() }
        else { askParent("Settings", purpose: "to open Settings") { [weak self] in self?.showSettings() } }
    }

    @objc private func askToQuit() {
        guard !cover.isShowing else { return }
        if state.pin == nil { NSApp.terminate(nil); return }
        askParent("Quit", purpose: "to quit Sleepy Paws") { [weak self] in
            self?.approvedQuit = true
            NSApp.terminate(nil)
        }
    }

    private func askParent(_ title: String, purpose: String, approved: @escaping () -> Void) {
        parentWindow?.orderOut(nil)
        let view = ParentPrompt(purpose: purpose, submit: { [weak self] pin in
            guard let self else { return nil }
            if let error = self.authenticate(pin) { return error }
            self.parentWindow?.orderOut(nil)
            self.parentWindow = nil
            MediaPauser.requestPermission()
            approved()
            return nil
        }, cancel: { [weak self] in self?.parentWindow?.close() }, forgotPIN: { [weak self] in
            self?.checkAdministrator { passed in
                guard passed, let self else { return }
                self.parentWindow?.orderOut(nil)
                self.parentWindow = nil
                approved()
            }
        })
        let window = makeWindow(title: title, view: view)
        parentWindow = window
        present(window)
    }

    private func showSettings() {
        let window: NSWindow
        if state.pin == nil {
            window = makeWindow(title: "Sleepy Paws", view: OnboardingView(
                save: { [weak self] in
                    self?.saveSettings(minutes: DailyBudget.defaultMinutes, pin: $0)
                }
            ))
        } else {
            window = makeWindow(title: "Settings", view: SetupView(
                save: { [weak self] in self?.saveSettings(minutes: $0, pin: nil) },
                changePIN: { [weak self] pin in
                    guard let self else { return "Try again" }
                    return self.changePIN(pin)
                },
                minutes: state.budget.minutes
            ))
        }
        settingsWindow = window
        present(window)
    }

    /// Changes only the PIN, without touching today's countdown.
    private func changePIN(_ pin: String) -> String? {
        var edited = state
        do { edited.pin = try ParentPIN(pin) }
        catch {
            log.error("Could not set the PIN")
            return "Couldn’t save the parent PIN. Try again"
        }
        edited.attempts.reset()
        return replace(with: edited) ? nil : "Couldn’t save the PIN. Try again"
    }

    private func saveSettings(minutes: Int, pin: String?) -> String? {
        var edited = state
        edited.budget.restart(minutes: minutes) // the countdown starts over from the saved limit
        if let pin {
            do { edited.pin = try ParentPIN(pin) }
            catch {
                log.error("Could not set the PIN")
                return "Couldn’t save the parent PIN. Try again."
            }
            edited.attempts.reset()
        }
        guard replace(with: edited) else { return "Couldn’t save your settings. Try again." }
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
        // Ask for media player Automation now, while a parent is here, not behind the break screen.
        MediaPauser.requestPermission()
        tick()
        return nil
    }


    private func playSound() {
        sound?.stop()
        if sound?.play() != true { log.error("Could not play the break sound") }
    }

    private func authenticate(_ pin: String) -> String? {
        let now = Date()
        let wait = state.attempts.wait(at: now)
        if wait > 0 { return "Too many wrong PINs. Try again in \(wait) seconds" }
        var edited = state
        do {
            if try edited.pin?.matches(pin) == true {
                edited.attempts.reset()
                return replace(with: edited) ? nil : "Couldn’t save. Try again."
            }
        } catch {
            log.error("Could not verify the PIN")
            return "Couldn’t check the PIN. Try again."
        }
        edited.attempts.failed(at: now)
        guard replace(with: edited) else { return "Couldn’t save. Try again." }
        if state.attempts.wait(at: now) > 0 {
            return "Too many wrong PINs. Try again in \(Int(PINAttempts.lockout)) seconds"
        }
        let left = state.attempts.triesLeft
        return "Wrong PIN. \(left) \(left == 1 ? "try" : "tries") left before a \(Int(PINAttempts.lockout))-second wait"
    }

    private func replace(with edited: LocalState) -> Bool {
        do {
            try edited.save(to: stateURL, mirror: BackgroundAgent.defaults)
            state = edited
            stateIsDirty = false
            saveFailed = false
            lastSave = ProcessInfo.processInfo.systemUptime
            return true
        } catch {
            if !saveFailed { log.error("Could not save local state: \((error as NSError).code, privacy: .public)") }
            saveFailed = true
            return false
        }
    }

    private func persist() {
        if stateIsDirty {
            _ = replace(with: state)
            lastSave = ProcessInfo.processInfo.systemUptime
        }
    }

    private func makeWindow<Content: View>(title: String, view: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }

    private func present(_ window: NSWindow) {
        let cursor = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main,
           !window.isVisible || window.screen != screen {
            let area = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: area.midX - window.frame.width / 2,
                y: area.midY - window.frame.height / 2
            ))
        }
        window.orderFrontRegardless()
        NSApp.forceActivate()
        window.makeKeyAndOrderFront(nil)
    }

}

private extension URL {
    static var applicationSupportDirectoryCompat: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

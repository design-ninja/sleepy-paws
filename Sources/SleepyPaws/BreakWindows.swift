import AppKit
import Carbon
import OSLog
import SwiftUI

@MainActor
final class BreakWindows {
    private class Cover: NSWindow {
        /// Only the window with the PIN pad may take the keyboard; a click on another display
        /// must not steal key status from it.
        var takesKeyboard = false
        override var canBecomeKey: Bool { takesKeyboard }
        override var canBecomeMain: Bool { takesKeyboard }
        override func performClose(_ sender: Any?) {}

        override func sendEvent(_ event: NSEvent) {
            // Esc would otherwise cancel or close things on the cover; it does nothing here.
            if event.type == .keyDown && event.keyCode == UInt16(kVK_Escape) {
                return
            }
            super.sendEvent(event)
        }
    }

    private var windows: [Cover] = []
    private var previousPresentation: NSApplication.PresentationOptions?
    /// Presentation options to put back once a fade-out finishes.
    private var pendingRestore: NSApplication.PresentationOptions?
    private static let fadeIn: TimeInterval = 0.45
    nonisolated private static let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "cover")
    private static let fadeOut: TimeInterval = 0.35
    private var content: (options: [Int], initial: Int, verify: (String) -> String?, unlock: (BreakAction) -> String?)?
    var rememberExtra: (Int) -> Void = { _ in }
    /// While the system password dialog is up, don't pull the keyboard away from it.
    var isAuthorizing = false
    var forgotPIN: (@escaping @MainActor (Bool) -> Void) -> Void = { _ in }
    private var activationObserver: NSObjectProtocol?
    var isShowing: Bool { content != nil }
    func show(extraOptions: [Int], initialExtra: Int, verify: @escaping (String) -> String?,
              unlock: @escaping (BreakAction) -> String?) {
        let wasShowing = isShowing
        content = (extraOptions, initialExtra, verify, unlock)
        if !wasShowing { MediaPauser.pauseAll() }
        if activationObserver == nil {
            // Anything that activates another app (Spotlight, a notification, a Dock-less launch)
            // must not leave it usable: take the keyboard back right away.
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                MainActor.assumeIsolated { self?.focus() }
            }
        }
        if previousPresentation == nil {
            // Shown again while the last cover is still fading out: keep the original options.
            previousPresentation = pendingRestore ?? NSApp.presentationOptions
            pendingRestore = nil
            NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableAppleMenu,
                                         .disableProcessSwitching, .disableForceQuit, .disableHideApplication,
                                         .disableMenuBarTransparency]
        }
        rebuild()
    }

    /// Rebuilds the covers only when the displays really changed. Hiding the Dock and menu bar
    /// for the cover also posts a screen-parameters change, which must not rebuild the windows
    /// in the middle of their fade-in.
    func screensChanged() {
        let frames = NSScreen.screens.map(\.frame)
        guard frames != windows.map(\.frame) else { return }
        rebuild()
    }

    func rebuild() {
        guard let content else { return }

        let screens = NSScreen.screens
        let primary = screens.first
        let old = windows
        let fades = old.isEmpty // a first appearance fades in; a display change swaps instantly
        windows = screens.map { screen in
            let window = Cover(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.takesKeyboard = screen == primary
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.animationBehavior = .none
            window.isMovable = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.title = "Time’s up!"

            let material = NSVisualEffectView()
            material.material = .fullScreenUI
            material.blendingMode = .behindWindow
            material.state = .active
            let view = NSHostingView(rootView: BreakView(
                extraOptions: content.options,
                initialExtra: content.initial,
                rememberExtra: { [weak self] in self?.rememberExtra($0) },
                hasControls: screen == primary,
                verify: content.verify,
                unlock: content.unlock,
                forgotPIN: { [weak self] done in self?.forgotPIN(done) }
            ))
            view.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                view.topAnchor.constraint(equalTo: material.topAnchor),
                view.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            window.contentView = material
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
        focus()
        old.forEach { $0.orderOut(nil) }
        // A rebuild during the fade-in carries on from where the old covers were.
        let alpha = fades ? 0 : (old.first?.alphaValue ?? 1)
        windows.forEach { $0.alphaValue = alpha }
        if alpha < 1 {
            Self.log.debug("Fading in from \(alpha, privacy: .public), rebuild: \(!fades, privacy: .public)")
            Self.fade(windows, to: 1, duration: Self.fadeIn * Double(1 - alpha))
        }
        // Safety net: the cover must never stay see-through, whatever happened to the fade.
        let shown = windows
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeIn + 0.35) { [weak self] in
            guard let self, self.isShowing else { return }
            shown.forEach { if $0.alphaValue < 1 { $0.alphaValue = 1 } }
        }
    }

    func focus() {
        guard isShowing, !isAuthorizing else { return }
        NSApp.forceActivate()
        windows.first { $0.takesKeyboard }?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard let previousPresentation else { return }
        content = nil
        self.previousPresentation = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        let closing = windows
        windows.removeAll()
        pendingRestore = previousPresentation
        closing.forEach { $0.ignoresMouseEvents = true }
        Self.fade(closing, to: 0, duration: Self.fadeOut) { [weak self] in
            closing.forEach { $0.orderOut(nil) }
            guard let self, !self.isShowing, let restore = self.pendingRestore else { return }
            self.pendingRestore = nil
            NSApp.presentationOptions = restore
        }
    }

    /// Fades window opacity with a display-rate timer. Core Animation's window animator was
    /// unreliable for these borderless screen-saver-level windows.
    private static func fade(_ windows: [NSWindow], to target: CGFloat, duration: TimeInterval,
                             completion: @escaping () -> Void = {}) {
        let start = windows.map(\.alphaValue)
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            let progress = min(1, (CACurrentMediaTime() - began) / duration)
            let eased = target > 0 ? 1 - pow(1 - progress, 3) : progress * progress // ease out / in
            for (window, from) in zip(windows, start) {
                window.alphaValue = from + (target - from) * CGFloat(eased)
            }
            if progress >= 1 {
                log.debug("Fade to \(target, privacy: .public) done")
                timer.invalidate()
                MainActor.assumeIsolated { completion() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

extension NSApplication {
    /// `activate()` on macOS 14+ is cooperative and is refused while the child is using another
    /// app, which leaves keystrokes going to that app behind the cover. Force the activation.
    func forceActivate() {
        activate(ignoringOtherApps: true)
    }
}

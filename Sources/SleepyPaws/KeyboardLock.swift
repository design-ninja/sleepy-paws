import AppKit
import ApplicationServices
import OSLog

/// While the break screen is up, swallows every key and system event except what the PIN pad
/// needs (digits, Delete, Return, Tab), before macOS handles shortcuts: Cmd-Tab, Spotlight,
/// Mission Control, Launchpad, function and media keys, Cmd-Q and the rest.
///
/// Needs the Accessibility permission, which a parent grants once from Settings. Without it the
/// break screen still relies on the system's presentation options.
@MainActor
final class KeyboardLock {
    private static let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "keyboard")

    /// Off while the system password dialog ("Forgot PIN?") needs the whole keyboard.
    var suspended = false {
        didSet { Self.state.suspended = suspended }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and opens Privacy & Security → Accessibility.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        guard tap == nil else { return }
        guard Self.isTrusted else {
            Self.log.info("No Accessibility permission; shortcuts aren't blocked")
            return
        }
        let mask: CGEventMask = ~0 // every event type; the callback decides
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: Self.callback, userInfo: nil) else {
            Self.log.error("Could not install the keyboard lock")
            return
        }
        Self.state.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        Self.log.info("Keyboard lock on")
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        Self.state.tap = nil
        Self.log.info("Keyboard lock off")
    }

    // MARK: - Event filter (runs on the main run loop)

    private final class State: @unchecked Sendable {
        var tap: CFMachPort?
        var suspended = false
    }

    nonisolated private static let state = State()

    /// Digits (top row and keypad), Delete, Forward Delete, Return, Enter and Tab.
    nonisolated private static let allowedKeys: Set<Int64> = Set(
        [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] + [82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
            + [51, 117, 36, 76, 48]
    )

    /// The power button / Touch ID key (sleep, lock screen): a system-defined event, either the
    /// power-key subtype or the power key among the auxiliary (media) keys.
    nonisolated private static func isPowerButton(type: CGEventType, event: CGEvent) -> Bool {
        guard type.rawValue == 14, let system = NSEvent(cgEvent: event) else { return false } // NX_SYSDEFINED
        if system.subtype.rawValue == 1 { return true }             // NX_SUBTYPE_POWER_KEY
        guard system.subtype.rawValue == 8 else { return false }    // NX_SUBTYPE_AUX_CONTROL_BUTTONS
        return (system.data1 & 0xFFFF_0000) >> 16 == 6              // NX_POWER_KEY
    }

    nonisolated private static let callback: CGEventTapCallBack = { _, type, event, _ in
        let state = KeyboardLock.state
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = state.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel, .flagsChanged:
            return Unmanaged.passUnretained(event) // clicks on the cover; modifier state
        default:
            break
        }
        if state.suspended { return Unmanaged.passUnretained(event) }
        if type == .keyDown || type == .keyUp {
            let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn])
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if flags.isEmpty && allowedKeys.contains(key) { return Unmanaged.passUnretained(event) }
            // Ctrl-Cmd-Q, Lock Screen: locking isn't a way out, the cover is back after login.
            if flags == [.maskCommand, .maskControl] && key == 12 { return Unmanaged.passUnretained(event) }
        }
        if isPowerButton(type: type, event: event) { return Unmanaged.passUnretained(event) }
        // Everything else: shortcuts, function and media keys (system-defined events),
        // trackpad gestures (Mission Control, App Exposé), and so on.
        return nil
    }
}

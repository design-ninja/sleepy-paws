import SwiftUI
import SleepyPawsCore

/// Four PIN cells, used everywhere a PIN is entered. A key-catching view behind the cells
/// handles typing, so it works the same in the borderless break screen and in regular windows.
struct PINPad: View {
    enum Size { case large, regular }

    let label: String
    @Binding var digits: PINDigits
    var size = Size.regular
    /// Whether the cells hold the keyboard. Set it to true to move the keyboard here.
    @Binding var focused: Bool
    /// Increase to shake the cells, after a wrong PIN.
    var shakes = 0
    /// The PIN was accepted: the cells turn green and stop taking input.
    var accepted = false
    var submit: () -> Void = {}

    init(label: String, digits: Binding<PINDigits>, size: Size = .regular,
         focused: Binding<Bool> = .constant(false), shakes: Int = 0, accepted: Bool = false,
         submit: @escaping () -> Void = {}) {
        self.label = label
        _digits = digits
        self.size = size
        _focused = focused
        self.shakes = shakes
        self.accepted = accepted
        self.submit = submit
    }

    private var cell: CGFloat { size == .large ? 54 : 34 }

    var body: some View {
        HStack(spacing: size == .large ? 10 : 6) {
            ForEach(digits.slots.indices, id: \.self) { index in
                let shape = RoundedRectangle(cornerRadius: size == .large ? 10 : 7)
                let current = !accepted && focused && index == min(digits.count, digits.slots.count - 1)
                ZStack {
                    // Compact cells are opaque, like text fields, so they look the same on a
                    // window, a sheet or a grouped form row.
                    shape.fill(accepted ? Color.green.opacity(0.18)
                               : size == .large ? Color.primary.opacity(0.08)
                               : Color(nsColor: .textBackgroundColor))
                    shape.strokeBorder(accepted ? Color.green : current ? Color.accentColor : Color.primary.opacity(0.22),
                                       lineWidth: accepted || current ? 2 : 1)
                    if !digits.slots[index].isEmpty {
                        Circle().fill(accepted ? Color.green : Color.primary).frame(width: cell / 4, height: cell / 4)
                    }
                }
                .frame(width: cell, height: cell)
            }
        }
        .modifier(Shake(shakes: CGFloat(shakes)))
        .animation(.linear(duration: 0.4), value: shakes)
        .animation(.easeOut(duration: 0.2), value: accepted)
        .accessibilityValue(accepted ? "PIN accepted" : "")
        .overlay(
            PINKeyCatcher(
                label: label,
                filled: digits.count,
                focused: $focused,
                type: { if !accepted { digits.type($0) } },
                delete: { if !accepted { digits.deleteLast() } },
                submit: submit
            )
        )
    }
}

/// A quick horizontal shake, like a rejected password on the macOS login window.
private struct Shake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(shakes * .pi * 6), y: 0))
    }
}

private struct PINKeyCatcher: NSViewRepresentable {
    let label: String
    let filled: Int
    @Binding var focused: Bool
    let type: (String) -> Void
    let delete: () -> Void
    let submit: () -> Void

    final class KeyView: NSView {
        var type: (String) -> Void = { _ in }
        var delete: () -> Void = {}
        var submit: () -> Void = {}
        var focusChanged: (Bool) -> Void = { _ in }
        /// Take the keyboard whenever the window becomes key (the break screen and prompts).
        var wantsFocus = false
        private var observer: NSObjectProtocol?

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { focusChanged(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { focusChanged(false) }
            return resigned
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { if self?.wantsFocus == true { self?.takeFocus() } }
            }
            DispatchQueue.main.async { [weak self] in
                if self?.wantsFocus == true { self?.takeFocus() }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func takeFocus() {
            guard let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }

        override func mouseDown(with event: NSEvent) { takeFocus() }

        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            switch Int(event.keyCode) {
            case 51, 117: delete()                 // Delete, Forward Delete
            case 36, 76: submit()                  // Return, Enter
            case 48:                               // Tab, Shift-Tab
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
                else { window?.selectNextKeyView(self) }
            default:
                guard modifiers.isEmpty, let characters = event.characters, !characters.isEmpty else {
                    super.keyDown(with: event)
                    return
                }
                type(characters)
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Paste with Command-V.
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "v",
               window?.firstResponder === self,
               let text = NSPasteboard.general.string(forType: .string) {
                type(text)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.textField)
        view.setAccessibilitySubrole(.secureTextField)
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.type = type
        view.delete = delete
        view.submit = submit
        let focused = $focused
        view.focusChanged = { value in
            DispatchQueue.main.async { if focused.wrappedValue != value { focused.wrappedValue = value } }
        }
        view.wantsFocus = focused.wrappedValue
        if focused.wrappedValue, view.window?.firstResponder !== view {
            DispatchQueue.main.async { view.takeFocus() }
        }
        view.setAccessibilityLabel(label)
        view.setAccessibilityValue("\(filled) of \(ParentPIN.length) digits entered")
    }
}

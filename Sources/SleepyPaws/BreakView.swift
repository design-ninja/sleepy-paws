import SwiftUI
import SleepyPawsCore

/// What a parent chose on the break screen.
enum BreakAction { case addTime(minutes: Int), pause }

struct BreakView: View {
    /// The amounts a parent can add, and the one picked last time.
    let extraOptions: [Int]
    let initialExtra: Int
    /// Remembers a newly picked amount for the next break.
    var rememberExtra: (Int) -> Void = { _ in }
    var hasControls = true
    /// Checks a complete PIN; returns an error to show, or nil when it is right.
    let verify: (String) -> String?
    /// Runs a choice after the PIN (or an administrator) approved; returns an error to show.
    let unlock: (BreakAction) -> String?
    /// Runs the administrator check and reports whether it passed.
    var forgotPIN: (@escaping @MainActor (Bool) -> Void) -> Void = { _ in }

    private enum Approval { case pin, administrator }

    @State private var pin = PINDigits()
    @State private var extra: Int?
    @State private var approval: Approval?
    @State private var checking = false
    @State private var pinFocused = true
    @State private var shakes = 0
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            AppBadge(size: 82)
            VStack(spacing: 4) {
                Text("Time’s up!")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if hasControls {
                    // Problems replace the subtitle, so nothing below moves.
                    Text(error ?? "Ask a grown-up for more time")
                        .foregroundStyle(error == nil ? Color.secondary : Color.red)
                        .animation(.easeInOut(duration: 0.15), value: error)
                }
            }

            if hasControls {
                VStack(spacing: 22) {
                    if approval == .administrator {
                        Label("Approved by an administrator", systemImage: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                            .frame(height: 54)
                    } else {
                        PINPad(label: "Parent PIN", digits: $pin, size: .large, focused: $pinFocused,
                               shakes: shakes, accepted: approval == .pin) { submit(.addTime(minutes: amount)) }
                            .onChange(of: pin.isComplete) { complete in
                                // Let the last dot appear before the (deliberately slow) PIN check.
                                if complete { DispatchQueue.main.async(execute: check) }
                            }
                            .onChange(of: pin.count) { count in
                                if count > 0 { error = nil } // typing again clears the message
                            }
                    }
                    // One control: − and + change how much the blue button adds.
                    HStack(spacing: 8) {
                        Button { step(-1) } label: {
                            Image(systemName: "minus").frame(width: 14)
                        }
                        .disabled(optionIndex == 0)
                        .accessibilityLabel("Less time")
                        Button { submit(.addTime(minutes: amount)) } label: {
                            Text("Add \(DurationText.short(amount))")
                                .monospacedDigit()
                                .frame(minWidth: 110)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        Button { step(1) } label: {
                            Image(systemName: "plus").frame(width: 14)
                        }
                        .disabled(optionIndex == extraOptions.count - 1)
                        .accessibilityLabel("More time")
                    }
                    .modalButtonShape()
                    .controlSize(.large)
                    .disabled(approval == nil)
                    // Before the PIN: Forgot PIN?. After it: the rarer choice, a pause for today.
                    ZStack {
                        Button("Forgot PIN?") {
                            checking = true
                            forgotPIN { approved in
                                checking = false
                                if approved {
                                    approval = .administrator
                                    error = nil
                                }
                            }
                        }
                        .disabled(checking || approval != nil)
                        .opacity(approval == nil ? 1 : 0)
                        Button("Pause until midnight") { submit(.pause) }
                            .disabled(approval == nil)
                            .opacity(approval == nil ? 0 : 1)
                    }
                    .buttonStyle(.link)
                    .padding(.top, 4)
                }
                .padding(.top, 18)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55).ignoresSafeArea())
    }

    private func check() {
        guard pin.isComplete else { return }
        if let problem = verify(pin.value) {
            pin = PINDigits()
            error = problem
            shakes += 1
        } else { // keep the dots; the cells turn green
            error = nil
            approval = .pin
        }
    }

    private var amount: Int { extra ?? initialExtra }

    private var optionIndex: Int { extraOptions.firstIndex(of: amount) ?? 0 }

    private func step(_ offset: Int) {
        let index = min(max(optionIndex + offset, 0), extraOptions.count - 1)
        extra = extraOptions[index]
        rememberExtra(extraOptions[index])
    }

    private func submit(_ action: BreakAction) {
        guard approval != nil else { return }
        error = unlock(action)
        approval = nil
        pin = PINDigits()
    }
}

private extension View {
    /// Capsule buttons, as in system alerts and sheets on current macOS.
    @ViewBuilder
    func modalButtonShape() -> some View {
        if #available(macOS 14.0, *) { buttonBorderShape(.capsule) } else { self }
    }
}

import SwiftUI
import SleepyPawsCore

struct AppBadge: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Settings, in the grouped-form style of System Settings.
struct SetupView: View {
    /// Saves a new daily limit (and restarts today's countdown); returns an error to show.
    let save: (Int) -> String?
    /// Saves a new parent PIN; returns an error to show.
    let changePIN: (String) -> String?

    @State var minutes: Int
    @State private var hoursText = ""
    @State private var minutesText = ""
    @State private var changingPIN = false
    @State private var pinChanged = false
    @State private var error: String?

    var body: some View {
        if #available(macOS 13, *) {
            Form {
                // The pane card System Settings opens with: big icon, name, one line about it.
                Section {
                    VStack(spacing: 0) {
                        AppBadge(size: 56)
                            .padding(.bottom, 8)
                        Text("Sleepy Paws")
                            .font(.title3.weight(.semibold))
                        Text("A gentle nudge when it’s time for a break")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section("Screen Time") {
                    LabeledContent("Daily limit") {
                        DailyLimitFields(hours: $hoursText, minutes: $minutesText)
                    }
                }
                Section {
                    LabeledContent {
                        Button("Change PIN…") { changingPIN = true }
                    } label: {
                        Text("Parent PIN")
                        Text(pinChanged ? "Changed" : "Needed to add time, pause or open Settings")
                    }
                } footer: {
                    footer
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 460, height: 384)
            .onAppear(perform: fillLimit)
            .sheet(isPresented: $changingPIN) { sheet }
        } else {
            Form {
                Section(header: Text("Screen Time")) {
                    HStack { Text("Daily limit"); Spacer(); DailyLimitFields(hours: $hoursText, minutes: $minutesText) }
                }
                Section(header: Text("Parent PIN")) {
                    HStack { Text("Parent PIN"); Spacer(); Button("Change PIN…") { changingPIN = true } }
                }
                footer
            }
            .padding(20)
            .frame(width: 460)
            .onAppear(perform: fillLimit)
            .sheet(isPresented: $changingPIN) { sheet }
        }
    }

    private var sheet: some View {
        ChangePINSheet(change: { newPIN in
            if let problem = changePIN(newPIN) { return problem }
            pinChanged = true
            changingPIN = false
            return nil
        }, cancel: { changingPIN = false })
    }

    private var footer: some View {
        HStack {
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Save", action: submit)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 6)
    }

    private func fillLimit() {
        hoursText = String(minutes / 60)
        minutesText = String(minutes % 60)
    }

    private func submit() {
        guard let minutes = DailyLimitFields.limit(hours: hoursText, minutes: minutesText) else {
            error = "Enter a daily limit from 1 minute to 12 hours"
            return
        }
        error = save(minutes)
    }
}

/// Hours and minutes fields with stepper arrows, used in Settings and onboarding. Typing is
/// checked on save, so any minute from 0 to 59 can be entered though the arrows step by five.
struct DailyLimitFields: View {
    @Binding var hours: String
    @Binding var minutes: String

    var body: some View {
        HStack(spacing: 6) {
            field($hours, unit: "h", range: 0...12, step: 1, label: "Hours")
            field($minutes, unit: "min", range: 0...55, step: 5, label: "Minutes")
                .padding(.leading, 12)
        }
    }

    /// The limit in minutes, if the two fields hold a valid one.
    static func limit(hours: String, minutes: String) -> Int? {
        func number(_ text: String) -> Int? {
            let text = text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? 0 : Int(text)
        }
        guard let h = number(hours), let m = number(minutes), (0...12).contains(h), (0...59).contains(m)
        else { return nil }
        let total = h * 60 + m
        return DailyBudget.limits.contains(total) ? total : nil
    }

    private func field(_ text: Binding<String>, unit: String, range: ClosedRange<Int>,
                       step: Int, label: String) -> some View {
        HStack(spacing: 6) {
            // The stepper sits right against its field, the unit comes after them.
            HStack(spacing: 2) {
                TextField(label, text: text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 38)
                    .accessibilityLabel("Daily limit, \(label.lowercased())")
                Stepper(label, value: Binding(
                    get: { Int(text.wrappedValue) ?? 0 },
                    set: { text.wrappedValue = String($0) }
                ), in: range, step: step)
                .labelsHidden()
            }
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct ParentPrompt: View {
    /// What the PIN is for, finishing "Enter the parent PIN …", such as "to open Settings".
    let purpose: String
    let submit: (String) -> String?
    let cancel: () -> Void
    var forgotPIN: () -> Void = {}

    @State private var pin = PINDigits()
    @State private var pinFocused = true
    @State private var shakes = 0
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                .padding(.bottom, 16)
            VStack(spacing: 4) {
                Text("Enter the parent PIN").font(.headline)
                // Problems replace the purpose line. Two lines stay reserved below the title,
                // so the window doesn't jump when a longer message appears.
                Text(error ?? purpose)
                    .foregroundStyle(error == nil ? Color.secondary : Color.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .top)
            }
            .padding(.bottom, 14)
            PINPad(label: "Parent PIN", digits: $pin, focused: $pinFocused, shakes: shakes, submit: send)
                .onChange(of: pin.isComplete) { complete in
                    // Check as soon as the fourth digit is in, after it has been drawn.
                    if complete { DispatchQueue.main.async(execute: send) }
                }
                .onChange(of: pin.count) { count in
                    if count > 0 { error = nil }
                }
                .padding(.bottom, 14)
            Button("Forgot PIN?", action: forgotPIN)
                .buttonStyle(.link)
                .padding(.bottom, 24)
            // The PIN is checked on its fourth digit, so there is nothing else to press.
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 330)
    }

    private func send() {
        guard pin.isComplete else { return }
        error = submit(pin.value)
        pin = PINDigits()
        if error != nil { shakes += 1 }
    }
}

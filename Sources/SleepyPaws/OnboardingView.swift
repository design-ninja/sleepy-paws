import SwiftUI
import SleepyPawsCore

/// Two centred rows of PIN cells, "PIN" and "Repeat PIN", for creating a new parent PIN.
/// The keyboard moves to the second row by itself; a mismatch shakes it and clears it.
struct NewPINRows: View {
    /// Called with the PIN once both rows match; returns an error to show, if any.
    let done: (String) -> String?
    @Binding var message: String?

    @State private var pin = PINDigits()
    @State private var repeated = PINDigits()
    @State private var pinFocused = true
    @State private var repeatFocused = false
    @State private var shakes = 0

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("PIN").font(.callout).foregroundStyle(.secondary)
                PINPad(label: "New PIN", digits: $pin, focused: $pinFocused)
                    .onChange(of: pin.isComplete) { complete in
                        if complete { repeatFocused = true }
                    }
            }
            VStack(spacing: 6) {
                Text("Repeat PIN").font(.callout).foregroundStyle(.secondary)
                PINPad(label: "Repeat PIN", digits: $repeated, focused: $repeatFocused, shakes: shakes)
                    .onChange(of: repeated.isComplete) { complete in
                        if complete { DispatchQueue.main.async(execute: finish) }
                    }
            }
        }
        .onChange(of: pin.count) { if $0 > 0 { message = nil } }
        .onChange(of: repeated.count) { if $0 > 0 { message = nil } }
    }

    private func finish() {
        guard repeated.isComplete else { return }
        guard pin.isComplete else {
            message = "Enter the PIN in the first row"
            repeated = PINDigits()
            pinFocused = true
            return
        }
        guard repeated == pin else {
            message = "The PINs don’t match. Repeat it again"
            repeated = PINDigits()
            shakes += 1
            return
        }
        message = done(pin.value)
    }
}

/// First launch: create the parent PIN; the timer starts with the default limit.
struct OnboardingView: View {
    let save: (String) -> String?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            AppBadge(size: 64)
                .padding(.bottom, 14)
            Text("Welcome to Sleepy Paws")
                .font(.title2.weight(.semibold))
            Text(message ?? "Create a four-digit parent PIN")
                .foregroundStyle(message == nil ? Color.secondary : Color.red)
                .padding(.top, 4)
                .padding(.bottom, 20)
            NewPINRows(done: save, message: $message)
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 32)
        .frame(width: 330)
    }
}

/// The Change PIN… sheet in Settings.
struct ChangePINSheet: View {
    let change: (String) -> String?
    let cancel: () -> Void
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
            Text("Change Parent PIN")
                .font(.headline)
            Text(message ?? "Enter a new four-digit PIN")
                .foregroundStyle(message == nil ? Color.secondary : Color.red)
                .padding(.top, 4)
                .padding(.bottom, 20)
            NewPINRows(done: change, message: $message)
                .padding(.bottom, 24)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 330)
    }
}

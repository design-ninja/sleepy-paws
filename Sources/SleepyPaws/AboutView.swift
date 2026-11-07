import SwiftUI

struct AboutView: View {
    /// One size for every line under the name.
    private static let small = Font.system(size: 12)
    static let repository = URL(string: "https://github.com/design-ninja/sleepy-paws")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            AppBadge(size: 64)
                .padding(.bottom, 14)
            Text("Sleepy Paws")
                .font(.system(size: 17, weight: .semibold))
            Text("Version \(version)")
                .font(Self.small)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            Text("A gentle screen-time limit for kids")
                .font(Self.small)
                .padding(.top, 18)
            Link("GitHub", destination: Self.repository)
                .font(Self.small)
                .fixedSize()
                .padding(.top, 6)
            Text("© 2026 lirik")
                .font(Self.small)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(minWidth: 280)
    }
}

import Foundation
import OSLog
import SleepyPawsCore

/// Saved progress, the parent PIN and failed attempts.
///
/// Two copies are kept: `state.json` in Application Support and a mirror in the app's
/// UserDefaults. Loading takes the stricter copy, so deleting, corrupting or editing one of
/// them can't reset the day's usage or remove the PIN.
struct LocalState: Codable {
    var budget = DailyBudget()
    var pin: ParentPIN?
    var attempts = PINAttempts()

    private static let mirrorKey = "LocalState.mirror"
    private static let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "state")

    static func load(from url: URL, mirror defaults: UserDefaults = .standard) -> Self {
        let file = decode(try? Data(contentsOf: url), source: "file")
        let mirror = decode(defaults.data(forKey: mirrorKey), source: "mirror")
        switch (file, mirror) {
        case let (file?, mirror?): return stricter(file, mirror)
        case let (file?, nil): return file
        case let (nil, mirror?): return mirror
        case (nil, nil): return Self()
        }
    }

    func save(to url: URL, mirror defaults: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(self)
        defaults.set(data, forKey: Self.mirrorKey)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
    }

    private static func decode(_ data: Data?, source: StaticString) -> Self? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            log.error("Ignoring unreadable saved state (\(source, privacy: .public))")
            return nil
        }
    }

    /// Combines two copies, keeping the stricter budget and any PIN.
    static func stricter(_ a: Self, _ b: Self) -> Self {
        var result = a
        result.budget = DailyBudget.stricter(a.budget, b.budget)
        // Keep a PIN if either copy has one; when both do, the mirror is harder to find and edit.
        result.pin = b.pin ?? a.pin
        if b.attempts.wait(at: Date()) > a.attempts.wait(at: Date()) { result.attempts = b.attempts }
        return result
    }
}

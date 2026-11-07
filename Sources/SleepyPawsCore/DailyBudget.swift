import Foundation

public struct DailyBudget: Codable {
    public static let defaultMinutes = 60
    public static let limits = 1...720

    public private(set) var minutes = defaultMinutes
    private var day = ""
    private var spent: TimeInterval = 0
    private var extra: TimeInterval = 0
    /// The day a parent paused the timer. Optional so state saved before pausing existed
    /// still decodes; a pause ends by itself when the next day starts.
    private var pausedDay: String?

    public init() {}

    public var remaining: TimeInterval { max(0, allowance - spent) }
    public var expired: Bool { remaining == 0 }
    /// While paused, no time is counted and the break screen stays away.
    public var isPaused: Bool { pausedDay != nil && pausedDay == day }
    /// Whether the break screen should be up.
    public var blocks: Bool { expired && !isPaused }
    private var allowance: TimeInterval { Double(minutes * 60) + extra }

    /// Of two saved copies, the one that leaves less time: a later day wins, and on the same
    /// day the copy with less time remaining. Editing or deleting one copy can't add time.
    public static func stricter(_ a: Self, _ b: Self) -> Self {
        if a.day != b.day { return a.day > b.day ? a : b }
        // A pause is written to both copies, so one that only one copy has was added by hand.
        if a.isPaused != b.isPaused { return a.isPaused ? b : a }
        return a.remaining <= b.remaining ? a : b
    }

    public mutating func setLimit(minutes: Int) {
        precondition(Self.limits.contains(minutes))
        self.minutes = minutes
    }

    /// Sets a new limit and starts today's countdown from it, as when a parent saves Settings.
    public mutating func restart(minutes: Int) {
        setLimit(minutes: minutes)
        spent = 0
        extra = 0
        pausedDay = nil
    }

    public mutating func pause() { pausedDay = day }

    public mutating func resume() { pausedDay = nil }

    /// Adds time on top of whatever was used, by default one more daily limit.
    public mutating func grantExtraTime(minutes added: Int? = nil) {
        let base = Double(minutes * 60)
        extra = max(extra, spent - base) + Double((added ?? minutes) * 60)
    }

    public mutating func record(_ elapsed: TimeInterval, at now: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let today = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        var elapsed = max(0, elapsed)
        if today > day {
            day = today
            spent = 0
            extra = 0
            pausedDay = nil
            elapsed = min(elapsed, now.timeIntervalSince(calendar.startOfDay(for: now)))
        }
        if !expired && !isPaused { spent = min(allowance, spent + elapsed) }
    }
}

public struct PINAttempts: Codable {
    public static let limit = 5
    public static let lockout: TimeInterval = 30

    private var failures = 0
    private var retryAfter: Date?

    public init() {}

    /// Wrong PINs still allowed before the next wait.
    public var triesLeft: Int { Self.limit - failures }

    public func wait(at now: Date) -> Int {
        Int(ceil(max(0, retryAfter?.timeIntervalSince(now) ?? 0)))
    }

    public mutating func failed(at now: Date) {
        failures += 1
        if failures == Self.limit {
            retryAfter = now.addingTimeInterval(Self.lockout)
            failures = 0
        }
    }

    public mutating func reset() { self = Self() }
}

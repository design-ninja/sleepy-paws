import Foundation

public struct UsageClock {
    private var previous: (uptime: TimeInterval, counts: Bool)?

    public init() {}

    public mutating func sample(at uptime: TimeInterval, counts: Bool) -> TimeInterval {
        defer { previous = (uptime, counts) }
        guard counts, let previous, previous.counts else { return 0 }
        return max(0, uptime - previous.uptime)
    }
}

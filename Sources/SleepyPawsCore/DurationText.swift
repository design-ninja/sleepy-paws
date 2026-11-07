/// Short, readable durations for buttons and the menu bar.
public enum DurationText {
    /// "1 Minute", "30 Minutes", "1 Hour", "2 Hours", "4 h 30 min".
    public static func minutes(_ total: Int) -> String {
        let hours = total / 60, minutes = total % 60
        switch (hours, minutes) {
        case (0, 1): return "1 Minute"
        case (0, _): return "\(minutes) Minutes"
        case (1, 0): return "1 Hour"
        case (_, 0): return "\(hours) Hours"
        default: return "\(hours) h \(minutes) min"
        }
    }

    /// Compact: "5m", "30m", "1h", "1h 30m".
    public static func short(_ total: Int) -> String {
        let hours = total / 60, minutes = total % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)m"
        }
    }

    /// A countdown: "29:59", or "4:29:59" from an hour up.
    public static func countdown(seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds / 60 % 60, rest = seconds % 60
        return hours > 0
            ? "\(hours):\(pad(minutes)):\(pad(rest))"
            : "\(minutes):\(pad(rest))"
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}

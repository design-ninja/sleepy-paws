import CoreGraphics
import IOKit
import IOKit.pwr_mgt

final class MacUsageState {
    private let powerDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))

    deinit {
        if powerDomain != IO_OBJECT_NULL { IOObjectRelease(powerDomain) }
    }

    var lidIsClosed: Bool {
        guard powerDomain != IO_OBJECT_NULL else { return false }
        let value = IORegistryEntryCreateCFProperty(powerDomain, kAppleClamshellStateKey as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? Bool == true
    }

    var sessionIsUnlocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        // Quartz's public console/login flags also remain true on the lock screen.
        return session["kCGSSessionOnConsoleKey"] as? Bool == true
            && session["kCGSessionLoginDoneKey"] as? Bool == true
            && session["CGSSessionScreenIsLocked"] as? Bool != true
    }
}

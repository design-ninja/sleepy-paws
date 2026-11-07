import AppKit
import Darwin
import OSLog

/// Freezes the apps behind the break screen with SIGSTOP, so nothing moves, plays or counts
/// down underneath it, and thaws them with SIGCONT when the break ends.
///
/// Only regular (Dock) apps are frozen, together with their child processes and the XPC
/// services they are responsible for (a browser's video, for example, plays in a helper).
/// System UI, accessibility, this app and SecurityAgent (needed for "Forgot PIN?") are never
/// touched.
/// Frozen PIDs are saved, and every launch thaws them, so a crash can't leave apps stuck.
@MainActor
final class AppFreezer {
    private static let defaultsKey = "AppFreezer.pids"
    private static let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "freeze")

    /// Apps that keep running: system UI and accessibility.
    private static let spared: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.controlcenter",
        "com.apple.notificationcenterui", "com.apple.loginwindow", "com.apple.SecurityAgent",
        "com.apple.VoiceOver", "com.apple.accessibility.AccessibilityVisualsAgent",
    ]

    private let defaults: UserDefaults
    private var frozen: Set<pid_t> = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
        frozen = Set((defaults.array(forKey: Self.defaultsKey) as? [Int] ?? []).map { pid_t($0) })
    }

    var isFrozen: Bool { !frozen.isEmpty }

    /// Freezes every regular app (and its helpers) that isn't frozen yet.
    func freeze() {
        let me = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
                && !Self.spared.contains($0.bundleIdentifier ?? "")
        }
        let roots = Set(apps.map(\.processIdentifier))
        guard !roots.isEmpty else { return }
        let targets = Self.processes(belongingTo: roots).subtracting([me]).subtracting(frozen)
        guard !targets.isEmpty else { return }
        for pid in targets where kill(pid, SIGSTOP) == 0 {
            frozen.insert(pid)
        }
        persist()
        Self.log.info("Froze \(targets.count, privacy: .public) processes of \(roots.count, privacy: .public) apps")
    }

    /// Lets everything frozen run again. Cheap when nothing is frozen.
    func thaw() {
        guard !frozen.isEmpty else { return }
        for pid in frozen { kill(pid, SIGCONT) } // harmless for a PID that is gone or running
        Self.log.info("Thawed \(self.frozen.count, privacy: .public) processes")
        frozen.removeAll()
        persist()
    }

    private func persist() {
        if frozen.isEmpty { defaults.removeObject(forKey: Self.defaultsKey) }
        else { defaults.set(frozen.map { Int($0) }, forKey: Self.defaultsKey) }
    }

    // MARK: - Process tree

    /// The roots, their descendants, and processes the roots are responsible for (XPC helpers).
    private static func processes(belongingTo roots: Set<pid_t>) -> Set<pid_t> {
        let all = userProcesses()
        var children: [pid_t: [pid_t]] = [:]
        for process in all { children[process.parent, default: []].append(process.pid) }

        var result = roots
        var queue = Array(roots)
        while let pid = queue.popLast() {
            for child in children[pid] ?? [] where result.insert(child).inserted { queue.append(child) }
        }
        if let responsible = responsiblePID {
            for process in all where !result.contains(process.pid) && roots.contains(responsible(process.pid)) {
                result.insert(process.pid)
            }
        }
        return result
    }

    /// All processes of the current user, with their parents.
    private static func userProcesses() -> [(pid: pid_t, parent: pid_t)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var list = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = list.count * stride
        guard sysctl(&mib, 4, &list, &size, nil, 0) == 0 else { return [] }
        return list.prefix(size / stride).map { ($0.kp_proc.p_pid, $0.kp_eproc.e_ppid) }
    }

    /// `responsibility_get_pid_responsible_for_pid`: which app an XPC service works for.
    private static let responsiblePID: ((pid_t) -> pid_t)? = {
        typealias Function = @convention(c) (pid_t) -> pid_t
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        let function = unsafeBitCast(symbol, to: Function.self)
        return { function($0) }
    }()
}

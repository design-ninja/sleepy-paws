import AppKit
import OSLog
import ServiceManagement

/// Keeps Sleepy Paws running: a per-user launchd agent starts it at login and restarts it
/// within a couple of seconds if the process is killed or crashes (Activity Monitor,
/// `killall`). A normal quit (after the parent PIN, or at logout and shutdown) exits with
/// status 0, which the agent's `KeepAlive` → `SuccessfulExit = false` rule leaves alone.
///
/// The agent is a plain plist in ~/Library/LaunchAgents with the app's absolute path. The app
/// rewrites and reloads it whenever it is missing, edited, or points at another copy.
enum BackgroundAgent {
    static let label = "pro.lirik.sleepypaws.agent"

    private static let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "agent")
    private static var domain: String { "gui/\(getuid())" }
    private static var service: String { "\(domain)/\(label)" }

    /// Debug builds launched with `SLEEPYPAWS_TEST=1` run on their own, with separate defaults,
    /// next to the real copy. Use together with `CFFIXED_USER_HOME` for a separate state file.
    static var isTestInstance: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SLEEPYPAWS_TEST"] == "1"
        #else
        return false
        #endif
    }

    static var defaults: UserDefaults {
        isTestInstance ? UserDefaults(suiteName: "pro.lirik.sleepypaws.test")! : .standard
    }

    /// Whether launchd started this process for the agent.
    static var isAgentInstance: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label
    }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var plist: [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath ?? ""],
            "AssociatedBundleIdentifiers": [Bundle.main.bundleIdentifier ?? ""],
            "RunAtLoad": true,
            // Restart after a kill or crash, but not after a normal quit (exit status 0).
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 2,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
    }

    /// Called before the app starts. Returns false when this process should exit right away
    /// because another instance is (or will be) running.
    @MainActor
    static func shouldLaunch() -> Bool {
        guard !isTestInstance else { return true }
        if !isAgentInstance && plistIsCurrent && isLoaded {
            // Opened by hand while the agent is set up: start the agent's copy instead, so the
            // running app is always the one launchd keeps alive.
            launchctl("kickstart", service)
            if wait(4, until: { agentIsRunning }) { return false }
            log.error("The background agent didn't start; running this copy")
            return true
        }
        // A previous copy may still be quitting during a handover; give it a moment.
        return wait(3, until: { !otherInstanceIsRunning })
    }

    enum Installation { case running, handOver, unavailable }

    /// Installs and loads the agent. `.handOver` means launchd's own copy has started and this
    /// one should quit; `.unavailable` means this copy keeps running without the agent.
    @MainActor
    static func install() -> Installation {
        guard !isTestInstance else { return .running }
        // Earlier builds used a plain login item; the agent replaces it.
        if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        if isAgentInstance && plistIsCurrent { return .running }
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            log.error("Could not write the background agent: \((error as NSError).code, privacy: .public)")
            return .unavailable
        }
        // Unloading its own job would end this copy, so launchd picks up the new plist next time.
        if isAgentInstance { return .running }
        if isLoaded { launchctl("bootout", service) }
        // The agent's copy starts right away (RunAtLoad) and waits for this one to quit.
        guard launchctl("bootstrap", domain, plistURL.path) else {
            log.error("Could not load the background agent")
            return .unavailable
        }
        if wait(4, until: { agentIsRunning }) { return .handOver }
        log.error("The background agent didn't start; running without it")
        return .unavailable
    }

    /// The installed plist exists and starts this copy of the app.
    private static var plistIsCurrent: Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let installed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary
        else { return false }
        return installed.isEqual(to: plist)
    }

    private static var isLoaded: Bool { launchctl("print", service) }

    /// launchd has a process running for the agent. (It may not show up as a running app yet:
    /// it waits for this copy to quit before it starts its user interface.)
    private static var agentIsRunning: Bool {
        var output = ""
        guard launchctl("print", service, output: &output) else { return false }
        return output.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("pid = ") }
    }

    /// Runs the run loop until `condition` holds or `seconds` pass; returns the condition.
    private static func wait(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private static var otherInstanceIsRunning: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != me && !$0.isTerminated }
    }

    @discardableResult
    private static func launchctl(_ arguments: String...) -> Bool {
        var output = ""
        return launchctl(arguments, output: &output)
    }

    private static func launchctl(_ arguments: String..., output: inout String) -> Bool {
        launchctl(arguments, output: &output)
    }

    private static func launchctl(_ arguments: [String], output: inout String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        output = String(decoding: data, as: UTF8.self)
        return process.terminationStatus == 0
    }
}

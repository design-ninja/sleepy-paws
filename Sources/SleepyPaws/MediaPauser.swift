import AppKit
import CoreServices
import OSLog

/// Pauses whatever is playing when the break screen appears.
///
/// 1. A system "pause" media command goes to the Now Playing app — any browser playing
///    video or music through Media Session, Music, Spotify, Podcasts and so on.
/// 2. Players with an AppleScript `pause` command that are running get it directly, because
///    only one app owns Now Playing at a time. This needs the Automation permission for each
///    player, which is asked while a parent is at the Mac, never behind the break screen.
///
/// Anything still audible after that (a second browser tab, Firefox, a game) is silenced by
/// `AudioGuard` for as long as the break screen is up.
enum MediaPauser {
    private struct Player {
        let bundleID: String
        let script: String
    }

    private static let players = [
        Player(bundleID: "com.apple.Music", script: "pause"),
        Player(bundleID: "com.spotify.client", script: "pause"),
        Player(bundleID: "com.apple.TV", script: "pause"),
        Player(bundleID: "com.apple.QuickTimePlayerX", script: "pause every document"),
        Player(bundleID: "org.videolan.vlc", script: "if playing then play"), // VLC's play toggles
    ]

    private static let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "media")

    private static var runningPlayers: [Player] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return players.filter { running.contains($0.bundleID) }
    }

    /// Asks for the Automation permission for each running player. Call only when a parent
    /// is at the Mac; does nothing for players whose permission was already decided.
    @MainActor
    static func requestPermission() {
        for player in runningPlayers {
            DispatchQueue.global(qos: .utility).async {
                _ = automationStatus(of: player.bundleID, ask: true)
            }
        }
    }

    @MainActor
    static func pauseAll() {
        sendSystemPause()
        for player in runningPlayers {
            DispatchQueue.global(qos: .userInitiated).async {
                let status = automationStatus(of: player.bundleID, ask: false)
                guard status == noErr else {
                    log.info("No Automation permission for \(player.bundleID, privacy: .public) (\(status, privacy: .public))")
                    return
                }
                let paused = run("""
                    with timeout of 3 seconds
                        tell application id "\(player.bundleID)" to \(player.script)
                    end timeout
                    """)
                log.info("Paused \(player.bundleID, privacy: .public): \(paused, privacy: .public)")
            }
        }
    }

    private static func automationStatus(of bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    }

    /// Runs a script in `osascript` and kills it if the target app doesn't answer in time,
    /// so a hung player can never pile up work in this process.
    private static func run(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return false }
        if done.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    /// Sends MediaRemote's "pause" (not "toggle") command to the current Now Playing app.
    private static func sendSystemPause() {
        typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return }
        let send = unsafeBitCast(symbol, to: SendCommand.self)
        let pause: UInt32 = 1 // kMRPause
        if !send(pause, nil) { log.info("System pause command was not accepted") }
    }
}

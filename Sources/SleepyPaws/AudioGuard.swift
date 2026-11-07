import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// Keeps every app silent while the break screen is up by muting the current output device
/// (or turning its volume down when it has no mute control), and puts things back afterwards.
///
/// `enforce()` is called on every timer tick, so a press of the volume keys or a switch to
/// headphones is undone within a quarter of a second. What was changed is also written to
/// UserDefaults, so a crash or forced quit doesn't leave the Mac muted: `restore()` at launch
/// puts it back.
@MainActor
final class AudioGuard {
    /// The original value of each setting this guard changed, by device UID.
    private struct Change: Codable, Equatable {
        var mute: UInt32?
        var volume: Float32?
    }

    private static let defaultsKey = "AudioGuard.changes"
    private let log = Logger(subsystem: "pro.lirik.sleepypaws", category: "audio")
    private var changes: [String: Change] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: Change].self, from: data) {
            changes = saved
        }
    }

    func enforce() {
        guard let device = Self.defaultOutputDevice, let uid = Self.uid(of: device) else { return }
        let before = changes[uid] ?? Change()
        var change = before

        if let mute = Self.mute(of: device) {
            if mute == 0, Self.setMute(1, of: device) {
                if change.mute == nil { change.mute = 0 }
            }
        } else if let volume = Self.volume(of: device), volume > 0, Self.setVolume(0, of: device) {
            if change.volume == nil { change.volume = volume }
        }

        if change != before {
            changes[uid] = change
            persist()
        }
    }

    /// Puts back what `enforce()` changed. Cheap when there is nothing to restore, so it is
    /// called on every tick while the break screen is hidden.
    func restore() {
        guard !changes.isEmpty else { return }
        for (uid, change) in changes {
            // A device that isn't connected right now (headphones) is restored when it's back.
            guard let device = Self.device(uid: uid) else { continue }
            if let mute = change.mute, !Self.setMute(mute, of: device) {
                log.error("Could not unmute an output device")
            }
            if let volume = change.volume, !Self.setVolume(volume, of: device) {
                log.error("Could not restore an output device's volume")
            }
            changes[uid] = nil
        }
        persist()
    }

    private func persist() {
        if changes.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(changes) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var defaultOutputDevice: AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func uid(of device: AudioDeviceID) -> String? {
        var address = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func device(uid: String) -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func mute(of device: AudioDeviceID) -> UInt32? {
        var address = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return nil }
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr ? mute : nil
    }

    private static func setMute(_ mute: UInt32, of device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var mute = mute
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute) == noErr
    }

    private static func volume(of device: AudioDeviceID) -> Float32? {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    private static func setVolume(_ volume: Float32, of device: AudioDeviceID) -> Bool {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var volume = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume) == noErr
    }
}

import Foundation
import CoreAudio
import AudioToolbox

/// Coupe le son du Mac pendant la dictée (musique, YouTube, vidéos…), quelle que soit l'app qui joue,
/// puis le remet exactement comme avant. Bonus : la musique ne se mélange plus à la voix dans le micro.
@MainActor
final class AudioDucker {
    private var device: AudioDeviceID?
    private var savedVolume: Float32?
    private var usedMute = false
    private var fadeTask: Task<Void, Never>?

    private static let pendingVolumeKey = "pendingVolumeRestore"
    private static let pendingMuteKey = "pendingUnmute"

    var isDucking: Bool { device != nil }

    /// Baisse le son en fondu (≈ 0,2 s). Ne fait rien si le son est déjà coupé.
    func duck() {
        guard device == nil, let output = Self.defaultOutputDevice() else { return }

        if Self.canSetVolume(output), let volume = Self.volume(output) {
            guard volume > 0.001, Self.isMuted(output) != true else { return }
            device = output
            savedVolume = volume
            UserDefaults.standard.set(Double(volume), forKey: Self.pendingVolumeKey)
            fadeTask = Task { @MainActor in
                let steps = 8
                for step in 1...steps {
                    if Task.isCancelled { return }
                    Self.setVolume(output, volume * Float32(steps - step) / Float32(steps))
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
            }
        } else if Self.canSetMute(output), Self.isMuted(output) == false {
            device = output
            usedMute = true
            UserDefaults.standard.set(true, forKey: Self.pendingMuteKey)
            Self.setMuted(output, true)
        }
    }

    /// Remet le son tel qu'il était avant la dictée.
    func restore() {
        fadeTask?.cancel()
        fadeTask = nil
        guard let device else { return }
        if usedMute {
            Self.setMuted(device, false)
        } else if let savedVolume {
            Self.setVolume(device, savedVolume)
        }
        self.device = nil
        savedVolume = nil
        usedMute = false
        UserDefaults.standard.removeObject(forKey: Self.pendingVolumeKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingMuteKey)
    }

    /// Au lancement : si Plume s'est arrêtée en pleine dictée, on rend le son.
    static func restorePendingIfNeeded() {
        let defaults = UserDefaults.standard
        guard let output = defaultOutputDevice() else { return }
        if let volume = defaults.object(forKey: pendingVolumeKey) as? Double {
            if canSetVolume(output) { setVolume(output, Float32(volume)) }
            defaults.removeObject(forKey: pendingVolumeKey)
        }
        if defaults.bool(forKey: pendingMuteKey) {
            if canSetMute(output) { setMuted(output, false) }
            defaults.removeObject(forKey: pendingMuteKey)
        }
    }

    // MARK: - Core Audio

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        var address = volumeAddress()
        guard AudioHardwareServiceHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioHardwareServiceIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func volume(_ device: AudioDeviceID) -> Float32? {
        var address = volumeAddress()
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioHardwareServiceGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func setVolume(_ device: AudioDeviceID, _ volume: Float32) {
        var address = volumeAddress()
        var value = max(0, min(1, volume))
        _ = AudioHardwareServiceSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private static func canSetMute(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value != 0 : nil
    }

    private static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var address = muteAddress()
        var value: UInt32 = muted ? 1 : 0
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

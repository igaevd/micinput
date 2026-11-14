import CoreAudio
import Foundation

/// A connected audio device. One physical device can be an input, an output, or both.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    let isInput: Bool
    let isOutput: Bool

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }

    /// The connection type, worded like the "Type" column in System Settings › Sound.
    var kind: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "Built-in"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "Bluetooth"
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: "Thunderbolt"
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: "Continuity Camera"
        case kAudioDeviceTransportTypeVirtual: "Virtual"
        case kAudioDeviceTransportTypeAggregate: "Aggregate"
        default: "Audio device"
        }
    }
}

/// Thin wrapper over the few Core Audio calls micinput needs.
enum Audio {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// Every visible device that can be picked as the system input or output.
    static func devices() -> [AudioDevice] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard number(id, kAudioDevicePropertyIsHidden) == 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            let isInput = canBeDefault(id, kAudioObjectPropertyScopeInput)
            let isOutput = canBeDefault(id, kAudioObjectPropertyScopeOutput)
            guard isInput || isOutput else { return nil }
            return AudioDevice(id: id, uid: uid, name: name,
                               transport: number(id, kAudioDevicePropertyTransportType),
                               isInput: isInput, isOutput: isOutput)
        }
    }

    static var defaultInput: AudioDeviceID { number(system, kAudioHardwarePropertyDefaultInputDevice) }
    static var defaultOutput: AudioDeviceID { number(system, kAudioHardwarePropertyDefaultOutputDevice) }

    @discardableResult
    static func setDefaultInput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(system, &address, 0, nil, size, &id) == noErr
    }

    /// Calls `handler` on the main queue whenever devices come or go, or the system input/output changes.
    static func observe(_ handler: @escaping @MainActor () -> Void) {
        for selector in [kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultInputDevice,
                         kAudioHardwarePropertyDefaultOutputDevice] {
            var address = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &address, .main) { _, _ in
                MainActor.assumeIsolated(handler)
            }
        }
    }

    // MARK: - Property plumbing

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func number(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32 {
        var address = address(selector, scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// True when the device has streams in `scope` and macOS allows it as the default there.
    private static func canBeDefault(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        return number(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope) != 0
    }
}

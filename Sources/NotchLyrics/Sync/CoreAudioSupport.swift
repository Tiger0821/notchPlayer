import CoreAudio
import Foundation

/// Small helpers for reading Core Audio object properties.
enum CoreAudioProperty {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) -> T? {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        var result = initial
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? result : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var result: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let result else { return nil }
        return result.takeRetainedValue() as String
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? ids : []
    }

    static var defaultOutputDevice: AudioObjectID? {
        let device = value(system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown))
        return device == AudioObjectID(kAudioObjectUnknown) ? nil : device
    }
}

/// Delay between audio being rendered and being heard on the current output device (large for Bluetooth).
@MainActor
final class OutputLatencyMonitor: ObservableObject {
    @Published private(set) var latency: TimeInterval = 0
    @Published private(set) var deviceName = ""
    @Published private(set) var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        refresh()
        var address = CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(CoreAudioProperty.system, &address, .main) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard let device = CoreAudioProperty.defaultOutputDevice,
              let rate = CoreAudioProperty.value(device, kAudioDevicePropertyNominalSampleRate, initial: Float64(0)), rate > 0
        else {
            latency = 0
            deviceName = ""
            deviceID = AudioObjectID(kAudioObjectUnknown)
            return
        }
        let output = kAudioObjectPropertyScopeOutput
        let deviceFrames = [kAudioDevicePropertyLatency, kAudioDevicePropertySafetyOffset, kAudioDevicePropertyBufferFrameSize]
            .map { CoreAudioProperty.value(device, $0, scope: output, initial: UInt32(0)) ?? 0 }
            .reduce(0, +)
        let streamFrames = CoreAudioProperty.objects(device, kAudioDevicePropertyStreams, scope: output).first
            .flatMap { CoreAudioProperty.value($0, kAudioStreamPropertyLatency, initial: UInt32(0)) } ?? 0

        latency = Double(deviceFrames + streamFrames) / rate
        deviceName = CoreAudioProperty.string(device, kAudioObjectPropertyName) ?? ""
        deviceID = device
        Log.sync.info("output device \(self.deviceName, privacy: .public): latency \(self.latency, format: .fixed(precision: 3))s")
    }
}

import CoreAudio
import Foundation
import QuartzCore

/// Captures Music.app's audio output with a Core Audio process tap. macOS asks for "System Audio Recording"
/// permission the first time; if it's denied the tap only delivers silence.
final class MusicAudioTap: @unchecked Sendable {
    /// Mono Float32 samples, their sample rate, and the host time (CACurrentMediaTime clock) of the first sample.
    typealias Handler = @Sendable (_ samples: [Float], _ sampleRate: Double, _ hostTime: CFTimeInterval) -> Void

    struct TapError: Error, CustomStringConvertible {
        let description: String
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "NotchLyrics.AudioTap", qos: .userInteractive)

    deinit { stop() }

    func start(bundleID: String, handler: @escaping Handler) throws {
        stop()
        let processes = Self.audioProcesses(bundleIDPrefix: bundleID)
        guard !processes.isEmpty else { throw TapError(description: "\(bundleID) has no audio process") }

        let description = CATapDescription(monoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "NotchLyrics"

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create process tap")
        tapID = tap

        guard let format = CoreAudioProperty.value(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription()),
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            throw TapError(description: "unsupported tap format")
        }
        let sampleRate = format.mSampleRate

        guard let output = CoreAudioProperty.defaultOutputDevice,
              let outputUID = CoreAudioProperty.string(output, kAudioDevicePropertyDeviceUID) else {
            throw TapError(description: "no output device")
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchLyrics Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var aggregateDevice = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateDevice), "create aggregate device")
        aggregateID = aggregateDevice

        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDevice, ioQueue) { _, inputData, inputTime, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            guard let first = buffers.first, let raw = first.mData else { return }
            let channels = max(Int(first.mNumberChannels), 1)
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
            guard frames > 0 else { return }

            let source = raw.assumingMemoryBound(to: Float.self)
            var mono = [Float](repeating: 0, count: frames)
            if channels == 1 {
                mono.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: source, count: frames) }
            } else {
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels { sum += source[frame * channels + channel] }
                    mono[frame] = sum / Float(channels)
                }
            }
            let timestamp = inputTime.pointee
            let hostTime = timestamp.mFlags.contains(.hostTimeValid)
                ? Double(AudioConvertHostTimeToNanos(timestamp.mHostTime)) / 1_000_000_000
                : CACurrentMediaTime()
            handler(mono, sampleRate, hostTime)
        }, "create IO proc")
        ioProcID = procID
        try check(AudioDeviceStart(aggregateDevice, procID), "start capture")
    }

    func stop() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Core Audio process objects belonging to an app (including helper processes with the same bundle prefix).
    static func audioProcesses(bundleIDPrefix: String) -> [AudioObjectID] {
        CoreAudioProperty.objects(CoreAudioProperty.system, kAudioHardwarePropertyProcessObjectList).filter {
            CoreAudioProperty.string($0, kAudioProcessPropertyBundleID)?.hasPrefix(bundleIDPrefix) == true
        }
    }

    /// Bundle IDs of processes currently playing audio, for diagnostics.
    static func processesPlayingAudio() -> [String] {
        CoreAudioProperty.objects(CoreAudioProperty.system, kAudioHardwarePropertyProcessObjectList).compactMap { process in
            guard CoreAudioProperty.value(process, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) == 1 else { return nil }
            return CoreAudioProperty.string(process, kAudioProcessPropertyBundleID) ?? "pid \(CoreAudioProperty.value(process, kAudioProcessPropertyPID, initial: pid_t(0)) ?? 0)"
        }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw TapError(description: "\(step) failed (\(status))") }
    }
}

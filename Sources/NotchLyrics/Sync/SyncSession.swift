import AVFAudio
import CoreMedia
import Foundation
import LyricsCore
import os
import Speech

/// One listening session: taps Music's audio, transcribes the singing on-device, and reports recognized
/// words timed on the song's playback clock.
final class SyncSession: @unchecked Sendable {
    enum Event: Sendable {
        case preparingModel
        case listening(locale: String)
        case units([TimedUnit])
        /// Periodic capture stats: seconds of audio fed while playing, and the share that was pure silence.
        case audio(seconds: Double, silentFraction: Double)
        case failed(String)
    }

    private struct Mark: Sendable {
        var sample: AVAudioFramePosition
        var position: TimeInterval
        var trackID: String?
    }

    private let trackID: String
    private let clock: PlaybackClock
    private let tap = MusicAudioTap()
    private let processing = DispatchQueue(label: "NotchLyrics.SyncSession")
    private let marks = OSAllocatedUnfairLock(initialState: [Mark]())

    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    // Only touched on `processing`.
    private var analyzerFormat: AVAudioFormat?
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var fedFrames: AVAudioFramePosition = 0
    private var fedSeconds = 0.0
    private var silentSeconds = 0.0
    private var lastStatsReport = 0.0

    init(trackID: String, clock: PlaybackClock) {
        self.trackID = trackID
        self.clock = clock
    }

    func start(locale requested: Locale, phrases: [String], onEvent: @escaping @Sendable (Event) -> Void) async {
        do {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
                onEvent(.failed("speech recognition doesn't support \(requested.identifier)"))
                return
            }
            let transcriber = SpeechTranscriber(
                locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                onEvent(.preparingModel)
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                onEvent(.failed("no compatible audio format"))
                return
            }

            let analyzer = SpeechAnalyzer(
                modules: [transcriber], options: SpeechAnalyzer.Options(priority: .utility, modelRetention: .whileInUse))
            // Hint the recognizer with the song's own lines; sung words are much easier to catch when expected.
            let context = AnalysisContext()
            context.contextualStrings[.general] = phrases
            try? await analyzer.setContext(context)

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer
            self.continuation = continuation
            processing.sync { analyzerFormat = format }

            let sampleRate = format.sampleRate
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        let units = self.units(from: result, sampleRate: sampleRate)
                        if !units.isEmpty { onEvent(.units(units)) }
                    }
                } catch {
                    if !Task.isCancelled { onEvent(.failed("transcription: \(error.localizedDescription)")) }
                }
            }

            try await analyzer.start(inputSequence: stream)
            try tap.start(bundleID: "com.apple.Music") { [weak self] samples, rate, hostTime in
                self?.processing.async { self?.ingest(samples, rate: rate, hostTime: hostTime, onEvent: onEvent) }
            }
            Log.sync.info("listening: locale=\(locale.identifier, privacy: .public) phrases=\(phrases.count) playing-audio=\(MusicAudioTap.processesPlayingAudio(), privacy: .public)")
            onEvent(.listening(locale: locale.identifier))
        } catch {
            onEvent(.failed(String(describing: error)))
        }
    }

    func stop() async {
        tap.stop()
        continuation?.finish()
        continuation = nil
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
    }

    // MARK: - Audio

    private func ingest(_ samples: [Float], rate: Double, hostTime: CFTimeInterval, onEvent: @Sendable (Event) -> Void) {
        guard let analyzerFormat, let continuation else { return }
        let playback = clock.position(at: hostTime)
        guard playback.isPlaying, playback.trackID == trackID else { return }

        if inputFormat?.sampleRate != rate {
            inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
            converter = inputFormat.flatMap { AVAudioConverter(from: $0, to: analyzerFormat) }
        }
        guard let inputFormat, let converter,
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let duration = Double(samples.count) / rate
        fedSeconds += duration
        if samples.allSatisfy({ $0 == 0 }) { silentSeconds += duration }
        if fedSeconds - lastStatsReport >= 5 {
            lastStatsReport = fedSeconds
            onEvent(.audio(seconds: fedSeconds, silentFraction: silentSeconds / fedSeconds))
        }

        let capacity = AVAudioFrameCount(Double(samples.count) * analyzerFormat.sampleRate / rate) + 256
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0 else { return }

        let startSample = fedFrames
        marks.withLock { marks in
            marks.append(Mark(sample: startSample, position: playback.position, trackID: playback.trackID))
            if marks.count > 40_000 { marks.removeFirst(10_000) }
        }
        fedFrames += AVAudioFramePosition(output.frameLength)
        continuation.yield(AnalyzerInput(buffer: output))
    }

    // MARK: - Results

    /// Maps a time on the analyzer's input stream back to the song position when that audio was captured.
    private func songPosition(atStreamTime seconds: Double, sampleRate: Double) -> TimeInterval? {
        let sample = AVAudioFramePosition(seconds * sampleRate)
        return marks.withLock { marks -> TimeInterval? in
            var low = 0, high = marks.count - 1
            var found: Int?
            while low <= high {
                let mid = (low + high) / 2
                if marks[mid].sample <= sample {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            guard let found, marks[found].trackID == trackID else { return nil }
            return marks[found].position + Double(sample - marks[found].sample) / sampleRate
        }
    }

    private func units(from result: SpeechTranscriber.Result, sampleRate: Double) -> [TimedUnit] {
        var units: [TimedUnit] = []
        for run in result.text.runs {
            guard let range = run.audioTimeRange,
                  let start = songPosition(atStreamTime: range.start.seconds, sampleRate: sampleRate),
                  let end = songPosition(atStreamTime: range.end.seconds, sampleRate: sampleRate) else { continue }
            let text = String(result.text[run.range].characters)
            units += LyricsAligner.units(from: text, start: start, end: max(start, end))
        }
        return units
    }
}

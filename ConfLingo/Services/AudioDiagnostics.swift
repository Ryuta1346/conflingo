import Foundation
import Synchronization

/// Numeric metadata only. No transcript or PCM enters this collector.
final class AudioDiagnostics: Sendable {
    enum Metric: String, Sendable {
        case tap, converted, conversionEmpty, conversionFailure, copyFailure, enqueued, yieldDropped, yieldTerminated, consumed
        case osPartial, osFinal, osEmpty, partialResult, finalResult, emptyResult, normalized, normalizationRejected
        case storeAccepted, storeRejected, inputStopped, recognitionFinished, recognitionCancelled
    }
    enum Stage: String { case stopStarted, deliveryFinished }
    struct Format: Codable, Equatable, Sendable {
        let sampleRate: Double
        let channels: UInt32
    }
    struct Input: Codable, Equatable, Sendable {
        var counts: [String: Int] = [:]
        var sampleCounts: [String: Int] = [:]
        var first: [String: Double] = [:]
        var last: [String: Double] = [:]
        var formats: [String: Format] = [:]
        var formatChanges: [String: Int] = [:]
    }
    struct Snapshot: Codable, Equatable, Sendable {
        let id: UUID
        let startedAt: Date
        var inputs: [String: Input] = [:]
        var stages: [String: Double] = [:]
    }
    private struct State {
        var active = false
        var start = 0.0
        var value: Snapshot?
    }
    private let enabled: Bool
    private let persistOnStop: Bool
    private let state = Mutex(State())

    init(enabled: Bool = true, persistOnStop: Bool = false) {
        #if DEBUG
        self.enabled = enabled
        #else
        self.enabled = false
        #endif
        self.persistOnStop = persistOnStop
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> AudioDiagnostics? {
        #if DEBUG
        if environment["CONFLINGO_AUDIO_DIAGNOSTICS"] == "1" { return AudioDiagnostics(persistOnStop: true) }
        #endif
        return nil
    }

    func begin() {
        guard enabled else { return }
        state.withLock {
            $0 = State(active: true, start: ProcessInfo.processInfo.systemUptime,
                       value: Snapshot(id: UUID(), startedAt: Date()))
        }
    }

    func record(_ metric: Metric, origin: AudioOrigin, samples: Int = 0, sampleRate: Double? = nil, channels: UInt32? = nil) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        state.withLock { state in
            guard state.active, var value = state.value else { return }
            var input = value.inputs[origin.rawValue] ?? Input()
            let key = metric.rawValue
            input.counts[key, default: 0] += 1
            if samples > 0 { input.sampleCounts[key, default: 0] += samples }
            if input.first[key] == nil { input.first[key] = now - state.start }
            input.last[key] = now - state.start
            if let sampleRate, let channels {
                let format = Format(sampleRate: sampleRate, channels: channels)
                if let previous = input.formats[key], previous != format { input.formatChanges[key, default: 0] += 1 }
                input.formats[key] = format
            }
            value.inputs[origin.rawValue] = input
            state.value = value
        }
    }

    func mark(_ stage: Stage) {
        guard enabled else { return }
        state.withLock {
            guard $0.active, $0.value?.stages[stage.rawValue] == nil else { return }
            $0.value?.stages[stage.rawValue] = ProcessInfo.processInfo.systemUptime - $0.start
        }
    }

    func finish() { state.withLock { $0.active = false } }
    var snapshot: Snapshot? { state.withLock { $0.active ? nil : $0.value } }

    func save(to url: URL) throws {
        guard let snapshot else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    func saveIfRequested() throws {
        guard persistOnStop, let snapshot else { return }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("ConfLingo/Validation/audio-diagnostics")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try save(to: directory.appendingPathComponent("\(snapshot.id).json"))
    }
}

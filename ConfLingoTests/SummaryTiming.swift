import Foundation

@MainActor
final class SummaryTiming {
    enum Stage: String, CaseIterable {
        case clientStart, transport, countStart, countEnd, generationStart
        case firstChunk, lastChunk, firstPreview, streamEnd, usageSettled
        case observerStart, observerEnd, clientEnd
    }

    struct Snapshot: Codable {
        let sectionID: String
        let startedAt: Date
        var times: [String: Double?]
        var chunkCount = 0
        var receivedBytes = 0
        var maxPreviewCharacters = 0
        var outcome = "running"
        var failure: String?
    }

    private let clock: () -> Double
    private let started: Double
    private(set) var snapshot: Snapshot

    init(sectionID: String, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        started = clock()
        snapshot = Snapshot(sectionID: sectionID, startedAt: Date(),
                            times: Dictionary(uniqueKeysWithValues: Stage.allCases.map { ($0.rawValue, Optional<Double>.none) }))
        snapshot.times[Stage.clientStart.rawValue] = 0
    }

    func mark(_ stage: Stage) {
        if snapshot.times[stage.rawValue] == .some(nil) { snapshot.times[stage.rawValue] = clock() - started }
    }

    func receive(bytes: Int) {
        guard bytes > 0 else { return }
        mark(.firstChunk)
        snapshot.times[Stage.lastChunk.rawValue] = clock() - started
        snapshot.chunkCount += 1
        snapshot.receivedBytes += bytes
    }

    func preview(characters: Int) {
        guard characters > 0 else { return }
        mark(.firstPreview)
        snapshot.maxPreviewCharacters = max(snapshot.maxPreviewCharacters, characters)
    }

    func finish(outcome: String, failure: String? = nil) {
        mark(.clientEnd)
        snapshot.outcome = outcome
        snapshot.failure = failure
    }
}

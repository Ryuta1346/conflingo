import Foundation
import Observation

struct MeetingTranslation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sourceLanguage: String
    let targetLanguage: String
    let text: String
}

struct MeetingTranslationRequest: Sendable {
    let event: TranscriptEvent
    let targetLanguage: String
    var text: String
    var terms: [String] = []

    init(event: TranscriptEvent, targetLanguage: String) {
        self.event = event
        self.targetLanguage = targetLanguage
        text = event.text
    }
}

typealias MeetingTranslationBegin = @MainActor @Sendable (UUID) -> MeetingTranslationRequest?
typealias MeetingTranslationComplete = @MainActor @Sendable (UUID, Result<String, any Error>) -> Void

protocol MeetingTranslating: Sendable {
    func run(_ ids: AsyncStream<UUID>, source: String, target: String,
             begin: @escaping MeetingTranslationBegin, complete: @escaping MeetingTranslationComplete) async
}

func processMeetingTranslations(_ ids: AsyncStream<UUID>, begin: MeetingTranslationBegin,
                                complete: MeetingTranslationComplete,
                                translate: (MeetingTranslationRequest) async throws -> String) async {
    for await id in ids {
        guard !Task.isCancelled else { return }
        guard let request = await begin(id) else { continue }
        do {
            let (masked, mapping) = TermProtector.mask(request.text, terms: request.terms)
            var protected = request
            protected.text = masked
            let translated = try await translate(protected)
            try Task.checkCancellation()
            let restored = TermProtector.unmask(translated, mapping: mapping)
            let text: String
            if restored.unresolvedTokens.isEmpty {
                text = restored.text
            } else {
                text = try await translate(request)
                try Task.checkCancellation()
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CocoaError(.coderValueNotFound)
            }
            await complete(id, .success(text))
        } catch {
            guard !Task.isCancelled else { return }
            await complete(id, .failure(error))
        }
    }
}

struct MeetingTranslationEntry {
    let request: MeetingTranslationRequest
    var state: TranslationState = .pending
    var translation: MeetingTranslation?
}

@MainActor
@Observable
final class MeetingTranslationLane: Identifiable {
    let id = UUID()
    let sourceLanguage: String
    let targetLanguage: String
    var generation = UUID()
    var ready = false
    var error: String?
    var queue: [UUID] = []
    var task: Task<Void, Never>?
    var continuation: AsyncStream<UUID>.Continuation?

    isolated deinit {
        continuation?.finish()
        task?.cancel()
    }

    init(sourceLanguage: String, targetLanguage: String) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

@MainActor
@Observable
final class MeetingTranslations {
    private(set) var sessionID: UUID
    private(set) var entries: [UUID: MeetingTranslationEntry] = [:] { didSet { displayRevision &+= 1 } }
    private(set) var displayRevision = 0
    private(set) var lanes: [MeetingTranslationLane] = []
    let requiresPreparation: Bool
    var termsForRequest: (MeetingTranslationRequest) -> [String] = { _ in [] }
    private let clientFactory: (String, String) -> any MeetingTranslating

    init(sessionID: UUID, clientFactory: @escaping (String, String) -> any MeetingTranslating = { _, _ in AppleMeetingTranslator() },
         requiresPreparation: Bool = true) {
        self.sessionID = sessionID
        self.clientFactory = clientFactory
        self.requiresPreparation = requiresPreparation
    }

    var isWorking: Bool { lanes.contains { $0.ready && !$0.queue.isEmpty } }
    var pendingCount: Int { entries.values.filter { $0.state == .pending || $0.state == .translating }.count }
    var completed: [MeetingTranslation] {
        entries.values.compactMap(\.translation).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func receive(_ event: TranscriptEvent, targetLanguage: String?) {
        guard event.sessionID == sessionID, event.isFinal, !event.text.isEmpty,
              entries[event.id] == nil, let targetLanguage, !targetLanguage.isEmpty else { return }
        let source = Locale.Language(identifier: event.languageCode).minimalIdentifier
        let target = Locale.Language(identifier: targetLanguage).minimalIdentifier
        guard source != target else { return }
        let lane: MeetingTranslationLane
        if let existing = lanes.first(where: { $0.sourceLanguage == source && $0.targetLanguage == target }) {
            lane = existing
        } else {
            lane = MeetingTranslationLane(sourceLanguage: source, targetLanguage: target)
            lane.ready = !requiresPreparation
            lanes.append(lane)
        }
        entries[event.id] = MeetingTranslationEntry(request: MeetingTranslationRequest(event: event, targetLanguage: target),
            state: lane.error.map { .failed($0) } ?? .pending)
        if lane.error == nil {
            lane.queue.append(event.id)
            lane.continuation?.yield(event.id)
        }
        process(lane)
    }

    func prepared(_ id: UUID, generation: UUID) {
        guard let lane = lanes.first(where: { $0.id == id }), lane.generation == generation,
              !lane.ready, !Task.isCancelled else { return }
        lane.ready = true
        lane.error = nil
        process(lane)
    }

    func preparationFailed(_ id: UUID, generation: UUID, message: String) {
        guard let lane = lanes.first(where: { $0.id == id }), lane.generation == generation,
              !lane.ready, !Task.isCancelled else { return }
        lane.ready = false
        lane.error = message
        for id in lane.queue { entries[id]?.state = .failed(message) }
        lane.queue = []
    }

    func retry(_ id: UUID) {
        guard let entry = entries[id], case .failed = entry.state,
              let lane = lanes.first(where: {
                  $0.sourceLanguage == Locale.Language(identifier: entry.request.event.languageCode).minimalIdentifier
                      && $0.targetLanguage == entry.request.targetLanguage
              }) else { return }
        entries[id]?.state = .pending
        lane.queue.append(id)
        lane.continuation?.yield(id)
        if !lane.ready {
            lane.error = nil
            lane.generation = UUID()
            lane.ready = !requiresPreparation
        }
        process(lane)
    }

    func reset(sessionID: UUID) {
        for lane in lanes {
            lane.continuation?.finish()
            lane.task?.cancel()
        }
        lanes = []
        entries = [:]
        self.sessionID = sessionID
    }

    private func process(_ lane: MeetingTranslationLane) {
        guard lane.ready, lane.task == nil, !lane.queue.isEmpty else { return }
        let session = sessionID
        let generation = lane.generation
        let client = clientFactory(lane.sourceLanguage, lane.targetLanguage)
        let (stream, continuation) = AsyncStream.makeStream(of: UUID.self)
        lane.continuation = continuation
        for id in lane.queue { continuation.yield(id) }
        let source = lane.sourceLanguage
        let target = lane.targetLanguage
        lane.task = Task { [weak self, weak lane] in
            await client.run(stream, source: source, target: target, begin: { [weak self, weak lane] id in
                guard let self, let lane, self.sessionID == session, lane.generation == generation,
                      !Task.isCancelled, self.entries[id]?.state == .pending else { return nil }
                guard var request = self.entries[id]?.request else { return nil }
                request.terms = self.termsForRequest(request)
                self.entries[id]?.state = .translating
                return request
            }, complete: { [weak self, weak lane] id, result in
                guard let self, let lane, self.sessionID == session, lane.generation == generation,
                      !Task.isCancelled, let entry = self.entries[id] else { return }
                lane.queue.removeAll { $0 == id }
                switch result {
                case .success(let text):
                    self.entries[id]?.translation = MeetingTranslation(id: id, sourceLanguage: entry.request.event.languageCode,
                        targetLanguage: entry.request.targetLanguage, text: text)
                    self.entries[id]?.state = .done
                case .failure(let error):
                    self.entries[id]?.state = .failed(error.localizedDescription)
                }
            })
        }
    }
}

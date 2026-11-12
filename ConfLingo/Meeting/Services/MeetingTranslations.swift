import Foundation
import Observation
import Translation

struct MeetingTranslation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sourceLanguage: String
    let targetLanguage: String
    let text: String
}

struct MeetingTranslationRequest: Sendable {
    let event: TranscriptEvent
    let targetLanguage: String
}

protocol MeetingTranslating: Sendable {
    func translate(_ request: MeetingTranslationRequest) async throws -> String
}

struct AppleMeetingTranslator: MeetingTranslating {
    func translate(_ request: MeetingTranslationRequest) async throws -> String {
        let session = TranslationSession(installedSource: Locale.Language(identifier: request.event.languageCode),
                                         target: Locale.Language(identifier: request.targetLanguage))
        return try await session.translate(request.event.text).targetText
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

    init(sourceLanguage: String, targetLanguage: String) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

@MainActor
@Observable
final class MeetingTranslations {
    private(set) var sessionID: UUID
    private(set) var entries: [UUID: MeetingTranslationEntry] = [:]
    private(set) var lanes: [MeetingTranslationLane] = []
    let requiresPreparation: Bool
    private let client: any MeetingTranslating

    init(sessionID: UUID, client: any MeetingTranslating = AppleMeetingTranslator(), requiresPreparation: Bool = true) {
        self.sessionID = sessionID
        self.client = client
        self.requiresPreparation = requiresPreparation
    }

    var isWorking: Bool { lanes.contains { $0.task != nil } }
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
        if lane.error == nil { lane.queue.append(event.id) }
        process(lane)
    }

    func prepared(_ id: UUID, generation: UUID) {
        guard let lane = lanes.first(where: { $0.id == id }), lane.generation == generation else { return }
        lane.ready = true
        lane.error = nil
        process(lane)
    }

    func preparationFailed(_ id: UUID, generation: UUID, message: String) {
        guard let lane = lanes.first(where: { $0.id == id }), lane.generation == generation else { return }
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
        if !lane.ready {
            lane.error = nil
            lane.generation = UUID()
            lane.ready = !requiresPreparation
        }
        process(lane)
    }

    func reset(sessionID: UUID) {
        for lane in lanes { lane.task?.cancel() }
        lanes = []
        entries = [:]
        self.sessionID = sessionID
    }

    private func process(_ lane: MeetingTranslationLane) {
        guard lane.ready, lane.task == nil, !lane.queue.isEmpty else { return }
        let session = sessionID
        let client = client
        lane.task = Task { [weak self, weak lane] in
            guard let lane else { return }
            defer { lane.task = nil }
            while !Task.isCancelled, let id = lane.queue.first {
                lane.queue.removeFirst()
                guard let entry = self?.entries[id], self?.sessionID == session else { return }
                self?.entries[id]?.state = .translating
                do {
                    let text = try await client.translate(entry.request)
                    try Task.checkCancellation()
                    guard self?.sessionID == session else { return }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw CocoaError(.coderValueNotFound)
                    }
                    self?.entries[id]?.translation = MeetingTranslation(id: id, sourceLanguage: entry.request.event.languageCode,
                        targetLanguage: entry.request.targetLanguage, text: text)
                    self?.entries[id]?.state = .done
                } catch {
                    guard !Task.isCancelled, self?.sessionID == session else { return }
                    self?.entries[id]?.state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class MeetingSessionStore {
    private(set) var sessionID: UUID
    private(set) var finals: [TranscriptEvent] = []
    private(set) var partials: [TranscriptEvent] = []
    private var latest: [UUID: TranscriptEvent] = [:]

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    func receive(_ event: TranscriptEvent) {
        guard event.sessionID == sessionID,
              !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let previous = latest[event.id] {
            guard !previous.isFinal, event.revision > previous.revision else { return }
        }
        latest[event.id] = event
        partials.removeAll { $0.origin == event.origin }
        if event.isFinal {
            let position = finals.firstIndex { $0.startOffset > event.startOffset } ?? finals.endIndex
            finals.insert(event, at: position)
        } else {
            partials.append(event)
        }
    }

    func clearPartials() {
        partials = []
        latest = latest.filter { $0.value.isFinal }
    }

    func reset(sessionID: UUID) {
        self.sessionID = sessionID
        finals = []
        partials = []
        latest = [:]
    }
}

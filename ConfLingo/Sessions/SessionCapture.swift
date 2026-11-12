import Foundation

extension MeetingWorkspace {
    var sessionSnapshot: SessionSnapshot? {
        guard !isSavingSession, summary.state != .sending, !knowledge.isBusy,
              let snapshot = exportSnapshot, !snapshot.events.isEmpty else { return nil }
        return .meeting(snapshot, insights.filter { $0.status == .complete })
    }

    func saveSession(to library: SessionsLibrary) async {
        guard !library.isBusy, let snapshot = sessionSnapshot else { return }
        isSavingSession = true
        defer { isSavingSession = false }
        await library.save(snapshot)
    }
}

extension SessionStore {
    func sessionSnapshot(sourceLanguage: String, targetLanguage: String?, support: ConferenceSupportSnapshot? = nil) -> SessionSnapshot? {
        guard phase == .idle, !segments.isEmpty || support?.hasCompletedAnswers == true else { return nil }
        let title = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return .conference(ConferenceSnapshot(id: sessionID, title: title.isEmpty ? "名前のない字幕" : title,
            startedAt: startedAt, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, segments: segments, units: units, support: support))
    }
}

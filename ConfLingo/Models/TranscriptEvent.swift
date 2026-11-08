import Foundation

enum AudioOrigin: String, Codable, Sendable {
    case microphone
    case systemAudio
}

struct TranscriptEvent: Identifiable, Sendable, Equatable {
    let id: UUID
    let sessionID: UUID
    let origin: AudioOrigin
    let languageCode: String
    let startOffset: TimeInterval
    let endOffset: TimeInterval?
    let text: String
    let isFinal: Bool
    let revision: Int
    /// Conferenceの保存形式は各入力開始からの時刻（取得できなければnil）を維持する。
    let sourceStartTime: TimeInterval?
}

struct SpeechResult: Sendable {
    let text: String
    let isFinal: Bool
    let startTime: TimeInterval
    let endTime: TimeInterval
}

struct TranscriptEventNormalizer {
    let sessionID: UUID
    let origin: AudioOrigin
    let languageCode: String
    let inputOffset: TimeInterval
    private var utteranceID: UUID?
    private var utteranceStart: TimeInterval?
    private var revision = 0

    init(sessionID: UUID, origin: AudioOrigin, languageCode: String, inputOffset: TimeInterval) {
        self.sessionID = sessionID
        self.origin = origin
        self.languageCode = languageCode
        self.inputOffset = inputOffset
    }

    mutating func makeEvent(_ result: SpeechResult, receivedOffset: TimeInterval) -> TranscriptEvent? {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let sourceStart = result.startTime.isFinite && result.startTime >= 0 ? result.startTime : nil
        if utteranceID == nil || utteranceStart != sourceStart {
            utteranceID = UUID()
            utteranceStart = sourceStart
            revision = 0
        }
        guard let id = utteranceID else { return nil }
        revision += 1
        let start = sourceStart.map { inputOffset + $0 } ?? receivedOffset
        let end = result.endTime.isFinite && result.endTime >= 0
            && inputOffset + result.endTime >= start ? inputOffset + result.endTime : nil
        let event = TranscriptEvent(
            id: id, sessionID: sessionID, origin: origin, languageCode: languageCode,
            startOffset: start, endOffset: end, text: text, isFinal: result.isFinal,
            revision: revision, sourceStartTime: sourceStart
        )
        if result.isFinal { utteranceID = nil }
        return event
    }
}

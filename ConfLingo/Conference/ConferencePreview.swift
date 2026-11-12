#if DEBUG
import Foundation

@MainActor
enum ConferencePreview {
    static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: "com.gavrri.conflingo.ui-preview") else {
            fatalError("Cannot create isolated preview preferences")
        }
        return defaults
    }()

    static func populate(_ session: SessionStore) {
        session.mode = .translation
        session.sessionName = "WWDC セッション"
        let examples = [
            ("Great tools help us stay present in the conversation, without getting in the way.",
             "優れた道具は、会話の妨げにならず、その場に集中する手助けをします。"),
            ("With on-device speech recognition, spoken words become useful context while audio stays on the Mac.",
             "オンデバイスの音声認識で、音声をMacに保ったまま、話し言葉を役立つ文脈に変えることができます。")
        ]
        for (index, example) in examples.enumerated() {
            if let id = session.appendFinal(example.0, startTime: Double(index * 15 + 492)),
               let unit = session.bufferSegment(id) {
                session.applyTranslation(id: unit.id, japanese: example.1)
            }
        }
    }
}
#endif

import Foundation

// Display cache is not exercised by this store/adapter probe.
@MainActor enum TranscriptPresentation { final class Cache {} }

@main struct Probe {
    @MainActor static func main() async {
        print("case,conference_segments,meeting_finals,translation_queue,markdown_segments")
        for name in ["distinct_same_source", "same_id_replay", "different_sources", "restart_same_text", "japanese_repeat"] {
            let session = UUID()
            let store = SessionStore()
            let meeting = MeetingSessionStore(sessionID: session)
            let coordinator = TranslationCoordinator()
            let stream = coordinator.attach()
            var adapter = LegacyTranslationAdapter(sessionID: session, store: store, coordinator: coordinator, origins: [.microphone, .systemAudio])
            var normalizer = TranscriptEventNormalizer(sessionID: session, origin: .microphone, languageCode: "en-US", inputOffset: 0)
            let text = name == "japanese_repeat" ? "はい。" : "Yes."
            let first = normalizer.makeEvent(SpeechResult(text: text, isFinal: true, startTime: 1, endTime: 2), receivedOffset: 2)!
            let second: TranscriptEvent
            if name == "same_id_replay" {
                second = first
            } else if name == "different_sources" {
                var other = TranscriptEventNormalizer(sessionID: session, origin: .systemAudio, languageCode: "en-US", inputOffset: 0)
                second = other.makeEvent(SpeechResult(text: text, isFinal: true, startTime: 3, endTime: 4), receivedOffset: 4)!
            } else {
                second = normalizer.makeEvent(SpeechResult(text: text, isFinal: true, startTime: 3, endTime: 4), receivedOffset: 4)!
                precondition(first.id != second.id)
            }
            adapter.receive(first)
            meeting.receive(first)
            if name == "restart_same_text" {
                await adapter.finish()
                adapter = LegacyTranslationAdapter(sessionID: session, store: store, coordinator: coordinator)
            }
            adapter.receive(second)
            meeting.receive(second)
            await adapter.finish()
            coordinator.finish()
            var queued = 0
            for await _ in stream { queued += 1 }
            let markdown = MarkdownExporter.render(sessionName: "probe", date: nil, segments: store.segments, sourceLanguage: "en-US", targetLanguage: nil)
            let exported = markdown.components(separatedBy: "### Segment ").count - 1
            print("\(name),\(store.segments.count),\(meeting.finals.count),\(queued),\(exported)")
            let expectedConference = name == "different_sources" ? 2 : 1
            precondition(store.segments.count == expectedConference)
            precondition(meeting.finals.count == (name == "same_id_replay" ? 1 : 2))
            precondition(queued == expectedConference && exported == expectedConference)
        }
    }
}

import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct MeetingExportTests {
    @Test func exportSeparatesReviewStatesAndEscapesUntrustedText() throws {
        let store = summaryStore(count: 1)
        let event = try #require(store.finals.first)
        let candidateStore = MeetingCandidateStore(transcript: store)
        for (index, review) in MeetingCandidate.Review.allCases.enumerated() {
            let card = MeetingInsight(kind: index == 1 ? .decisionCandidate : .actionCandidate,
                                      text: "Item \(index)\n# Confirmed <script> [x](https://invalid)", priority: 1, evidenceIDs: [event.id])
            candidateStore.receive(card, sessionID: store.sessionID)
            candidateStore.setReview(review, for: card.id)
        }
        let partial = insightEvent(session: store.sessionID, text: "DO NOT EXPORT", final: false)
        let snapshot = MeetingExportSnapshot(title: "Meeting / ../<title>", startedAt: nil,
                                              microphoneLocale: "ja-JP", systemLocale: "en-US", sessionID: store.sessionID,
                                              events: [event, partial], candidates: candidateStore.items, summary: nil)
        let markdown = snapshot.markdown
        #expect(markdown.contains("## 確認済みの決定"))
        #expect(markdown.contains("## 未確認の候補"))
        #expect(markdown.contains("## 却下した候補"))
        #expect(markdown.contains("[00:00:00 · 内部音声](#utterance-\(event.id.uuidString.lowercased()))"))
        #expect(!markdown.contains("\n# Confirmed"))
        #expect(!markdown.contains("<script>"))
        #expect(!markdown.contains("DO NOT EXPORT"))
        #expect(markdown.contains("開始日時: 未取得"))
        #expect(!snapshot.filename.contains("/"))
        #expect(!snapshot.filename.contains(".."))
    }

    @Test func cancelledAndFailedWritesPreserveLastSuccessfulExport() throws {
        let store = summaryStore(count: 1)
        let snapshot = MeetingExportSnapshot(title: "Test", startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
                                              sessionID: store.sessionID, events: store.finals, candidates: [], summary: nil)
        let exporter = MeetingExportState()
        let url = URL(fileURLWithPath: "/private/tmp/conflingo-pr7-export-test.md")
        var writes = 0
        exporter.save(snapshot, to: nil) { _, _ in writes += 1 }
        #expect(writes == 0)
        #expect(exporter.message.isEmpty)
        exporter.save(snapshot, to: url) { content, target in
            writes += 1
            #expect(content == snapshot.markdown)
            #expect(target == url)
        }
        #expect(exporter.matches(snapshot))
        #expect(exporter.message.contains("書き出しました"))
        exporter.save(snapshot, to: url) { _, _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(exporter.message.contains("失敗"))
        #expect(exporter.matches(snapshot))
        #expect(writes == 1)
        exporter.reset()
        #expect(!exporter.matches(snapshot))
    }
}

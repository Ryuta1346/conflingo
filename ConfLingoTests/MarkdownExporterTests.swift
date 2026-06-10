import Foundation
import Testing
@testable import ConfLingo

struct MarkdownExporterTests {
    private let date = Date(timeIntervalSince1970: 1_780_000_000)

    private func segment(index: Int, english: String, japanese: String?) -> TranscriptSegment {
        TranscriptSegment(
            id: UUID(),
            index: index,
            english: english,
            japanese: japanese,
            translationState: japanese == nil ? .pending : .done,
            finalizedAt: date
        )
    }

    @Test func rendersFullSessionWithTranslatedAndUntranslated() {
        let segments = [
            segment(index: 1, english: "Hello everyone.", japanese: "皆さんこんにちは。"),
            segment(index: 2, english: "Welcome to the conference.", japanese: nil),
        ]
        let markdown = MarkdownExporter.render(
            sessionName: "WWDC Keynote",
            date: date,
            segments: segments,
            sourceLanguage: "en-US",
            targetLanguage: "ja"
        )

        let dateString = MarkdownExporter.dateFormatter.string(from: date)
        let expected = """
        # ConfLingo Session: WWDC Keynote

        - Date: \(dateString)
        - Source language: en-US
        - Target language: ja
        - Segments: 2

        ## Transcript

        ### Segment 1

        English:
        Hello everyone.

        Japanese:
        皆さんこんにちは。

        ### Segment 2

        English:
        Welcome to the conference.

        Japanese:
        (untranslated)
        """
        #expect(markdown == expected)
    }

    @Test func emptySessionNameFallsBackToUntitled() {
        let markdown = MarkdownExporter.render(
            sessionName: "  ", date: date, segments: [],
            sourceLanguage: "en-US", targetLanguage: "ja"
        )
        #expect(markdown.hasPrefix("# ConfLingo Session: Untitled"))
    }

    @Test func emptySegmentsRendersHeaderOnly() {
        let markdown = MarkdownExporter.render(
            sessionName: "Empty", date: date, segments: [],
            sourceLanguage: "en-US", targetLanguage: "ja"
        )
        #expect(markdown.contains("- Segments: 0"))
        #expect(!markdown.contains("### Segment"))
    }

    @Test func rendersSelectedLanguagePair() {
        let markdown = MarkdownExporter.render(
            sessionName: "中国語セッション", date: date, segments: [],
            sourceLanguage: "zh-Hans", targetLanguage: "ko"
        )
        #expect(markdown.contains("- Source language: zh-Hans"))
        #expect(markdown.contains("- Target language: ko"))
    }
}

import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized)
    struct DR4ReadingTests {
        @Test func sharedAnswerScalesButActionLabelsDoNot() async throws {
            let answer = MeetingInsight(kind: .answerSuggestion,
                text: String(repeating: "本文を大きくして確認します。", count: 8), priority: 1, evidenceIDs: [], status: .complete)
            func measure(_ size: Double) async throws -> (CGFloat, CGFloat) {
                let fixture = DR3Host(AssistanceAnswerView(answer: answer, events: [], research: { _ in })
                    .environment(\.readingFontSize, size), width: 640, height: 1600)
                defer { fixture.close() }
                await fixture.layout()
                let text = try #require(fixture.elements(fixture.host).first {
                    fixture.value("accessibilityValue", $0) as? String == answer.text
                })
                let action = try #require(fixture.element("この提案をWebで調べる"))
                let textFrame = try #require(fixture.value("accessibilityFrame", text) as? NSValue).rectValue
                let actionFrame = try #require(fixture.value("accessibilityFrame", action) as? NSValue).rectValue
                return (textFrame.height, actionFrame.height)
            }
            let small = try await measure(16)
            let large = try await measure(48)
            #expect(large.0 > small.0 * 2)
            #expect(abs(large.1 - small.1) < 2)
        }
    }
}

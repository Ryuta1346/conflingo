import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized)
    struct DR4ReadingTests {
        @Test func correctionSheetMaterialExcerptUsesReadingSize() async throws {
            func measure(_ size: Double) async throws -> CGFloat {
                let suite = "DR4.CorrectionReading." + UUID().uuidString
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                defaults.set(size, forKey: "fontSize")
                let composition = AppComposition(arguments: ["--ui-preview"], defaults: defaults)
                let unit = try #require(composition.store.units.first)
                let material = unit.english + " " + String(repeating: "資料の内容を確認します。", count: 8)
                await composition.conferenceKnowledge.knowledge.add(data: Data(material.utf8), filename: "reading.md")
                let references = try await composition.conferenceKnowledge.knowledge.localReferences(unit.english)
                let snippet = try #require(references.first).snippet
                let fixture = DR3Host(ContentView(composition: composition), width: 1280, height: 900, padding: 0)
                defer { fixture.close() }
                await fixture.layout()
                try #require(fixture.element("この発話を資料で補正")).perform(NSSelectorFromString("accessibilityPerformPress"))
                #expect(try await waitForTestCondition { fixture.window.attachedSheet != nil })
                let sheet = try #require(fixture.window.attachedSheet)
                let content = try #require(sheet.contentView)
                await fixture.layout()
                let disclosure = try #require(fixture.elements(content).first {
                    fixture.value("accessibilityLabel", $0) as? String == "参照する資料を確認"
                        && $0.responds(to: NSSelectorFromString("accessibilityPerformPress"))
                })
                disclosure.perform(NSSelectorFromString("accessibilityPerformPress"))
                #expect(try await waitForTestCondition {
                    fixture.elements(content).contains { fixture.value("accessibilityValue", $0) as? String == snippet }
                })
                content.layoutSubtreeIfNeeded()
                let text = try #require(fixture.elements(content).first { fixture.value("accessibilityValue", $0) as? String == snippet })
                return try #require(fixture.value("accessibilityFrame", text) as? NSValue).rectValue.height
            }
            let small = try await measure(16)
            let medium = try await measure(32)
            let large = try await measure(48)
            #expect(medium > small * 1.5)
            #expect(large > medium * 1.25)
        }

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

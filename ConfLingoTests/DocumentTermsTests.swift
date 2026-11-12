import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct DocumentTermsTests {
    @Test func extractionKeepsProvenanceAndDoesNotInventTranslations() async throws {
        let knowledge = KnowledgeStore()
        await knowledge.add(data: Data("# Photon\n**Managed Agents** and `refundPayment`\n| source | target |\n| --- | --- |\n| rate limit | 利用上限 |\n普通の文章です。".utf8), filename: "terms.md")
        let terms = DocumentTerms()
        terms.extract(try await knowledge.contents())
        #expect(terms.candidates.contains { $0.term == "Photon" && $0.target.isEmpty && $0.line == 1 })
        #expect(terms.candidates.contains { $0.term == "refundPayment" && $0.target.isEmpty })
        #expect(terms.candidates.contains { $0.term == "rate limit" && $0.target == "利用上限" && $0.line == 5 })
        #expect(terms.candidates.allSatisfy { !$0.selected && $0.documentTitle == "terms.md" })
        #expect(!terms.candidates.contains { $0.term == "普通の文章です。" || $0.term == "source" })
    }

    @Test func confirmedTermsRespectLanguageDirectionAndManualPriority() throws {
        let terms = DocumentTerms()
        terms.addManual(term: "Photon", target: "フォトン")
        try terms.apply(sourceLanguage: "en-US", targetLanguage: "ja", manual: [])
        #expect(terms.glossary(sourceLanguage: "en-GB", targetLanguage: "ja", manual: []).first?.target == "フォトン")
        #expect(terms.glossary(sourceLanguage: "ja", targetLanguage: "en", manual: []).isEmpty)
        let manual = [KeywordParser.GlossaryEntry(term: "Photon", target: "手入力訳")]
        #expect(terms.glossary(sourceLanguage: "en", targetLanguage: "ja", manual: manual) == manual)
    }

    @Test func conflictsAndCombinedLimitDoNotReplaceAppliedTerms() throws {
        let terms = DocumentTerms()
        terms.addManual(term: "first", target: "最初")
        try terms.apply(sourceLanguage: "en", targetLanguage: "ja", manual: [])
        let original = terms.applied
        terms.addManual(term: "first", target: "別訳")
        #expect(throws: (any Error).self) { try terms.apply(sourceLanguage: "en", targetLanguage: "ja", manual: []) }
        #expect(terms.applied == original)
        terms.candidates = []
        terms.addManual(term: "extra", target: "")
        let manual = (0..<100).map { KeywordParser.GlossaryEntry(term: "term\($0)", target: nil) }
        #expect(throws: (any Error).self) { try terms.apply(sourceLanguage: "en", targetLanguage: "ja", manual: manual) }
        #expect(terms.applied == original)
    }
}

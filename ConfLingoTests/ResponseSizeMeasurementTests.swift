import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct ResponseSizeMeasurementTests {
    @Test func preflightBuildsOnlyApprovedSyntheticProductRequests() async throws {
        let requests = try await sizeEvaluationRequests()
        #expect(requests.map(\.0) == ["summary-ja", "summary-en", "research-ja", "research-en"])
        #expect(requests.allSatisfy { $0.1.value(forHTTPHeaderField: "x-goog-api-key") == "synthetic-key" })
    }

    @Test func streamCountsUTF8AndUsageWithoutPersistingText() throws {
        let payload = #"{"text":"日本語","kind":"answerSuggestion","evidenceIDs":[]}"#
        let data = try geminiSSE(payload: payload)
        let result = try SizeMeasurement.parse(data, caseID: "summary-ja")
        #expect(result.wireBytes == data.count)
        #expect(result.decodedBytes == payload.utf8.count)
        #expect(result.decodedCharacters == payload.count)
        #expect(result.maximumLineBytes > result.maximumEventBytes)
        #expect(result.events > 0)
        #expect(result.usageKnown)
        #expect(result.productDecode == "success")
        let saved = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!saved.contains("日本語"))
        #expect(!saved.contains("evidenceIDs"))
    }

    @Test func missingUsageIsExplicitAndLargeMultilineFrameIsRejected() throws {
        let result = try SizeMeasurement.parse(nativeResearchFixture(.gemini), caseID: "research-ja")
        #expect(!result.usageKnown)
        #expect(result.state == "complete-usage-unknown")
        #expect(result.productDecode == "success")
        let lines = String(repeating: "data: " + String(repeating: "a", count: 32_768) + "\n", count: 33)
        #expect(throws: InsightFailure.oversized) { try SizeMeasurement.parse(Data(lines.utf8), caseID: "summary-ja") }
    }
}

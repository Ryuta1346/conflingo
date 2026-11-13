import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(6)))
struct ResponseSizeLiveEvaluationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONFLINGO_R2_SIZE_LIVE"] == "1"))
    func approvedFourRequestMeasurement() async throws {
        let environment = ProcessInfo.processInfo.environment
        let otherFlags = RAGLiveConfiguration.legacyFlags + ["CONFLINGO_RAG_LIVE"] + SummaryEvaluationRun.allCases.map(\.flag)
        guard otherFlags.allSatisfy({ environment[$0] != "1" }), GeminiInsightClient.model == "gemini-3.8-flash" else {
            throw SizeEvaluationFailure.configuration
        }
        // Preflight all four product-generated requests before accessing credentials.
        let requests = try await sizeEvaluationRequests()
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("ConfLingo/Validation/r2-response-size-20261113")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledger = directory.appendingPathComponent("measurements.json")
        guard !FileManager.default.fileExists(atPath: ledger.path) else { throw SizeEvaluationFailure.duplicate }
        guard let key = try await KeychainAPIKeyStore().read(), APIKeyCredentials.isValid(key) else { throw InsightFailure.missingKey }
        try Data("[]".utf8).write(to: ledger, options: .withoutOverwriting)
        var records: [SizeMeasurement] = []
        for (caseID, original) in requests {
            var request = original
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            records.append(SizeMeasurement(caseID: caseID))
            try save(records, to: ledger)
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let data = try await receive(request)
                var result = try SizeMeasurement.parse(data, caseID: caseID)
                result.seconds = ProcessInfo.processInfo.systemUptime - started
                records[records.count - 1] = result
                try save(records, to: ledger)
                guard result.usageKnown else { throw SizeEvaluationFailure.usageUnknown }
            } catch {
                if records[records.count - 1].state == "reserved" {
                    records[records.count - 1].state = "failed-usage-unknown"
                    records[records.count - 1].seconds = ProcessInfo.processInfo.systemUptime - started
                    records[records.count - 1].failure = String(describing: InsightFailure.sanitized(error))
                    try save(records, to: ledger)
                }
                // Never expose raw URLSession errors, responses, or credentials.
                throw SizeEvaluationFailure.stopped
            }
        }
        #expect(records.count == 4)
    }

    private func save(_ records: [SizeMeasurement], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: url, options: .atomic)
        if let last = records.last {
            print("R2_SIZE " + String(decoding: try encoder.encode(last), as: UTF8.self))
        }
    }

    private func receive(_ request: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: InsightRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw InsightFailure.invalidResponse }
        guard response.statusCode == 200 else { throw InsightFailure.http(response.statusCode) }
        let streaming = request.value(forHTTPHeaderField: "Accept") == "text/event-stream"
        guard response.mimeType == (streaming ? "text/event-stream" : "application/json") else { throw InsightFailure.invalidResponse }
        var data = Data()
        var lineBytes = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 8 * 1_024 * 1_024 else { throw InsightFailure.oversized }
            data.append(byte)
            if streaming {
                lineBytes = byte == 10 ? 0 : lineBytes + 1
                guard lineBytes <= 1_024 * 1_024 else { throw InsightFailure.oversized }
            }
        }
        return data
    }
}

enum SizeEvaluationFailure: Error { case configuration, captured, duplicate, usageUnknown, stopped }

@MainActor
func sizeEvaluationRequests() async throws -> [(String, URLRequest)] {
    var result: [(String, URLRequest)] = []
    for research in [false, true] {
        for language in [AnswerLanguage.japanese, .english] {
            let japanese = language == .japanese
            let sessionID = UUID()
            let lines = (1...10).flatMap { index in
                japanese ? [
                    "架空の議題\(index)：試験対象は\(index + 2)店舗、測定期間は14日と決定しました。",
                    "議題\(index)の担当はテスト担当\(index)、期限は来月\(index + 1)日です。結果は件数と所要時間で評価します。",
                    "議題\(index)の追加予算\(index * 10)万円は提案段階です。承認者、運用費用、障害時の手順は未確認です。"
                ] : [
                    "Fictional agenda \(index): we agreed to test in \(index + 2) stores for 14 days.",
                    "Test owner \(index) owns agenda \(index), due on day \(index + 1) next month. Evaluate counts and elapsed time.",
                    "The extra budget of JPY \(index * 100000) for agenda \(index) is only a proposal. Approver, operating cost and incident procedure are unverified."
                ]
            }
            guard lines.count <= 30, lines.reduce(0, { $0 + $1.count }) <= 6_000 else { throw SizeEvaluationFailure.configuration }
            let events: [TranscriptEvent] = research ? [] : lines.enumerated().map { index, line in
                TranscriptEvent(id: UUID(), sessionID: sessionID, origin: .microphone, languageCode: japanese ? "ja" : "en",
                                startOffset: Double(index * 5), endOffset: Double(index * 5 + 4), text: line,
                                isFinal: true, revision: 1, sourceStartTime: Double(index * 5))
            }
            let question: String
            if research {
                question = japanese ? "HTTPのETagとIf-None-Matchによるキャッシュ検証の仕組みを、公開仕様を根拠に説明してください。"
                    : "Explain HTTP cache validation using ETag and If-None-Match, citing public specifications."
            } else {
                question = japanese ? "全議題の決定・担当・期限・未決事項を区別し、省略せず詳しく要約してください。"
                    : "Summarize every agenda item in detail, distinguishing decisions, owners, deadlines and unresolved matters without omitting topics."
            }
            let request = try InsightRequest(sessionID: sessionID, question: question, trigger: .manual, events: events,
                                             answerLanguage: language, purpose: research ? .webResearch : .summary)
            guard request.omittedCount == 0, request.knowledge.isEmpty else { throw SizeEvaluationFailure.configuration }
            let capture = SizeRequestCapture()
            do {
                if research {
                    _ = try await LLMWebResearchClient(connection: .legacyGemini, key: { "synthetic-key" }, transport: capture).generate(request)
                } else {
                    _ = try await GeminiInsightClient(key: { "synthetic-key" }, transport: capture).generate(request) { _ in }
                }
            } catch SizeEvaluationFailure.captured {} // Expected: no network in preflight.
            guard let http = capture.request, let body = http.httpBody, body.count <= 32_768,
                  http.httpMethod == "POST", http.timeoutInterval == 60,
                  http.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:" + (research ? "generateContent" : "streamGenerateContent?alt=sse"),
                  let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  (object["generationConfig"] as? [String: Any])?["maxOutputTokens"] as? Int == 8_192 else {
                throw SizeEvaluationFailure.configuration
            }
            result.append(("\(research ? "research" : "summary")-\(language.rawValue)", http))
        }
    }
    return result
}

@MainActor
private final class SizeRequestCapture: InsightHTTPTransport, ResearchHTTPTransport {
    var request: URLRequest?
    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        self.request = request
        throw SizeEvaluationFailure.captured
    }
    func fetch(_ request: URLRequest) async throws -> Data {
        self.request = request
        throw SizeEvaluationFailure.captured
    }
}

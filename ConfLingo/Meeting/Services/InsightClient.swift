import Foundation

struct InsightRequest: Sendable {
    enum Trigger: String, Sendable { case manual, automatic }
    let id = UUID()
    let sessionID: UUID
    let question: String
    let answerLanguage: AnswerLanguage
    let trigger: Trigger
    let events: [TranscriptEvent]
    let omittedCount: Int
    let knowledge: [KnowledgeReference]

    init(sessionID: UUID, question: String, trigger: Trigger, events: [TranscriptEvent],
         answerLanguage: AnswerLanguage = .japanese, knowledge: [KnowledgeReference] = []) throws {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 2_000 else { throw InsightFailure.invalidQuestion }
        self.sessionID = sessionID
        self.question = question
        self.answerLanguage = answerLanguage
        self.trigger = trigger
        var referenceIDs: Set<UUID> = []
        var referenceSize = 0
        self.knowledge = trigger == .manual ? Array(knowledge.filter {
            guard !$0.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  $0.snippet.count <= 1_200, $0.title.count <= 200,
                  $0.startLine > 0, $0.characterOffset >= 0,
                  referenceIDs.insert($0.id).inserted, referenceSize + $0.snippet.count <= 6_000 else { return false }
            referenceSize += $0.snippet.count
            return true
        }.prefix(5)) : []
        var seen: Set<UUID> = []
        let finals = events.filter {
            $0.sessionID == sessionID && $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.startOffset.isFinite && seen.insert($0.id).inserted
        }.sorted { $0.startOffset < $1.startOffset }
        var selected: [TranscriptEvent] = []
        var size = 0
        for event in finals.reversed() where selected.count < 30 {
            guard size + event.text.count <= 12_000 else { continue }
            selected.append(event)
            size += event.text.count
        }
        self.events = selected.reversed()
        omittedCount = finals.count - selected.count
    }
}

struct InsightUsage: Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let thinkingTokens: Int
}

struct InsightResult: Sendable {
    let kind: MeetingInsight.Kind
    let text: String
    let evidenceIDs: [UUID]
    var usage: InsightUsage?
    var knowledgeIDs: [UUID] = []

    func card(for request: InsightRequest) throws -> MeetingInsight {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 8_000 else {
            throw InsightFailure.invalidResponse
        }
        let allowed = Set(request.events.map(\.id))
        var seen: Set<UUID> = []
        let references = Dictionary(request.knowledge.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seenReferences: Set<UUID> = []
        let invalidKnowledge = knowledgeIDs.contains { references[$0] == nil }
        return MeetingInsight(id: request.id, kind: kind, text: text, priority: kind.priority,
                              evidenceIDs: evidenceIDs.filter { allowed.contains($0) && seen.insert($0).inserted },
                              hasInvalidEvidence: invalidKnowledge || evidenceIDs.contains { !allowed.contains($0) },
                              knowledgeReferences: knowledgeIDs.filter { seenReferences.insert($0).inserted }.compactMap { references[$0] })
    }
}

@MainActor
protocol InsightClient {
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult
}

enum InsightFailure: Error, Equatable, LocalizedError {
    case queueOverflow, invalidQuestion, invalidResponse, missingKey, keyStorage, oversized, timeout, offline, interrupted, blocked
    case http(Int)
    case knowledge

    var errorDescription: String? {
        switch self {
        case .knowledge: "資料を検索できなかったため送信を中止しました。資料の状態を確認してください。"
        case .queueOverflow: "AIの処理が追いつかないため自動提案を停止しました。字幕は継続します。"
        case .invalidQuestion: "質問は1〜2,000文字で入力してください。"
        case .invalidResponse: "AIの応答を確認できませんでした。必要なら手動で再試行してください。"
        case .missingKey: "設定でGemini APIキーを登録してください。"
        case .keyStorage: "APIキーをKeychainで読み書きできませんでした。"
        case .oversized: "送受信する内容が上限を超えました。"
        case .timeout: "AIへの接続がタイムアウトしました。字幕は継続します。"
        case .offline: "AIに接続できません。ネットワークを確認してください。"
        case .interrupted: "AI生成を中断しました。"
        case .blocked: "AIが応答を返しませんでした。質問内容をご確認ください。"
        case .http(401), .http(403): "Geminiの認証に失敗しました。APIキーと利用権限をご確認ください。"
        case .http(429): "Geminiの利用上限に達しました。時間をおいて手動で再試行してください。"
        case .http(404): "Geminiモデルを利用できません。利用権限またはアプリの更新をご確認ください。"
        case .http: "Geminiへの要求に失敗しました。自動で再送はしません。"
        }
    }

    static func sanitized(_ error: any Error) -> Self {
        if let failure = error as? Self { return failure }
        if error is KnowledgeFailure { return .knowledge }
        if let urlError = error as? URLError {
            if urlError.code == .timedOut { return .timeout }
            if urlError.code == .cancelled { return .interrupted }
            return .offline
        }
        return error is CancellationError ? .interrupted : .invalidResponse
    }
}

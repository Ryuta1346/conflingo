#if DEBUG
import AVFAudio
import Foundation

@MainActor
enum MeetingPreview {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: "com.gavrri.conflingo.meeting-preview") ?? .standard
    }

    static var scenario: String {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--meeting-state=") }?
            .replacingOccurrences(of: "--meeting-state=", with: "") ?? "setup"
    }

    static func liveAIEnabled(arguments: [String]) -> Bool {
        arguments.contains("--meeting-preview") && arguments.contains("--meeting-live-ai")
    }

    static func make(activity: AudioInputUse, scenario: String = "setup", liveAI: Bool = false,
                     defaults: UserDefaults = MeetingPreview.defaults) -> MeetingWorkspace {
        let microphone = PreviewAudioSource(origin: .microphone)
        let system = PreviewAudioSource(origin: .systemAudio, denied: scenario == "permission-denied")
        let controller = DualTranscriptionController(
            microphone: microphone, systemAudio: system,
            microphoneSpeech: PreviewSpeech(), systemSpeech: PreviewSpeech(failStopOnce: scenario == "stop-failed"),
            activity: activity, owner: .meeting, prepareModel: { locale in
                try await Task.sleep(for: .milliseconds(100))
                return locale
            }
        )
        let meeting = liveAI
            ? MeetingWorkspace(controller: controller, defaults: defaults)
            : MeetingWorkspace(controller: controller, insightClient: PreviewInsightClient(),
                               credentials: GeminiCredentials(store: PreviewAPIKeyStore()), defaults: defaults)
        meeting.previewUsesLiveAI = liveAI
        return meeting
    }

    static func prepare(_ meeting: MeetingWorkspace, scenario: String) async {
        if scenario == "repository-review" || scenario == "repository-automatic" || scenario == "library-setup" {
            guard !meeting.previewUsesLiveAI else { return }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyntheticProduct-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try Data("// 架空の実装: security review pilot レビュー担当者\nfunc reviewStatus() -> String { \"pending\" }\n".utf8)
                    .write(to: root.appendingPathComponent("ReviewService.swift"))
                try Data("# 架空の設計\nsecurity review 完了後のパイロットを検討する。担当者は未確定。".utf8)
                    .write(to: root.appendingPathComponent("README.md"))
                let scan = try await RepositoryImporter.scan(root)
                await meeting.knowledge.importRepository(scan, selected: Set(scan.eligible.map(\.path)))
            } catch {
                meeting.previewAIStatus = "合成リポジトリの準備に失敗・外部送信なし"
                return
            }
        }
        if scenario == "library-setup" || scenario == "pr8-setup" || scenario == "pr8-live" || scenario == "pr8-review" {
            await meeting.knowledge.add(data: Data("# 製品仕様（架空の資料）\n料金は月額100円です。\nAPI rate limit is 50 requests per minute.\n多要素認証を利用できます。".utf8), filename: "製品仕様.md")
        }
        guard scenario != "setup", scenario != "pr8-setup", scenario != "library-setup" else { return }
        meeting.name = "プロダクト定例"
        meeting.consentConfirmed = true
        await meeting.start()
        guard meeting.phase == .listening else { return }
        populate(meeting, includeCandidates: scenario == "pr7-review")
        if scenario == "repository-automatic", !meeting.previewUsesLiveAI {
            meeting.setAIAllowed(true)
            meeting.setAutomaticAI(true)
            meeting.setAutomaticKnowledgeAllowed(true)
            if let event = meeting.store.finals.last { await meeting.ai.receive(event)?.value }
        }
        if scenario == "pr8-live" || scenario == "pr8-review" {
            meeting.setAIAllowed(true)
            meeting.setKnowledgeAllowed(true)
            await meeting.ai.ask("料金はいくらですか？")
        }
        if scenario == "repository-review" || scenario == "pr8-review" || scenario == "review" || scenario == "pr7-review" || scenario == "stop-failed" { await meeting.end() }
        guard !meeting.previewUsesLiveAI else { return }
        if scenario == "offline" { meeting.previewAIStatus = "プレビュー：AIオフライン・外部送信なし" }
        if scenario == "sending" { meeting.previewAIStatus = "プレビュー：AI送信中の表示（実通信なし）" }
    }

    static func populate(_ meeting: MeetingWorkspace, count: Int = 12, includeCandidates: Bool = false) {
        let lines = ["まずは少人数のパイロットで、実際の利用状況を確認したいですね。",
                     "The security review is still in progress. We should have an update by Wednesday.",
                     "Can we launch the pilot next Friday, or do we need more time for the security review?",
                     "レビューの担当者と、完了条件を確認しましょう。"]
        var ids: [UUID] = []
        for index in 0..<count {
            let id = UUID()
            ids.append(id)
            meeting.store.receive(TranscriptEvent(
                id: id, sessionID: meeting.store.sessionID, origin: index.isMultiple(of: 2) ? .microphone : .systemAudio,
                languageCode: index.isMultiple(of: 2) ? "ja-JP" : "en-US", startOffset: Double(index * 12),
                endOffset: Double(index * 12 + 8), text: lines[index % lines.count], isFinal: true,
                revision: 1, sourceStartTime: Double(index * 12)
            ))
        }
        guard !meeting.previewUsesLiveAI else { return }
        meeting.insights = [
            MeetingInsight(kind: .answerSuggestion, text: "来週金曜は、セキュリティレビューの完了を条件に。日程を確約する前に、担当者と完了予定を確認しましょう。",
                           priority: 2, evidenceIDs: Array(ids.dropFirst().prefix(1))),
            MeetingInsight(kind: .followUpQuestion, text: "レビューの担当者は決まっていますか？", priority: 1,
                           evidenceIDs: Array(ids.suffix(1)))
        ]
        if includeCandidates {
            meeting.insights += [
                MeetingInsight(kind: .decisionCandidate, text: "少人数のパイロットで利用状況を確認する案（架空の候補）", priority: 1, evidenceIDs: Array(ids.prefix(1))),
                MeetingInsight(kind: .actionCandidate, text: "レビュー担当者と完了条件を確認する案（架空の候補）", priority: 1, evidenceIDs: Array(ids.suffix(1)))
            ]
        }
        meeting.previewAIStatus = "プレビュー：架空の提案・外部送信なし"
    }
}

@MainActor
private struct PreviewInsightClient: InsightClient {
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        if request.purpose == .summary, let reference = request.knowledge.first {
            return InsightResult(kind: .answerSuggestion, text: "会議では担当者と完了予定を確認しています。（架空の要約）",
                                 evidenceIDs: Array(request.events.prefix(1).map(\.id)), knowledgeIDs: [reference.id],
                                 supplement: "選択した資料の内容を補足として参照しています。（架空の補足）")
        }
        if let reference = request.knowledge.first {
            if reference.source != nil {
                return InsightResult(kind: .answerSuggestion, text: "取り込んだ実装・設計を参照し、レビューの担当者と完了条件を確認しましょう。（架空の自動提案・外部送信なし）",
                                     evidenceIDs: Array(request.events.suffix(1).map(\.id)), knowledgeIDs: [reference.id])
            }
            return InsightResult(kind: .answerSuggestion, text: "資料には月額100円と記載されています。（架空の回答）", evidenceIDs: [],
                                 knowledgeIDs: [reference.id])
        }
        for text in ["担当者と", "担当者と完了予定を", "担当者と完了予定を確認しましょう。（架空の回答）"] {
            try await Task.sleep(for: .milliseconds(150))
            update(text)
        }
        return InsightResult(kind: .followUpQuestion, text: "担当者と完了予定を確認しましょう。（架空の回答）",
                             evidenceIDs: Array(request.events.prefix(1).map(\.id)))
    }
}

@MainActor
private final class PreviewAPIKeyStore: APIKeyStore {
    func read() throws -> String? { nil }
    func save(_ key: String) throws { throw InsightFailure.keyStorage }
    func delete() throws { throw InsightFailure.keyStorage }
}

@MainActor
private final class PreviewAudioSource: AudioSource {
    let origin: AudioOrigin
    let denied: Bool
    var permissionStatus: AudioPermissionStatus { denied ? .denied : .granted }
    var state: AudioSourceState { .idle }
    init(origin: AudioOrigin, denied: Bool = false) { self.origin = origin; self.denied = denied }
    func requestPermission() async -> Bool { !denied }
    func start(targetFormat: AVAudioFormat) async throws -> AudioFrameStream {
        AudioFrameStream { $0.finish() }
    }
    func stop() async throws {}
}

@MainActor
private final class PreviewSpeech: SpeechTranscribing {
    private var failStopOnce: Bool
    init(failStopOnce: Bool = false) { self.failStopOnce = failStopOnce }
    func start(
        locale: Locale, contextKeywords: [String], fastResults: Bool,
        onInputStarted: @escaping @MainActor () -> Void,
        receive: @escaping @MainActor (SpeechResult) async throws -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws { onInputStarted() }
    func stopInput() async throws {
        if failStopOnce {
            failStopOnce = false
            throw NSError(domain: "MeetingPreview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "停止失敗のプレビュー"])
        }
    }
    func finishRecognition() async throws {}
    func cancelRecognition() async {}
    func stop() async throws { try await stopInput() }
}
#endif

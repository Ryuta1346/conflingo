import Foundation
import Observation

@MainActor
@Observable
final class InsightCoordinator {
    enum State: Equatable { case off, ready, paused, sending, failed(InsightFailure) }

    private(set) var permitted = false
    private(set) var automaticEnabled = false
    private(set) var subscriptionFailed = false
    private(set) var state: State = .off
    var answerLanguage: AnswerLanguage = .japanese
    var insights: [MeetingInsight] = []
    private(set) var lastUsage: InsightUsage?
    private(set) var contextDescription = "手動質問では、許可前を含む直近の確定発話を最大30件送ります。"
    private let store: MeetingSessionStore
    private let client: any InsightClient
    private let now: () -> TimeInterval
    private let timeout: Duration
    private var active = false
    private var preparing = false
    private var startupEvents: [TranscriptEvent] = []
    private var allowedAfter = TimeInterval.infinity
    private var automaticAfter = TimeInterval.infinity
    private var seen: Set<UUID> = []
    private var recentTriggers: [(time: TimeInterval, text: String)] = []
    private var request: InsightRequest?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var consumer: Task<Void, Never>?
    private var subscriptionID = UUID()

    init(store: MeetingSessionStore, client: any InsightClient,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, timeout: Duration = .seconds(30)) {
        self.store = store
        self.client = client
        self.now = now
        self.timeout = timeout
    }

    deinit { task?.cancel(); deadline?.cancel(); consumer?.cancel() }

    var canAsk: Bool { active && permitted && request?.trigger != .manual }
    var statusText: String {
        let status = switch state {
        case .off: "AIオフ・外部送信なし"
        case .ready: automaticEnabled ? "AI許可済み・自動提案オン" : "AI許可済み・手動質問のみ"
        case .paused: "AI一時停止・新規送信なし"
        case .sending: "確定発話をAIへ送信中"
        case .failed(let error): error.localizedDescription
        }
        return subscriptionFailed
            ? "\(status) · 自動提案を再開するには会議を一時停止して再開してください。"
            : status
    }

    func setPermission(_ value: Bool, after offset: TimeInterval) {
        guard permitted != value else { return }
        cancelRequest()
        startupEvents = []
        permitted = value
        allowedAfter = value ? offset : .infinity
        automaticEnabled = false
        automaticAfter = .infinity
        state = value ? (active ? .ready : .paused) : .off
    }

    func setAutomatic(_ value: Bool, after offset: TimeInterval) {
        automaticEnabled = value && permitted && !subscriptionFailed
        automaticAfter = automaticEnabled ? offset : .infinity
        if !automaticEnabled { startupEvents = [] }
        if !automaticEnabled, request?.trigger == .automatic { cancelRequest() }
        if request == nil { state = permitted ? (active ? .ready : .paused) : .off }
    }

    func resume() {
        active = true
        preparing = false
        state = permitted ? .ready : .off
        let pending = startupEvents.sorted { $0.startOffset > $1.startOffset }
        startupEvents = []
        for event in pending { receive(event) }
    }

    func suspend() {
        active = false
        preparing = false
        startupEvents = []
        cancelRequest()
        consumer?.cancel()
        consumer = nil
        subscriptionID = UUID()
        state = permitted ? .paused : .off
    }

    func reset() {
        suspend()
        permitted = false
        automaticEnabled = false
        subscriptionFailed = false
        allowedAfter = .infinity
        automaticAfter = .infinity
        insights = []
        seen = []
        recentTriggers = []
        lastUsage = nil
        state = .off
    }

    func attach(to hub: TranscriptEventHub) async {
        consumer?.cancel()
        let id = UUID()
        subscriptionID = id
        let subscription = await hub.subscribe()
        guard subscriptionID == id, !Task.isCancelled else {
            await subscription.cancel()
            return
        }
        subscriptionFailed = false
        preparing = !active
        startupEvents = []
        consumer = Task { [weak self] in
            do {
                while let event = try await subscription.next() {
                    guard let self, self.subscriptionID == id, !Task.isCancelled else { break }
                    self.receive(event)
                }
            } catch {
                guard let self, self.subscriptionID == id, !Task.isCancelled else { return }
                self.cancelRequest()
                self.automaticEnabled = false
                self.subscriptionFailed = true
                self.startupEvents = []
                self.state = .failed(.queueOverflow)
            }
            await subscription.cancel()
        }
    }

    func ask(_ question: String) async {
        guard canAsk else { return }
        do {
            let next = try InsightRequest(sessionID: store.sessionID, question: question, trigger: .manual, events: store.finals,
                                          answerLanguage: answerLanguage)
            await launch(next).value
        } catch {
            cancelRequest()
            state = .failed(.sanitized(error))
        }
    }

    @discardableResult
    func receive(_ event: TranscriptEvent) -> Task<Void, Never>? {
        guard permitted, automaticEnabled, request == nil,
              event.sessionID == store.sessionID, event.isFinal,
              event.startOffset.isFinite, event.startOffset >= max(allowedAfter, automaticAfter),
              ConversationEventDetector.isCandidate(event.text) else { return nil }
        guard active else {
            if preparing { bufferStartup(event) }
            return nil
        }
        guard seen.insert(event.id).inserted else { return nil }
        let time = now()
        recentTriggers.removeAll { time - $0.time >= 60 }
        let normalized = Self.normalized(event.text)
        guard recentTriggers.count < 2, !recentTriggers.contains(where: { $0.text == normalized }),
              recentTriggers.last.map({ time - $0.time >= 12 }) ?? true else { return nil }
        let context = (store.finals + [event]).filter { $0.startOffset >= allowedAfter }
        guard let next = try? InsightRequest(sessionID: store.sessionID,
                                             question: "この発話に関連する回答・確認事項・リスク・未確認候補を短く提案してください。",
                                             trigger: .automatic, events: context, answerLanguage: answerLanguage),
              next.events.contains(where: { $0.id == event.id }) else { return nil }
        recentTriggers.append((time, normalized))
        return launch(next)
    }

    private func bufferStartup(_ event: TranscriptEvent) {
        guard event.text.count <= 12_000, !startupEvents.contains(where: { $0.id == event.id }) else { return }
        startupEvents.append(event)
        startupEvents.sort { $0.startOffset < $1.startOffset }
        while startupEvents.count > 30 || startupEvents.reduce(0, { $0 + $1.text.count }) > 12_000 {
            startupEvents.removeFirst()
        }
    }

    private func launch(_ next: InsightRequest) -> Task<Void, Never> {
        cancelRequest()
        request = next
        state = .sending
        lastUsage = nil
        contextDescription = "今回の文脈：確定発話 \(next.events.count)件・上限により除外 \(next.omittedCount)件"
        insights.append(MeetingInsight(id: next.id, kind: .answerSuggestion, text: "回答を生成しています…",
                                       priority: 1, evidenceIDs: [], status: .generating))
        if insights.count > 100 { insights.removeFirst(insights.count - 100) }
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.request?.id == next.id else { return }
            self.cancelRequest()
            self.automaticEnabled = false
            self.state = .failed(.timeout)
        }
        let operation = Task { [weak self, client] in
            guard self?.accepts(next) == true, !Task.isCancelled else { return }
            do {
                let result = try await client.generate(next) { [weak self] text in
                    guard let self, self.accepts(next), text.count <= 8_000,
                          let index = self.insights.firstIndex(where: { $0.id == next.id }) else { return }
                    self.insights[index].text = text
                }
                guard let self, self.accepts(next), !Task.isCancelled else { return }
                let card = try result.card(for: next)
                if next.trigger == .automatic,
                   self.insights.contains(where: { $0.status == .complete && Self.normalized($0.text) == Self.normalized(card.text) }) {
                    self.insights.removeAll { $0.id == next.id }
                } else if let index = self.insights.firstIndex(where: { $0.id == next.id }) {
                    self.insights[index] = card
                }
                self.lastUsage = result.usage
                self.finishRequest()
                self.state = .ready
            } catch {
                guard let self, self.accepts(next) else { return }
                self.cancelRequest()
                self.automaticEnabled = false
                self.state = .failed(.sanitized(error))
            }
        }
        task = operation
        return operation
    }

    private func accepts(_ next: InsightRequest) -> Bool {
        active && permitted && request?.id == next.id && store.sessionID == next.sessionID
    }

    private func finishRequest() {
        deadline?.cancel()
        deadline = nil
        request = nil
        task = nil
    }

    private func cancelRequest() {
        if let id = request?.id, let index = insights.firstIndex(where: { $0.id == id }) {
            insights[index].status = .interrupted
        }
        task?.cancel()
        finishRequest()
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}

enum ConversationEventDetector {
    static func isCandidate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["?", "？", "でしょうか", "ですか", "確認", "懸念", "決定", "担当", "risk", "concern",
                "decided", "action item", "will follow up", "contradict"].contains { lower.contains($0) }
    }
}

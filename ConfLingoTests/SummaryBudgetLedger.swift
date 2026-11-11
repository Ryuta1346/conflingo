import Darwin
import Foundation
@testable import ConfLingo

@MainActor
final class SummaryBudgetLedger {
    enum Operation: String, Codable { case count, generate }
    struct Entry: Codable {
        let caseID: String
        let operation: Operation
        let hash: String
        let reservedUSD: Double
        let startedAt: Date
        var state = "reserved"
        var costUSD: Double?
        var countedTokens: Int?
        var inputTokens: Int?
        var outputTokens: Int?
        var thinkingTokens: Int?
    }
    private struct Snapshot: Codable {
        var version = 1
        var evaluationID = "pr7-summary-quality-20261111"
        var pricingSource = "https://aistudio.google.com/docs/pricing#gemini-3.8-flash"
        var model = "gemini-3.8-flash"
        var pricingDate = "2026-11-11"
        var inputUSDPerMillion = 0.75
        var outputUSDPerMillion = 3.75
        var countUSD = 0.0
        var countPricingSource = "https://aistudio.google.com/docs/billing#is-gettokens-billed"
        var budgetUSD: Double
        var entries: [Entry] = []
    }
    private let run: SummaryEvaluationRun
    private let url: URL
    private let lock: Int32
    private var snapshot: Snapshot
    var entries: [Entry] { snapshot.entries }
    var spent: Double { entries.reduce(0) { $0 + ($1.costUSD ?? $1.reservedUSD) } }

    init(url: URL, run: SummaryEvaluationRun = .initial, budget: Double? = nil) throws {
        let budget = budget ?? run.budgetUSD
        guard budget.isFinite, budget > 0, budget <= run.budgetUSD else { throw SummaryEvaluationError.budget }
        self.url = url
        self.run = run
        let descriptor = open(url.path + ".lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw SummaryEvaluationError.ledger }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw SummaryEvaluationError.ledger }
        lock = descriptor
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
                guard snapshot.version == 1, snapshot.evaluationID == run.id, snapshot.model == "gemini-3.8-flash", snapshot.budgetUSD == budget,
                      snapshot.inputUSDPerMillion == 0.75, snapshot.outputUSDPerMillion == 3.75, snapshot.countUSD == 0,
                      snapshot.entries.count <= run.sectionIDs.count * 2,
                      snapshot.entries.allSatisfy({ $0.reservedUSD.isFinite && $0.reservedUSD >= 0
                          && ($0.costUSD.map { $0.isFinite && $0 >= 0 } ?? true) }) else { throw SummaryEvaluationError.ledger }
            } else {
                snapshot = Snapshot(evaluationID: run.id, budgetUSD: budget)
                try persist(snapshot)
            }
        } catch { close(descriptor); throw SummaryEvaluationError.ledger }
    }

    deinit { close(lock) }

    static var reservation: Double { cost(input: 6_000, output: 8_192, thinking: 0) * 1.2 }

    func requireFreshRun() throws {
        guard entries.isEmpty else { throw SummaryEvaluationError.duplicate }
    }

    func begin(caseID: String, operation: Operation, hash: String, reservation: Double) throws {
        guard run.sectionIDs.contains(caseID), !hash.isEmpty,
              reservation.isFinite, reservation >= 0, operation == .generate ? reservation >= Self.reservation : reservation == 0 else { throw SummaryEvaluationError.budget }
        guard !entries.contains(where: { $0.caseID == caseID && $0.operation == operation }) else { throw SummaryEvaluationError.duplicate }
        guard entries.allSatisfy({ $0.state == "complete" }), entries.filter({ $0.operation == operation }).count < run.sectionIDs.count,
              spent + reservation <= snapshot.budgetUSD else { throw SummaryEvaluationError.budget }
        if operation == .generate {
            guard entries.contains(where: { $0.caseID == caseID && $0.operation == .count && $0.hash == hash
                && $0.state == "complete" && ($0.countedTokens ?? 6_001) <= 6_000 }) else { throw SummaryEvaluationError.tokens }
        }
        var next = snapshot
        next.entries.append(Entry(caseID: caseID, operation: operation, hash: hash, reservedUSD: reservation, startedAt: Date()))
        try persist(next)
        snapshot = next
    }

    func completeCount(caseID: String, tokens: Int) throws {
        guard tokens > 0, tokens <= 6_000 else { throw SummaryEvaluationError.tokens }
        try update(caseID, operation: .count) { entry in
            entry.countedTokens = tokens
            entry.costUSD = 0
            entry.state = "complete"
        }
    }

    func completeGeneration(caseID: String, usage: InsightUsage?) throws {
        try update(caseID, operation: .generate) { entry in
            guard let usage, usage.inputTokens >= 0, usage.outputTokens >= 0, usage.thinkingTokens >= 0 else {
                entry.state = "unknown"
                return
            }
            entry.inputTokens = usage.inputTokens
            entry.outputTokens = usage.outputTokens
            entry.thinkingTokens = usage.thinkingTokens
            entry.costUSD = Self.cost(input: usage.inputTokens, output: usage.outputTokens, thinking: usage.thinkingTokens)
            entry.state = usage.inputTokens <= 6_000 && Double(usage.outputTokens) + Double(usage.thinkingTokens) <= 8_192 ? "complete" : "limit-exceeded"
        }
    }

    static func cost(input: Int, output: Int, thinking: Int) -> Double {
        (Double(input) * 0.75 + (Double(output) + Double(thinking)) * 3.75) / 1_000_000
    }

    private func update(_ caseID: String, operation: Operation, change: (inout Entry) -> Void) throws {
        guard let index = entries.firstIndex(where: { $0.caseID == caseID && $0.operation == operation }),
              entries[index].state == "reserved" else { throw SummaryEvaluationError.ledger }
        var next = snapshot
        change(&next.entries[index])
        try persist(next)
        snapshot = next
    }

    private func persist(_ value: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

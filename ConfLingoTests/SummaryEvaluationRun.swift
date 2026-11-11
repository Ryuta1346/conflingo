import Foundation

// Only these approved runs can select cases, limits, and persistent ledger identities.
enum SummaryEvaluationRun: CaseIterable {
    case initial, remaining, deadline

    var id: String {
        switch self {
        case .initial: "pr7-summary-quality-20261111"
        case .remaining: "pr7-summary-remaining-20261111"
        case .deadline: "pr7-summary-deadline-20261111"
        }
    }
    var flag: String {
        switch self {
        case .initial: "CONFLINGO_SUMMARY_LIVE"
        case .remaining: "CONFLINGO_SUMMARY_REMAINING_LIVE"
        case .deadline: "CONFLINGO_SUMMARY_DEADLINE_LIVE"
        }
    }
    var budgetUSD: Double { self == .initial ? 2 : 1 }
    var cases: [SummaryEvaluationCase] {
        self == .initial ? SummaryEvaluationCase.all : [SummaryEvaluationCase(number: 8, japanese: true),
                                                       SummaryEvaluationCase(number: 8, japanese: false),
                                                       SummaryEvaluationCase(number: 7, japanese: false)]
    }
    var sectionIDs: [String] { cases.flatMap { sample in (1...sample.sectionCount).map { "\(sample.id)-\($0)" } } }
}

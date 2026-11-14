import Foundation
import OSLog

@MainActor
struct LLMDiagnostics {
    enum Operation: String {
        case assistance, summary, documentQuestion, transcriptCorrection, webResearch, models

        init(_ purpose: InsightRequest.Purpose) {
            switch purpose {
            case .assistance: self = .assistance
            case .summary: self = .summary
            case .documentQuestion: self = .documentQuestion
            case .transcriptCorrection: self = .transcriptCorrection
            case .webResearch: self = .webResearch
            }
        }
    }

    enum Reason: String {
        case queueOverflow, invalidQuestion, invalidResponse, missingKey, keyStorage, oversized
        case timeout, offline, cancelled, blocked, http, knowledge, invalidEndpoint, invalidConfiguration
        case unsupported, noSources, unknown
    }

    struct Event: Equatable {
        let provider: LLMProvider
        let operation: Operation
        let reason: Reason
        let code: Int?

        var message: String {
            "provider=\(provider.rawValue) operation=\(operation.rawValue) reason=\(reason.rawValue) code=\(code.map(String.init) ?? "none")"
        }
    }

    var emit: @MainActor (Event) -> Void = Self.write
    private static let logger = Logger(subsystem: "com.gavrri.conflingo", category: "LLM")

    func capture<T>(provider: LLMProvider, operation: Operation, body: () async throws -> T) async rethrows -> T {
        do { return try await body() }
        catch {
            let (reason, code) = Self.classify(error)
            emit(Event(provider: provider, operation: operation, reason: reason, code: code))
            throw error
        }
    }

    private static func write(_ event: Event) {
        if event.reason == .cancelled { logger.info("\(event.message, privacy: .public)") }
        else { logger.error("\(event.message, privacy: .public)") }
    }

    private static func classify(_ error: any Error) -> (Reason, Int?) {
        if error is CancellationError { return (.cancelled, nil) }
        if let error = error as? URLError {
            let reason: Reason = error.code == .cancelled ? .cancelled : error.code == .timedOut ? .timeout : .offline
            return (reason, error.code.rawValue)
        }
        if let failure = error as? ResearchFailure {
            return (failure == .unsupported ? .unsupported : .noSources, nil)
        }
        if error is KnowledgeFailure { return (.knowledge, nil) }
        if error is DecodingError || (error as? CocoaError)?.code == .propertyListReadCorrupt {
            return (.invalidResponse, nil)
        }
        guard let failure = error as? InsightFailure else { return (.unknown, nil) }
        switch failure {
        case .queueOverflow: return (.queueOverflow, nil)
        case .invalidQuestion: return (.invalidQuestion, nil)
        case .invalidResponse: return (.invalidResponse, nil)
        case .missingKey: return (.missingKey, nil)
        case .keyStorage: return (.keyStorage, nil)
        case .oversized: return (.oversized, nil)
        case .timeout: return (.timeout, nil)
        case .offline: return (.offline, nil)
        case .interrupted: return (.cancelled, nil)
        case .blocked: return (.blocked, nil)
        case .http(let code): return (.http, code)
        case .knowledge: return (.knowledge, nil)
        case .invalidEndpoint: return (.invalidEndpoint, nil)
        case .invalidConfiguration: return (.invalidConfiguration, nil)
        }
    }
}

import Foundation
@testable import ConfLingo

struct SizeMeasurement: Encodable {
    let caseID: String
    let model = "gemini-3.8-flash"
    var state = "reserved"
    var wireBytes = 0
    var decodedBytes = 0
    var decodedCharacters = 0
    var maximumLineBytes = 0
    var maximumEventBytes = 0
    var events = 0
    var inputTokens: Int?
    var outputTokens: Int?
    var thinkingTokens: Int?
    var finishReason = "unknown"
    var productDecode = "not-run"
    var seconds = 0.0
    var failure: String?
    var usageKnown: Bool { inputTokens != nil && outputTokens != nil && thinkingTokens != nil }

    static func parse(_ data: Data, caseID: String) throws -> Self {
        var result = Self(caseID: caseID)
        result.wireBytes = data.count
        var objects: [[String: Any]] = []
        if caseID.hasPrefix("summary-") {
            var frame = Data()
            for line in data.split(separator: 10, omittingEmptySubsequences: false) {
                result.maximumLineBytes = max(result.maximumLineBytes, line.count)
                var bytes = Data(line)
                if bytes.last == 13 { bytes.removeLast() }
                if bytes.isEmpty {
                    if !frame.isEmpty {
                        try result.acceptFrame(frame, into: &objects)
                        frame.removeAll(keepingCapacity: true)
                    }
                } else if bytes.starts(with: Data("data:".utf8)) {
                    bytes.removeFirst(5)
                    if bytes.first == 32 { bytes.removeFirst() }
                    if !frame.isEmpty { frame.append(10) }
                    frame.append(bytes)
                    guard frame.count <= 1_024 * 1_024 else { throw InsightFailure.oversized }
                }
            }
            if !frame.isEmpty { try result.acceptFrame(frame, into: &objects) }
            var decoder = GeminiStreamDecoder()
            do { try decoder.consume(data); _ = try decoder.finish(); result.productDecode = "success" }
            catch { result.productDecode = String(describing: InsightFailure.sanitized(error)) }
        } else {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InsightFailure.invalidResponse }
            objects = [object]
            result.events = 1
            result.maximumEventBytes = data.count
            let request = try InsightRequest(sessionID: UUID(), question: "size probe", trigger: .manual, events: [])
            do { _ = try LLMResearchResponse.decode(data, provider: .gemini, request: request); result.productDecode = "success" }
            catch { result.productDecode = String(describing: InsightFailure.sanitized(error)) }
        }
        var text = ""
        for object in objects {
            if let usage = object["usageMetadata"] as? [String: Any],
               let input = usage["promptTokenCount"] as? Int, let output = usage["candidatesTokenCount"] as? Int,
               input >= 0, output >= 0, (usage["thoughtsTokenCount"] as? Int ?? 0) >= 0 {
                result.inputTokens = input
                result.outputTokens = output
                result.thinkingTokens = usage["thoughtsTokenCount"] as? Int ?? 0
            }
            for candidate in object["candidates"] as? [[String: Any]] ?? [] {
                for part in (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [] where part["thought"] as? Bool != true {
                    text += part["text"] as? String ?? ""
                }
                if let reason = candidate["finishReason"] as? String {
                    result.finishReason = ["STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "OTHER"].contains(reason) ? reason : "other"
                }
            }
        }
        result.decodedBytes = text.utf8.count
        result.decodedCharacters = text.count
        result.state = result.usageKnown ? "complete" : "complete-usage-unknown"
        return result
    }

    private mutating func acceptFrame(_ frame: Data, into objects: inout [[String: Any]]) throws {
        guard frame.count <= 1_024 * 1_024 else { throw InsightFailure.oversized }
        maximumEventBytes = max(maximumEventBytes, frame.count)
        events += 1
        if frame == Data("[DONE]".utf8) { return }
        guard let object = try JSONSerialization.jsonObject(with: frame) as? [String: Any] else { throw InsightFailure.invalidResponse }
        objects.append(object)
    }
}

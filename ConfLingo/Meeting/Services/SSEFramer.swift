import Foundation

struct SSEFramer {
    private var line = Data()
    private var frame: [String] = []
    private var frameBytes = 0
    private var totalBytes = 0

    mutating func consume(_ byte: UInt8) throws -> String? {
        totalBytes += 1
        guard totalBytes <= LLMResponseLimits.wireBytes else { throw InsightFailure.oversized }
        if byte == 10 { return try acceptLine() }
        line.append(byte)
        guard line.count <= LLMResponseLimits.eventBytes else { throw InsightFailure.oversized }
        return nil
    }

    mutating func finish() throws -> String? {
        if !line.isEmpty, let event = try acceptLine() { return event }
        return dispatch()
    }

    private mutating func acceptLine() throws -> String? {
        guard var text = String(data: line, encoding: .utf8) else { throw InsightFailure.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if text.last == "\r" { text.removeLast() }
        if text.isEmpty { return dispatch() }
        if text.hasPrefix("data:") {
            var value = String(text.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            let nextBytes = frameBytes + value.utf8.count + (frame.isEmpty ? 0 : 1)
            guard nextBytes <= LLMResponseLimits.eventBytes else { throw InsightFailure.oversized }
            frameBytes = nextBytes
            frame.append(value)
        }
        return nil
    }

    private mutating func dispatch() -> String? {
        guard !frame.isEmpty else { return nil }
        let text = frame.joined(separator: "\n")
        frame.removeAll(keepingCapacity: true)
        frameBytes = 0
        return text
    }
}

import Foundation
import Testing
@testable import ConfLingo

struct ResponseLimitTests {
    @Test(arguments: [LLMProvider.gemini, .openai, .claude, .local], [1, 1_023])
    func multilineFrameCountsSeparatorsAndResetsBetweenEvents(provider: LLMProvider, chunkBytes: Int) throws {
        let stream = String(decoding: try responseStream(provider, payload: responsePayload("回答😀")), as: UTF8.self)
        let boundary = try #require(stream.range(of: "\n\n"))
        let json = String(stream[..<boundary.lowerBound].dropFirst(6))
        let remaining = String(stream[boundary.upperBound...])
        func paddedFrame(bytes: Int) -> Data {
            let lines = ["{", "", String(repeating: " ", count: 32_700),
                         String(repeating: " ", count: bytes - json.utf8.count - 32_700 - 4), String(json.dropFirst())]
            #expect(lines.joined(separator: "\n").utf8.count == bytes)
            return Data((lines.map { "data: " + $0 }.joined(separator: "\n") + "\n\n" + remaining).utf8)
        }
        #expect(try decodeResponse(provider, stream: paddedFrame(bytes: 65_536), chunkBytes: chunkBytes).text == "回答😀")
        #expect(throws: InsightFailure.oversized) {
            try decodeResponse(provider, stream: paddedFrame(bytes: 65_537), chunkBytes: chunkBytes)
        }
    }

    @Test(arguments: LLMProvider.allCases)
    func allowedAnswerSurvivesSmallSSEEventsAndUTF8Chunks(provider: LLMProvider) throws {
        let text = String(repeating: "あ", count: 7_999) + "😀"
        let payload = try responsePayload(text)
        let stream = try responseStream(provider, payload: payload, charactersPerEvent: 1)
        #expect(stream.count > 262_144)
        #expect(try decodeResponse(provider, stream: stream, chunkBytes: 1_023).text == text)
    }

    @Test(arguments: LLMProvider.allCases)
    func maximumAnswerAndSupplementSurviveSingleCharacterEvents(provider: LLMProvider) throws {
        let text = String(repeating: "あ", count: 8_000)
        let object: [String: Any] = ["text": text, "supplement": text, "kind": "answerSuggestion", "evidenceIDs": []]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let stream = try responseStream(provider, payload: payload, charactersPerEvent: 1)
        #expect(stream.count > 262_144)
        let result = try decodeResponse(provider, stream: stream)
        #expect(result.text == text)
        #expect(result.supplement == text)
    }

    @Test(arguments: LLMProvider.allCases)
    func decodedPayloadBoundaryRemainsIndependent(provider: LLMProvider) throws {
        let base = #"{"text":"answer","kind":"answerSuggestion","evidenceIDs":[],"padding":""}"#
        let exact = base.replacingOccurrences(of: #""padding":"""#, with: "\"padding\":\"" + String(repeating: "a", count: 65_536 - base.utf8.count) + "\"")
        #expect(exact.utf8.count == 65_536)
        #expect(try decodeResponse(provider, stream: responseStream(provider, payload: exact, charactersPerEvent: 512)).text == "answer")
        let overflow = exact + " "
        #expect(throws: InsightFailure.oversized) {
            try decodeResponse(provider, stream: responseStream(provider, payload: overflow, charactersPerEvent: 512))
        }
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude, .local])
    func largeWireAllowanceDoesNotPermitLongLinesOrFrames(provider: LLMProvider) throws {
        #expect(throws: InsightFailure.oversized) {
            try decodeResponse(provider, stream: Data((":" + String(repeating: "a", count: 65_536)).utf8))
        }
        let frame = String(repeating: "data: " + String(repeating: "a", count: 32_769) + "\n", count: 2)
        #expect(throws: InsightFailure.oversized) { try decodeResponse(provider, stream: Data(frame.utf8)) }
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude, .local])
    func semanticTextLimitAndIncompleteEndRemainRejected(provider: LLMProvider) throws {
        #expect(throws: InsightFailure.invalidResponse) {
            try decodeResponse(provider, stream: responseStream(provider, payload: responsePayload(String(repeating: "a", count: 8_001))))
        }
        #expect(throws: InsightFailure.invalidResponse) {
            try decodeResponse(provider, stream: responseStream(provider, payload: responsePayload("answer"), complete: false))
        }
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude, .local])
    func totalWireBudgetAcceptsBoundaryAndRejectsNextByte(provider: LLMProvider) throws {
        var stream = try responseStream(provider, payload: responsePayload("answer"))
        let budget = 2 * 1_024 * 1_024
        let comment = Data((":" + String(repeating: "x", count: 1_022) + "\n").utf8)
        while stream.count + comment.count <= budget { stream.append(comment) }
        stream.append(Data(repeating: 10, count: budget - stream.count))
        #expect(try decodeResponse(provider, stream: stream).text == "answer")
        stream.append(10)
        #expect(throws: InsightFailure.oversized) { try decodeResponse(provider, stream: stream) }
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude])
    func researchWireBudgetIsFinite(provider: LLMProvider) throws {
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        var data = try nativeResearchFixture(provider)
        data.append(Data(repeating: 32, count: 2 * 1_024 * 1_024 - data.count))
        #expect(try LLMResearchResponse.decode(data, provider: provider, request: request).webReferences?.count == 1)
        data.append(32)
        #expect(throws: InsightFailure.oversized) { try LLMResearchResponse.decode(data, provider: provider, request: request) }
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude])
    func shortResearchAnswerSurvivesLargerJSONEnvelope(provider: LLMProvider) throws {
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        var response = try nativeResearchFixture(provider)
        response.append(Data(repeating: 32, count: 300_000))
        let answer = try LLMResearchResponse.decode(response, provider: provider, request: request)
        #expect(answer.text.hasPrefix("Finding"))
        #expect(answer.webReferences?.count == 1)
        #expect(throws: InsightFailure.invalidResponse) {
            try LLMResearchResponse.decode(nativeResearchFixture(provider, text: String(repeating: "a", count: 8_001)), provider: provider, request: request)
        }
    }
}

func responsePayload(_ text: String) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["text": text, "kind": "answerSuggestion", "evidenceIDs": []]), as: UTF8.self)
}

func decodeResponse(_ provider: LLMProvider, stream: Data, chunkBytes: Int = 4_096) throws -> InsightResult {
    var gemini = LLMStreamDecoder(provider: .gemini)
    var llm = LLMStreamDecoder(provider: provider)
    for offset in stride(from: 0, to: stream.count, by: chunkBytes) {
        let data = stream.subdata(in: offset..<min(offset + chunkBytes, stream.count))
        if provider == .gemini { try gemini.consume(data) } else { try llm.consume(data) }
    }
    return try provider == .gemini ? gemini.finish() : llm.finish()
}

func responseStream(_ provider: LLMProvider, payload: String, charactersPerEvent: Int = 512, complete: Bool = true) throws -> Data {
    func frame(_ object: [String: Any]) throws -> Data {
        Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: object)) + Data("\n\n".utf8)
    }
    var result = Data()
    let characters = Array(payload)
    for offset in stride(from: 0, to: characters.count, by: charactersPerEvent) {
        let part = String(characters[offset..<min(offset + charactersPerEvent, characters.count)])
        switch provider {
        case .gemini: result += try frame(["candidates": [["index": 0, "content": ["parts": [["text": part]]]]]])
        case .openai: result += try frame(["type": "response.output_text.delta", "delta": part])
        case .claude: result += try frame(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": part]])
        default: result += try frame(["choices": [["index": 0, "delta": ["content": part], "finish_reason": NSNull()]]])
        }
    }
    guard complete else { return result }
    switch provider {
    case .gemini: result += try frame(["candidates": [["index": 0, "finishReason": "STOP"]]])
    case .openai: result += try frame(["type": "response.completed", "response": ["status": "completed"]])
    case .claude:
        result += try frame(["type": "message_delta", "delta": ["stop_reason": "end_turn"]])
        result += try frame(["type": "message_stop"])
    default:
        result += try frame(["choices": [["index": 0, "delta": [:], "finish_reason": "stop"]]])
        result += Data("data: [DONE]\n\n".utf8)
    }
    return result
}

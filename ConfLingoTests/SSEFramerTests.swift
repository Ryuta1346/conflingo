import Foundation
import Testing
@testable import ConfLingo

struct SSEFramerTests {
    @Test func fragmentedUTF8CRLFAndMultipleDataLines() throws {
        var framer = SSEFramer()
        let stream = ": heartbeat\r\nevent: delta\r\nid: 1\r\ndata: 日本🙂\r\ndata:  indented\r\ndata:\r\n\r\n\ndata: second\n\n"
        let events = try stream.utf8.compactMap { try framer.consume($0) }
        #expect(events == ["日本🙂\n indented\n", "second"])
        #expect(try framer.finish() == nil)
    }

    @Test(arguments: ["data: final", "data: final\n", "data: final\r\n", "data: final\n\r"])
    func flushesFinalEventOnceAtEOF(stream: String) throws {
        var framer = SSEFramer()
        #expect(try stream.utf8.compactMap { try framer.consume($0) }.isEmpty)
        #expect(try framer.finish() == "final")
        #expect(try framer.finish() == nil)
    }

    @Test func emptyDataIsAnEventButCommentsAreNot() throws {
        var framer = SSEFramer()
        #expect(try "data:\n\n: comment\n\n".utf8.compactMap { try framer.consume($0) } == [""])
        #expect(try framer.finish() == nil)
    }

    @Test func rejectsInvalidUTF8AtLineEndAndEOF() throws {
        for terminated in [false, true] {
            var framer = SSEFramer()
            let prefix = Array("data: ".utf8) + [0xF0, 0x9F]
            for byte in prefix { _ = try framer.consume(byte) }
            #expect(throws: InsightFailure.invalidResponse) {
                if terminated { _ = try framer.consume(10) } else { _ = try framer.finish() }
            }
        }
    }

    @Test func limitsCountJoinedNewlinesAndResetAfterDispatch() throws {
        var framer = SSEFramer()
        let stream = "data: " + String(repeating: "x", count: 32_767) + "\ndata: " + String(repeating: "y", count: 32_768) + "\n\ndata: next\n\n"
        let events = try stream.utf8.compactMap { try framer.consume($0) }
        #expect(events.map { $0.utf8.count } == [65_536, 4])
        var overflow = SSEFramer()
        let excessive = "data: " + String(repeating: "x", count: 32_768) + "\ndata: " + String(repeating: "y", count: 32_768) + "\n"
        #expect(throws: InsightFailure.oversized) {
            for byte in excessive.utf8 { _ = try overflow.consume(byte) }
        }
    }

    @Test func ignoredLinesAndBlankLinesStillConsumeBudgets() throws {
        var line = SSEFramer()
        for byte in (":" + String(repeating: "x", count: 65_535)).utf8 { _ = try line.consume(byte) }
        #expect(throws: InsightFailure.oversized) { try line.consume(120) }
        var wire = SSEFramer()
        for _ in 0..<LLMResponseLimits.wireBytes { _ = try wire.consume(10) }
        #expect(throws: InsightFailure.oversized) { try wire.consume(10) }
    }
}

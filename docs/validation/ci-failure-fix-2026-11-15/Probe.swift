import Foundation

final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: 2 * 1024 * 1024))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct Probe {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for background in [false, true] {
            let (bytes, _) = try await session.bytes(from: URL(string: "https://example.invalid/probe")!)
            let start = ContinuousClock.now
            let result = try await background ? readBackground(bytes) : readMain(bytes)
            print("background=\(background), bytes=\(result.count), duration=\(start.duration(to: .now))")
        }
    }
    @MainActor static func readMain(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2 * 1024 * 1024 else { fatalError() }
            data.append(byte)
        }
        return data
    }
    @concurrent static func readBackground(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2 * 1024 * 1024 else { fatalError() }
            data.append(byte)
        }
        return data
    }
}

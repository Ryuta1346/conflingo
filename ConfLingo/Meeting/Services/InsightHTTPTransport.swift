import Foundation

@MainActor
protocol InsightHTTPTransport {
    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws
}

final class InsightRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
struct URLSessionInsightTransport: InsightHTTPTransport {
    var configuration: URLSessionConfiguration = .ephemeral
    var allowedBaseURL: URL? = nil

    static func permits(_ url: URL, base: URL?) -> Bool {
        guard url.user == nil, url.password == nil else { return false }
        guard let base else { return url.scheme == "https" && url.host == "generativelanguage.googleapis.com" }
        guard url.scheme == base.scheme, url.host == base.host, url.port == base.port else { return false }
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return url.path == base.path || url.path.hasPrefix(prefix)
    }

    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        try Task.checkCancellation()
        guard let url = request.url, Self.permits(url, base: allowedBaseURL) else {
            throw InsightFailure.invalidResponse
        }
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        let session = URLSession(configuration: configuration, delegate: InsightRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw InsightFailure.invalidResponse }
        guard response.statusCode == 200 else { throw InsightFailure.http(response.statusCode) }
        guard response.mimeType == "text/event-stream" else { throw InsightFailure.invalidResponse }
        var buffer = Data()
        var count = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            count += 1
            guard count <= LLMResponseLimits.wireBytes else { throw InsightFailure.oversized }
            buffer.append(byte)
            if byte == 10 || buffer.count >= 1_024 {
                try receive(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { try receive(buffer) }
    }
}

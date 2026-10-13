import Foundation

/// Test-only `URLProtocol` that captures the outgoing request (URL, headers, body)
/// and returns a canned response. Note: `URLSession` moves a request's `httpBody`
/// into `httpBodyStream` before it reaches a protocol, so the body is resolved from
/// whichever is present. Not production code.
final class MockURLProtocol: URLProtocol {
    /// Given the request and its resolved body, produce a response + body.
    static var handler: ((URLRequest, Data?) throws -> (HTTPURLResponse, Data))?
    /// The last request seen and its resolved body, for assertions.
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    static func reset() {
        handler = nil
        lastRequest = nil
        lastBody = nil
    }

    /// A `URLSession` wired to route all traffic through this mock.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Install a fixed JSON/text/binary response for the next request.
    static func stub(status: Int = 200,
                     headers: [String: String]? = nil,
                     body: Data = Data()) {
        handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            return (response, body)
        }
    }

    static func stub(status: Int = 200, json: String) {
        stub(status: status,
             headers: ["Content-Type": "application/json"],
             body: Data(json.utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.resolveBody(from: request)
        Self.lastRequest = request
        Self.lastBody = body

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request, body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Read the body from `httpBody` or, if `URLSession` streamed it, `httpBodyStream`.
    private static func resolveBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

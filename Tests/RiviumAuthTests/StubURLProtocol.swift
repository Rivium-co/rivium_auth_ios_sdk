import Foundation

/// Answers requests from a handler instead of the network, and records them.
final class StubURLProtocol: URLProtocol {
    struct Recorded {
        let method: String
        let path: String
        let headers: [String: String]
        let body: [String: Any]
    }

    enum Reply {
        case json(Int, Any, delay: TimeInterval = 0)
        case empty(Int)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    private static var _handler: ((Recorded) -> Reply)?
    private static var _requests: [Recorded] = []

    static func reset(_ handler: @escaping (Recorded) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _requests = []
    }

    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func requests(to path: String) -> [Recorded] {
        requests.filter { $0.path == path }
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = Recorded(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        Self.lock.lock()
        Self._requests.append(recorded)
        let handler = Self._handler
        Self.lock.unlock()

        let reply = handler?(recorded) ?? .empty(404)
        switch reply {
        case let .json(status, object, delay):
            let data = try! JSONSerialization.data(withJSONObject: object)
            let respond = { [self] in
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: respond)
            } else {
                respond()
            }
        case let .empty(status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            var buffer = Data()
            stream.open()
            let chunk = 4096
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
            defer { bytes.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let read = stream.read(bytes, maxLength: chunk)
                if read <= 0 { break }
                buffer.append(bytes, count: read)
            }
            data = buffer
        }
        guard let data = data, !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

/// A sign-in response body.
func sessionBody(access: String, refresh: String, user: String = "user-1", expiresIn: Int = 3600, created: Bool? = nil) -> [String: Any] {
    var body: [String: Any] = [
        "accessToken": access,
        "expiresIn": expiresIn,
        "expiresAt": "2026-10-16T12:00:00.000Z",
        "refreshToken": refresh,
        "userId": user,
    ]
    if let created = created { body["created"] = created }
    return body
}

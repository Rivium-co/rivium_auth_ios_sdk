import Foundation

/// Sends requests to Rivium Auth and turns error bodies into `RiviumAuthError`.
final class HTTPClient {
    let baseURL: URL
    let apiKey: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    /// Sends a request and decodes the JSON answer.
    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: String]? = nil,
        bearer: String? = nil,
        as type: T.Type
    ) async throws -> T {
        let data = try await raw(method, path, body: body, bearer: bearer)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RiviumAuthError(code: .invalidResponse, message: "Unexpected response from Rivium Auth", underlying: error)
        }
    }

    /// Sends a request whose answer has no body the SDK needs.
    func send(_ method: String, _ path: String, body: [String: String]? = nil, bearer: String? = nil) async throws {
        _ = try await raw(method, path, body: body, bearer: bearer)
    }

    private func raw(_ method: String, _ path: String, body: [String: String]?, bearer: String?) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(riviumAuthSDKHeader, forHTTPHeaderField: "X-Rivium-SDK")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer = bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw RiviumAuthError(code: .invalidResponse, message: "No HTTP response")
        }
        if (200..<300).contains(http.statusCode) { return data }
        throw Self.error(status: http.statusCode, data: data, retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"))
    }

    /// `URLSession.data(for:)` needs iOS 15; this works from iOS 13.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: RiviumAuthError(
                        code: .network,
                        message: "Could not reach Rivium Auth",
                        underlying: error
                    ))
                } else if let response = response {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: RiviumAuthError(code: .invalidResponse, message: "No HTTP response"))
                }
            }
            task.resume()
        }
    }

    static func error(status: Int, data: Data, retryAfterHeader: String?) -> RiviumAuthError {
        let body = try? JSONDecoder().decode(ErrorResponse.self, from: data)
        let code = body?.code.map(RiviumAuthError.Code.init(rawValue:))
            ?? (status >= 500 ? .internal : .invalidResponse)
        return RiviumAuthError(
            code: code,
            message: body?.message ?? "Request failed (\(status))",
            httpStatus: status,
            retryAfterSec: body?.retryAfterSec ?? retryAfterHeader.flatMap(Int.init),
            fields: body?.fields
        )
    }
}

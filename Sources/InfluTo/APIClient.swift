import Foundation

/// Thin URLSession wrapper. Bearer auth + JSON; throws `InfluToError` on non-2xx or
/// transport failure. Responses are snake_case → `.convertFromSnakeCase` maps them to the
/// camelCase model properties. Request bodies are built as dictionaries by the caller (so
/// `/sdk/event` + `/sdk/purchase` can use camelCase keys while others use snake_case).
final class APIClient {
    private let baseURL: URL
    private let apiKey: String
    private let debug: Bool
    private let session: URLSession

    init(baseURL: URL, apiKey: String, debug: Bool) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.debug = debug
        self.session = URLSession(configuration: .default)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await request(path, method: "POST", body: body)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET", body: nil)
    }

    private func request<T: Decodable>(_ path: String, method: String, body: [String: Any]?) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw InfluToError.transport(URLError(.badURL))
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw InfluToError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if debug { print("[InfluTo] \(method) \(path) -> \(status)") }
        guard (200..<300).contains(status) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            if status == 400 { throw InfluToError.notConfigured(bodyText) }
            if status == 503 || status >= 500 { throw InfluToError.retryable(status: status) }
            throw InfluToError.http(status: status, body: bodyText)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw InfluToError.decoding(error)
        }
    }
}

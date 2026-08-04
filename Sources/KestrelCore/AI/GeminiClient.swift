import Foundation

/// Minimal HTTP transport so the Gemini client is testable without a network or key.
public protocol HTTPClient: Sendable {
    func post(url: URL, headers: [String: String], body: Data) async throws -> (data: Data, status: Int)
}

public struct URLSessionHTTP: HTTPClient {
    public init() {}
    public func post(url: URL, headers: [String: String], body: Data) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Thin client for Google's Gemini `generateContent` API.
///
/// This is the project's only path that sends data off the device, so it is strictly
/// opt-in: nothing happens without an API key the user supplies, and callers send only
/// metadata (names, sizes, categories) — never file contents (see `AIAssistant`).
/// A pluggable large-language-model backend for the assistant. Lets Kestrel run the same
/// honest prompts through a cloud model (Gemini) or a fully on-device one — without any of the
/// assistant logic caring which. `system` carries the honesty system-prompt.
public protocol LLMBackend: Sendable {
    var isConfigured: Bool { get }
    func generate(_ prompt: String, system: String?) async throws -> String
}

public struct GeminiClient: LLMBackend {
    public enum GeminiError: Error, Equatable {
        case noAPIKey
        case http(Int)
        case badResponse
        case empty
    }

    private let apiKey: String
    private let model: String
    private let http: HTTPClient

    public init(apiKey: String, model: String = "gemini-3.5-flash", http: HTTPClient = URLSessionHTTP()) {
        self.apiKey = apiKey
        self.model = model
        self.http = http
    }

    public var isConfigured: Bool { !apiKey.isEmpty }

    public func generate(_ prompt: String, system: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.noAPIKey }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiError.badResponse
        }

        var payload: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.4],
        ]
        if let system {
            payload["systemInstruction"] = ["parts": [["text": system]]]
        }
        let body = try JSONSerialization.data(withJSONObject: payload)

        let (data, status) = try await http.post(
            url: url,
            headers: ["Content-Type": "application/json", "x-goog-api-key": apiKey],
            body: body
        )
        guard status == 200 else { throw GeminiError.http(status) }
        return try Self.parseText(data)
    }

    /// Extract the answer text from a `generateContent` response.
    public static func parseText(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.badResponse
        }
        guard let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.empty
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw GeminiError.empty }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

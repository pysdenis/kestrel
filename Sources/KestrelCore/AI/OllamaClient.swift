import Foundation

/// An LLM backend that talks to a locally-running **Ollama** server (`localhost:11434`). Fully
/// offline and free — the model (Llama, Qwen, Mistral, Phi…) runs on the user's own machine, so
/// like the rest of Kestrel nothing leaves the Mac. No API key. Used only when Ollama is actually
/// running with a model pulled; otherwise the app falls back to another backend.
public struct OllamaClient: LLMBackend {
    public enum OllamaError: Error, Equatable { case notRunning, http(Int), empty }

    public let host: URL
    public let model: String

    public init(host: URL = URL(string: "http://localhost:11434")!, model: String) {
        self.host = host
        self.model = model
    }

    public var isConfigured: Bool { !model.isEmpty }

    public func generate(_ prompt: String, system: String?) async throws -> String {
        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": prompt])
        let payload: [String: Any] = ["model": model, "messages": messages, "stream": false]

        var request = URLRequest(url: host.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120   // local models can be slow on first token

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OllamaError.notRunning }
        guard http.statusCode == 200 else { throw OllamaError.http(http.statusCode) }
        return try Self.parseChat(data)
    }

    /// Extract the assistant text from an `/api/chat` (non-streamed) response.
    public static func parseChat(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let content = message["content"] as? String else { throw OllamaError.empty }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OllamaError.empty }
        return text
    }

    /// The names of the models installed in an `/api/tags` response.
    public static func parseModels(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// The first installed model, or nil if Ollama isn't reachable / has no models. Quick timeout
    /// so a missing server never stalls the UI.
    public static func firstAvailableModel(host: URL = URL(string: "http://localhost:11434")!) async -> String? {
        var request = URLRequest(url: host.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return parseModels(data).first
    }
}

import Foundation

/// An LLM backend that talks to a locally-running **Ollama** server (`localhost:11434`). Fully
/// offline and free — the model (Llama, Qwen, Mistral, Phi…) runs on the user's own machine, so
/// like the rest of Kestrel nothing leaves the Mac. No API key. Used only when Ollama is actually
/// running with a model pulled; otherwise the app falls back to another backend.
public struct OllamaClient: LLMBackend {
    public enum OllamaError: Error, Equatable { case notRunning, http(Int), empty }

    public let host: URL
    public let model: String
    /// How long Ollama keeps the model resident in RAM after a reply. Short by design so an idle
    /// Kestrel (or a closed laptop) doesn't hold a multi-GB model in memory or wake the machine —
    /// it stays warm through a back-and-forth chat, then unloads. First message after idle pays a
    /// one-time reload; a fair trade for battery and a light background footprint.
    public let keepAlive: String

    public init(host: URL = URL(string: "http://localhost:11434")!, model: String, keepAlive: String = "90s") {
        self.host = host
        self.model = model
        self.keepAlive = keepAlive
    }

    public var isConfigured: Bool { !model.isEmpty }

    public func generate(_ prompt: String, system: String?) async throws -> String {
        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": prompt])
        let payload: [String: Any] = ["model": model, "messages": messages, "stream": false, "keep_alive": keepAlive]

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

    /// Ask Ollama to drop this model from RAM right now, instead of waiting out the keep-alive
    /// window — used when Kestrel goes to the background so an idle app holds no model in memory.
    /// A safe no-op if the model isn't loaded: Ollama never loads it just to unload it.
    public func unload() async {
        var request = URLRequest(url: host.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0])
        request.timeoutInterval = 3
        _ = try? await URLSession.shared.data(for: request)
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

    /// A good model for Kestrel's quick, honest metadata Q&A, or nil if Ollama isn't reachable /
    /// has no models. Prefers a small, fast, general-purpose model so insights come back snappily —
    /// a big coder/reasoning model would be slow and is overkill for this. Quick timeout so a
    /// missing server never stalls the UI.
    public static func firstAvailableModel(host: URL = URL(string: "http://localhost:11434")!) async -> String? {
        var request = URLRequest(url: host.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return preferredModel(from: parseModels(data))
    }

    /// Pick a good general chat model for Kestrel's assistant. Ordered for **multilingual quality
    /// that still runs light** — small models like llama3.2:3b garble non-English (e.g. Czech), so a
    /// solid 7–9B multilingual model is preferred when present, falling back to the small ones, and
    /// always avoiding a heavy coder/reasoning model. Prefixes are specific (e.g. "qwen2.5:7b") so a
    /// bare-family match never accidentally selects "qwen2.5-coder:14b". Pure — unit-testable.
    public static func preferredModel(from names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let preferred = [
            "qwen2.5:7b", "gemma2:9b", "llama3.1:8b", "mistral-nemo",   // strong multilingual, ~mid weight
            "qwen2.5:3b", "llama3.2", "phi3.5", "phi3", "gemma2:2b",     // lighter fallbacks
            "llama3.1", "mistral", "llama3",
        ]
        for family in preferred {
            if let match = names.first(where: { $0.hasPrefix(family) }) { return match }
        }
        // Otherwise avoid the obviously-heavy models (big coders / 14B+ / reasoning).
        let heavy = ["coder", "70b", "72b", "34b", "32b", "14b", "deepseek-r1"]
        if let light = names.first(where: { name in !heavy.contains(where: name.contains) }) { return light }
        return names.first
    }
}

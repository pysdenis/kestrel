import Foundation
import KestrelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// An LLM backend that runs **entirely on device** via Apple's Foundation Models (macOS 26,
/// Apple silicon with Apple Intelligence). The model executes locally, so the assistant's
/// honest advice — like everything else in Kestrel — never leaves the Mac. Zero network,
/// zero API key. Falls back gracefully (reports unavailable) when the model isn't present.
struct OnDeviceLLM: LLMBackend {
    var isConfigured: Bool { Self.isAvailable }

    /// Whether the on-device model is ready to use right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func generate(_ prompt: String, system: String?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession()
            let full = system.map { "\($0)\n\n\(prompt)" } ?? prompt
            let response = try await session.respond(to: full)
            return response.content
        }
        #endif
        throw NSError(domain: "Kestrel.OnDeviceLLM", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "On-device model is unavailable."])
    }
}

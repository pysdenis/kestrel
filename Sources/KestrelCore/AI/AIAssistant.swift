import Foundation

/// Kestrel's optional AI assistant, backed by Gemini. Every prompt it sends contains
/// only metadata — category names, sizes, file/dir names, questions — and never the
/// contents of any file. The system instruction enforces Kestrel's honesty rule: no
/// invented threats, no fake urgency.
public struct AIAssistant {
    private let client: GeminiClient

    public static let systemPrompt = """
    You are Kestrel, an honest macOS maintenance assistant. Be concise and factual. \
    Never invent malware, threats, or urgency. Only reason about the metadata you are \
    given (names and sizes) — you cannot see file contents. When you are unsure whether \
    something is safe to remove, say so and recommend keeping it. Prefer plain language.
    """

    public init(client: GeminiClient) {
        self.client = client
    }

    public var isConfigured: Bool { client.isConfigured }

    /// A friendly, honest summary of a cleanup scan plus prioritized safe suggestions.
    public func summarize(plan: CleanupPlan, disk: DiskSpace?) async throws -> String {
        var lines: [String] = []
        if let disk {
            lines.append("Disk: \(bytes(disk.used)) used of \(bytes(disk.total)), \(bytes(disk.available)) free.")
        }
        lines.append("Reclaimable now: \(bytes(plan.totalBytes)) across \(plan.count) items.")
        for (category, size) in plan.bytesByCategory.sorted(by: { $0.value > $1.value }) {
            lines.append("  • \(category.rawValue): \(bytes(size))")
        }
        let top = plan.items.sorted { $0.entry.size > $1.entry.size }.prefix(8)
        if !top.isEmpty {
            lines.append("Largest items:")
            for item in top { lines.append("  • \(item.entry.url.lastPathComponent) — \(bytes(item.entry.size)) (\(item.category.rawValue))") }
        }
        let prompt = """
        Here is a macOS cleanup scan (names and sizes only, no file contents):
        \(lines.joined(separator: "\n"))

        In 3–5 short sentences, summarize what this means for the user and give a couple \
        of prioritized, safe suggestions. Do not overstate urgency.
        """
        return try await client.generate(prompt, system: Self.systemPrompt)
    }

    /// Explain what a single item is and whether it is safe to remove.
    public func explain(name: String, category: Category, reason: String) async throws -> String {
        let prompt = """
        Explain briefly (2–4 sentences) what this macOS item is and whether it is safe to \
        remove. Metadata only:
        - name: \(name)
        - Kestrel category: \(category.rawValue)
        - Kestrel's note: \(reason)
        """
        return try await client.generate(prompt, system: Self.systemPrompt)
    }

    /// Free-form question answered against a caller-provided metadata context.
    public func ask(_ question: String, context: String) async throws -> String {
        let prompt = """
        Context (metadata only, no file contents):
        \(context)

        Question: \(question)
        """
        return try await client.generate(prompt, system: Self.systemPrompt)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

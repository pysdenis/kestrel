import Foundation

/// Kestrel's optional AI assistant, backed by Gemini. Every prompt it sends contains
/// only metadata — category names, sizes, file/dir names, questions — and never the
/// contents of any file. The system instruction enforces Kestrel's honesty rule: no
/// invented threats, no fake urgency.
public struct AIAssistant {
    private let client: LLMBackend
    private let systemPrompt: String

    public static let basePrompt = """
    You are Kestrel, an honest macOS maintenance assistant. Be concise and factual. \
    Never invent malware, threats, or urgency. Only reason about the metadata you are \
    given (names and sizes) — you cannot see file contents. When you are unsure whether \
    something is safe to remove, say so and recommend keeping it. Prefer plain language.
    """

    /// `responseLanguage` (e.g. "Czech", "English") makes the assistant answer in the user's UI
    /// language — the model otherwise defaults to English regardless of the question's language.
    public init(client: LLMBackend, responseLanguage: String = "English") {
        self.client = client
        self.systemPrompt = "\(Self.basePrompt) Always reply in \(responseLanguage), regardless of the language of the question."
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
        return try await client.generate(prompt, system: systemPrompt)
    }

    /// A second opinion before applying a cleanup: flag anything that looks risky.
    public func review(plan: CleanupPlan) async throws -> String {
        let items = plan.items.sorted { $0.entry.size > $1.entry.size }.prefix(30)
            .map { "  • \($0.entry.url.lastPathComponent) — \(bytes($0.entry.size)) [\($0.category.rawValue)] — \($0.reason)" }
        let prompt = """
        The user is about to move these items to Kestrel's reversible vault (not a \
        permanent delete — everything can be undone). Metadata only, no file contents:
        \(items.joined(separator: "\n"))

        Briefly: does anything here look risky or like it shouldn't be removed? If it all \
        looks safe to move to a reversible vault, say so in one line. Be honest and concise.
        """
        return try await client.generate(prompt, system: systemPrompt)
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
        return try await client.generate(prompt, system: systemPrompt)
    }

    /// Explain an antivirus finding in plain language — what it likely means and what to
    /// do — without over-alarming. Metadata only.
    public func explainFinding(_ finding: ScanFinding) async throws -> String {
        let prompt = """
        An antivirus scan flagged a file. In 2–4 sentences, explain what this likely means \
        and what a cautious user should do. Metadata only:
        - rule matched: \(finding.rule)
        - severity: \(finding.severity.rawValue)
        - evidence: \(finding.evidence)
        - file name: \((finding.path as NSString).lastPathComponent)
        Be calm and honest — if it is the harmless EICAR anti-malware test file, say so plainly.
        """
        return try await client.generate(prompt, system: systemPrompt)
    }

    /// Turn a plain-language cleanup request into a Kestrel rule as JSON. The user reviews
    /// and adds it — the assistant only proposes, it never writes or deletes anything.
    public func suggestRule(from description: String) async throws -> String {
        let prompt = """
        Convert this maintenance request into a single Kestrel rule as strict JSON only \
        (no prose, no code fences). Schema:
        {"name": string, "root": string (a folder path, ~ allowed),
         "criteria": {"olderThanDays"?: int, "largerThanBytes"?: int, "nameContains"?: string, "extensions"?: [string]}}
        Request: "\(description)"
        Output only the JSON object.
        """
        let text = try await client.generate(prompt, system: systemPrompt)
        // Strip any accidental code fences.
        return text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Free-form question answered against a caller-provided metadata context.
    public func ask(_ question: String, context: String) async throws -> String {
        let prompt = """
        Context (metadata only, no file contents):
        \(context)

        Question: \(question)
        """
        return try await client.generate(prompt, system: systemPrompt)
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

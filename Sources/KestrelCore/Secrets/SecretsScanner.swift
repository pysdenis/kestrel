import Foundation

/// A credential found in a project file. The preview is redacted — Kestrel never echoes
/// a full secret back at you.
public struct SecretMatch: Sendable, Equatable {
    public let path: String
    public let rule: String
    public let line: Int
    public let preview: String

    public init(path: String, rule: String, line: Int, preview: String) {
        self.path = path
        self.rule = rule
        self.line = line
        self.preview = preview
    }
}

/// Scans source trees for leaked credentials (API keys, tokens, private keys). Aimed at
/// the developer use case: point it at a project and it flags secrets that shouldn't be
/// committed. Read-only — it reports, it never edits or removes. Dev-artifact
/// directories and protected trees (incl. `.git`) are skipped by the scanner walk.
public struct SecretsScanner {
    public struct Rule: Sendable {
        public let name: String
        public let regex: NSRegularExpression
    }

    public static let defaultRules: [Rule] = build([
        ("AWS access key id", "AKIA[0-9A-Z]{16}"),
        ("Private key block", "-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----"),
        ("GitHub token", "gh[pousr]_[0-9A-Za-z]{36,}"),
        ("Slack token", "xox[baprs]-[0-9A-Za-z-]{10,}"),
        ("Google API key", "AIza[0-9A-Za-z_\\-]{35}"),
        ("Stripe secret key", "sk_live_[0-9A-Za-z]{24,}"),
        ("Generic assigned secret", "(?i)(?:api[_-]?key|secret|token|passw(?:or)?d)\\s*[:=]\\s*[\"'][^\"']{8,}[\"']"),
    ])

    public let rules: [Rule]
    /// Files larger than this are skipped (a secret lives in config/source, not a blob).
    public let maxFileBytes: Int

    public init(rules: [Rule] = SecretsScanner.defaultRules, maxFileBytes: Int = 2 * 1024 * 1024) {
        self.rules = rules
        self.maxFileBytes = maxFileBytes
    }

    public func scan(root: URL) -> [SecretMatch] {
        // Read-only scan: include protected *files* like `.pem`/`.env` (that is exactly
        // what we're hunting for), while the walk still skips protected *trees* such as
        // `.git`/`.ssh` and dev-artifact directories.
        let files = (try? Scanner().scanFiles(under: root, includingHidden: true, skipProtectedFiles: false)) ?? []
        return files.flatMap { scanFile($0.url) }
    }

    public func scanFile(_ url: URL) -> [SecretMatch] {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes, let data = try? Data(contentsOf: url) else { return [] }
        // Skip binaries: a NUL byte in the head is a reliable signal.
        if data.prefix(8000).contains(0) { return [] }
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var matches: [SecretMatch] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for rule in rules where rule.regex.firstMatch(in: line, options: [], range: range) != nil {
                matches.append(SecretMatch(path: url.path, rule: rule.name, line: index + 1, preview: redact(line)))
            }
        }
        return matches
    }

    // MARK: - Internals

    private static func build(_ specs: [(String, String)]) -> [Rule] {
        specs.compactMap { name, pattern in
            (try? NSRegularExpression(pattern: pattern)).map { Rule(name: name, regex: $0) }
        }
    }

    /// Show only enough to locate the line; never the full secret.
    private func redact(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let head = trimmed.prefix(12)
        return trimmed.count > 12 ? "\(head)… (redacted)" : "(redacted)"
    }
}

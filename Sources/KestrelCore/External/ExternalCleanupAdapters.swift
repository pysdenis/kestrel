import Foundation

/// A read-only reclaimable-space preview from an external tool that manages its own
/// storage (Docker layers, Homebrew's cellar/cache). Because that storage cannot be
/// moved into Kestrel's vault, these are **advisory**: Kestrel reports what could be
/// reclaimed and the native command to do it, but deletes nothing itself. Actual
/// pruning is left to the user, since it is delegated to the tool and not undoable
/// through the vault.
public struct ExternalCleanupPreview: Sendable, Equatable {
    public let tool: String
    public let available: Bool
    public let reclaimableBytes: Int64
    public let details: [String]
    public let command: String?
    public let note: String?

    public init(tool: String, available: Bool, reclaimableBytes: Int64, details: [String], command: String?, note: String?) {
        self.tool = tool
        self.available = available
        self.reclaimableBytes = reclaimableBytes
        self.details = details
        self.command = command
        self.note = note
    }

    static func unavailable(_ tool: String) -> ExternalCleanupPreview {
        ExternalCleanupPreview(
            tool: tool, available: false, reclaimableBytes: 0,
            details: ["\(tool) not found on PATH"], command: nil, note: nil
        )
    }
}

/// Previews reclaimable Docker space via `docker system df`. Advisory only.
public struct DockerAdapter {
    private let runner: CommandRunner
    public init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    public func preview() -> ExternalCleanupPreview {
        guard let version = try? runner.run("docker", ["--version"]), !version.isEmpty else {
            return .unavailable("Docker")
        }
        let output = (try? runner.run("docker", ["system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"])) ?? ""

        var total: Int64 = 0
        var details: [String] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            // Reclaimable looks like "1.2GB (60%)" — take the leading size token.
            let sizeToken = parts[1].split(separator: " ").first.map(String.init) ?? parts[1]
            guard let bytes = parseHumanBytes(sizeToken) else { continue }
            total += bytes
            if bytes > 0 { details.append("\(parts[0]): \(parts[1])") }
        }

        return ExternalCleanupPreview(
            tool: "Docker", available: true, reclaimableBytes: total, details: details,
            command: "docker system prune",
            note: "Delegated to Docker — not moved to Kestrel's vault."
        )
    }
}

/// Previews reclaimable Homebrew space via `brew cleanup --dry-run`. Advisory only.
public struct HomebrewAdapter {
    private let runner: CommandRunner
    public init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    public func preview() -> ExternalCleanupPreview {
        guard let version = try? runner.run("brew", ["--version"]), !version.isEmpty else {
            return .unavailable("Homebrew")
        }
        let output = (try? runner.run("brew", ["cleanup", "--dry-run"])) ?? ""

        var total: Int64 = 0
        var details: [String] = []
        for line in output.split(separator: "\n") {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            if text.lowercased().contains("free approximately") {
                // "==> This operation would free approximately 1.2GB of disk space."
                if let bytes = text.split(separator: " ").compactMap({ parseHumanBytes(String($0)) }).first {
                    total = bytes
                }
            } else if text.hasPrefix("Would remove") {
                details.append(text)
            }
        }

        return ExternalCleanupPreview(
            tool: "Homebrew", available: true, reclaimableBytes: total, details: details,
            command: "brew cleanup",
            note: "Delegated to Homebrew — not moved to Kestrel's vault."
        )
    }

    /// Formulae no longer needed by anything (orphaned dependencies) via `brew autoremove --dry-run`.
    /// Advisory only — the user runs `brew autoremove` themselves.
    public func autoremovePreview() -> ExternalCleanupPreview {
        guard let version = try? runner.run("brew", ["--version"]), !version.isEmpty else {
            return .unavailable("Homebrew")
        }
        let output = (try? runner.run("brew", ["autoremove", "--dry-run"])) ?? ""
        return Self.parseAutoremove(output)
    }

    /// Parse `brew autoremove --dry-run` output (formulae list + reclaimable). Pure — unit-testable.
    public static func parseAutoremove(_ output: String) -> ExternalCleanupPreview {
        var total: Int64 = 0
        var formulae: [String] = []
        var inList = false
        for rawLine in output.split(separator: "\n") {
            let text = String(rawLine).trimmingCharacters(in: .whitespaces)
            if text.lowercased().contains("free approximately") {
                if let bytes = text.split(separator: " ").compactMap({ parseHumanBytes(String($0)) }).first { total = bytes }
                inList = false
            } else if text.hasPrefix("==> Would remove") || text.lowercased().contains("would remove") {
                inList = true
            } else if inList, !text.isEmpty, !text.hasPrefix("==>") {
                // A space-separated list of formula names.
                formulae.append(contentsOf: text.split(separator: " ").map(String.init))
            }
        }
        let available = !formulae.isEmpty || total > 0
        return ExternalCleanupPreview(
            tool: "Homebrew unused", available: available, reclaimableBytes: total,
            details: formulae.isEmpty ? [] : ["\(formulae.count) unused: \(formulae.prefix(12).joined(separator: ", "))"],
            command: "brew autoremove",
            note: available ? "Orphaned dependencies — run brew autoremove to remove them." : "No unused formulae."
        )
    }
}

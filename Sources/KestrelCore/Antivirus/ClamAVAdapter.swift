import Foundation

public struct ClamResult: Sendable, Equatable {
    public let available: Bool
    public let infected: Int
    public let findings: [String]

    public init(available: Bool, infected: Int, findings: [String]) {
        self.available = available
        self.infected = infected
        self.findings = findings
    }
}

/// Advisory adapter for a locally installed ClamAV (`clamscan`). Bundling ClamAV +
/// freshclam is a Phase 4 packaging task; until then, if the user already has clamscan
/// on PATH we delegate to it and report its real findings. Injectable runner so it is
/// testable without ClamAV installed.
public struct ClamAVAdapter {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func isAvailable() -> Bool {
        !(((try? runner.run("clamscan", ["--version"])) ?? "").isEmpty)
    }

    public func scan(path: String) -> ClamResult {
        guard isAvailable() else { return ClamResult(available: false, infected: 0, findings: []) }
        let output = (try? runner.run("clamscan", ["-r", "--infected", "--no-summary", path])) ?? ""
        let findings = output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasSuffix("FOUND") }
        return ClamResult(available: true, infected: findings.count, findings: findings)
    }
}

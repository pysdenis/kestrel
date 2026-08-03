import Foundation

/// APFS / Time Machine local snapshots on a volume. These can quietly hold gigabytes of
/// "purgeable" space. Read via `tmutil listlocalsnapshots`. Deleting them needs `tmutil`
/// (and usually admin), so — like other system-state changes — Kestrel reports them and
/// the exact command rather than deleting behind your back.
public struct LocalSnapshotAuditor {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Snapshot names (e.g. `com.apple.TimeMachine.2026-01-01-120000.local`) on `volume`.
    public func snapshots(on volume: String = "/") -> [String] {
        let output = (try? runner.run("tmutil", ["listlocalsnapshots", volume])) ?? ""
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }
    }

    /// The date token used by `tmutil deletelocalsnapshots <date>`.
    public func deletionDate(from snapshot: String) -> String? {
        // com.apple.TimeMachine.2026-01-01-120000.local  →  2026-01-01-120000
        let trimmed = snapshot.replacingOccurrences(of: ".local", with: "")
        return trimmed.split(separator: ".").last.map(String.init)
    }
}

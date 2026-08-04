import Foundation

/// Frees inactive memory by invoking macOS's own `purge`. Non-destructive — it flushes
/// and compacts caches so more RAM shows as free; it never touches user data. Advisory
/// and opt-in (the user presses a button); Kestrel doesn't do it silently.
public struct MemoryReliever {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Runs `purge`. Returns true only when the tool is actually present and the command
    /// ran without throwing — so the UI never claims success when nothing happened.
    @discardableResult
    public func freeInactiveMemory() -> Bool {
        let candidates = ["/usr/sbin/purge", "/usr/bin/purge"]
        guard candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        return (try? runner.run("purge", [])) != nil
    }
}

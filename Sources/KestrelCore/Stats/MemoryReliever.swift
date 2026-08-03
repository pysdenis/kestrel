import Foundation

/// Frees inactive memory by invoking macOS's own `purge`. Non-destructive — it flushes
/// and compacts caches so more RAM shows as free; it never touches user data. Advisory
/// and opt-in (the user presses a button); Kestrel doesn't do it silently.
public struct MemoryReliever {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Runs `purge`. Returns true if the command ran without throwing.
    @discardableResult
    public func freeInactiveMemory() -> Bool {
        return (try? runner.run("purge", [])) != nil
    }
}

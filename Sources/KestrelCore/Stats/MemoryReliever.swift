import Foundation

/// Frees inactive memory by invoking macOS's own `purge`. Non-destructive — it flushes
/// and compacts caches so more RAM shows as free; it never touches user data. Advisory
/// and opt-in (the user presses a button); Kestrel doesn't do it silently.
public struct MemoryReliever {
    static let candidates = ["/usr/sbin/purge", "/usr/bin/purge"]

    public init() {}

    /// Where `purge` lives, if it's installed. Split out so it's testable without prompting.
    public static func purgePath(fm: FileManager = .default) -> String? {
        candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// Runs `purge`. It requires root on modern macOS, so this asks for authorization via a
    /// standard admin prompt. Returns `true` only when it actually ran (exit 0) — so the UI
    /// never claims success when the user cancelled or the tool is missing. Never fakes it.
    @discardableResult
    public func freeInactiveMemory() -> Bool {
        guard let tool = Self.purgePath() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(tool)\" with administrator privileges"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

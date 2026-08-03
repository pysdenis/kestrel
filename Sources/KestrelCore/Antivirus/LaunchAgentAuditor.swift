import Foundation

/// A registered launchd job (login item / background agent) and whether the program it
/// points at still exists.
public struct LaunchItem: Sendable, Equatable {
    public let path: String
    public let label: String?
    public let program: String?
    public let programExists: Bool

    public init(path: String, label: String?, program: String?, programExists: Bool) {
        self.path = path
        self.label = label
        self.program = program
        self.programExists = programExists
    }
}

/// Audits LaunchAgents/LaunchDaemons directories. Its most useful output is *orphans* —
/// jobs whose executable was deleted (often left behind by an incompletely uninstalled
/// app), which are safe to point out and clean up.
public struct LaunchAgentAuditor {
    private let fm: FileManager
    private let directories: [URL]

    public init(directories: [URL]? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser, fm: FileManager = .default) {
        self.fm = fm
        self.directories = directories ?? [
            home.appendingPathComponent("Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons"),
        ]
    }

    public func audit() -> [LaunchItem] {
        directories.flatMap { dir -> [LaunchItem] in
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return entries.filter { $0.pathExtension == "plist" }.map(parse)
        }
    }

    /// Jobs whose program no longer exists on disk.
    public func orphans() -> [LaunchItem] {
        audit().filter { $0.program != nil && !$0.programExists }
    }

    private func parse(_ url: URL) -> LaunchItem {
        let dict = (try? Data(contentsOf: url))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
        let label = dict?["Label"] as? String
        let program = (dict?["Program"] as? String)
            ?? (dict?["ProgramArguments"] as? [String])?.first
        let exists = program.map { fm.fileExists(atPath: $0) } ?? true
        return LaunchItem(path: url.path, label: label, program: program, programExists: exists)
    }
}

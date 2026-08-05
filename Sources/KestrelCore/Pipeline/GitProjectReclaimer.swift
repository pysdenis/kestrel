import Foundation

/// A git repository with regenerable build junk inside it, annotated with how recently it was
/// worked on — so the user can nuke `node_modules`/`DerivedData`/`target/` from projects they
/// haven't touched in months, with confidence, instead of guessing from a flat glob.
public struct StaleProject: Sendable, Equatable, Identifiable {
    public let repoPath: String
    public let repoName: String
    public let lastCommit: Date?
    public let branch: String?
    public let artifacts: [FileEntry]   // regenerable artifacts inside this repo

    public var id: String { repoPath }
    public var reclaimableBytes: Int64 { artifacts.reduce(0) { $0 + $1.size } }
    public func daysSinceCommit(now: Date = Date()) -> Int? {
        lastCommit.map { max(0, Int(now.timeIntervalSince($0) / 86400)) }
    }

    public init(repoPath: String, repoName: String, lastCommit: Date?, branch: String?, artifacts: [FileEntry]) {
        self.repoPath = repoPath; self.repoName = repoName
        self.lastCommit = lastCommit; self.branch = branch; self.artifacts = artifacts
    }
}

/// Scans a dev root for regenerable build artifacts, groups them by their enclosing git repo, and
/// enriches each repo with last-commit date + branch. Only ever touches regenerable artifacts
/// (invariant #4) — never source or lockfiles — and removal (elsewhere) still routes through the
/// vault. The scan itself is read-only.
public struct GitProjectReclaimer {
    private let runner: CommandRunner
    private let fm: FileManager
    public init(runner: CommandRunner = ProcessRunner(), fm: FileManager = .default) {
        self.runner = runner; self.fm = fm
    }

    public func scan(root: URL, now: Date = Date()) -> [StaleProject] {
        let classified = (try? ScanCoordinator().scan(root: root)) ?? []
        let artifacts = classified.filter { $0.category == .devArtifact }.map(\.entry)
        let grouped = group(artifacts: artifacts)
        return grouped.map { repoPath, entries in
            let (date, branch) = repoInfo(repoPath)
            return StaleProject(repoPath: repoPath,
                                repoName: URL(fileURLWithPath: repoPath).lastPathComponent,
                                lastCommit: date, branch: branch, artifacts: entries)
        }
        // Stalest (oldest commit) first; unknown-age repos after dated ones; ties broken by size.
        .sorted { a, b in
            switch (a.lastCommit, b.lastCommit) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.reclaimableBytes > b.reclaimableBytes
            }
        }
    }

    /// Group artifacts by the path of their nearest enclosing git repo. Artifacts with no repo
    /// above them are grouped under their own parent directory (so they're still surfaced). Pure —
    /// unit-testable with temp dirs.
    func group(artifacts: [FileEntry]) -> [String: [FileEntry]] {
        var groups: [String: [FileEntry]] = [:]
        for entry in artifacts {
            let repo = enclosingRepo(of: entry.url) ?? entry.url.deletingLastPathComponent().path
            groups[repo, default: []].append(entry)
        }
        return groups
    }

    /// Walk up from a file to the nearest ancestor directory that contains a `.git` entry.
    func enclosingRepo(of url: URL) -> String? {
        var dir = url.deletingLastPathComponent()
        while dir.path != "/" && !dir.path.isEmpty {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir.path }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// (last-commit date, current branch) for a repo, via git. Nil when git or the repo isn't usable.
    private func repoInfo(_ repoPath: String) -> (Date?, String?) {
        let ts = (try? runner.run("git", ["-C", repoPath, "log", "-1", "--format=%ct"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let date = ts.flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
        let branch = (try? runner.run("git", ["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (date, (branch?.isEmpty == false) ? branch : nil)
    }
}

import Foundation
import KestrelCore

// Minimal, dependency-free CLI for Phase 0. A richer interface (swift-argument-parser,
// colored output) can come once the GUI phase pulls in more tooling.

let paths = KestrelPaths()
let vault = VaultService(vaultRoot: paths.vault)
let audit = AuditLog(url: paths.auditLog)

func fmtBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

func categoryFilter(_ name: String?) -> Set<KestrelCore.Category>? {
    switch name {
    case nil, "all": return nil
    case "cache": return [.safeCache]
    case "logs": return [.logs]
    case "dev": return [.devArtifact]
    case "dupes": return [.duplicate]
    case "large": return [.largeOld]
    default:
        FileHandle.standardError.write(Data("Unknown category '\(name!)'. Use: all|cache|logs|dev|dupes|large\n".utf8))
        exit(2)
    }
}

func categoryLabel(_ c: KestrelCore.Category) -> String {
    switch c {
    case .safeCache: return "cache"
    case .logs: return "logs"
    case .devArtifact: return "dev artifact"
    case .duplicate: return "duplicate"
    case .largeOld: return "large & old"
    case .appLeftover: return "app leftover"
    case .trash: return "trash"
    case .unknown: return "unknown"
    }
}

func scanOptions(from args: [String]) -> ScanOptions {
    let minSizeMB = Int64(option("--min-size", in: args) ?? "") ?? (LargeOldClassifier.defaultMinSize / (1024 * 1024))
    let minAgeDays = Double(option("--min-age", in: args) ?? "") ?? (LargeOldClassifier.defaultMinAge / 86400)
    return ScanOptions(
        includeDuplicates: !flag("--no-dupes", in: args),
        includeLargeOld: !flag("--no-large", in: args),
        largeOld: LargeOldClassifier(minSize: minSizeMB * 1024 * 1024, minAge: minAgeDays * 86400)
    )
}

func classify(at path: String, args: [String]) throws -> [ClassifiedEntry] {
    let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    return try ScanCoordinator().scan(root: root, options: scanOptions(from: args))
}

/// Per-category totals, largest first.
func printBreakdown(_ plan: CleanupPlan) {
    let byCat = plan.bytesByCategory
    let counts = Dictionary(grouping: plan.items, by: { $0.category }).mapValues(\.count)
    for (cat, bytes) in byCat.sorted(by: { $0.value > $1.value }) {
        let label = categoryLabel(cat).padding(toLength: 14, withPad: " ", startingAt: 0)
        print("  \(label)\(fmtBytes(bytes).padding(toLength: 12, withPad: " ", startingAt: 0))(\(counts[cat] ?? 0))")
    }
}

func printPlan(_ plan: CleanupPlan, limit: Int = 25) {
    if plan.items.isEmpty {
        print("Nothing to clean. ✅")
        return
    }
    print("Reclaimable: \(fmtBytes(plan.totalBytes)) across \(plan.count) item(s)\n")
    printBreakdown(plan)
    print("")
    let sorted = plan.items.sorted(by: { $0.entry.size > $1.entry.size })
    for item in sorted.prefix(limit) {
        print("  \(fmtBytes(item.entry.size).padding(toLength: 10, withPad: " ", startingAt: 0))  \(item.entry.url.path)")
        print("             ↳ \(item.reason)")
    }
    if sorted.count > limit {
        print("  … and \(sorted.count - limit) more")
    }
}

/// Duplicates and large & old files are opt-in; surface them so the user knows they
/// exist without ever including them in a default cleanup.
func printReviewHints(_ classified: [ClassifiedEntry]) {
    let review: [(KestrelCore.Category, String)] = [(.duplicate, "dupes"), (.largeOld, "large")]
    var printedHeader = false
    for (cat, flagName) in review {
        let plan = Planner().plan(classified, categories: [cat])
        guard !plan.items.isEmpty else { continue }
        if !printedHeader { print("\nReview (opt-in — not cleaned automatically):"); printedHeader = true }
        print("  \(categoryLabel(cat).padding(toLength: 14, withPad: " ", startingAt: 0))\(fmtBytes(plan.totalBytes).padding(toLength: 12, withPad: " ", startingAt: 0))(\(plan.count))   → kestrel clean <path> --category \(flagName)")
    }
}

func printTree(_ node: DirNode, indent: String = "", isRoot: Bool = true) {
    if isRoot {
        print("\(fmtBytes(node.size).padding(toLength: 11, withPad: " ", startingAt: 0)) \(node.url.path)")
    }
    let shown = node.children.prefix(20)
    for (i, child) in shown.enumerated() {
        let last = (i == shown.count - 1)
        let branch = last ? "└─ " : "├─ "
        let bar = sizeBar(child.size, of: node.size)
        print("\(indent)\(branch)\(fmtBytes(child.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(bar) \(child.name)")
        if !child.children.isEmpty {
            printTree(child, indent: indent + (last ? "   " : "│  "), isRoot: false)
        }
    }
    if node.children.count > shown.count {
        print("\(indent)   … and \(node.children.count - shown.count) more")
    }
}

func sizeBar(_ part: Int64, of whole: Int64) -> String {
    guard whole > 0 else { return "" }
    let filled = Int((Double(part) / Double(whole)) * 10)
    return "[" + String(repeating: "█", count: filled) + String(repeating: " ", count: 10 - filled) + "]"
}

/// Take a disk snapshot: volume capacity plus a top-level size breakdown of `root`.
func takeSnapshot(root: URL) -> DiskSnapshot {
    let space = DiskUsageReader().space(at: root) ?? DiskSpace(total: 0, available: 0)
    let tree = DiskMap().measure(root, maxDepth: 1)
    let breakdown = Dictionary(uniqueKeysWithValues: tree.children.map { ($0.url.path, $0.size) })
    return DiskSnapshot(date: Date(), space: space, breakdown: breakdown)
}

func fmtDays(_ days: Double) -> String {
    days >= 365 ? String(format: "%.1f years", days / 365) : String(format: "%.0f days", days)
}

func printExternalPreview(_ p: ExternalCleanupPreview) {
    guard p.available else {
        print("\(p.tool): not found on PATH — nothing to report.")
        return
    }
    if p.reclaimableBytes == 0 {
        print("\(p.tool): nothing to reclaim. ✅")
        return
    }
    print("\(p.tool): reclaimable \(fmtBytes(p.reclaimableBytes))\n")
    for detail in p.details.prefix(25) { print("  \(detail)") }
    if let command = p.command { print("\nRun to reclaim:  \(command)") }
    if let note = p.note { print("(\(note))") }
}

// MARK: - Argument option helpers

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func flag(_ name: String, in args: [String]) -> Bool { args.contains(name) }

func usage() {
    print("""
    kestrel — honest macOS maintenance

    USAGE:
      kestrel scan <path> [--category all|cache|logs|dev|dupes|large] [scan opts]
      kestrel clean <path> [--category ...] [--apply] [scan opts]   (default: dry-run)
      kestrel vault list
      kestrel vault undo <session-id>
      kestrel vault purge [--days N]                                (default: 14)
      kestrel uninstall <app> [--apply]         (app bundle + leftovers → vault)
      kestrel map <path> [--depth N]            (directory size tree)
      kestrel snapshot [path]                   (record disk usage; default: home)
      kestrel trend                             (growth rate + fill forecast)
      kestrel diff                              (what changed since last snapshot)
      kestrel docker                            (reclaimable Docker space, advisory)
      kestrel brew                              (reclaimable Homebrew space, advisory)
      kestrel audit tail [N]

    SCAN OPTS:
      --min-size <MB>   large & old threshold size   (default: 100)
      --min-age <days>  large & old threshold age    (default: 180)
      --no-dupes        skip duplicate detection
      --no-large        skip large & old detection

    Categories 'dupes' and 'large' are opt-in: they are surfaced for review but
    never cleaned unless named explicitly with --category.

    Safety: clean is a dry-run unless --apply is passed. Even with --apply,
    files are moved to ~/.kestrel/vault (never deleted) and can be undone.
    """)
}

// MARK: - Dispatch

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage(); exit(0) }
let rest = Array(args.dropFirst())

do {
    switch command {
    case "scan":
        guard let path = rest.first(where: { !$0.hasPrefix("-") }) else { usage(); exit(2) }
        let classified = try classify(at: path, args: rest)
        let plan = Planner().plan(classified, categories: categoryFilter(option("--category", in: rest)))
        printPlan(plan)
        if option("--category", in: rest) == nil { printReviewHints(classified) }

    case "clean":
        guard let path = rest.first(where: { !$0.hasPrefix("-") }) else { usage(); exit(2) }
        let apply = flag("--apply", in: rest)
        let classified = try classify(at: path, args: rest)
        let plan = Planner().plan(classified, categories: categoryFilter(option("--category", in: rest)))
        printPlan(plan)
        guard apply else {
            print("\nDRY-RUN — nothing moved. Re-run with --apply to move these to the vault.")
            break
        }
        let executor = CleanupExecutor(vault: vault, audit: audit)
        let result = try executor.execute(plan, apply: true)
        print("\nMoved \(result.movedCount) item(s), \(fmtBytes(result.movedBytes)) → vault session \(result.sessionId ?? "?")")
        if !result.failures.isEmpty {
            print("Failures: \(result.failures.count)")
            for f in result.failures { print("  \(f.path): \(f.error)") }
        }
        print("Undo with:  kestrel vault undo \(result.sessionId ?? "")")

    case "vault":
        let sub = rest.first ?? "list"
        switch sub {
        case "list":
            let sessions = try vault.listSessions()
            if sessions.isEmpty { print("Vault is empty."); break }
            for s in sessions {
                print("\(s.id)  \(s.count) item(s)  \(fmtBytes(s.totalBytes))  (\(s.createdAt))")
            }
        case "undo":
            guard rest.count > 1 else { print("Usage: kestrel vault undo <session-id>"); exit(2) }
            let restored = try vault.undo(session: rest[1])
            print("Restored \(restored) item(s) from session \(rest[1]).")
        case "purge":
            let days = Double(option("--days", in: rest) ?? "14") ?? 14
            let purged = try vault.purge(olderThan: days * 24 * 60 * 60)
            print("Purged \(purged.count) session(s) older than \(Int(days)) day(s).")
        default:
            print("Unknown vault subcommand '\(sub)'."); exit(2)
        }

    case "uninstall":
        guard let target = rest.first(where: { !$0.hasPrefix("-") }) else {
            print("Usage: kestrel uninstall <app name or path> [--apply]"); exit(2)
        }
        let uninstaller = AppUninstaller()
        let app = try uninstaller.resolve(target)
        let plan = try uninstaller.plan(for: app)
        print("Uninstall \(app.lastPathComponent)\(uninstaller.bundleIdentifier(of: app).map { " (\($0))" } ?? "")\n")
        printPlan(plan)
        guard flag("--apply", in: rest) else {
            print("\nDRY-RUN — nothing moved. Re-run with --apply to move these to the vault.")
            break
        }
        let result = try CleanupExecutor(vault: vault, audit: audit).execute(plan, apply: true)
        print("\nMoved \(result.movedCount) item(s), \(fmtBytes(result.movedBytes)) → vault session \(result.sessionId ?? "?")")
        print("Undo with:  kestrel vault undo \(result.sessionId ?? "")")

    case "map":
        guard let path = rest.first(where: { !$0.hasPrefix("-") }) else { print("Usage: kestrel map <path> [--depth N]"); exit(2) }
        let depth = Int(option("--depth", in: rest) ?? "2") ?? 2
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        printTree(DiskMap().measure(root, maxDepth: depth))

    case "snapshot":
        let path = rest.first(where: { !$0.hasPrefix("-") }) ?? paths.home.path
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let store = SnapshotStore(directory: paths.snapshots)
        let snapshot = takeSnapshot(root: root)
        try store.save(snapshot)
        print("Snapshot saved: used \(fmtBytes(snapshot.space.used)) of \(fmtBytes(snapshot.space.total)) (\(Int(snapshot.space.usedFraction * 100))%), \(snapshot.breakdown.count) top-level entries under \(root.path)")

    case "trend":
        let store = SnapshotStore(directory: paths.snapshots)
        let snapshots = try store.all()
        guard snapshots.count >= 2 else {
            print("Need at least 2 snapshots. Run 'kestrel snapshot' on different days."); break
        }
        print("\(snapshots.count) snapshots, \(snapshots.first!.date) → \(snapshots.last!.date)")
        if let t = try store.trend() {
            let dir = t.dailyGrowthBytes >= 0 ? "+" : "-"
            print("Growth: \(dir)\(fmtBytes(abs(t.dailyGrowthBytes)))/day")
            if let full = t.daysUntilFull { print("At this rate the volume fills in ~\(fmtDays(full)).") }
            else { print("Not filling up — usage is flat or shrinking.") }
        }

    case "diff":
        let store = SnapshotStore(directory: paths.snapshots)
        let changes = try store.recentChanges()
        if changes.isEmpty { print("No change between the two most recent snapshots (need ≥2)."); break }
        print("What changed since the previous snapshot:")
        for c in changes.prefix(20) {
            let sign = c.delta >= 0 ? "+" : "-"
            print("  \(sign)\(fmtBytes(abs(c.delta)).padding(toLength: 10, withPad: " ", startingAt: 0))  \(c.path)")
        }

    case "docker":
        printExternalPreview(DockerAdapter().preview())

    case "brew", "homebrew":
        printExternalPreview(HomebrewAdapter().preview())

    case "audit":
        let entries = try audit.readAll()
        let n = Int(rest.count > 1 ? rest[1] : "20") ?? 20
        for e in entries.suffix(n) {
            print("\(e.timestamp)  \(e.action)  \(e.result)  \(fmtBytes(e.bytes))  \(e.paths.joined(separator: ", "))")
        }

    case "help", "-h", "--help":
        usage()

    default:
        print("Unknown command '\(command)'.\n")
        usage()
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit(1)
}

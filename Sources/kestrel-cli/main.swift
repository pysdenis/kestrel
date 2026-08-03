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

func buildPlan(at path: String, category: String?) throws -> CleanupPlan {
    let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let scanner = Scanner()
    let classifier = RuleClassifier()
    let planner = Planner()
    let entries = try scanner.scanChildren(of: root)
    let classified = entries.map(classifier.classify)
    return planner.plan(classified, categories: categoryFilter(category))
}

func printPlan(_ plan: CleanupPlan) {
    if plan.items.isEmpty {
        print("Nothing to clean. ✅")
        return
    }
    print("Reclaimable: \(fmtBytes(plan.totalBytes)) across \(plan.count) item(s)\n")
    for item in plan.items.sorted(by: { $0.entry.size > $1.entry.size }) {
        print("  \(fmtBytes(item.entry.size).padding(toLength: 10, withPad: " ", startingAt: 0))  \(item.entry.url.path)")
        print("             ↳ \(item.reason)")
    }
}

// MARK: - Argument option helpers

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func flag(_ name: String, in args: [String]) -> Bool { args.contains(name) }

func usage() {
    print("""
    kestrel — honest macOS maintenance (Phase 0)

    USAGE:
      kestrel scan <path> [--category all|cache|logs|dev|dupes|large]
      kestrel clean <path> [--category ...] [--apply]     (default: dry-run)
      kestrel vault list
      kestrel vault undo <session-id>
      kestrel vault purge [--days N]                       (default: 14)
      kestrel audit tail [N]

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
        let plan = try buildPlan(at: path, category: option("--category", in: rest))
        printPlan(plan)

    case "clean":
        guard let path = rest.first(where: { !$0.hasPrefix("-") }) else { usage(); exit(2) }
        let apply = flag("--apply", in: rest)
        let plan = try buildPlan(at: path, category: option("--category", in: rest))
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

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
    case "privacy": return [.privacy]
    default:
        FileHandle.standardError.write(Data("Unknown category '\(name!)'. Use: all|cache|logs|dev|dupes|large|privacy\n".utf8))
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
    case .privacy: return "privacy"
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
    let review: [(KestrelCore.Category, String)] = [(.duplicate, "dupes"), (.largeOld, "large"), (.privacy, "privacy")]
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

// MARK: - AI (Gemini, opt-in)

func geminiAssistant() -> AIAssistant? {
    let key = ProcessInfo.processInfo.environment["KESTREL_GEMINI_API_KEY"] ?? ""
    guard !key.isEmpty else { return nil }
    let model = ProcessInfo.processInfo.environment["KESTREL_GEMINI_MODEL"] ?? "gemini-2.5-flash"
    return AIAssistant(client: GeminiClient(apiKey: key, model: model))
}

let aiDisabledHelp = """
AI is off. It is opt-in and sends only metadata (names, sizes, categories) to Google's
Gemini — never file contents. Enable it by exporting your key:
  export KESTREL_GEMINI_API_KEY=your-key
  (optional) export KESTREL_GEMINI_MODEL=gemini-2.5-flash
"""

func runAI(_ op: @escaping () async -> String?) -> String? {
    let sem = DispatchSemaphore(value: 0)
    var result: String?
    Task { result = await op(); sem.signal() }
    sem.wait()
    return result
}

func aiContext(path: String?) -> String {
    var parts: [String] = []
    if let d = StatsCollector().disk() {
        parts.append("Disk: \(fmtBytes(d.used)) used of \(fmtBytes(d.total)), \(fmtBytes(d.available)) free.")
    }
    if let path {
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let classified = (try? ScanCoordinator().scan(root: root)) ?? []
        let plan = Planner().plan(classified)
        parts.append("Reclaimable under \(root.lastPathComponent): \(fmtBytes(plan.totalBytes)) across \(plan.count) items.")
        for (c, b) in plan.bytesByCategory.sorted(by: { $0.value > $1.value }) {
            parts.append("  \(categoryLabel(c)): \(fmtBytes(b))")
        }
    }
    return parts.joined(separator: "\n")
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

/// Print a plan, then either stop (dry-run) or move everything to the vault.
func runPlan(_ plan: CleanupPlan, apply: Bool) throws {
    printPlan(plan)
    guard apply else {
        if !plan.items.isEmpty { print("\nDRY-RUN — nothing moved. Re-run with --apply to move these to the vault.") }
        return
    }
    let result = try CleanupExecutor(vault: vault, audit: audit).execute(plan, apply: true)
    print("\nMoved \(result.movedCount) item(s), \(fmtBytes(result.movedBytes)) → vault session \(result.sessionId ?? "?")")
    print("Undo with:  kestrel vault undo \(result.sessionId ?? "")")
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
      kestrel scan <path> [--category all|cache|logs|dev|dupes|large|privacy] [scan opts]
      kestrel clean <path> [--category ...] [--apply] [scan opts]   (default: dry-run)
      kestrel vault list
      kestrel vault undo <session-id>
      kestrel vault purge [--days N]                                (default: 14)
      kestrel uninstall <app> [--apply]         (app bundle + leftovers → vault)
      kestrel orphans [--apply]                 (leftover data from removed apps)
      kestrel installers [path] [--apply]       (old .dmg/.pkg/.iso; default: Downloads)
      kestrel screenshots [path] [--apply]      (screenshots; default: Desktop)
      kestrel secrets <path>                    (scan a project for leaked credentials)
      kestrel power                             (what is keeping the Mac awake)
      kestrel localsnapshots                    (APFS/Time Machine local snapshots)
      kestrel shred <path> --apply              (secure permanent delete — no undo)
      kestrel rules list | run [name] [--apply] (declarative maintenance rules)
      kestrel stats [all|disk|mem|cpu|battery|net|health]
      kestrel energy                            (top battery/energy consumers now + 24h)
      kestrel speedtest                         (internet download speed + latency)
      kestrel map <path> [--depth N]            (directory size tree)
      kestrel snapshot [path]                   (record disk usage; default: home)
      kestrel trend                             (growth rate + fill forecast)
      kestrel diff                              (what changed since last snapshot)
      kestrel smartscan [path]                  (health + clutter + antivirus overview)
      kestrel maintenance                       (advisory system maintenance actions)
      kestrel updates                           (outdated Homebrew casks)
      kestrel activity                          (what Kestrel has reclaimed, from audit)
      kestrel advise [path]                     (AI cleanup summary — opt-in, metadata only)
      kestrel ask "<question>" [--path <dir>]   (ask the AI assistant — opt-in)
      kestrel explain <path>                    (AI: what is this / safe to delete? — opt-in)
      kestrel av scan <path>                    (honest on-demand malware scan)
      kestrel av watch [paths...]               (on-access scan; default: Downloads+Desktop)
      kestrel av status                         (Gatekeeper + XProtect status)
      kestrel av quarantine [path]              (files downloaded from the internet)
      kestrel av agents                         (orphaned launch agents)
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

    case "stats":
        let which = rest.first(where: { !$0.hasPrefix("-") }) ?? "all"
        let s = StatsCollector()
        // Sample CPU twice over a short interval so utilisation is real (not a baseline 0).
        let cpuSampler = CPUUsageSampler()
        _ = cpuSampler.sample()
        usleep(250_000)
        let base = s.cpu()
        let cpuStat = CPUStats(coreCount: base.coreCount, loadAverages: base.loadAverages, usagePercent: cpuSampler.sample())
        func showDisk() {
            if let d = s.disk() {
                print("Disk:    \(fmtBytes(d.used)) used of \(fmtBytes(d.total))  (\(Int(d.usedFraction * 100))% full), \(fmtBytes(d.available)) free" + (d.purgeable > 0 ? " + \(fmtBytes(d.purgeable)) purgeable" : ""))
            }
        }
        func showMem() { let m = s.memory(); print("Memory:  \(fmtBytes(m.used)) used of \(fmtBytes(m.total))  (\(Int(m.usedFraction * 100))%)") }
        func showCPU() { let c = cpuStat; print(String(format: "CPU:     %d%% used  ·  load %.2f / %.2f / %.2f on %d cores", Int(c.usagePercent.rounded()), c.loadAverages[0], c.loadAverages[1], c.loadAverages[2], c.coreCount)) }
        func hm(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }
        func showBattery() {
            if let b = s.battery() {
                var line = "Battery: \(b.percent)%\(b.isCharging ? " (charging)" : "")"
                if b.isCharging, let m = b.timeToFullMinutes { line += ", \(hm(m)) to full" }
                if !b.isCharging, let m = b.timeToEmptyMinutes { line += ", \(hm(m)) left" }
                if let h = b.healthPercent { line += ", health \(h)%" }
                if let cy = b.cycleCount { line += ", \(cy) cycles" }
                print(line)
            } else { print("Battery: none (desktop or unavailable)") }
        }
        func showNet() { let n = s.network(); print("Network: ↓\(fmtBytes(n.bytesIn)) ↑\(fmtBytes(n.bytesOut))\(n.ssid.map { "  Wi-Fi: \($0)" } ?? "")") }
        func showVolumes() { for v in s.volumes() { print("  \(v.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(fmtBytes(v.space.used)) / \(fmtBytes(v.space.total))") } }
        func showHealth() {
            let score = HealthScorer().score(disk: s.disk(), memory: s.memory(), cpu: cpuStat, battery: s.battery())
            print("Mac Health: \(score.overall)/100")
            for c in score.components {
                print("  \(c.name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(String(c.score).padding(toLength: 4, withPad: " ", startingAt: 0)) \(c.detail)")
            }
        }
        switch which {
        case "disk": showDisk(); showVolumes()
        case "mem", "memory": showMem()
        case "cpu": showCPU()
        case "battery": showBattery()
        case "net", "network": showNet()
        case "health": showHealth()
        case "all": showHealth(); print(""); showDisk(); showMem(); showCPU(); showBattery(); showNet()
        default: print("Unknown stats view '\(which)'. Use: all|disk|mem|cpu|battery|net|health"); exit(2)
        }

    case "speedtest":
        print("Testing internet speed (via Cloudflare)…")
        let sem = DispatchSemaphore(value: 0)
        var speedResult: Result<SpeedTestResult, Error>?
        Task {
            do { speedResult = .success(try await SpeedTest().run()) }
            catch { speedResult = .failure(error) }
            sem.signal()
        }
        sem.wait()
        switch speedResult {
        case .success(let r):
            print(String(format: "Download: %.1f Mbps   Latency: %.0f ms", r.downloadMbps, r.latencyMs))
        case .failure(let e):
            FileHandle.standardError.write(Data("Speed test failed: \(e)\n".utf8)); exit(1)
        case .none:
            exit(1)
        }

    case "ask":
        guard let assistant = geminiAssistant() else { print(aiDisabledHelp); exit(2) }
        let question = rest.filter { !$0.hasPrefix("-") && $0 != option("--path", in: rest) }.joined(separator: " ")
        guard !question.isEmpty else { print("Usage: kestrel ask \"<question>\" [--path <dir>]"); exit(2) }
        print("(AI: sending metadata only — names, sizes, your question. No file contents.)\n")
        let context = aiContext(path: option("--path", in: rest))
        let answer = runAI { try? await assistant.ask(question, context: context) }
        print(answer ?? "AI request failed.")

    case "explain":
        guard let assistant = geminiAssistant() else { print(aiDisabledHelp); exit(2) }
        guard let path = rest.first(where: { !$0.hasPrefix("-") }) else { print("Usage: kestrel explain <path>"); exit(2) }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let verdict = RuleClassifier().classify(Scanner().makeEntry(url))
        print("(AI: sending only the item's name and category.)\n")
        let answer = runAI { try? await assistant.explain(name: url.lastPathComponent, category: verdict.category, reason: verdict.reason) }
        print(answer ?? "AI request failed.")

    case "advise":
        guard let assistant = geminiAssistant() else { print(aiDisabledHelp); exit(2) }
        let path = rest.first(where: { !$0.hasPrefix("-") }) ?? paths.home.path
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        print("(AI: sending metadata only — category names and sizes.)\n")
        let classified = try ScanCoordinator().scan(root: root)
        let plan = Planner().plan(classified)
        let answer = runAI { try? await assistant.summarize(plan: plan, disk: StatsCollector().disk()) }
        print(answer ?? "AI request failed.")

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

    case "smartscan":
        let path = rest.first(where: { !$0.hasPrefix("-") }) ?? paths.home.path
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        print("Smart Scan of \(root.path)\n")
        let report = SmartScan().run(root: root)
        print("Mac Health: \(report.health.overall)/100")
        print("Reclaimable now: \(fmtBytes(report.cleanup.totalBytes)) across \(report.cleanup.count) item(s)")
        if !report.reviewByCategory.isEmpty {
            print("Opt-in review:")
            for (cat, bytes) in report.reviewByCategory.sorted(by: { $0.value > $1.value }) {
                print("  \(categoryLabel(cat).padding(toLength: 14, withPad: " ", startingAt: 0))\(fmtBytes(bytes))")
            }
        }
        print("Antivirus: " + (report.antivirus.isClean ? "clean ✅ (\(report.antivirus.scanned) files)" : "\(report.antivirus.findings.count) finding(s) in \(report.antivirus.scanned) files"))

    case "maintenance":
        print("Maintenance actions (run the command yourself — these change system state):\n")
        for t in MaintenanceService().tasks() {
            print("  • \(t.name)\(t.needsSudo ? "  [needs sudo]" : "")")
            print("      \(t.detail)")
            print("      $ \(t.command)")
        }

    case "updates":
        let outdated = AppUpdater().outdatedCasks()
        if outdated.isEmpty { print("No outdated Homebrew casks (or Homebrew not installed)."); break }
        print("\(outdated.count) outdated cask(s):")
        for c in outdated { print("  \(c.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(c.current) → \(c.latest)") }

    case "activity":
        let summary = ActivityReporter(audit: audit).summary()
        print("Kestrel has reclaimed \(fmtBytes(summary.reclaimedBytes)) across \(summary.totalActions) action(s).")
        for (cat, bytes) in summary.bytesByCategory.sorted(by: { $0.value > $1.value }) {
            print("  \(cat.padding(toLength: 16, withPad: " ", startingAt: 0)) \(fmtBytes(bytes))")
        }

    case "av":
        let sub = rest.first ?? "scan"
        switch sub {
        case "scan":
            guard let path = rest.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
                print("Usage: kestrel av scan <path>"); exit(2)
            }
            let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let report = AntivirusEngine().scan(root: root)
            if report.isClean {
                print("Scanned \(report.scanned) file(s). Clean. ✅")
            } else {
                print("Scanned \(report.scanned) file(s). \(report.findings.count) finding(s):\n")
                for f in report.findings {
                    print("  [\(f.severity.rawValue)] \(f.rule)\n     ↳ \(f.path)\n       \(f.evidence)")
                }
            }
        case "watch":
            let targets = Array(rest.dropFirst()).filter { !$0.hasPrefix("-") }
            let dirs = targets.isEmpty
                ? [paths.home.appendingPathComponent("Downloads"), paths.home.appendingPathComponent("Desktop")]
                : targets.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            print("On-access scan — watching for new/changed files (Ctrl-C to stop):")
            for d in dirs { print("  \(d.path)") }
            let watcher = OnAccessWatcher(paths: dirs) { findings in
                for f in findings {
                    FileHandle.standardOutput.write(Data("⚠️  [\(f.severity.rawValue)] \(f.rule): \(f.path)\n".utf8))
                }
            }
            watcher.start()
            dispatchMain() // blocks; FSEvents are delivered on the watcher's own queue

        case "status":
            let s = SystemProtectionReader().status()
            let gk = s.assessmentsEnabled.map { $0 ? "enabled" : "DISABLED" } ?? "unknown"
            print("Gatekeeper assessments: \(gk)")
            print("XProtect version: \(s.xprotectVersion ?? "unknown")")
        case "quarantine":
            let path = rest.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? paths.home.appendingPathComponent("Downloads").path
            let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: true)) ?? []
            let reader = QuarantineReader()
            let quarantined = files.compactMap { reader.read($0.url) }
            if quarantined.isEmpty { print("No quarantined files under \(root.path)."); break }
            print("\(quarantined.count) quarantined file(s):")
            for q in quarantined.prefix(40) { print("  \(q.agent.map { "[\($0)] " } ?? "")\(q.path)") }
        case "agents":
            let orphans = LaunchAgentAuditor().orphans()
            if orphans.isEmpty { print("No orphaned launch agents. ✅"); break }
            print("\(orphans.count) orphaned launch agent(s) (program missing):")
            for o in orphans { print("  \(o.label ?? "?")  →  \(o.program ?? "?")\n     ↳ \(o.path)") }
        default:
            print("Unknown av subcommand '\(sub)'. Use: scan|status|quarantine|agents"); exit(2)
        }

    case "orphans":
        try runPlan(OrphanFinder().find(), apply: flag("--apply", in: rest))

    case "installers":
        let path = rest.first(where: { !$0.hasPrefix("-") }) ?? paths.home.appendingPathComponent("Downloads").path
        let days = Int(option("--min-age", in: rest) ?? "30") ?? 30
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try runPlan(ClutterFinder().oldInstallers(under: root, olderThanDays: days), apply: flag("--apply", in: rest))

    case "screenshots":
        let path = rest.first(where: { !$0.hasPrefix("-") }) ?? paths.home.appendingPathComponent("Desktop").path
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try runPlan(ClutterFinder().screenshots(under: root), apply: flag("--apply", in: rest))

    case "secrets":
        guard let path = rest.first(where: { !$0.hasPrefix("-") }) else { print("Usage: kestrel secrets <path>"); exit(2) }
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let matches = SecretsScanner().scan(root: root)
        if matches.isEmpty { print("No leaked credentials found. ✅"); break }
        print("\(matches.count) potential secret(s):\n")
        for m in matches.prefix(100) {
            print("  [\(m.rule)] \(m.path):\(m.line)\n     ↳ \(m.preview)")
        }

    case "rules":
        let sub = rest.first ?? "list"
        let stored = RulesEngine.load(from: paths.rules)
        switch sub {
        case "list":
            if stored.isEmpty {
                print("No rules defined. Create \(paths.rules.path), e.g.:\n")
                print(#"  [{"name":"old downloads","root":"~/Downloads","criteria":{"olderThanDays":30}}]"#)
                break
            }
            for r in stored {
                var parts: [String] = []
                if let d = r.criteria.olderThanDays { parts.append("older than \(d)d") }
                if let b = r.criteria.largerThanBytes { parts.append("larger than \(fmtBytes(b))") }
                if let n = r.criteria.nameContains { parts.append("name contains '\(n)'") }
                if let e = r.criteria.extensions { parts.append("ext in [\(e.joined(separator: ","))]") }
                print("  • \(r.name): \(r.root) — \(parts.joined(separator: ", "))")
            }
        case "run":
            let named = rest.dropFirst().first(where: { !$0.hasPrefix("-") })
            let selected = named.map { name in stored.filter { $0.name == name } } ?? stored
            guard !selected.isEmpty else { print("No matching rules."); break }
            let items = selected.flatMap { RulesEngine().evaluate($0).items }
            try runPlan(CleanupPlan(items: items), apply: flag("--apply", in: rest))
        default:
            print("Unknown rules subcommand '\(sub)'. Use: list|run"); exit(2)
        }

    case "energy":
        let consumers = EnergyMonitor().topConsumers(limit: 12)
        let log = EnergyLog(url: paths.energyLog)
        log.append(consumers)
        if consumers.isEmpty { print("Could not read energy usage."); break }
        print("Top energy consumers right now:")
        for c in consumers {
            print("  \(String(format: "%6.1f", c.energyImpact))  \(String(format: "%5.1f", c.cpuPercent))% CPU  \(c.name) (pid \(c.pid))")
        }
        let usage = log.usage()
        if usage.count > 1 {
            print("\nMost draining over the recorded window (up to 24h, while Kestrel ran):")
            for u in usage.prefix(8) { print("  \(String(format: "%8.1f", u.total))  \(u.name)") }
        }

    case "power":
        let assertions = PowerAuditor().assertionsPreventingSleep()
        if assertions.isEmpty { print("Nothing is preventing sleep. ✅"); break }
        print("Processes keeping the Mac awake:")
        for a in assertions { print("  \(a.process.padding(toLength: 24, withPad: " ", startingAt: 0)) \(a.type)") }

    case "localsnapshots":
        let auditor = LocalSnapshotAuditor()
        let snaps = auditor.snapshots()
        if snaps.isEmpty { print("No local Time Machine snapshots."); break }
        print("\(snaps.count) local snapshot(s) (purgeable space):")
        for s in snaps { print("  \(s)") }
        if let date = auditor.deletionDate(from: snaps[0]) {
            print("\nDelete one with:  tmutil deletelocalsnapshots \(date)")
            print("(Delegated to tmutil — not moved to Kestrel's vault.)")
        }

    case "shred":
        guard let path = rest.first(where: { !$0.hasPrefix("-") }) else { print("Usage: kestrel shred <path> --apply"); exit(2) }
        let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard flag("--apply", in: rest) else {
            print("Would securely shred: \(target.path)")
            print("\nWARNING: shredding is PERMANENT and bypasses the vault — it cannot be undone.")
            print("Re-run with --apply to proceed.")
            break
        }
        try Shredder(audit: audit).shred(target)
        print("Shredded \(target.path). (Best-effort overwrite; on SSDs FileVault is the real protection.)")

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

    case "version", "--version", "-v":
        print("kestrel \(Kestrel.version)")

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

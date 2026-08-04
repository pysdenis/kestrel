import Foundation
import AppIntents
import KestrelCore

// Apple Shortcuts / Siri integration. Every intent here is read-only or dry-run — a
// Shortcut can *report* things (health, free space, reclaimable dev junk) but never
// deletes anything without the user reviewing it in the app (safety invariants #1/#2).

/// "What's my Mac's health?"
struct MacHealthIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Mac Health"
    static var description = IntentDescription("Report your Mac's current health score out of 100.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let stats = StatsCollector()
        let sampler = CPUUsageSampler()
        _ = sampler.sample()                                  // baseline
        try? await Task.sleep(nanoseconds: 800_000_000)
        let base = stats.cpu()
        let cpu = CPUStats(coreCount: base.coreCount, loadAverages: base.loadAverages, usagePercent: sampler.sample())
        let health = HealthScorer().score(disk: stats.disk(), memory: stats.memory(), cpu: cpu, battery: stats.battery())
        return .result(value: health.overall, dialog: "Your Mac's health is \(health.overall) out of 100 — \(Self.verdict(health.overall)).")
    }

    private static func verdict(_ score: Int) -> String {
        switch score { case 80...: return "in good shape"; case 50..<80: return "a little attention needed"; default: return "needs attention" }
    }
}

/// "How much free space do I have?"
struct FreeSpaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Free Disk Space"
    static var description = IntentDescription("Report how much free space is on your Mac.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let disk = StatsCollector().disk() else {
            return .result(dialog: "I couldn't read the disk right now.")
        }
        let free = ByteCountFormatter.string(fromByteCount: disk.available, countStyle: .file)
        let pct = disk.total > 0 ? Int(Double(disk.total - disk.available) / Double(disk.total) * 100) : 0
        return .result(dialog: "You have \(free) free — the disk is \(pct)% full.")
    }
}

/// "How much dev junk can I reclaim?" — dry-run only, nothing is removed.
struct ReclaimableDevJunkIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Reclaimable Dev Junk"
    static var description = IntentDescription("Scan your Home folder for regenerable developer artifacts (node_modules, build dirs, caches) and report how much you could reclaim. Nothing is deleted — open Kestrel to review and clean.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let home = KestrelPaths().home
        let classified = (try? ScanCoordinator().scan(root: home)) ?? []
        let plan = Planner().plan(classified, categories: [.devArtifact])
        let amount = ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)
        let dialog: IntentDialog = plan.items.isEmpty
            ? "No reclaimable dev junk found."
            : "You could reclaim \(amount) of dev junk across \(plan.count) item(s). Open Kestrel to review and clean it."
        return .result(value: amount, dialog: dialog)
    }
}

/// Surfaces the intents in the Shortcuts app with spoken phrases.
struct KestrelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MacHealthIntent(), phrases: [
            "Get my \(.applicationName) health",
            "What's my Mac health in \(.applicationName)",
        ], shortTitle: "Mac Health", systemImageName: "gauge.with.dots.needle.67percent")

        AppShortcut(intent: FreeSpaceIntent(), phrases: [
            "How much free space with \(.applicationName)",
            "Check free space in \(.applicationName)",
        ], shortTitle: "Free Space", systemImageName: "internaldrive")

        AppShortcut(intent: ReclaimableDevJunkIntent(), phrases: [
            "Check dev junk with \(.applicationName)",
            "How much dev junk in \(.applicationName)",
        ], shortTitle: "Dev Junk", systemImageName: "hammer")
    }
}

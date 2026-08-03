import Foundation

/// One combined pass over the machine: health, reclaimable clutter, opt-in review
/// candidates and an antivirus check — the "one button" overview, assembled from the
/// individual phases. Nothing here acts; it only reports, dry-run by nature.
public struct SmartScanReport: Sendable {
    public let health: HealthScore
    public let cleanup: CleanupPlan
    public let reviewByCategory: [Category: Int64]
    public let antivirus: ScanReport
}

public struct SmartScan {
    public init() {}

    public func run(root: URL) -> SmartScanReport {
        let stats = StatsCollector()
        let health = HealthScorer().score(disk: stats.disk(), memory: stats.memory(), cpu: stats.cpu(), battery: stats.battery())

        let classified = (try? ScanCoordinator().scan(root: root)) ?? []
        let cleanup = Planner().plan(classified)

        var review: [Category: Int64] = [:]
        for category in [Category.duplicate, .largeOld, .privacy] {
            let plan = Planner().plan(classified, categories: [category])
            if plan.totalBytes > 0 { review[category] = plan.totalBytes }
        }

        let antivirus = AntivirusEngine().scan(root: root)

        return SmartScanReport(health: health, cleanup: cleanup, reviewByCategory: review, antivirus: antivirus)
    }
}

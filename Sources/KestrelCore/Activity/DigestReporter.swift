import Foundation

/// A local weekly digest: what Kestrel reclaimed, how storage is trending, and what grew
/// since the previous snapshot. Built entirely from the audit log and snapshots — no
/// network, nothing invented.
public struct Digest: Sendable, Equatable {
    public let reclaimedAllTime: Int64
    public let totalActions: Int
    public let dailyGrowthBytes: Int64?
    public let daysUntilFull: Double?
    public let recentChanges: [SpaceDelta]

    public init(reclaimedAllTime: Int64, totalActions: Int, dailyGrowthBytes: Int64?, daysUntilFull: Double?, recentChanges: [SpaceDelta]) {
        self.reclaimedAllTime = reclaimedAllTime
        self.totalActions = totalActions
        self.dailyGrowthBytes = dailyGrowthBytes
        self.daysUntilFull = daysUntilFull
        self.recentChanges = recentChanges
    }
}

public struct DigestReporter {
    private let audit: AuditLog
    private let snapshots: SnapshotStore

    public init(audit: AuditLog, snapshots: SnapshotStore) {
        self.audit = audit
        self.snapshots = snapshots
    }

    public func generate() -> Digest {
        let summary = ActivityReporter(audit: audit).summary()
        let trend = try? snapshots.trend()
        let changes = (try? snapshots.recentChanges()) ?? []
        return Digest(
            reclaimedAllTime: summary.reclaimedBytes,
            totalActions: summary.totalActions,
            dailyGrowthBytes: trend?.dailyGrowthBytes,
            daysUntilFull: trend?.daysUntilFull,
            recentChanges: Array(changes.prefix(5))
        )
    }
}

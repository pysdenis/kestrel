import Foundation

/// How fast a tracked storage category grows back, and a suggested cleanup cadence — so "clean
/// DerivedData" turns into "…and it's worth doing about weekly".
public struct RegrowthEstimate: Sendable, Equatable, Identifiable {
    public let category: String
    public let dailyGrowthBytes: Int64
    /// Roughly how many days until it regrows a meaningful chunk (~1 GB) — a data-driven cadence.
    public let suggestedDays: Int?
    public var id: String { category }

    public init(category: String, dailyGrowthBytes: Int64, suggestedDays: Int?) {
        self.category = category; self.dailyGrowthBytes = dailyGrowthBytes; self.suggestedDays = suggestedDays
    }
}

/// Derives per-category regrowth rates from the daily snapshot history — the honest "ROI" of a
/// cleanup: not just what you can free, but how soon it comes back and how often to bother. Local
/// only (SnapshotStore), zero telemetry.
public struct RegrowthAnalyzer {
    /// A meaningful amount worth cleaning again; the suggested cadence is time-to-regrow this.
    static let meaningfulChunk: Int64 = 1_000_000_000   // ~1 GB

    private let store: SnapshotStore
    public init(store: SnapshotStore) { self.store = store }

    public func estimates(now: Date = Date()) -> [RegrowthEstimate] {
        let snaps = (try? store.all()) ?? []
        guard let first = snaps.first, let last = snaps.last, first.date < last.date else { return [] }
        let days = last.date.timeIntervalSince(first.date) / 86400
        guard days > 0 else { return [] }

        var out: [RegrowthEstimate] = []
        for key in Set(first.breakdown.keys).union(last.breakdown.keys) {
            let delta = (last.breakdown[key] ?? 0) - (first.breakdown[key] ?? 0)
            guard delta > 0 else { continue }                 // only things that are growing back
            let perDay = Int64(Double(delta) / days)
            guard perDay > 0 else { continue }
            let suggested = max(1, Int((Double(Self.meaningfulChunk) / Double(perDay)).rounded()))
            out.append(RegrowthEstimate(category: key, dailyGrowthBytes: perDay, suggestedDays: suggested))
        }
        return out.sorted { $0.dailyGrowthBytes > $1.dailyGrowthBytes }
    }
}

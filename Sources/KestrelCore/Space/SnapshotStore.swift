import Foundation

/// A point-in-time record of disk usage, plus a coarse top-level breakdown so we can
/// later say *what* grew, not just that the disk filled up.
public struct DiskSnapshot: Codable, Sendable, Equatable {
    public let date: Date
    public let space: DiskSpace
    /// Path → recursive size for the top-level entries of the scanned root.
    public let breakdown: [String: Int64]

    public init(date: Date, space: DiskSpace, breakdown: [String: Int64]) {
        self.date = date
        self.space = space
        self.breakdown = breakdown
    }
}

/// Growth rate and a naive fill forecast derived from the snapshot history.
public struct SpaceTrend: Sendable, Equatable {
    public let dailyGrowthBytes: Int64
    public let daysUntilFull: Double?
}

/// One entry's change in size between two snapshots.
public struct SpaceDelta: Sendable, Equatable {
    public let path: String
    public let delta: Int64

    public init(path: String, delta: Int64) {
        self.path = path
        self.delta = delta
    }
}

/// Persists daily disk snapshots as JSON (one file per calendar day) and derives trends
/// and diffs from them. Append-only in spirit — re-running on the same day overwrites
/// that day's snapshot, never another's.
public final class SnapshotStore {
    private let directory: URL
    private let fm = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    public func save(_ snapshot: DiskSnapshot) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = directory.appendingPathComponent("\(Self.dayKey(snapshot.date)).json")
        try encoder.encode(snapshot).write(to: file)
    }

    public func all() throws -> [DiskSnapshot] {
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return files
            .compactMap { try? decoder.decode(DiskSnapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date < $1.date }
    }

    /// Linear growth from the first to the last snapshot, and days until the volume is
    /// full at that rate. `nil` forecast when there is no growth or too little history.
    public func trend() throws -> SpaceTrend? {
        let snapshots = try all()
        guard let first = snapshots.first, let last = snapshots.last, first.date < last.date else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86400
        guard days > 0 else { return nil }
        let growth = Int64(Double(last.space.used - first.space.used) / days)
        let daysUntilFull = growth > 0 ? Double(last.space.available) / Double(growth) : nil
        return SpaceTrend(dailyGrowthBytes: growth, daysUntilFull: daysUntilFull)
    }

    /// What changed between the two most recent snapshots, largest change first.
    public func recentChanges() throws -> [SpaceDelta] {
        let snapshots = try all()
        guard snapshots.count >= 2 else { return [] }
        return changes(from: snapshots[snapshots.count - 2], to: snapshots[snapshots.count - 1])
    }

    /// What changed across a window: the latest snapshot vs. the newest snapshot that is at
    /// least `days` old (falling back to the earliest we have, so a 7-day view still shows
    /// something after only a few days of history). Largest absolute change first; empty when
    /// there isn't an older snapshot to compare against. This is the "culprit timeline" — it
    /// attributes weekly/monthly growth to a specific folder, not just day-over-day.
    public func changesOverLast(days: Int, now: Date = Date()) throws -> [SpaceDelta] {
        let snapshots = try all()
        guard let latest = snapshots.last else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        let baseline = snapshots.last(where: { $0.date <= cutoff }) ?? snapshots.first
        guard let baseline, baseline.date < latest.date else { return [] }
        return changes(from: baseline, to: latest)
    }

    public func changes(from a: DiskSnapshot, to b: DiskSnapshot) -> [SpaceDelta] {
        let paths = Set(a.breakdown.keys).union(b.breakdown.keys)
        return paths
            .map { SpaceDelta(path: $0, delta: (b.breakdown[$0] ?? 0) - (a.breakdown[$0] ?? 0)) }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }
    }
}

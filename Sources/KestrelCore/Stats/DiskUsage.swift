import Foundation

/// Total / available / used capacity of the volume a path lives on.
///
/// `available` is the *raw* free space (what Finder and `df` call "Available") so the
/// used figure is honest. `purgeable` is the extra space macOS could reclaim on demand
/// (caches, local snapshots) — shown separately rather than being counted as free,
/// which is exactly the mistake that made the disk look emptier than it is.
public struct DiskSpace: Codable, Sendable, Equatable {
    public let total: Int64
    public let available: Int64
    public let purgeable: Int64

    public init(total: Int64, available: Int64, purgeable: Int64 = 0) {
        self.total = total
        self.available = available
        self.purgeable = purgeable
    }

    public var used: Int64 { max(0, total - available) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// Reads volume capacity via the public `URLResourceValues` volume keys.
public struct DiskUsageReader {
    public init() {}

    public func space(at url: URL = URL(fileURLWithPath: NSHomeDirectory())) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        guard total > 0 else { return nil }

        // Raw free space (matches Finder/df "Available"); this is the honest free figure.
        let rawAvailable = Int64(values.volumeAvailableCapacity ?? 0)
        // "…ForImportantUsage" = raw free + purgeable, so their difference is purgeable.
        let importantAvailable = values.volumeAvailableCapacityForImportantUsage ?? rawAvailable
        let purgeable = max(0, importantAvailable - rawAvailable)

        return DiskSpace(total: total, available: rawAvailable, purgeable: purgeable)
    }
}

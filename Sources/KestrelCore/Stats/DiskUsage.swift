import Foundation

/// Total / available / used capacity of the volume a path lives on.
public struct DiskSpace: Codable, Sendable, Equatable {
    public let total: Int64
    public let available: Int64

    public init(total: Int64, available: Int64) {
        self.total = total
        self.available = available
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
        // "…ForImportantUsage" reflects what the user can realistically reclaim; fall
        // back to the raw available capacity when it is unavailable.
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        guard total > 0 else { return nil }
        return DiskSpace(total: total, available: available)
    }
}

import Foundation

/// One recorded per-process energy sample.
public struct EnergySample: Codable, Sendable, Equatable {
    public let time: Date
    public let name: String
    public let energyImpact: Double

    public init(time: Date, name: String, energyImpact: Double) {
        self.time = time
        self.name = name
        self.energyImpact = energyImpact
    }
}

/// A process's accumulated energy over a window.
public struct EnergyUsage: Sendable, Equatable, Identifiable {
    public let name: String
    public let total: Double
    public var id: String { name }

    public init(name: String, total: Double) {
        self.name = name
        self.total = total
    }
}

/// Persists energy samples so Kestrel can answer "what drained the battery over the last
/// 24 hours" — honestly, meaning *while Kestrel was running to record it*. The app appends
/// the current top consumers periodically; this aggregates them by process and prunes
/// anything older than the window.
public final class EnergyLog {
    private let url: URL
    private let fm = FileManager.default

    public init(url: URL) {
        self.url = url
    }

    public func append(_ consumers: [ProcessEnergy], now: Date = Date(), window: TimeInterval = 24 * 3600) {
        var samples = load().filter { now.timeIntervalSince($0.time) <= window }
        samples.append(contentsOf: consumers.map { EnergySample(time: now, name: $0.name, energyImpact: $0.energyImpact) })
        save(samples)
    }

    /// Total energy per process over the last `window`, most draining first.
    public func usage(within window: TimeInterval = 24 * 3600, now: Date = Date()) -> [EnergyUsage] {
        var totals: [String: Double] = [:]
        for sample in load() where now.timeIntervalSince(sample.time) <= window {
            totals[sample.name, default: 0] += sample.energyImpact
        }
        return totals
            .map { EnergyUsage(name: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    /// Timestamp of the earliest retained sample (how far back the data really goes).
    public func earliestSample() -> Date? {
        load().map(\.time).min()
    }

    // MARK: - Persistence

    private func load() -> [EnergySample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([EnergySample].self, from: data)) ?? []
    }

    private func save(_ samples: [EnergySample]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}

import Foundation

/// One transparent contributor to the overall health score.
public struct HealthComponent: Sendable, Equatable {
    public let name: String
    public let score: Int      // 0…100
    public let weight: Double
    public let detail: String
}

public struct HealthScore: Sendable, Equatable {
    public let overall: Int
    public let components: [HealthComponent]
}

/// Computes a Mac Health score from live metrics. Deliberately transparent: the overall
/// number is just a weighted average of named components, each of which explains itself,
/// so the score can always be justified rather than being a black box.
public struct HealthScorer {
    public init() {}

    public func score(disk: DiskSpace?, memory: MemoryStats, cpu: CPUStats, battery: BatteryStats?) -> HealthScore {
        var components: [HealthComponent] = []

        if let disk {
            let free = 1 - disk.usedFraction
            // Full marks with ≥25% free, falling to 0 as the disk fills completely.
            let s = clamp(percent(min(1, free / 0.25)))
            components.append(HealthComponent(
                name: "Disk", score: s, weight: 0.35,
                detail: "\(Int(disk.usedFraction * 100))% used"
            ))
        }

        let memFree = 1 - memory.usedFraction
        let memScore = clamp(percent(min(1, memFree / 0.2)))
        components.append(HealthComponent(
            name: "Memory", score: memScore, weight: 0.25,
            detail: "\(Int(memory.usedFraction * 100))% used"
        ))

        // CPU pressure of 1.0 (load == cores) is the knee; above ~2.0 scores 0.
        let cpuScore = clamp(percent(1 - min(1, max(0, cpu.pressure - 1) / 1.0)))
        components.append(HealthComponent(
            name: "CPU", score: cpuScore, weight: 0.25,
            detail: String(format: "load %.2f on %d cores", cpu.loadAverages.first ?? 0, cpu.coreCount)
        ))

        if let battery, let health = battery.healthPercent {
            components.append(HealthComponent(
                name: "Battery", score: clamp(health), weight: 0.15,
                detail: "\(health)% health" + (battery.cycleCount.map { ", \($0) cycles" } ?? "")
            ))
        }

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let overall = totalWeight > 0
            ? Int((components.reduce(0.0) { $0 + Double($1.score) * $1.weight } / totalWeight).rounded())
            : 0
        return HealthScore(overall: overall, components: components)
    }

    private func clamp(_ value: Int) -> Int { min(100, max(0, value)) }
    private func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }
}

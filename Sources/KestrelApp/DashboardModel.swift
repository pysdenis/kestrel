import SwiftUI
import KestrelCore

/// Drives the dashboard: refreshes live stats on a timer and runs cleanup scans off the
/// main thread. UI-only glue — every metric and every scan comes straight from Core.
@MainActor
final class DashboardModel: ObservableObject {
    @Published var health: HealthScore?
    @Published var disk: DiskSpace?
    @Published var memory: MemoryStats?
    @Published var cpu: CPUStats?
    @Published var battery: BatteryStats?

    @Published var scanning = false
    @Published var scanSummary: String?

    private let stats = StatsCollector()
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let disk = stats.disk()
        let memory = stats.memory()
        let cpu = stats.cpu()
        let battery = stats.battery()
        self.disk = disk
        self.memory = memory
        self.cpu = cpu
        self.battery = battery
        self.health = HealthScorer().score(disk: disk, memory: memory, cpu: cpu, battery: battery)
    }

    /// Dry-run scan of a folder; reports reclaimable space without touching anything.
    func scan(path: String) {
        scanning = true
        scanSummary = nil
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        Task.detached {
            let classified = (try? ScanCoordinator().scan(root: root)) ?? []
            let plan = Planner().plan(classified)
            let summary = plan.items.isEmpty
                ? "Nothing to clean under \(root.lastPathComponent). ✅"
                : "Reclaimable: " + ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file)
                    + " across \(plan.count) item(s)"
            await MainActor.run {
                self.scanSummary = summary
                self.scanning = false
            }
        }
    }
}

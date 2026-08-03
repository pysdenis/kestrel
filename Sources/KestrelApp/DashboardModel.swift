import SwiftUI
import AppKit
import KestrelCore

/// Shared app state: live system metrics refreshed on a timer, plus the on-demand speed
/// test. UI-only glue — every value comes from KestrelCore. Injected into both the
/// menu-bar popover and the main window.
@MainActor
final class AppModel: ObservableObject {
    @Published var health: HealthScore?
    @Published var disk: DiskSpace?
    @Published var memory: MemoryStats?
    @Published var cpu: CPUStats?
    @Published var battery: BatteryStats?
    @Published var network: NetworkStats?

    @Published var speedTesting = false
    @Published var speed: SpeedTestResult?

    @Published var energyNow: [ProcessEnergy] = []
    @Published var energy24h: [EnergyUsage] = []
    @Published var energyStart: Date?

    let paths = KestrelPaths()
    private let stats = StatsCollector()
    private lazy var energyLog = EnergyLog(url: paths.energyLog)
    private var timer: Timer?
    private var energyTimer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        refreshEnergy()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Sampling top is heavier, so do it less often; it also feeds the 24h history.
        energyTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshEnergy() }
        }
    }

    func refreshEnergy() {
        let log = energyLog
        Task.detached {
            let consumers = EnergyMonitor().topConsumers(limit: 8)
            log.append(consumers)
            let usage = log.usage()
            let earliest = log.earliestSample()
            await MainActor.run {
                self.energyNow = consumers
                self.energy24h = usage
                self.energyStart = earliest
            }
        }
    }

    func quitProcess(pid: Int) {
        _ = ProcessController().quit(pid: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshEnergy() }
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
        self.network = stats.network()
        self.health = HealthScorer().score(disk: disk, memory: memory, cpu: cpu, battery: battery)
    }

    func runSpeedTest() {
        guard !speedTesting else { return }
        speedTesting = true
        speed = nil
        Task {
            let result = try? await SpeedTest().run()
            await MainActor.run {
                self.speed = result
                self.speedTesting = false
            }
        }
    }

    /// Bring up the full window and give the app a Dock presence while it is open.
    func openMainWindow(_ open: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        open(id: "main")
    }

    /// Return to menu-bar-only once the main window closes.
    func mainWindowClosed() {
        NSApp.setActivationPolicy(.accessory)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

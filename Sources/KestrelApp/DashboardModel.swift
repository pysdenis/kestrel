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
    @Published var speedLive: Double = 0

    @Published var energyNow: [ProcessEnergy] = []
    @Published var energy24h: [EnergyUsage] = []
    @Published var energyStart: Date?

    @Published var netDownBps: Double = 0
    @Published var netUpBps: Double = 0
    @Published var netHistory: [Double] = []          // recent download throughput
    private var lastNet: (inB: Int64, outB: Int64, at: Date)?

    /// Smoothed battery time estimate (minutes) so the instantaneous figure doesn't
    /// jump around as load spikes.
    @Published var batteryTimeMinutes: Int?
    private var batteryMinutesEMA: Double?

    /// Time-left / time-to-full caption for the battery card.
    var batteryCaptionText: String {
        guard let b = battery else { return "" }
        if let m = batteryTimeMinutes { return b.isCharging ? "\(minutesString(m)) to full" : "\(minutesString(m)) left" }
        return b.healthPercent.map { "health \($0)%" } ?? (b.isCharging ? "charging" : "on battery")
    }

    let paths = KestrelPaths()
    private let stats = StatsCollector()
    private let cpuSampler = CPUUsageSampler()
    private lazy var energyLog = EnergyLog(url: paths.energyLog)
    private var timer: Timer?
    private var energyTimer: Timer?
    /// How many UI surfaces (popover, main window) are on screen. When this drops to
    /// zero the app stops polling entirely, so an idle menu-bar app costs ~nothing.
    private var visibleSurfaces = 0

    // MARK: - Lifecycle (drives all polling — nothing runs while nothing is shown)

    /// Call from a surface's `.onAppear`.
    func surfaceAppeared() {
        visibleSurfaces += 1
        refresh()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    /// Call from a surface's `.onDisappear`.
    func surfaceDisappeared() {
        visibleSurfaces = max(0, visibleSurfaces - 1)
        if visibleSurfaces == 0 {
            timer?.invalidate(); timer = nil
            cpuSampler.reset()   // next visible session starts from a fresh baseline
        }
    }

    /// The Energy section is the only place `top` runs; sample only while it is visible.
    func energyAppeared() {
        refreshEnergy()
        if energyTimer == nil {
            // top is heavy; sample it sparingly (only while the Energy section is open).
            energyTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshEnergy() }
            }
        }
    }

    func energyDisappeared() {
        energyTimer?.invalidate(); energyTimer = nil
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
        let base = stats.cpu()
        let cpu = CPUStats(coreCount: base.coreCount, loadAverages: base.loadAverages, usagePercent: cpuSampler.sample())
        let battery = stats.battery()
        self.disk = disk
        self.memory = memory
        self.cpu = cpu
        self.battery = battery
        self.health = HealthScorer().score(disk: disk, memory: memory, cpu: cpu, battery: battery)

        // Smooth the battery time estimate (EMA) so it stays steady between load spikes.
        let raw = battery.flatMap { $0.isCharging ? $0.timeToFullMinutes : $0.timeToEmptyMinutes }
        if let raw {
            let ema = batteryMinutesEMA.map { $0 * 0.6 + Double(raw) * 0.4 } ?? Double(raw)
            batteryMinutesEMA = ema
            batteryTimeMinutes = Int(ema.rounded())
        } else {
            batteryMinutesEMA = nil
            batteryTimeMinutes = nil
        }

        let net = stats.network()
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.5, dt < 10 {   // ignore long gaps (surface was closed)
                netDownBps = max(0, Double(net.bytesIn - last.inB) / dt)
                netUpBps = max(0, Double(net.bytesOut - last.outB) / dt)
                netHistory.append(netDownBps)
                if netHistory.count > 40 { netHistory.removeFirst(netHistory.count - 40) }
            }
        }
        lastNet = (net.bytesIn, net.bytesOut, now)
        self.network = net
    }

    func runSpeedTest() {
        guard !speedTesting else { return }
        speedTesting = true
        speed = nil
        speedLive = 0
        Task {
            let result = try? await SpeedTest().run(onProgress: { mbps in
                Task { @MainActor in self.speedLive = mbps }
            })
            await MainActor.run {
                self.speed = result
                self.speedTesting = false
            }
        }
    }

    /// The number the speed gauge should show — the live rate while testing, else the
    /// final result (nil = never run).
    var speedDisplay: Double? {
        if speedTesting { return speedLive }
        return speed?.downloadMbps
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

    // MARK: - AI (opt-in)

    /// The key from the environment (CLI) or `~/.kestrel/gemini.key` (GUI apps don't
    /// inherit the shell environment).
    func geminiKey() -> String {
        if let env = ProcessInfo.processInfo.environment["KESTREL_GEMINI_API_KEY"], !env.isEmpty { return env }
        if let file = try? String(contentsOf: paths.geminiKey, encoding: .utf8) {
            return file.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    var aiConfigured: Bool { !geminiKey().isEmpty }

    var aiAssistant: AIAssistant? {
        let key = geminiKey()
        return key.isEmpty ? nil : AIAssistant(client: GeminiClient(apiKey: key))
    }

    func aiContext() -> String {
        var parts: [String] = []
        if let d = disk { parts.append("Disk: \(bytesString(d.used)) used of \(bytesString(d.total)), \(bytesString(d.available)) free" + (d.purgeable > 0 ? ", \(bytesString(d.purgeable)) purgeable." : ".")) }
        if let m = memory { parts.append("Memory: \(Int(m.usedFraction * 100))% used.") }
        return parts.joined(separator: "\n")
    }
}

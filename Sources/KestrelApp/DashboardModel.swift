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

    /// Selected sidebar section (shared so the command palette can navigate).
    @Published var section: AppSection? = .dashboard
    @Published var showPalette = false

    /// Drives Kestrel's own confirmation modal (see `ConfirmHost`). Nil = nothing shown.
    @Published var confirmRequest: ConfirmRequest?

    /// First-run onboarding — shown once until the user gets started.
    @Published var showOnboarding = !UserDefaults.standard.bool(forKey: "kestrel.onboarded")
    func finishOnboarding() {
        showOnboarding = false
        UserDefaults.standard.set(true, forKey: "kestrel.onboarded")
    }

    /// Present the custom confirm modal for a destructive/irreversible action.
    func requestConfirm(_ request: ConfirmRequest) { confirmRequest = request }

    @Published var energyNow: [ProcessEnergy] = []
    @Published var energy24h: [EnergyUsage] = []
    @Published var energyStart: Date?
    @Published var bandwidth: [AppBandwidth] = []

    @Published var netDownBps: Double = 0
    @Published var netUpBps: Double = 0
    @Published var netHistory: [Double] = []          // recent download throughput
    @Published var cpuHistory: [Double] = []          // recent CPU usage %
    private var lastNet: (inB: Int64, outB: Int64, at: Date)?

    /// Smoothed battery time estimate (minutes), computed once from a smoothed current
    /// so the same value is shown everywhere.
    @Published var batteryTimeMinutes: Int?
    private var amperageEMA: Double?
    private var batteryWasCharging: Bool?

    /// One steady estimate used everywhere: exponential moving average of the *current*
    /// (mA), then remaining capacity ÷ current. Falls back to macOS's own estimate if the
    /// raw components aren't available. Resets the average when charging state flips.
    private func computeBatteryMinutes(_ b: BatteryStats?) -> Int? {
        guard let b else { amperageEMA = nil; return nil }
        if batteryWasCharging != b.isCharging { amperageEMA = nil; batteryWasCharging = b.isCharging }

        if let charge = b.chargemAh, let cap = b.capacitymAh, let amp = b.amperagemA, amp != 0 {
            let magnitude = Double(abs(amp))
            amperageEMA = amperageEMA.map { $0 * 0.82 + magnitude * 0.18 } ?? magnitude
            let rate = amperageEMA ?? magnitude
            guard rate > 0 else { return nil }
            let minutes = (b.isCharging ? Double(max(0, cap - charge)) : Double(charge)) / rate * 60
            return minutes.isFinite ? Int(minutes.rounded()) : nil
        }
        // Fallback: macOS's own estimate.
        return b.isCharging ? b.timeToFullMinutes : b.timeToEmptyMinutes
    }

    /// Time-left / time-to-full caption for the battery card.
    var batteryCaptionText: String {
        guard let b = battery else { return "" }
        if let m = batteryTimeMinutes { return b.isCharging ? "\(minutesString(m)) to full" : "\(minutesString(m)) left" }
        return b.healthPercent.map { "health \($0)%" } ?? (b.isCharging ? "charging" : "on battery")
    }

    let paths = KestrelPaths()

    // Scan state lives here (not in the section views) so a scan survives navigating
    // between modules — start it in one, switch away, come back, it's still going.
    lazy var cleanup = CleanupController(paths: paths)
    lazy var smartcare = SmartCareController(paths: paths)
    lazy var dashboard = DashboardController(paths: paths)
    lazy var security = SecurityController()
    lazy var apps = AppsController(paths: paths)
    lazy var permissions = PermissionsController()
    lazy var energy = EnergyController()
    lazy var space = SpaceController(paths: paths)
    lazy var tools = ToolsController(paths: paths)
    lazy var automation = AutomationController(paths: paths)
    lazy var assistant = AssistantController()
    lazy var settingsController = SettingsController(paths: paths)

    /// Whether the app can read Full-Disk-Access-gated locations (Trash, Mail, some
    /// caches). Refreshed when a surface appears; features that need it show a hint.
    @Published var fullDiskAccess = true

    /// Opt-in local notifications (low disk space). Off by default; nothing leaves the Mac.
    @Published var notificationsEnabled = UserDefaults.standard.bool(forKey: "kestrel.notifications")
    private var lowDiskNotified = false

    // MARK: Self-update (GitHub Releases)

    /// The one feature that reaches the network on its own — a read-only check of the public
    /// GitHub releases API. On by default (the user asked for auto-updates), fully toggleable,
    /// and it sends no data. See KestrelCore.SelfUpdate.
    @Published var autoCheckUpdates = UserDefaults.standard.object(forKey: "kestrel.autoUpdate") as? Bool ?? true
    @Published var updateChecking = false
    @Published var updateAvailable: ReleaseInfo?
    @Published var updateMessage: String?
    @Published var updateDownloading = false
    /// Dismissed banners shouldn't nag again for the same version this launch.
    private var dismissedUpdateTag: String?
    private var didAutoCheck = false

    func setAutoCheckUpdates(_ on: Bool) {
        autoCheckUpdates = on
        UserDefaults.standard.set(on, forKey: "kestrel.autoUpdate")
        if on { checkForUpdates(manual: false) }
    }

    /// Check GitHub for a newer release. `manual` distinguishes the Settings button (which
    /// reports "you're up to date") from the silent launch check (which stays quiet).
    func checkForUpdates(manual: Bool) {
        guard !updateChecking else { return }
        updateChecking = true
        if manual { updateMessage = nil }
        let current = Kestrel.version
        Task { @MainActor in
            defer { updateChecking = false }
            do {
                let release = try await SelfUpdate.check(current: current)
                if let release {
                    updateAvailable = release
                    if manual { updateMessage = nil }
                } else if manual {
                    updateMessage = L("You're on the latest version.")
                }
            } catch {
                if manual { updateMessage = L("Couldn't reach GitHub to check for updates.") }
            }
        }
    }

    /// Silent check once per launch when auto-update is enabled.
    func autoCheckOnLaunchIfEnabled() {
        guard autoCheckUpdates, !didAutoCheck else { return }
        didAutoCheck = true
        checkForUpdates(manual: false)
    }

    func dismissUpdateBanner() {
        dismissedUpdateTag = updateAvailable?.tag
        updateAvailable = nil
    }

    var showUpdateBanner: Bool {
        guard let u = updateAvailable else { return false }
        return u.tag != dismissedUpdateTag
    }

    /// Download the release asset to ~/Downloads and reveal it in Finder, so the user can
    /// drag it to Applications. Safe for an unsigned build (no in-place swap of a running app).
    /// Falls back to opening the release page when the release has no downloadable asset.
    func downloadUpdate(_ release: ReleaseInfo) {
        guard let url = release.downloadURL else {
            NSWorkspace.shared.open(release.pageURL); return
        }
        guard !updateDownloading else { return }
        updateDownloading = true
        updateMessage = nil
        let name = release.assetName ?? url.lastPathComponent
        Task { @MainActor in
            defer { updateDownloading = false }
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                var dest = downloads.appendingPathComponent(name)
                var n = 1
                while FileManager.default.fileExists(atPath: dest.path) {
                    let base = (name as NSString).deletingPathExtension
                    let ext = (name as NSString).pathExtension
                    dest = downloads.appendingPathComponent("\(base) \(n).\(ext)")
                    n += 1
                }
                try FileManager.default.moveItem(at: tempURL, to: dest)
                NSWorkspace.shared.activateFileViewerSelecting([dest])
                updateMessage = L("Downloaded to your Downloads folder — open it and drag Kestrel to Applications.")
            } catch {
                updateMessage = L("Download failed. Opening the release page instead.")
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    /// UI language. Changing it republishes the model, so every view re-renders in the new
    /// language. `t(_:)` translates a source string via the lightweight table.
    @Published var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "kestrel.language") ?? "") ?? .system

    func setLanguage(_ l: AppLanguage) {
        language = l
        Localization.setting = l
        UserDefaults.standard.set(l.rawValue, forKey: "kestrel.language")
    }

    func t(_ en: String) -> String { L(en) }

    init() { Localization.setting = language }   // sync the persisted language on launch

    func setNotifications(_ on: Bool) {
        notificationsEnabled = on
        UserDefaults.standard.set(on, forKey: "kestrel.notifications")
        if on { Notifier.shared.requestAuthorization() }
    }

    private func maybeNotifyLowDisk(_ disk: DiskSpace?) {
        guard let disk, notificationsEnabled, disk.total > 0 else { return }
        let freeFraction = Double(disk.available) / Double(disk.total)
        if freeFraction < 0.10, !lowDiskNotified {
            lowDiskNotified = true
            Notifier.shared.notify(title: "Low disk space",
                                   body: "Only \(bytesString(disk.available)) free. Open Kestrel to reclaim space.",
                                   id: "kestrel.low-disk")
        } else if freeFraction > 0.15 {
            lowDiskNotified = false
        }
    }

    private let stats = StatsCollector()
    private let cpuSampler = CPUUsageSampler()
    lazy var cpuBrand: String = stats.cpuBrand()
    var uptimeDays: Int { Int(ProcessInfo.processInfo.systemUptime / 86400) }
    func volumes() -> [VolumeInfo] { stats.volumes() }
    private lazy var energyLog = EnergyLog(url: paths.energyLog)
    private var timer: Timer?
    private var energyTimer: Timer?
    /// How many UI surfaces (popover, main window) are on screen. When this drops to
    /// zero the app stops polling entirely, so an idle menu-bar app costs ~nothing.
    private var visibleSurfaces = 0

    // MARK: - Lifecycle (drives all polling — nothing runs while nothing is shown)

    /// Call from a surface's `.onAppear`.
    private var requestedNotifAuth = false
    func surfaceAppeared() {
        visibleSurfaces += 1
        if notificationsEnabled, !requestedNotifAuth { requestedNotifAuth = true; Notifier.shared.requestAuthorization() }
        refresh()
        Task.detached {
            let granted = FullDiskAccess.isGranted()
            await MainActor.run { self.fullDiskAccess = granted }
        }
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
            let bw = BandwidthMonitor().topConsumers(limit: 10)
            await MainActor.run {
                self.energyNow = consumers
                self.energy24h = usage
                self.energyStart = earliest
                self.bandwidth = bw
            }
        }
    }

    func quitProcess(pid: Int) {
        _ = ProcessController().quit(pid: pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshEnergy() }
    }

    @Published var freeingMemory = false

    /// Run macOS `purge` to free inactive memory (non-destructive), then refresh so the
    /// user sees the change. Opt-in — only when they press the button.
    func freeMemory() {
        guard !freeingMemory else { return }
        freeingMemory = true
        Task.detached { [weak self] in
            _ = MemoryReliever().freeInactiveMemory()
            await MainActor.run { [weak self] in self?.freeingMemory = false; self?.refresh() }
        }
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

        maybeNotifyLowDisk(disk)

        cpuHistory.append(cpu.usagePercent)
        if cpuHistory.count > 40 { cpuHistory.removeFirst(cpuHistory.count - 40) }

        batteryTimeMinutes = computeBatteryMinutes(battery)

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

    /// Menu-bar quick action: open the window on Cleanup and immediately scan dev junk
    /// (node_modules, DerivedData, build dirs…) for review — honest, no silent delete.
    func freeDevJunk(_ open: OpenWindowAction) {
        section = .cleanup
        cleanup.choice = .dev
        cleanup.scan()
        openMainWindow(open)
    }

    /// Bring up the full window and give the app a Dock presence while it is open.
    func openMainWindow(_ open: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        open(id: "main")
    }

    /// The window closed — keep the app running (Dock + menu bar) so it stays reachable.
    func mainWindowClosed() {}

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

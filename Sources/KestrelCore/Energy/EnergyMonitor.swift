import Foundation

/// A process and its current energy / CPU impact.
public struct ProcessEnergy: Sendable, Equatable, Identifiable {
    public let pid: Int
    public let name: String
    public let cpuPercent: Double
    public let energyImpact: Double
    public var id: Int { pid }

    public init(pid: Int, name: String, cpuPercent: Double, energyImpact: Double) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.energyImpact = energyImpact
    }
}

/// Reports which processes are drawing the most power *right now*, by parsing `top`'s
/// energy-impact ("power") column. Read-only measurement; acting on it (quitting a
/// process) is a separate, explicit step via `ProcessController`. Injectable runner for
/// tests.
public struct EnergyMonitor {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func topConsumers(limit: Int = 8) -> [ProcessEnergy] {
        // Two samples so CPU/power figures are real (the first sample is a baseline).
        let output = (try? runner.run("top", [
            "-l", "2", "-n", "\(max(limit * 2, 20))",
            "-stats", "pid,command,cpu,power", "-o", "power", "-s", "1",
        ])) ?? ""
        return Self.parse(output, limit: limit)
    }

    /// Parse `top -stats pid,command,cpu,power` rows. The command name may contain spaces,
    /// so pid is the first token and cpu/power are the last two. Duplicate pids (two
    /// samples) collapse to the last — i.e. the accurate second sample.
    public static func parse(_ output: String, limit: Int) -> [ProcessEnergy] {
        var byPid: [Int: ProcessEnergy] = [:]
        for rawLine in output.split(separator: "\n") {
            let tokens = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tokens.count >= 4, let pid = Int(tokens[0]),
                  let power = Double(tokens[tokens.count - 1]),
                  let cpu = Double(tokens[tokens.count - 2]) else { continue }
            let name = tokens[1..<(tokens.count - 2)].joined(separator: " ")
            byPid[pid] = ProcessEnergy(pid: pid, name: name, cpuPercent: cpu, energyImpact: power)
        }
        return Array(byPid.values.sorted { $0.energyImpact > $1.energyImpact }.prefix(limit))
    }
}

/// Acts on a process the user chose to stop. Kept separate from measurement so nothing
/// terminates anything as a side effect of reading stats.
public struct ProcessController {
    public init() {}

    /// Ask a process to quit (SIGTERM). Returns whether the signal was delivered.
    /// Refuses pids ≤ 1: `kill(0, …)` signals the *entire process group* and pid 1 is
    /// launchd — neither must ever be targeted.
    @discardableResult
    public func quit(pid: Int) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid_t(pid), SIGTERM) == 0
    }

    /// Force a process to stop (SIGKILL). Use only when quit is ignored.
    @discardableResult
    public func forceQuit(pid: Int) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid_t(pid), SIGKILL) == 0
    }
}

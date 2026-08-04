import Foundation

/// Cumulative network bytes a process has moved (since it started, as `nettop` reports).
public struct AppBandwidth: Sendable, Equatable, Identifiable {
    public let name: String
    public let bytesIn: Int64
    public let bytesOut: Int64
    public var total: Int64 { bytesIn + bytesOut }
    public var id: String { name }

    public init(name: String, bytesIn: Int64, bytesOut: Int64) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Reports per-app network usage by parsing `nettop`. Read-only measurement — Kestrel
/// never throttles or blocks anything. Injectable runner for tests.
public struct BandwidthMonitor {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func topConsumers(limit: Int = 12) -> [AppBandwidth] {
        // -P per-process, -L 1 one sample, -x machine-readable, -J selects columns.
        let output = (try? runner.run("nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"])) ?? ""
        return Self.parse(output, limit: limit)
    }

    /// Parse `nettop -x -J bytes_in,bytes_out` CSV rows: `name.pid,bytes_in,bytes_out,`.
    /// The header row (`,bytes_in,bytes_out,`) is skipped because its numeric columns
    /// don't parse. Rows are aggregated by process name and sorted by total, biggest first.
    public static func parse(_ output: String, limit: Int) -> [AppBandwidth] {
        var byName: [String: (inB: Int64, outB: Int64)] = [:]
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3, let bin = Int64(cols[1]), let bout = Int64(cols[2]) else { continue }
            let field = cols[0]
            let name = field.lastIndex(of: ".").map { String(field[field.startIndex..<$0]) } ?? field
            guard !name.isEmpty else { continue }
            let entry = byName[name] ?? (0, 0)
            byName[name] = (entry.inB + bin, entry.outB + bout)
        }
        return byName
            .map { AppBandwidth(name: $0.key, bytesIn: $0.value.inB, bytesOut: $0.value.outB) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { $0 }
    }
}

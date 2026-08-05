import Foundation

/// One established outbound TCP connection, attributed to the process that owns it.
public struct OutboundConnection: Sendable, Equatable, Identifiable {
    public let process: String
    public let pid: Int
    public let remote: String   // host:port
    public var id: String { "\(pid)|\(remote)" }

    public init(process: String, pid: Int, remote: String) {
        self.process = process; self.pid = pid; self.remote = remote
    }
}

/// An honest, read-only snapshot of which apps are talking to the network right now (via `lsof`).
/// This is the *observability* half of a firewall — it reports, it never blocks (blocking needs a
/// Network Extension, out of scope). Pairs with the app-exposure map.
public struct ConnectionAuditor {
    private let runner: CommandRunner
    public init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    /// Currently-established outbound connections, grouped-friendly (sorted by process name).
    public func established() -> [OutboundConnection] {
        let output = (try? runner.run("lsof", ["-i", "-nP", "-sTCP:ESTABLISHED"])) ?? ""
        return Self.parse(output)
    }

    /// Parse `lsof -i -nP -sTCP:ESTABLISHED` output. Pure — unit-testable with canned text.
    public static func parse(_ output: String) -> [OutboundConnection] {
        var out: [OutboundConnection] = []
        for line in output.split(separator: "\n").dropFirst() {   // drop the header row
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard cols.count >= 9, let pid = Int(cols[1]) else { continue }
            // The NAME field looks like "192.168.1.5:54321->140.82.112.3:443". Find the token with "->".
            guard let nameToken = cols.first(where: { $0.contains("->") }) else { continue }
            let parts = nameToken.components(separatedBy: "->")
            guard parts.count == 2 else { continue }
            let remote = parts[1]
            out.append(OutboundConnection(process: cols[0], pid: pid, remote: remote))
        }
        // De-duplicate identical process→remote pairs and sort by process for grouping.
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted {
            $0.process.localizedCaseInsensitiveCompare($1.process) == .orderedAscending
        }
    }
}

import Foundation

/// A local port that a process is currently listening on — the "what's running on :3000?" answer
/// developers reach for constantly.
public struct ListeningPort: Sendable, Equatable, Identifiable {
    public let port: Int
    public let process: String
    public let pid: Int
    public var id: String { "\(port)|\(pid)" }

    public init(port: Int, process: String, pid: Int) {
        self.port = port; self.process = process; self.pid = pid
    }
}

/// Read-only inventory of processes listening on local TCP ports (via `lsof`). Handy for finding a
/// stray dev server hogging :3000 or :8080. Reports only — it never kills anything.
public struct PortAuditor {
    private let runner: CommandRunner
    public init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    public func listening() -> [ListeningPort] {
        let output = (try? runner.run("lsof", ["-iTCP", "-sTCP:LISTEN", "-nP"])) ?? ""
        return Self.parse(output)
    }

    /// Parse `lsof -iTCP -sTCP:LISTEN -nP` output. Pure — unit-testable with canned text.
    public static func parse(_ output: String) -> [ListeningPort] {
        var out: [ListeningPort] = []
        for line in output.split(separator: "\n").dropFirst() {   // drop header
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard cols.count >= 9, let pid = Int(cols[1]) else { continue }
            // The address token looks like "*:62310" or "127.0.0.1:3000"; a trailing "(LISTEN)"
            // follows it, so scan for the token that ends in ":<port>" rather than taking the last.
            guard let name = cols.last(where: { token in
                      guard let colon = token.lastIndex(of: ":") else { return false }
                      return Int(token[token.index(after: colon)...]) != nil
                  }), let colon = name.lastIndex(of: ":"), let port = Int(name[name.index(after: colon)...]) else { continue }
            out.append(ListeningPort(port: port, process: cols[0], pid: pid))
        }
        // De-duplicate identical port+pid pairs, lowest port first.
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted { $0.port < $1.port }
    }
}

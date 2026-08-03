import Foundation

/// Runs an external command and returns its standard output. Injectable so adapters
/// can be unit-tested with canned output — no Docker or Homebrew install required.
public protocol CommandRunner: Sendable {
    func run(_ tool: String, _ arguments: [String]) throws -> String
}

/// Real runner: launches `tool` via `/usr/bin/env` so it is resolved on `PATH`.
public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe() // swallow tool chatter
        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Parses a human-readable size such as `1.2GB`, `512MB`, `1.05kB`, `0B` into bytes.
/// Accepts both SI (kB/MB/GB) and binary (KiB/MiB/GiB) suffixes.
public func parseHumanBytes(_ raw: String) -> Int64? {
    let cleaned = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
    guard !cleaned.isEmpty else { return nil }

    // Longest suffixes first so "GiB" wins over "B" and "kB" over "B".
    let units: [(String, Double)] = [
        ("TiB", 1_099_511_627_776), ("GiB", 1_073_741_824), ("MiB", 1_048_576), ("KiB", 1024),
        ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1),
    ]
    for (unit, multiplier) in units where cleaned.hasSuffix(unit) {
        let number = cleaned.dropLast(unit.count)
        if let value = Double(number) { return Int64(value * multiplier) }
    }
    return nil
}

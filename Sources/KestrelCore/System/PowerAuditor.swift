import Foundation

/// A process currently asserting that the Mac must stay awake.
public struct SleepAssertion: Sendable, Equatable {
    public let process: String
    public let type: String

    public init(process: String, type: String) {
        self.process = process
        self.type = type
    }
}

/// Reports which processes are keeping the Mac awake, by parsing `pmset -g assertions`.
/// Read-only — this answers "why won't my Mac sleep / why is it hot in my bag" without
/// changing anything. Injectable runner for tests.
public struct PowerAuditor {
    private let runner: CommandRunner
    private static let line = try? NSRegularExpression(pattern: #"pid \d+\((.+?)\): \[.*?\] (\w*Prevent\w*Sleep)"#)

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func assertionsPreventingSleep() -> [SleepAssertion] {
        let output = (try? runner.run("pmset", ["-g", "assertions"])) ?? ""
        guard let regex = Self.line else { return [] }
        var seen = Set<String>()
        var result: [SleepAssertion] = []
        for raw in output.split(separator: "\n") {
            let text = String(raw)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  let processRange = Range(match.range(at: 1), in: text),
                  let typeRange = Range(match.range(at: 2), in: text) else { continue }
            let assertion = SleepAssertion(process: String(text[processRange]), type: String(text[typeRange]))
            let key = "\(assertion.process)|\(assertion.type)"
            if seen.insert(key).inserted { result.append(assertion) }
        }
        return result
    }
}

import Foundation

/// A third-party system extension (network filters, endpoint security, drivers…).
public struct SystemExtension: Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let state: String

    public init(identifier: String, name: String, state: String) {
        self.identifier = identifier
        self.name = name
        self.state = state
    }
}

/// Lists installed system extensions by parsing `systemextensionsctl list`. Read-only —
/// a security/inventory view. Injectable runner for tests.
public struct SystemExtensionAuditor {
    private let runner: CommandRunner
    private static let line = try? NSRegularExpression(pattern: #"([A-Za-z0-9._\-]+) \([^)]+\)\s*(.*?)\s*\[([^\]]+)\]"#)

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func list() -> [SystemExtension] {
        Self.parse((try? runner.run("systemextensionsctl", ["list"])) ?? "")
    }

    public static func parse(_ output: String) -> [SystemExtension] {
        guard let regex = line else { return [] }
        var out: [SystemExtension] = []
        for raw in output.split(separator: "\n") {
            let text = String(raw)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  let idRange = Range(match.range(at: 1), in: text),
                  let stateRange = Range(match.range(at: 3), in: text) else { continue }
            let identifier = String(text[idRange])
            let state = String(text[stateRange])
            // Skip the column-header line ("… bundleID (version) name [state]").
            guard identifier != "bundleID", state != "state", identifier.contains(".") else { continue }
            let name = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            out.append(SystemExtension(
                identifier: identifier,
                name: name.trimmingCharacters(in: .whitespaces),
                state: state
            ))
        }
        return out
    }
}

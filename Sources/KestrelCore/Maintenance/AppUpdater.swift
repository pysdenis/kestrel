import Foundation

public struct OutdatedCask: Sendable, Equatable {
    public let name: String
    public let current: String
    public let latest: String

    public init(name: String, current: String, latest: String) {
        self.name = name
        self.current = current
        self.latest = latest
    }
}

/// Advisory update checker. Lists outdated Homebrew casks (delegating to `brew`) and can
/// read an app's Sparkle appcast URL, so the user can see what has updates without
/// Kestrel silently changing anything. Injectable runner for testing.
public struct AppUpdater {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Parses `brew outdated --cask --verbose`, whose lines look like
    /// `name (1.0) != 2.0` or `name (1.0) < 2.0`.
    public func outdatedCasks() -> [OutdatedCask] {
        guard !(((try? runner.run("brew", ["--version"])) ?? "").isEmpty) else { return [] }
        let output = (try? runner.run("brew", ["outdated", "--cask", "--verbose"])) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 4 else { return nil }
            let name = parts[0]
            let current = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            let latest = parts[3]
            return OutdatedCask(name: name, current: current, latest: latest)
        }
    }

    /// The Sparkle appcast feed URL declared in an app's Info.plist, if any.
    public func sparkleFeed(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["SUFeedURL"] as? String
    }
}

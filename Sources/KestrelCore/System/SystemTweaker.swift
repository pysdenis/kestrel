import Foundation

/// A single reversible macOS preference tweak. Deterministic and honest: `detail` states exactly
/// what it writes — no "makes your Mac faster" placebo. Because these are `defaults` writes (not
/// file deletions), reversibility comes from snapshotting the PRIOR value, not from the file vault.
public struct SystemTweak: Sendable, Equatable, Identifiable {
    public enum ValueType: String, Sendable { case bool, int, string }

    public let id: String            // stable key, also the prior-value store key
    public let title: String
    public let detail: String        // plain, literal description of the write
    public let domain: String        // e.g. "com.apple.finder" or "NSGlobalDomain"
    public let key: String
    public let onValue: String       // the value that means "enabled"
    public let offValue: String?     // value to write when turning off (nil = delete the key)
    public let type: ValueType
    public let restart: String?      // process to `killall` so the change takes effect

    public init(id: String, title: String, detail: String, domain: String, key: String,
                onValue: String, offValue: String?, type: ValueType, restart: String?) {
        self.id = id; self.title = title; self.detail = detail; self.domain = domain; self.key = key
        self.onValue = onValue; self.offValue = offValue; self.type = type; self.restart = restart
    }
}

/// Reads and applies reversible system tweaks via `defaults`, snapshotting each key's prior value
/// into a JSON store so any tweak can be reverted to exactly how it was. Every write is auditable.
public final class SystemTweaker {
    private let runner: CommandRunner
    private let storeURL: URL
    private let fm = FileManager.default

    public init(runner: CommandRunner = ProcessRunner(), storeURL: URL) {
        self.runner = runner
        self.storeURL = storeURL
    }

    /// A curated, dev-friendly catalog — each entry is a plain `defaults` write with no placebo claim.
    public static let catalog: [SystemTweak] = [
        SystemTweak(id: "finder.hidden", title: "Show hidden files in Finder",
                    detail: "Writes com.apple.finder AppleShowAllFiles = true.",
                    domain: "com.apple.finder", key: "AppleShowAllFiles",
                    onValue: "true", offValue: "false", type: .bool, restart: "Finder"),
        SystemTweak(id: "global.extensions", title: "Show all file extensions",
                    detail: "Writes NSGlobalDomain AppleShowAllExtensions = true.",
                    domain: "NSGlobalDomain", key: "AppleShowAllExtensions",
                    onValue: "true", offValue: "false", type: .bool, restart: "Finder"),
        SystemTweak(id: "finder.pathbar", title: "Show Finder path bar",
                    detail: "Writes com.apple.finder ShowPathbar = true.",
                    domain: "com.apple.finder", key: "ShowPathbar",
                    onValue: "true", offValue: "false", type: .bool, restart: "Finder"),
        SystemTweak(id: "desktop.nodsstore", title: "No .DS_Store on network shares",
                    detail: "Writes com.apple.desktopservices DSDontWriteNetworkStores = true.",
                    domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores",
                    onValue: "true", offValue: "false", type: .bool, restart: nil),
        SystemTweak(id: "screencapture.png", title: "Screenshots as PNG",
                    detail: "Writes com.apple.screencapture type = png.",
                    domain: "com.apple.screencapture", key: "type",
                    onValue: "png", offValue: nil, type: .string, restart: "SystemUIServer"),
        SystemTweak(id: "screencapture.noshadow", title: "No window shadow in screenshots",
                    detail: "Writes com.apple.screencapture disable-shadow = true.",
                    domain: "com.apple.screencapture", key: "disable-shadow",
                    onValue: "true", offValue: "false", type: .bool, restart: "SystemUIServer"),
    ]

    /// The current stored value for a tweak's key, or nil if unset (`defaults read` fails).
    public func currentValue(_ tweak: SystemTweak) -> String? {
        let raw = (try? runner.run("defaults", ["read", tweak.domain, tweak.key]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// Whether the tweak is currently in its "on" state.
    public func isEnabled(_ tweak: SystemTweak) -> Bool {
        guard let value = currentValue(tweak) else { return false }
        if tweak.type == .bool {
            let on = ["1", "true", "yes"]
            return on.contains(value.lowercased()) == on.contains(tweak.onValue.lowercased())
        }
        return value == tweak.onValue
    }

    /// Apply or revert a tweak, snapshotting the prior value on the first change so it can be undone.
    @discardableResult
    public func setEnabled(_ tweak: SystemTweak, _ on: Bool) -> Bool {
        var priors = loadPriors()
        if priors[tweak.id] == nil { priors[tweak.id] = PriorValue(value: currentValue(tweak)) ; savePriors(priors) }

        let ok: Bool
        if on {
            ok = write(tweak, value: tweak.onValue)
        } else if let off = tweak.offValue {
            ok = write(tweak, value: off)
        } else {
            ok = (try? runner.run("defaults", ["delete", tweak.domain, tweak.key])) != nil
        }
        if let restart = tweak.restart { _ = try? runner.run("killall", [restart]) }
        return ok
    }

    /// Restore a tweak's key to exactly the value it had before Kestrel first touched it.
    @discardableResult
    public func revert(_ tweak: SystemTweak) -> Bool {
        var priors = loadPriors()
        guard let prior = priors[tweak.id] else { return false }
        let ok: Bool
        if let value = prior.value {
            ok = write(tweak, value: value)
        } else {
            ok = (try? runner.run("defaults", ["delete", tweak.domain, tweak.key])) != nil
        }
        priors[tweak.id] = nil; savePriors(priors)
        if let restart = tweak.restart { _ = try? runner.run("killall", [restart]) }
        return ok
    }

    public func hasPrior(_ tweak: SystemTweak) -> Bool { loadPriors()[tweak.id] != nil }

    private func write(_ tweak: SystemTweak, value: String) -> Bool {
        var args = ["write", tweak.domain, tweak.key]
        switch tweak.type {
        case .bool: args += ["-bool", value]
        case .int: args += ["-int", value]
        case .string: args += ["-string", value]
        }
        return (try? runner.run("defaults", args)) != nil
    }

    // MARK: - Prior-value store (so undo is exact, not "best effort")

    struct PriorValue: Codable, Equatable { let value: String? }

    private func loadPriors() -> [String: PriorValue] {
        guard let data = try? Data(contentsOf: storeURL),
              let map = try? JSONDecoder().decode([String: PriorValue].self, from: data) else { return [:] }
        return map
    }

    private func savePriors(_ map: [String: PriorValue]) {
        try? fm.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(map).write(to: storeURL, options: .atomic)
    }
}

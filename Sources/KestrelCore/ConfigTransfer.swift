import Foundation

/// A portable snapshot of the Kestrel settings that are worth carrying to another Mac or backing
/// up: the allowlist (paths Kestrel must never touch) and the declarative maintenance rules.
/// Deliberately excludes secrets (the Gemini key) and machine-specific state.
public struct KestrelConfig: Codable, Sendable, Equatable {
    public var version: Int
    public var exclusions: [String]
    public var rules: [MaintenanceRule]

    public init(version: Int = 1, exclusions: [String], rules: [MaintenanceRule]) {
        self.version = version; self.exclusions = exclusions; self.rules = rules
    }
}

/// Exports/imports `KestrelConfig` as JSON. Import is additive-merge for exclusions (union) and
/// rules (by name, incoming wins) so importing never silently drops what you already had.
public enum ConfigTransfer {
    public static func export(paths: KestrelPaths) -> KestrelConfig {
        KestrelConfig(exclusions: ExclusionStore(url: paths.exclusions).load().sorted(),
                      rules: RulesEngine.load(from: paths.rules))
    }

    public static func exportData(paths: KestrelPaths) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export(paths: paths))
    }

    /// Merge an imported config into the current one and persist it. Returns the merged config.
    @discardableResult
    public static func merge(_ incoming: KestrelConfig, into paths: KestrelPaths) throws -> KestrelConfig {
        // Exclusions: union (never lose an existing allowlist entry).
        let store = ExclusionStore(url: paths.exclusions)
        let mergedExclusions = Array(Set(store.load()).union(incoming.exclusions)).sorted()
        store.save(mergedExclusions)

        // Rules: merge by name — incoming replaces a same-named rule, others are kept/added.
        var byName: [String: MaintenanceRule] = [:]
        for rule in RulesEngine.load(from: paths.rules) { byName[rule.name] = rule }
        for rule in incoming.rules { byName[rule.name] = rule }
        let mergedRules = byName.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        try RulesEngine.save(mergedRules, to: paths.rules)

        return KestrelConfig(exclusions: mergedExclusions, rules: mergedRules)
    }

    public static func importData(_ data: Data, into paths: KestrelPaths) throws -> KestrelConfig {
        let config = try JSONDecoder().decode(KestrelConfig.self, from: data)
        return try merge(config, into: paths)
    }
}

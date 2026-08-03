import Foundation

/// Recognises regenerable developer artifacts — dependency and build directories that
/// can always be rebuilt from source (`node_modules`, `target`, `DerivedData`, …).
///
/// The safety principle: a directory is only claimed when its name *and* the project
/// context agree. Ambiguous names (`build`, `dist`, `target`, `Pods`) are required to
/// sit next to the project marker that produces them (`Cargo.toml`, `Podfile`, …);
/// without that marker they are left `.unknown`. Distinctive names (`node_modules`,
/// `DerivedData`, `__pycache__`) are trusted on their own. Source and lockfiles are
/// never matched — only directories, by well-known artifact names.
public struct DevArtifactClassifier: Classifier {
    /// A rule for one artifact directory name (or `*.suffix` pattern).
    struct Rule {
        let ecosystem: String
        /// Sibling files (in the parent dir) that confirm the artifact. Any one suffices.
        let siblingMarkers: [String]
        /// Files that must exist *inside* the directory to confirm it. Any one suffices.
        let innerMarkers: [String]
        /// Confidence when the name matches and a marker confirms (or none is required).
        let confirmed: Confidence
        /// Confidence when the name matches but no marker is present. `nil` ⇒ skip
        /// (leave `.unknown`) because the bare name is too ambiguous to trust.
        let unconfirmed: Confidence?
    }

    /// Exact-name rules.
    static let rules: [String: Rule] = [
        // JavaScript / TypeScript
        "node_modules": Rule(ecosystem: "Node", siblingMarkers: ["package.json"], innerMarkers: [".package-lock.json"], confirmed: .high, unconfirmed: .medium),
        ".next": Rule(ecosystem: "Next.js", siblingMarkers: ["package.json"], innerMarkers: [], confirmed: .high, unconfirmed: .medium),
        ".nuxt": Rule(ecosystem: "Nuxt", siblingMarkers: ["package.json"], innerMarkers: [], confirmed: .high, unconfirmed: .medium),
        ".svelte-kit": Rule(ecosystem: "SvelteKit", siblingMarkers: ["package.json"], innerMarkers: [], confirmed: .high, unconfirmed: .medium),
        ".turbo": Rule(ecosystem: "Turborepo", siblingMarkers: ["package.json"], innerMarkers: [], confirmed: .high, unconfirmed: .medium),
        ".parcel-cache": Rule(ecosystem: "Parcel", siblingMarkers: ["package.json"], innerMarkers: [], confirmed: .high, unconfirmed: .medium),
        "bower_components": Rule(ecosystem: "Bower", siblingMarkers: ["bower.json", "package.json"], innerMarkers: [], confirmed: .high, unconfirmed: .medium),
        // Apple / Swift
        "DerivedData": Rule(ecosystem: "Xcode", siblingMarkers: [], innerMarkers: [], confirmed: .high, unconfirmed: .high),
        ".build": Rule(ecosystem: "SwiftPM", siblingMarkers: ["Package.swift"], innerMarkers: [], confirmed: .high, unconfirmed: nil),
        "Pods": Rule(ecosystem: "CocoaPods", siblingMarkers: ["Podfile"], innerMarkers: [], confirmed: .high, unconfirmed: nil),
        "Carthage": Rule(ecosystem: "Carthage", siblingMarkers: ["Cartfile"], innerMarkers: [], confirmed: .high, unconfirmed: nil),
        // Python
        ".venv": Rule(ecosystem: "Python venv", siblingMarkers: [], innerMarkers: ["pyvenv.cfg"], confirmed: .high, unconfirmed: nil),
        "venv": Rule(ecosystem: "Python venv", siblingMarkers: [], innerMarkers: ["pyvenv.cfg"], confirmed: .high, unconfirmed: nil),
        "__pycache__": Rule(ecosystem: "Python", siblingMarkers: [], innerMarkers: [], confirmed: .high, unconfirmed: .high),
        ".pytest_cache": Rule(ecosystem: "pytest", siblingMarkers: [], innerMarkers: [], confirmed: .high, unconfirmed: .high),
        ".mypy_cache": Rule(ecosystem: "mypy", siblingMarkers: [], innerMarkers: [], confirmed: .high, unconfirmed: .high),
        ".ruff_cache": Rule(ecosystem: "Ruff", siblingMarkers: [], innerMarkers: [], confirmed: .high, unconfirmed: .high),
        ".tox": Rule(ecosystem: "tox", siblingMarkers: [], innerMarkers: [], confirmed: .high, unconfirmed: .high),
        // Rust / JVM / generic build output
        "target": Rule(ecosystem: "Rust/Maven", siblingMarkers: ["Cargo.toml", "pom.xml", "build.gradle", "build.gradle.kts"], innerMarkers: [], confirmed: .high, unconfirmed: nil),
        ".gradle": Rule(ecosystem: "Gradle", siblingMarkers: [], innerMarkers: [], confirmed: .high, unconfirmed: .high),
        "dist": Rule(ecosystem: "build output", siblingMarkers: projectMarkers, innerMarkers: [], confirmed: .medium, unconfirmed: nil),
        "build": Rule(ecosystem: "build output", siblingMarkers: projectMarkers, innerMarkers: [], confirmed: .medium, unconfirmed: nil),
        "out": Rule(ecosystem: "build output", siblingMarkers: projectMarkers, innerMarkers: [], confirmed: .medium, unconfirmed: nil),
    ]

    /// Project markers that confirm a generic build-output directory belongs to a project.
    static let projectMarkers = [
        "package.json", "tsconfig.json", "Cargo.toml", "pyproject.toml", "setup.py",
        "build.gradle", "build.gradle.kts", "pom.xml", "Makefile", "CMakeLists.txt",
    ]

    /// Directory name suffixes (e.g. `foo.egg-info`) mapped to their rule.
    static let suffixRules: [String: Rule] = [
        ".egg-info": Rule(ecosystem: "Python", siblingMarkers: ["setup.py", "pyproject.toml", "setup.cfg"], innerMarkers: [], confirmed: .high, unconfirmed: .medium),
    ]

    /// Names the deep scanner should not descend into (each is a single unit here).
    public static var pruneDirectories: Set<String> {
        Set(rules.keys)
    }

    private let fm: FileManager

    public init(fm: FileManager = .default) {
        self.fm = fm
    }

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        guard entry.isDirectory else { return unknown(entry) }
        let name = entry.url.lastPathComponent

        if let rule = Self.rules[name] {
            return apply(rule, name: name, to: entry)
        }
        for (suffix, rule) in Self.suffixRules where name.hasSuffix(suffix) {
            return apply(rule, name: name, to: entry)
        }
        return unknown(entry)
    }

    private func apply(_ rule: Rule, name: String, to entry: FileEntry) -> ClassifiedEntry {
        let requiresMarker = !(rule.siblingMarkers.isEmpty && rule.innerMarkers.isEmpty)
        let confirmedBy = confirmation(for: rule, dir: entry.url)

        let confidence: Confidence?
        let detail: String
        if !requiresMarker {
            confidence = rule.confirmed
            detail = "regenerable"
        } else if let marker = confirmedBy {
            confidence = rule.confirmed
            detail = "confirmed by \(marker)"
        } else {
            confidence = rule.unconfirmed
            detail = "no project marker found"
        }

        guard let confidence else { return unknown(entry) }
        return ClassifiedEntry(
            entry: entry,
            category: .devArtifact,
            confidence: confidence,
            reason: "Regenerable \(rule.ecosystem) artifact: \(name) (\(detail))"
        )
    }

    /// Returns the first marker that confirms the rule, or `nil` if none is present.
    private func confirmation(for rule: Rule, dir: URL) -> String? {
        let parent = dir.deletingLastPathComponent()
        for marker in rule.siblingMarkers where fm.fileExists(atPath: parent.appendingPathComponent(marker).path) {
            return marker
        }
        for marker in rule.innerMarkers where fm.fileExists(atPath: dir.appendingPathComponent(marker).path) {
            return marker
        }
        return nil
    }

    private func unknown(_ entry: FileEntry) -> ClassifiedEntry {
        ClassifiedEntry(entry: entry, category: .unknown, confidence: .low, reason: "Not a known dev artifact")
    }
}

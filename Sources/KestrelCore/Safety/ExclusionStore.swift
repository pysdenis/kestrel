import Foundation

/// Persists the user's allowlist — absolute paths Kestrel must never touch — as a small JSON
/// file. The paths are fed into `SafetyGuard.userExclusions`, so they're honoured everywhere a
/// removal is considered, not just in one module.
public struct ExclusionStore {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> [String] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list.sorted()
    }

    public func save(_ paths: [String]) {
        let unique = Array(Set(paths.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 })).sorted()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(unique) { try? data.write(to: url) }
    }

    @discardableResult
    public func add(_ path: String) -> [String] {
        var list = load(); list.append(path); save(list); return load()
    }

    @discardableResult
    public func remove(_ path: String) -> [String] {
        save(load().filter { $0 != path }); return load()
    }
}

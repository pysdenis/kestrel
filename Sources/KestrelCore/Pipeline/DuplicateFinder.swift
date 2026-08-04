import Foundation
import CryptoKit

/// Finds byte-identical duplicate files using a three-stage funnel that avoids hashing
/// everything: group by **size**, then by a **partial hash** of the first bytes, then
/// by a **full SHA-256**. Only files that survive all three stages are duplicates.
///
/// For each duplicate set one file is kept as the original (the oldest, tie-broken by
/// path) and the *copies* are returned as `.duplicate`. The original is never returned,
/// so it is never scheduled for removal — the bytes always survive. `duplicate` is a
/// review-only category, so duplicates are surfaced but only removed when opted into.
/// A set of byte-identical files: one kept `original` plus its `copies`. Removing the copies
/// reclaims `reclaimable` bytes while the content always survives in the original.
public struct DuplicateGroup: Sendable, Equatable, Identifiable {
    public let original: FileEntry
    public let copies: [FileEntry]

    public init(original: FileEntry, copies: [FileEntry]) {
        self.original = original
        self.copies = copies
    }

    public var id: String { original.url.path }
    public var all: [FileEntry] { [original] + copies }
    public var reclaimable: Int64 { copies.reduce(0) { $0 + $1.size } }
}

public struct DuplicateFinder {
    public let partialBytes: Int

    public init(partialBytes: Int = 4096) {
        self.partialBytes = partialBytes
    }

    public func find(in entries: [FileEntry]) -> [ClassifiedEntry] {
        duplicateSets(in: entries).flatMap { markCopies($0) }
    }

    /// The same duplicate sets as `find`, but grouped for review UI: each group keeps its
    /// original (never removed) alongside the byte-identical copies, sorted so the groups that
    /// free the most space come first.
    public func findGroups(in entries: [FileEntry]) -> [DuplicateGroup] {
        duplicateSets(in: entries).map { group in
            let ordered = group.sorted {
                $0.modified != $1.modified ? $0.modified < $1.modified : $0.url.path < $1.url.path
            }
            return DuplicateGroup(original: ordered[0], copies: Array(ordered.dropFirst()))
        }
        .sorted { $0.reclaimable > $1.reclaimable }
    }

    // MARK: - Internals

    /// The three-stage funnel (size → partial hash → full hash) shared by `find`/`findGroups`.
    private func duplicateSets(in entries: [FileEntry]) -> [[FileEntry]] {
        var bySize: [Int64: [FileEntry]] = [:]
        for entry in entries where !entry.isDirectory && entry.size > 0 {
            bySize[entry.size, default: []].append(entry)
        }
        var sets: [[FileEntry]] = []
        for (size, sizeGroup) in bySize where sizeGroup.count > 1 {
            for partialGroup in groupBy(sizeGroup, hash: partialHash).values where partialGroup.count > 1 {
                // If the whole file already fits in the partial read, the partial hash
                // is the full hash — no need to read the files a second time.
                let confirmed = size <= partialBytes
                    ? [partialGroup]
                    : Array(groupBy(partialGroup, hash: fullHash).values)
                for group in confirmed where group.count > 1 { sets.append(group) }
            }
        }
        return sets
    }

    private func groupBy(_ entries: [FileEntry], hash: (URL) -> String?) -> [String: [FileEntry]] {
        var out: [String: [FileEntry]] = [:]
        for entry in entries {
            guard let digest = hash(entry.url) else { continue }
            out[digest, default: []].append(entry)
        }
        return out
    }

    /// Keep the oldest file (tie-broken by path); mark the rest as duplicates of it.
    private func markCopies(_ group: [FileEntry]) -> [ClassifiedEntry] {
        let ordered = group.sorted {
            $0.modified != $1.modified ? $0.modified < $1.modified : $0.url.path < $1.url.path
        }
        let original = ordered[0]
        return ordered.dropFirst().map { copy in
            ClassifiedEntry(
                entry: copy,
                category: .duplicate,
                confidence: .high,
                reason: "Identical copy of \(original.url.path)"
            )
        }
    }

    private func partialHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: partialBytes)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

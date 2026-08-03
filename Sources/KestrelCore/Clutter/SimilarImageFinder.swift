import Foundation
import CoreGraphics
import ImageIO

/// Groups visually similar images using a perceptual "average hash": each image is
/// reduced to 8×8 greyscale and turned into a 64-bit fingerprint; images whose
/// fingerprints are within a small Hamming distance look alike (resizes, re-saves,
/// near-duplicate shots). Unlike the exact `DuplicateFinder`, this catches *similar*,
/// not byte-identical, images.
public struct SimilarImageFinder {
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "webp"]

    public let maxDistance: Int

    public init(maxDistance: Int = 8) {
        self.maxDistance = maxDistance
    }

    /// Clusters of two-or-more similar images. The largest file in each group is listed
    /// first (the one worth keeping).
    public func find(in entries: [FileEntry]) -> [[FileEntry]] {
        let hashed: [(entry: FileEntry, hash: UInt64)] = entries
            .filter { Self.imageExtensions.contains($0.url.pathExtension.lowercased()) }
            .compactMap { entry in Self.averageHash(entry.url).map { (entry, $0) } }

        var used = Set<Int>()
        var groups: [[FileEntry]] = []
        for i in hashed.indices where !used.contains(i) {
            var group = [hashed[i]]
            used.insert(i)
            for j in hashed.indices where j > i && !used.contains(j) {
                if Self.hamming(hashed[i].hash, hashed[j].hash) <= maxDistance {
                    group.append(hashed[j]); used.insert(j)
                }
            }
            if group.count > 1 {
                groups.append(group.sorted { $0.entry.size > $1.entry.size }.map(\.entry))
            }
        }
        return groups
    }

    /// A cleanup plan that keeps the largest image in each group and offers the rest for
    /// removal (review-only, so it is always the user's choice).
    public func plan(in entries: [FileEntry]) -> CleanupPlan {
        let items = find(in: entries).flatMap { group -> [CleanupItem] in
            let keep = group[0]
            return group.dropFirst().map {
                CleanupItem(entry: $0, category: .duplicate, reason: "Similar to \(keep.url.lastPathComponent)")
            }
        }
        return CleanupPlan(items: items)
    }

    // MARK: - Perceptual hash

    public static func averageHash(_ url: URL) -> UInt64? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let ctx = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        let average = pixels.reduce(0) { $0 + Int($1) } / (side * side)
        var hash: UInt64 = 0
        for (i, value) in pixels.enumerated() where Int(value) >= average {
            hash |= (UInt64(1) << UInt64(i))
        }
        return hash
    }

    public static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}

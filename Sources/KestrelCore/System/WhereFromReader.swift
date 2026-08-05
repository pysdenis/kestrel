import Foundation

/// Reads a file's "where from" provenance — the origin URL(s) Safari/Chrome/etc. stamp onto a
/// download as an extended attribute. Read-only; turns Downloads cleanup into an informed choice
/// ("this .dmg came from a host you don't recognize, 8 months ago").
public enum WhereFromReader {
    /// The origin/referrer URLs recorded on a file, or empty if none. Decodes the
    /// `com.apple.metadata:kMDItemWhereFroms` xattr (a binary-plist array of strings).
    public static func origins(of url: URL) -> [String] {
        guard let data = extendedAttribute(named: "com.apple.metadata:kMDItemWhereFroms", at: url) else { return [] }
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) else { return [] }
        if let array = plist as? [String] {
            return array.filter { !$0.isEmpty }
        }
        if let array = plist as? [Any] {
            return array.compactMap { $0 as? String }.filter { !$0.isEmpty }
        }
        return []
    }

    /// The primary source URL (first non-empty origin), if any.
    public static func source(of url: URL) -> String? { origins(of: url).first }

    /// Raw extended-attribute bytes for `name`, or nil if the attribute isn't set.
    static func extendedAttribute(named name: String, at url: URL) -> Data? {
        let path = url.path
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return getxattr(path, name, base, length, 0, 0)
        }
        return result >= 0 ? data : nil
    }
}

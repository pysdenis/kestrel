import Foundation

/// Classifies browser privacy data — caches, history, cookies for the common browsers.
/// This is a review-only category: clearing it signs you out of sites and drops your
/// history, so it is only ever removed when the user asks for it by name. Matches are
/// location-based and conservative; bookmarks and passwords are never targeted.
public struct PrivacyClassifier: Classifier {
    struct Rule {
        let fragment: String
        let confidence: Confidence
        let reason: String
    }

    static let rules: [Rule] = [
        // Safari
        Rule(fragment: "/Library/Safari/History.db", confidence: .medium, reason: "Safari history"),
        Rule(fragment: "/Library/Caches/com.apple.Safari/", confidence: .medium, reason: "Safari cache"),
        Rule(fragment: "/Library/Cookies/", confidence: .medium, reason: "Cookies"),
        // Chrome / Chromium family (Chrome, Brave, Edge, Vivaldi share the layout)
        Rule(fragment: "/Google/Chrome/Default/Cache/", confidence: .medium, reason: "Chrome cache"),
        Rule(fragment: "/Google/Chrome/Default/History", confidence: .medium, reason: "Chrome history"),
        Rule(fragment: "/Google/Chrome/Default/Cookies", confidence: .medium, reason: "Chrome cookies"),
        Rule(fragment: "/BraveSoftware/Brave-Browser/Default/Cache/", confidence: .medium, reason: "Brave cache"),
        Rule(fragment: "/Microsoft Edge/Default/Cache/", confidence: .medium, reason: "Edge cache"),
        // Firefox
        Rule(fragment: "/Firefox/Profiles/", confidence: .low, reason: "Firefox profile data"),
        Rule(fragment: "/Caches/Firefox/", confidence: .medium, reason: "Firefox cache"),
    ]

    public init() {}

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        let path = entry.url.path
        for rule in Self.rules where path.contains(rule.fragment) {
            // Firefox profiles also hold bookmarks/logins — only claim the cache subtree.
            if rule.fragment == "/Firefox/Profiles/" && !path.contains("/cache2/") {
                continue
            }
            return ClassifiedEntry(entry: entry, category: .privacy, confidence: rule.confidence, reason: rule.reason)
        }
        return ClassifiedEntry(entry: entry, category: .unknown, confidence: .low, reason: "Not browser privacy data")
    }
}

import Foundation
import Security

/// The code-signing verdict for one application, read straight from the system with the public
/// Security framework — honest facts, no invented risk. "Unsigned" or "ad-hoc" is stated plainly;
/// it is not by itself a threat (plenty of legitimate developer tools are ad-hoc signed).
public struct CodeSignature: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable {
        case developerID    // Apple "Developer ID Application" — notarization-capable
        case appStore       // Mac App Store receipt
        case apple          // Apple system software
        case adHoc          // signed with no identity (common for local/dev builds)
        case unsigned       // no signature at all
        case invalid        // a signature is present but failed validation (tampered / revoked)

        public var label: String {
            switch self {
            case .developerID: return "Developer ID"
            case .appStore: return "App Store"
            case .apple: return "Apple"
            case .adHoc: return "Ad-hoc"
            case .unsigned: return "Unsigned"
            case .invalid: return "Invalid signature"
            }
        }

        /// Whether this verdict is worth the user's attention (facts, not fearmongering): a broken
        /// signature is genuinely notable; unsigned/ad-hoc are merely informational.
        public var isNoteworthy: Bool { self == .invalid }
    }

    public let path: String
    public let name: String
    public let status: Status
    public let teamID: String?
    public let authority: String?   // leaf signing authority (e.g. "Developer ID Application: …")

    public var id: String { path }

    public init(path: String, name: String, status: Status, teamID: String?, authority: String?) {
        self.path = path; self.name = name; self.status = status; self.teamID = teamID; self.authority = authority
    }
}

/// Reads code-signing information for application bundles via `SecStaticCode`. Read-only.
public struct CodeSignatureReader {
    public init() {}

    /// Inspect a single bundle. Never throws — an unreadable/odd bundle resolves to a best-effort
    /// verdict rather than failing the whole scan.
    public func read(_ appURL: URL) -> CodeSignature {
        let name = appURL.deletingPathExtension().lastPathComponent
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            return CodeSignature(path: appURL.path, name: name, status: .unsigned, teamID: nil, authority: nil)
        }

        // Validity: **basic** validation only, on purpose. A full check also re-seals every bundled
        // resource, which legitimately-modified big apps (MATLAB, some Electron apps, license files
        // dropped post-install) fail with errSecCSBadResource — that is NOT tampering, and flagging
        // it would violate the "never scare" rule. Basic validation still catches a genuinely broken
        // or revoked code signature.
        let checkFlags = SecCSFlags(rawValue: kSecCSBasicValidateOnly)
        let valid = SecStaticCodeCheckValidity(code, checkFlags, nil)

        var infoCF: CFDictionary?
        let infoFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
        SecCodeCopySigningInformation(code, infoFlags, &infoCF)
        let info = (infoCF as? [String: Any]) ?? [:]

        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32).map { SecCodeSignatureFlags(rawValue: $0) }
        let authority = leafAuthority(from: info)

        let status = classify(valid: valid, hasSignature: info[kSecCodeInfoIdentifier as String] != nil,
                              flags: flags, teamID: teamID, authority: authority)
        return CodeSignature(path: appURL.path, name: name, status: status, teamID: teamID, authority: authority)
    }

    /// The human name of the leaf (signing) certificate.
    private func leafAuthority(from info: [String: Any]) -> String? {
        guard let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }

    /// Map the raw signals to an honest status.
    func classify(valid: OSStatus, hasSignature: Bool, flags: SecCodeSignatureFlags?, teamID: String?, authority: String?) -> CodeSignature.Status {
        guard hasSignature else { return .unsigned }
        if valid != errSecSuccess { return .invalid }
        if let flags, flags.contains(.adhoc) { return .adHoc }
        let auth = authority ?? ""
        if auth.hasPrefix("Developer ID Application") { return .developerID }
        if auth.contains("Apple Mac OS Application Signing") || auth.contains("Apple Distribution") { return .appStore }
        if auth.hasPrefix("Software Signing") || auth.hasPrefix("Apple") { return .apple }
        // Signed and valid but with an unfamiliar authority (e.g. an enterprise cert): treat as
        // Developer-ID-like only if there is a Team ID, else fall back to ad-hoc-ish "signed".
        return teamID != nil ? .developerID : .adHoc
    }
}

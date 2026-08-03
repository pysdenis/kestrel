import Foundation
import KestrelCore

// Dependency-free test runner (no XCTest). Mirrors Tests/KestrelCoreTests so the
// safety invariants can be verified with only Command Line Tools installed.

var passed = 0
var failed = 0
let fm = FileManager.default

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    if condition() { passed += 1 } else { failed += 1; print("  ✗ [line \(line)] \(message)") }
}

func section(_ name: String) { print("• \(name)") }

func withTempDir(_ body: (URL) throws -> Void) {
    let dir = fm.temporaryDirectory.appendingPathComponent("kestrel-test-\(UUID().uuidString)")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    do { try body(dir) } catch { failed += 1; print("  ✗ threw: \(error)") }
}

@discardableResult
func makeFile(_ url: URL, _ contents: String = "hello") -> URL {
    try? contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// MARK: - Vault

section("VaultService: move removes original, stores in vault")
withTempDir { tmp in
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let file = makeFile(tmp.appendingPathComponent("junk.txt"))
    let session = try vault.beginSession()
    let record = try vault.move(url: file, session: session)
    check(!fm.fileExists(atPath: file.path), "original must be gone")
    check(fm.fileExists(atPath: record.vaultPath), "must exist in vault")
    check(record.size > 0, "size recorded")
}

section("VaultService: undo restores to original path")
withTempDir { tmp in
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let file = makeFile(tmp.appendingPathComponent("restore.txt"), "important")
    let session = try vault.beginSession()
    try vault.move(url: file, session: session)
    let restored = try vault.undo(session: session)
    check(restored == 1, "one item restored")
    check(fm.fileExists(atPath: file.path), "file back at original path")
    check((try? String(contentsOf: file, encoding: .utf8)) == "important", "contents intact")
}

section("VaultService: undo never overwrites an existing file")
withTempDir { tmp in
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let file = makeFile(tmp.appendingPathComponent("conflict.txt"), "original")
    let session = try vault.beginSession()
    try vault.move(url: file, session: session)
    makeFile(file, "new")
    _ = try vault.undo(session: session)
    check((try? String(contentsOf: file, encoding: .utf8)) == "new", "existing file not clobbered")
}

section("VaultService: moving a missing source throws")
withTempDir { tmp in
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let session = try vault.beginSession()
    let missing = tmp.appendingPathComponent("nope.txt")
    do {
        try vault.move(url: missing, session: session)
        check(false, "expected throw")
    } catch {
        check((error as? VaultError) == .sourceMissing(missing.path), "sourceMissing thrown")
    }
}

section("VaultService: directory size is recursive")
withTempDir { tmp in
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let dir = tmp.appendingPathComponent("node_modules")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    makeFile(dir.appendingPathComponent("a.js"), "aaaa")
    makeFile(dir.appendingPathComponent("b.js"), "bbbb")
    let session = try vault.beginSession()
    let record = try vault.move(url: dir, session: session)
    check(record.size == 8, "recursive size == 8 (got \(record.size))")
    check(!fm.fileExists(atPath: dir.path), "directory moved out")
}

section("VaultService: purge removes only old sessions")
withTempDir { tmp in
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    _ = try vault.beginSession(id: "old", createdAt: Date(timeIntervalSinceNow: -1000))
    _ = try vault.beginSession(id: "recent", createdAt: Date())
    let purged = try vault.purge(olderThan: 500)
    check(purged.map(\.id) == ["old"], "only old purged")
    let remaining = try vault.listSessions().map(\.id)
    check(remaining == ["recent"], "recent remains")
}

// MARK: - Pipeline

section("Pipeline: planner includes dev artifacts, excludes unknown source")
withTempDir { tmp in
    let nm = tmp.appendingPathComponent("node_modules")
    try fm.createDirectory(at: nm, withIntermediateDirectories: true)
    makeFile(nm.appendingPathComponent("index.js"), "x")
    makeFile(tmp.appendingPathComponent("main.swift"), "src")
    let entries = try Scanner().scanChildren(of: tmp)
    let plan = Planner().plan(entries.map(RuleClassifier().classify))
    let names = plan.items.map { $0.entry.url.lastPathComponent }
    check(names.contains("node_modules"), "dev artifact planned")
    check(!names.contains("main.swift"), "unknown source never planned")
}

section("Pipeline: dry-run moves nothing")
withTempDir { tmp in
    let dir = tmp.appendingPathComponent("build")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    makeFile(dir.appendingPathComponent("out.o"), "x")
    let entries = try Scanner().scanChildren(of: tmp)
    let plan = Planner().plan(entries.map(RuleClassifier().classify))
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let audit = AuditLog(url: tmp.appendingPathComponent("audit.log"))
    let result = try CleanupExecutor(vault: vault, audit: audit).execute(plan, apply: false)
    check(result.dryRun, "dryRun flag set")
    check(result.movedCount == 0, "nothing moved")
    check(fm.fileExists(atPath: dir.path), "filesystem untouched")
}

section("Pipeline: apply moves to vault and writes audit")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("Cargo.toml"), "[package]") // confirms 'target'
    let dir = tmp.appendingPathComponent("target")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    makeFile(dir.appendingPathComponent("app"), "x")
    let entries = try Scanner().scanChildren(of: tmp)
    let plan = Planner().plan(entries.map(RuleClassifier().classify))
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let audit = AuditLog(url: tmp.appendingPathComponent("audit.log"))
    let result = try CleanupExecutor(vault: vault, audit: audit).execute(plan, apply: true)
    check(result.movedCount == 1, "one item moved")
    check(!fm.fileExists(atPath: dir.path), "original path emptied")
    let log = try audit.readAll()
    check(log.count == 1 && log.first?.result == "ok", "audit recorded ok")
}

// MARK: - Audit

section("AuditLog: append/read round trip")
withTempDir { tmp in
    let log = AuditLog(url: tmp.appendingPathComponent("nested/audit.log"))
    try log.append(AuditEntry(action: "scan", paths: ["/a"], bytes: 10, result: "ok"))
    try log.append(AuditEntry(action: "vault-move", paths: ["/b"], bytes: 20, result: "ok", sessionId: "s1"))
    let all = try log.readAll()
    check(all.count == 2, "two entries")
    check(all.last?.sessionId == "s1", "session id preserved")
}

// MARK: - Dev artifact classifier

@discardableResult
func makeDir(_ url: URL) -> URL {
    try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func classifyDir(_ url: URL) -> ClassifiedEntry {
    DevArtifactClassifier().classify(Scanner().makeEntry(url))
}

section("DevArtifact: node_modules next to package.json is high-confidence")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("package.json"), "{}")
    let nm = makeDir(tmp.appendingPathComponent("node_modules"))
    let v = classifyDir(nm)
    check(v.category == .devArtifact && v.confidence == .high, "node_modules confirmed high")
}

section("DevArtifact: ambiguous 'target' requires a project marker")
withTempDir { tmp in
    let bare = makeDir(tmp.appendingPathComponent("target"))
    check(classifyDir(bare).category == .unknown, "bare 'target' left unknown")

    let proj = makeDir(tmp.appendingPathComponent("rust"))
    makeFile(proj.appendingPathComponent("Cargo.toml"), "[package]")
    let t = makeDir(proj.appendingPathComponent("target"))
    let v = classifyDir(t)
    check(v.category == .devArtifact && v.confidence == .high, "target next to Cargo.toml confirmed")
}

section("DevArtifact: 'Pods' without a Podfile is left alone")
withTempDir { tmp in
    let pods = makeDir(tmp.appendingPathComponent("Pods"))
    check(classifyDir(pods).category == .unknown, "Pods without Podfile is unknown")
    makeFile(tmp.appendingPathComponent("Podfile"), "platform :ios")
    check(classifyDir(pods).category == .devArtifact, "Pods with Podfile is a dev artifact")
}

section("DevArtifact: venv confirmed only by inner pyvenv.cfg")
withTempDir { tmp in
    let venv = makeDir(tmp.appendingPathComponent("venv"))
    check(classifyDir(venv).category == .unknown, "empty 'venv' is unknown")
    makeFile(venv.appendingPathComponent("pyvenv.cfg"), "home = /usr")
    check(classifyDir(venv).category == .devArtifact, "venv with pyvenv.cfg is a dev artifact")
}

section("DevArtifact: distinctive names need no marker; generic ones do")
withTempDir { tmp in
    check(classifyDir(makeDir(tmp.appendingPathComponent("__pycache__"))).confidence == .high, "__pycache__ trusted by name")
    let bareBuild = makeDir(tmp.appendingPathComponent("build"))
    check(classifyDir(bareBuild).category == .unknown, "generic 'build' without marker is unknown")
    makeFile(tmp.appendingPathComponent("package.json"), "{}")
    let v = classifyDir(bareBuild)
    check(v.category == .devArtifact && v.confidence == .medium, "'build' next to package.json is medium")
}

section("DevArtifact: source files and unrelated folders are never claimed")
withTempDir { tmp in
    let src = makeFile(tmp.appendingPathComponent("main.swift"), "print()")
    check(DevArtifactClassifier().classify(Scanner().makeEntry(src)).category == .unknown, "source file untouched")
    check(classifyDir(makeDir(tmp.appendingPathComponent("my-notes"))).category == .unknown, "random folder untouched")
}

// MARK: - Cache / log classifier

func classifyPath(_ path: String, dir: Bool = false) -> ClassifiedEntry {
    CacheLogClassifier().classify(FileEntry(url: URL(fileURLWithPath: path), size: 1, modified: Date(), isDirectory: dir))
}

section("CacheLog: recognises per-app and developer-tool caches")
check(classifyPath("/Users/x/Library/Caches/com.app/blob").category == .safeCache, "Library cache")
check(classifyPath("/Users/x/.npm/_cacache/index/ab").category == .safeCache, "npm cache")
check(classifyPath("/Users/x/.cargo/registry/cache/x.crate").category == .safeCache, "Cargo cache")
check(classifyPath("/Users/x/.gradle/caches/modules/x.jar").category == .safeCache, "Gradle cache")
check(classifyPath("/Users/x/go/pkg/mod/cache/download/x.zip").category == .safeCache, "Go mod cache")

section("CacheLog: log locations vs stray project logs")
check(classifyPath("/Users/x/Library/Logs/app.log").category == .logs, "Library log")
check(classifyPath("/Users/x/.npm/_logs/2026.log").category == .logs, "npm log")
check(classifyPath("/Users/x/proj/debug.log").category == .unknown, "stray project log left alone")
check(classifyPath("/Users/x/proj/src/main.swift").category == .unknown, "source left alone")

// MARK: - Safety guard

section("SafetyGuard: protects credentials, VCS, system and libraries")
check(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/.ssh/id_ed25519")), ".ssh key protected")
check(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/proj/.git")), ".git protected")
check(SafetyGuard.isProtected(URL(fileURLWithPath: "/System/Library/Foo")), "/System protected")
check(SafetyGuard.isProtected(URL(fileURLWithPath: "/Library/LaunchDaemons/x")), "system /Library protected")
check(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/Pictures/My.photoslibrary")), "Photos library protected")
check(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/login.keychain-db")), "keychain protected")
check(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/proj/package-lock.json")), "lockfile protected")
check(!SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/Library/Caches/com.app/blob")), "user cache not protected")
check(!SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/proj/node_modules")), "node_modules not protected")

section("Planner: drops protected paths even if classified deletable")
withTempDir { tmp in
    let git = FileEntry(url: tmp.appendingPathComponent(".git"), size: 100, modified: Date(), isDirectory: true)
    let classified = ClassifiedEntry(entry: git, category: .devArtifact, confidence: .high, reason: "misclassified")
    let plan = Planner().plan([classified])
    check(plan.items.isEmpty, ".git never planned even if a classifier says devArtifact")
}

section("Planner: review-only categories excluded from all, included when named")
withTempDir { tmp in
    let dupe = FileEntry(url: tmp.appendingPathComponent("copy.bin"), size: 100, modified: Date(), isDirectory: false)
    let classified = ClassifiedEntry(entry: dupe, category: .duplicate, confidence: .high, reason: "dupe")
    check(Planner().plan([classified]).items.isEmpty, "duplicates excluded from 'all' plan")
    check(Planner().plan([classified], categories: [.duplicate]).count == 1, "duplicates included when named")
}

// MARK: - Summary

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)

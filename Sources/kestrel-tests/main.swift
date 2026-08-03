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

// MARK: - Recursive scanner

section("Scanner.scanFiles: prunes dev artifacts and protected trees")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("keep.txt"), "a")
    let sub = makeDir(tmp.appendingPathComponent("src"))
    makeFile(sub.appendingPathComponent("nested.txt"), "b")
    let nm = makeDir(tmp.appendingPathComponent("node_modules"))
    makeFile(nm.appendingPathComponent("dep.js"), "c")
    let git = makeDir(tmp.appendingPathComponent(".git"))
    makeFile(git.appendingPathComponent("HEAD"), "ref")

    let files = try Scanner().scanFiles(under: tmp).map { $0.url.lastPathComponent }
    check(files.contains("keep.txt") && files.contains("nested.txt"), "loose files found")
    check(!files.contains("dep.js"), "node_modules not descended into")
    check(!files.contains("HEAD"), ".git tree skipped")
}

// MARK: - Large & old classifier

section("LargeOld: only large AND old files, review-only")
withTempDir { tmp in
    let bigOld = FileEntry(url: tmp.appendingPathComponent("movie.mov"), size: 500_000_000, modified: Date(timeIntervalSinceNow: -400 * 86400), isDirectory: false)
    let bigNew = FileEntry(url: tmp.appendingPathComponent("fresh.iso"), size: 500_000_000, modified: Date(), isDirectory: false)
    let smallOld = FileEntry(url: tmp.appendingPathComponent("note.txt"), size: 10, modified: Date(timeIntervalSinceNow: -400 * 86400), isDirectory: false)
    let clf = LargeOldClassifier()
    check(clf.classify(bigOld).category == .largeOld, "big + old flagged")
    check(clf.classify(bigNew).category == .unknown, "big but recent skipped")
    check(clf.classify(smallOld).category == .unknown, "old but small skipped")

    let hit = clf.classify(bigOld)
    check(Planner().plan([hit]).items.isEmpty, "largeOld excluded from 'all' plan")
    check(Planner().plan([hit], categories: [.largeOld]).count == 1, "included when named explicitly")
}

// MARK: - Duplicate finder

section("Duplicates: identical files, one original kept")
withTempDir { tmp in
    let a = makeFile(tmp.appendingPathComponent("a.bin"), "same content here")
    let b = makeFile(tmp.appendingPathComponent("b.bin"), "same content here")
    let c = makeFile(tmp.appendingPathComponent("c.bin"), "same content here")
    let entries = [a, b, c].map { Scanner().makeEntry($0) }
    let dupes = DuplicateFinder().find(in: entries)
    check(dupes.count == 2, "two of three flagged as duplicates (one kept)")
    check(dupes.allSatisfy { $0.category == .duplicate && $0.confidence == .high }, "high-confidence duplicates")
    let flaggedPaths = Set(dupes.map { $0.entry.url.path })
    check(flaggedPaths.count == 2, "the kept original is not flagged")
}

section("Duplicates: same size but different content are not duplicates")
withTempDir { tmp in
    let a = makeFile(tmp.appendingPathComponent("a.bin"), "aaaa")
    let b = makeFile(tmp.appendingPathComponent("b.bin"), "bbbb")
    let entries = [a, b].map { Scanner().makeEntry($0) }
    check(DuplicateFinder().find(in: entries).isEmpty, "different bytes, same size, not flagged")
}

section("Duplicates: partial-hash collision resolved by full hash")
withTempDir { tmp in
    // Same size, identical first 2 bytes, different tail — the full-hash stage must split them.
    let a = makeFile(tmp.appendingPathComponent("a.bin"), "abXX")
    let b = makeFile(tmp.appendingPathComponent("b.bin"), "abYY")
    let entries = [a, b].map { Scanner().makeEntry($0) }
    check(DuplicateFinder(partialBytes: 2).find(in: entries).isEmpty, "full hash separates partial collisions")
}

section("Duplicates: empty files are ignored")
withTempDir { tmp in
    let a = makeFile(tmp.appendingPathComponent("a.bin"), "")
    let b = makeFile(tmp.appendingPathComponent("b.bin"), "")
    let entries = [a, b].map { Scanner().makeEntry($0) }
    check(DuplicateFinder().find(in: entries).isEmpty, "zero-byte files not flagged")
}

// MARK: - Scan coordinator

section("ScanCoordinator: finds nested dev artifacts, caches, dupes; skips .git")
withTempDir { tmp in
    // A monorepo-ish project with a top-level and a nested node_modules.
    let proj = makeDir(tmp.appendingPathComponent("project"))
    makeFile(proj.appendingPathComponent("package.json"), #"{"name":"root"}"#)
    makeFile(makeDir(proj.appendingPathComponent("src")).appendingPathComponent("main.js"), "code")
    makeFile(makeDir(proj.appendingPathComponent("node_modules")).appendingPathComponent("dep.js"), "x")
    let front = makeDir(proj.appendingPathComponent("frontend"))
    makeFile(front.appendingPathComponent("package.json"), #"{"name":"frontend"}"#)
    makeFile(makeDir(front.appendingPathComponent("node_modules")).appendingPathComponent("dep2.js"), "y")

    // A per-app cache under Library/Caches.
    let appCache = makeDir(tmp.appendingPathComponent("Library/Caches/com.example.app"))
    makeFile(appCache.appendingPathComponent("blob"), "cache")

    // Two identical loose files → one duplicate.
    makeFile(tmp.appendingPathComponent("copyA.bin"), "same content here")
    makeFile(tmp.appendingPathComponent("copyB.bin"), "same content here")

    // A large & old file (mtime pushed into the past).
    let old = makeFile(tmp.appendingPathComponent("old.bin"), "0123456789")
    try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -400 * 86400)], ofItemAtPath: old.path)

    // Protected VCS tree.
    makeFile(makeDir(tmp.appendingPathComponent(".git")).appendingPathComponent("HEAD"), "ref")

    let options = ScanOptions(largeOld: LargeOldClassifier(minSize: 1, minAge: 100 * 86400))
    let classified = try ScanCoordinator().scan(root: tmp, options: options)

    let devPaths = classified.filter { $0.category == .devArtifact }.map { $0.entry.url.path }
    check(devPaths.count == 2, "both node_modules found (got \(devPaths.count))")
    check(devPaths.contains { $0.contains("frontend/node_modules") }, "nested node_modules found")
    check(classified.contains { $0.category == .safeCache && $0.entry.url.lastPathComponent == "com.example.app" }, "per-app cache is one unit")
    check(classified.filter { $0.category == .duplicate }.count == 1, "one duplicate found")
    check(classified.contains { $0.category == .largeOld }, "large & old file surfaced")
    check(!classified.contains { $0.entry.url.path.contains("/.git/") }, ".git never in results")

    // dev artifact sizes are real (recursive), not zero.
    check(classified.first { $0.category == .devArtifact }.map { $0.entry.size > 0 } == true, "dev artifact has recursive size")
}

section("ScanCoordinator: default 'all' plan excludes review-only categories")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("copyA.bin"), "same content here")
    makeFile(tmp.appendingPathComponent("copyB.bin"), "same content here")
    let classified = try ScanCoordinator().scan(root: tmp)
    check(Planner().plan(classified).items.isEmpty, "duplicates not in default plan")
    check(Planner().plan(classified, categories: [.duplicate]).count == 1, "duplicates when named")
}

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

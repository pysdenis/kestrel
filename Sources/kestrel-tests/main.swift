import Foundation
import CoreGraphics
import ImageIO
import SQLite3
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
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
    let outcome = try vault.undo(session: session)
    check(outcome.restored == 1, "one item restored")
    check(outcome.isComplete, "outcome reports a clean restore")
    check(fm.fileExists(atPath: file.path), "file back at original path")
    check((try? String(contentsOf: file, encoding: .utf8)) == "important", "contents intact")
}

section("VaultService: restoreItem brings back one file, leaves the session intact")
withTempDir { tmp in
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let a = makeFile(tmp.appendingPathComponent("a.txt"), "aaa")
    let b = makeFile(tmp.appendingPathComponent("b.txt"), "bbb")
    let session = try vault.beginSession()
    try vault.move(url: a, session: session)
    try vault.move(url: b, session: session)
    let outcome = try vault.restoreItem(originalPath: a.path, session: session)
    check(outcome.restored == 1, "only the one item restored")
    check(fm.fileExists(atPath: a.path), "a.txt is back")
    check(!fm.fileExists(atPath: b.path), "b.txt stays in the vault")
    let remaining = try vault.listSessions().first { $0.id == session }
    check(remaining?.count == 1 && remaining?.records.first?.originalPath == b.path, "session keeps only b.txt")
}

section("VaultService: undo never overwrites an existing file, and keeps it in the vault")
withTempDir { tmp in
    let vaultRoot = tmp.appendingPathComponent("vault")
    let vault = VaultService(vaultRoot: vaultRoot)
    let file = makeFile(tmp.appendingPathComponent("conflict.txt"), "original")
    let session = try vault.beginSession()
    try vault.move(url: file, session: session)
    makeFile(file, "new")
    let outcome = try vault.undo(session: session)
    check((try? String(contentsOf: file, encoding: .utf8)) == "new", "existing file not clobbered")
    check(outcome.restored == 0 && outcome.skippedExisting.count == 1, "skipped because occupied")
    // Data-safety: a skipped item must NOT be lost — the session and its file survive.
    check(fm.fileExists(atPath: vaultRoot.appendingPathComponent(session).path), "session kept, not purged on partial undo")
    let sessions = try vault.listSessions()
    check(sessions.first?.count == 1, "manifest rewritten to the one remaining record")
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

section("VaultService: same-named files in one session don't collide and undo to distinct paths")
withTempDir { tmp in
    // Two different files that share a basename must land at distinct vault paths,
    // otherwise the second move would clobber the first and the undo would lose data.
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let a = makeFile(tmp.appendingPathComponent("d1/cache.db"), "one")
    let b = makeFile(tmp.appendingPathComponent("d2/cache.db"), "two")
    let session = try vault.beginSession()
    let ra = try vault.move(url: a, session: session)
    let rb = try vault.move(url: b, session: session)
    check(ra.vaultPath != rb.vaultPath, "same-named files stored at distinct vault paths")
    check(fm.fileExists(atPath: ra.vaultPath) && fm.fileExists(atPath: rb.vaultPath), "both copies survive in the vault")
    let outcome = try vault.undo(session: session)
    check(outcome.restored == 2 && outcome.isComplete, "both restored cleanly")
    check((try? String(contentsOf: a, encoding: .utf8)) == "one", "d1/cache.db back with its own contents")
    check((try? String(contentsOf: b, encoding: .utf8)) == "two", "d2/cache.db back with its own contents")
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

    // Grouped view: one group, original + two copies, reclaimable = 2 copies.
    let groups = DuplicateFinder().findGroups(in: entries)
    check(groups.count == 1, "one duplicate group")
    check(groups.first?.copies.count == 2, "group has two copies (original kept)")
    check(groups.first?.all.count == 3, "group's all = original + copies")
    check(groups.first?.reclaimable == Int64("same content here".utf8.count) * 2, "reclaimable = two copies' bytes")
    check(!flaggedPaths.contains(groups.first!.original.url.path), "the group original is the kept file")
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

// MARK: - App uninstaller

@discardableResult
func makeApp(_ dir: URL, bundleId: String) -> URL {
    let app = dir.appendingPathComponent("Test.app")
    let contents = app.appendingPathComponent("Contents")
    try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
    makeFile(contents.appendingPathComponent("MacOS/Test"), "binary") // gives the bundle a size
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>\(bundleId)</string></dict></plist>
    """
    makeFile(contents.appendingPathComponent("Info.plist"), plist)
    return app
}

section("Uninstaller: reads bundle id and collects existing leftovers")
withTempDir { tmp in
    let apps = makeDir(tmp.appendingPathComponent("Applications"))
    let home = makeDir(tmp.appendingPathComponent("home"))
    let app = makeApp(apps, bundleId: "com.test.app")

    // Two real leftovers, one path that does not exist (must be skipped).
    makeFile(home.appendingPathComponent("Library/Application Support/com.test.app/db.sqlite"), "data")
    makeFile(home.appendingPathComponent("Library/Preferences/com.test.app.plist"), "prefs")

    let uninstaller = AppUninstaller(home: home)
    check(uninstaller.bundleIdentifier(of: app) == "com.test.app", "bundle id read from Info.plist")
    let plan = try uninstaller.plan(for: app)
    let names = plan.items.map { $0.entry.url.lastPathComponent }
    check(names.contains("Test.app"), "bundle included")
    check(names.contains("com.test.app") && names.contains("com.test.app.plist"), "existing leftovers included")
    check(!names.contains("Caches"), "non-existent leftover skipped")
    check(plan.items.allSatisfy { $0.category == .appLeftover }, "all classified as appLeftover")
}

section("Uninstaller: apply moves everything to the vault, undo restores")
withTempDir { tmp in
    let apps = makeDir(tmp.appendingPathComponent("Applications"))
    let home = makeDir(tmp.appendingPathComponent("home"))
    let app = makeApp(apps, bundleId: "com.test.app")
    makeFile(home.appendingPathComponent("Library/Preferences/com.test.app.plist"), "prefs")

    let plan = try AppUninstaller(home: home).plan(for: app)
    let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
    let audit = AuditLog(url: tmp.appendingPathComponent("audit.log"))
    let result = try CleanupExecutor(vault: vault, audit: audit).execute(plan, apply: true)
    check(result.movedCount == plan.count, "all items moved to vault")
    check(!fm.fileExists(atPath: app.path), "app bundle removed from Applications")
    _ = try vault.undo(session: result.sessionId!)
    check(fm.fileExists(atPath: app.path), "undo restores the app bundle")
}

section("Uninstaller: refuses non-app and system apps")
withTempDir { tmp in
    let notApp = makeFile(tmp.appendingPathComponent("thing.txt"), "x")
    do { _ = try AppUninstaller().plan(for: notApp); check(false, "expected throw") }
    catch { check((error as? AppUninstaller.UninstallError) == .notAnApp(notApp.path), "non-app rejected") }

    let sys = URL(fileURLWithPath: "/System/Applications/Fake.app")
    do { _ = try AppUninstaller().plan(for: sys); check(false, "expected throw") }
    catch { check((error as? AppUninstaller.UninstallError) == .systemApp(sys.path), "system app rejected") }
}

// MARK: - External tool adapters

struct StubRunner: CommandRunner {
    let responses: [String: String]
    func run(_ tool: String, _ arguments: [String]) throws -> String {
        responses[([tool] + arguments).joined(separator: " ")] ?? ""
    }
}

section("Docker adapter: parses reclaimable space, advisory only")
do {
    let runner = StubRunner(responses: [
        "docker --version": "Docker version 25.0.3, build abc",
        "docker system df --format {{.Type}}\t{{.Reclaimable}}":
            "Images\t1.2GB (60%)\nContainers\t0B (0%)\nLocal Volumes\t300MB (100%)\nBuild Cache\t512MB (100%)",
    ])
    let p = DockerAdapter(runner: runner).preview()
    check(p.available, "docker reported available")
    check(p.reclaimableBytes == 2_012_000_000, "reclaimable summed (got \(p.reclaimableBytes))")
    check(p.command == "docker system prune", "advisory command present")
    check(p.details.count == 3, "zero-reclaimable rows omitted from details")
}

section("Docker adapter: absent tool is reported, not invented")
check(!DockerAdapter(runner: StubRunner(responses: [:])).preview().available, "missing docker → unavailable")

section("Homebrew adapter: parses 'would free approximately' total")
do {
    let runner = StubRunner(responses: [
        "brew --version": "Homebrew 4.2.0",
        "brew cleanup --dry-run": """
        Would remove: /Users/x/Library/Caches/Homebrew/node--20.tar.gz (50MB)
        Would remove: /opt/homebrew/Cellar/python/3.10 (200MB)
        ==> This operation would free approximately 250MB of disk space.
        """,
    ])
    let p = HomebrewAdapter(runner: runner).preview()
    check(p.available && p.reclaimableBytes == 250_000_000, "brew reclaimable parsed (got \(p.reclaimableBytes))")
    check(p.details.count == 2, "two removal lines captured")
}

section("parseHumanBytes: SI and binary suffixes")
check(parseHumanBytes("1.2GB") == 1_200_000_000, "GB")
check(parseHumanBytes("512MB") == 512_000_000, "MB")
check(parseHumanBytes("1KiB") == 1024, "KiB")
check(parseHumanBytes("0B") == 0, "0B")
check(parseHumanBytes("nonsense") == nil, "garbage → nil")

// MARK: - Disk map

section("DiskMap: recursive sizes, sorted largest-first, depth-limited")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("a/file1.txt"), "aaaa")      // 4
    makeFile(tmp.appendingPathComponent("a/file2.txt"), "bbbbbb")    // 6
    makeFile(tmp.appendingPathComponent("b/big.bin"), "12345678901234567890") // 20
    makeFile(tmp.appendingPathComponent("c.txt"), "ccc")             // 3

    // physical: false → logical sizes, so the byte totals are deterministic (allocated
    // sizes are block-rounded and filesystem-dependent).
    let tree = DiskMap(physical: false).measure(tmp, maxDepth: 2)
    check(tree.size == 33, "root total = 33 (got \(tree.size))")
    check(tree.children.map(\.name) == ["b", "a", "c.txt"], "children sorted largest-first")
    check(tree.children.first(where: { $0.name == "a" })?.children.count == 2, "'a' expanded at depth 2")

    let shallow = DiskMap(physical: false).measure(tmp, maxDepth: 1)
    let aShallow = shallow.children.first { $0.name == "a" }
    check(aShallow?.size == 10 && aShallow?.children.isEmpty == true, "depth 1 sums but does not expand")
}

section("DiskMap: physical sizing reports on-disk bytes for sparse files (the Docker.raw fix)")
withTempDir { tmp in
    // A sparse file: 500 MB logical length, but almost nothing actually allocated —
    // exactly like Docker.raw / VM images that made the Space map show phantom 500 GB.
    let sparse = tmp.appendingPathComponent("Docker.raw")
    fm.createFile(atPath: sparse.path, contents: nil)
    if let fh = try? FileHandle(forWritingTo: sparse) {
        try? fh.truncate(atOffset: 500_000_000)
        try? fh.close()
    }
    let logical = DiskMap(physical: false).measure(tmp, maxDepth: 1).size
    let physicalSize = DiskMap(physical: true).measure(tmp, maxDepth: 1).size
    check(logical >= 500_000_000, "logical length is the full 500 MB (got \(logical))")
    check(physicalSize < logical / 10, "allocated size is a fraction of logical (got \(physicalSize) vs \(logical))")
}

// MARK: - Snapshots & trend

section("SnapshotStore: save/load, trend forecast, and change diff")
withTempDir { tmp in
    let store = SnapshotStore(directory: tmp.appendingPathComponent("snapshots"))
    let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    let day3 = day1.addingTimeInterval(2 * 86400)
    try store.save(DiskSnapshot(date: day1, space: DiskSpace(total: 1000, available: 900), breakdown: ["/x": 50, "/y": 50]))
    try store.save(DiskSnapshot(date: day3, space: DiskSpace(total: 1000, available: 860), breakdown: ["/x": 50, "/y": 90]))

    let count = try store.all().count
    check(count == 2, "two snapshots persisted")
    let trend = try store.trend()
    check(trend?.dailyGrowthBytes == 20, "growth 20 bytes/day (got \(trend?.dailyGrowthBytes ?? -1))")
    check(trend?.daysUntilFull == 43, "≈43 days until full (got \(trend?.daysUntilFull ?? -1))")

    let changes = try store.recentChanges()
    check(changes == [SpaceDelta(path: "/y", delta: 40)], "only /y grew, by 40")

    // Culprit timeline: diff the latest against the newest snapshot ≥ N days old.
    let now = day3.addingTimeInterval(3600)
    let window = try store.changesOverLast(days: 7, now: now)
    check(window == [SpaceDelta(path: "/y", delta: 40)], "7-day window falls back to earliest baseline (/y +40)")
    // Add a third day so a 1-day window has a proper ≥1-day-old baseline (day3, not day1).
    let day4 = day1.addingTimeInterval(3 * 86400)
    try store.save(DiskSnapshot(date: day4, space: DiskSpace(total: 1000, available: 850), breakdown: ["/x": 50, "/y": 100]))
    let oneDay = try store.changesOverLast(days: 1, now: day4.addingTimeInterval(3600))
    check(oneDay == [SpaceDelta(path: "/y", delta: 10)], "1-day window compares day4 vs day3 (/y +10)")

    // Regrowth: /y grew (50→100) over day1→day4; /x stayed flat. Only growing categories appear.
    let regrowth = RegrowthAnalyzer(store: store).estimates(now: day4.addingTimeInterval(3600))
    check(regrowth.contains { $0.category == "/y" && $0.dailyGrowthBytes > 0 }, "regrowth reports /y's daily growth")
    check(!regrowth.contains { $0.category == "/x" }, "flat category /x isn't listed (no regrowth)")
    check(regrowth.first?.suggestedDays != nil, "a suggested cadence is derived")
}

// MARK: - Stats & health

section("StatsCollector: live metrics are sane on this machine")
do {
    let s = StatsCollector()
    check(s.memory().total > 0, "physical memory reported")
    check(s.cpu().coreCount > 0, "core count reported")
    check((s.disk()?.total ?? 0) > 0, "home volume capacity reported")
    check(!s.volumes().isEmpty, "at least one mounted volume")
}

section("HealthScorer: transparent weighted average")
do {
    let disk = DiskSpace(total: 1000, available: 100)          // 90% used
    let mem = MemoryStats(total: 100, used: 50, free: 50)      // 50% used
    let cpu = CPUStats(coreCount: 8, loadAverages: [0.5, 0.4, 0.3])
    let score = HealthScorer().score(disk: disk, memory: mem, cpu: cpu, battery: nil)
    check(score.components.count == 3, "no battery → three components")
    check(score.components.first { $0.name == "Disk" }?.score == 40, "disk score reflects 90% full")
    check(score.overall == 75, "weighted overall = 75 (got \(score.overall))")
}

// MARK: - Antivirus

section("RuleScanner: detects the EICAR test file, clean files stay clean")
withTempDir { tmp in
    let infected = makeFile(tmp.appendingPathComponent("eicar.com"), RuleScanner.eicarSignature)
    let clean = makeFile(tmp.appendingPathComponent("readme.txt"), "hello world")
    let hits = RuleScanner().scanFile(infected)
    check(hits.count == 1 && hits.first?.severity == .malicious, "EICAR flagged malicious")
    check(RuleScanner().scanFile(clean).isEmpty, "clean file yields no findings")
}

section("AntivirusEngine: honest report over a tree")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("docs/notes.txt"), "safe")
    makeFile(tmp.appendingPathComponent("bin/eicar"), RuleScanner.eicarSignature)
    let report = AntivirusEngine().scan(root: tmp)
    check(report.scanned >= 2, "scanned the files")
    check(!report.isClean && report.findings.contains { $0.rule.contains("EICAR") }, "EICAR surfaced")

    let cleanReport = AntivirusEngine().scan(root: makeDir(tmp.appendingPathComponent("cleanonly")))
    check(cleanReport.isClean, "empty tree is clean")
}

section("QuarantineReader: reads the download agent from the xattr")
withTempDir { tmp in
    let f = makeFile(tmp.appendingPathComponent("dl.dmg"), "x")
    let value = "0081;00000000;Safari;ABCD-UUID"
    _ = value.withCString { setxattr(f.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    let info = QuarantineReader().read(f)
    check(info?.agent == "Safari", "quarantine agent parsed (got \(info?.agent ?? "nil"))")
    check(QuarantineReader().read(makeFile(tmp.appendingPathComponent("local.txt"), "x")) == nil, "no xattr → nil")
}

section("LaunchAgentAuditor: flags orphaned jobs, keeps valid ones")
withTempDir { tmp in
    let agents = makeDir(tmp.appendingPathComponent("LaunchAgents"))
    let realProgram = makeFile(tmp.appendingPathComponent("bin/tool"), "#!/bin/sh")
    func plist(_ label: String, _ program: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Label</key><string>\(label)</string>
        <key>Program</key><string>\(program)</string></dict></plist>
        """
    }
    makeFile(agents.appendingPathComponent("valid.plist"), plist("com.valid", realProgram.path))
    makeFile(agents.appendingPathComponent("orphan.plist"), plist("com.orphan", "/opt/gone/ghost"))

    let orphans = LaunchAgentAuditor(directories: [agents]).orphans()
    check(orphans.count == 1 && orphans.first?.label == "com.orphan", "only the orphan flagged")
}

section("ClamAV & Gatekeeper adapters parse tool output")
do {
    struct Stub: CommandRunner {
        let map: [String: String]
        func run(_ tool: String, _ args: [String]) throws -> String { map[([tool] + args).joined(separator: " ")] ?? "" }
    }
    let clam = ClamAVAdapter(runner: Stub(map: [
        "clamscan --version": "ClamAV 1.0.0",
        "clamscan -r --infected --no-summary /x": "/x/bad: Eicar-Test-Signature FOUND\n",
    ])).scan(path: "/x")
    check(clam.available && clam.infected == 1, "clamscan FOUND line parsed")

    let gk = SystemProtectionReader(runner: Stub(map: ["spctl --status": "assessments enabled"])).status()
    check(gk.assessmentsEnabled == true, "Gatekeeper status parsed")
}

// MARK: - Privacy

section("PrivacyClassifier: browser data is review-only, bookmarks untouched")
do {
    func p(_ path: String) -> ClassifiedEntry {
        PrivacyClassifier().classify(FileEntry(url: URL(fileURLWithPath: path), size: 1, modified: Date(), isDirectory: false))
    }
    check(p("/Users/x/Library/Safari/History.db").category == .privacy, "Safari history")
    check(p("/Users/x/Library/Application Support/Google/Chrome/Default/Cookies").category == .privacy, "Chrome cookies")
    check(p("/Users/x/Library/Application Support/Firefox/Profiles/ab.default/logins.json").category == .unknown, "Firefox logins left alone")
    let hit = p("/Users/x/Library/Cookies/Cookies.binarycookies")
    check(Planner().plan([hit]).items.isEmpty, "privacy excluded from 'all' plan")
    check(Planner().plan([hit], categories: [.privacy]).count == 1, "privacy included when named")
}

// MARK: - Orphaned data

section("OrphanFinder: leftovers of uninstalled apps, Apple data skipped")
withTempDir { tmp in
    let home = makeDir(tmp.appendingPathComponent("home"))
    let appSupport = "Library/Application Support"
    makeFile(home.appendingPathComponent("\(appSupport)/com.gone.app/state.db"), "x")
    makeFile(home.appendingPathComponent("\(appSupport)/com.present.app/state.db"), "x")
    makeFile(home.appendingPathComponent("\(appSupport)/com.apple.helpd/data"), "x")
    makeFile(home.appendingPathComponent("Library/Preferences/com.gone.app.plist"), "prefs")

    let plan = OrphanFinder(home: home).find(installedBundleIds: ["com.present.app"])
    let ids = plan.items.map { $0.entry.url.lastPathComponent }
    check(ids.contains("com.gone.app"), "orphaned app-support flagged")
    check(ids.contains("com.gone.app.plist"), "orphaned preferences flagged")
    check(!ids.contains("com.present.app"), "installed app kept")
    check(!ids.contains { $0.hasPrefix("com.apple.") }, "Apple data never flagged")
}

// MARK: - Maintenance, updates, activity

section("MaintenanceService: advisory catalog with real commands")
do {
    let tasks = MaintenanceService().tasks()
    check(tasks.contains { $0.name == "Flush DNS cache" }, "DNS flush listed")
    check(tasks.allSatisfy { !$0.command.isEmpty }, "every task has a command")
}

section("AppUpdater: parses brew outdated casks")
do {
    struct Stub: CommandRunner {
        func run(_ tool: String, _ args: [String]) throws -> String {
            let key = ([tool] + args).joined(separator: " ")
            if key == "brew --version" { return "Homebrew 4.2.0" }
            return "visual-studio-code (1.80.0) != 1.85.0\nslack (4.30) != 4.35\n"
        }
    }
    let outdated = AppUpdater(runner: Stub()).outdatedCasks()
    check(outdated.count == 2, "two outdated casks parsed")
    check(outdated.first == OutdatedCask(name: "visual-studio-code", current: "1.80.0", latest: "1.85.0"), "fields parsed")
}

section("ActivityReporter: savings summed from the audit log only")
withTempDir { tmp in
    let audit = AuditLog(url: tmp.appendingPathComponent("audit.log"))
    try audit.append(AuditEntry(action: "vault-move", category: "devArtifact", paths: ["/a"], bytes: 1000, result: "ok", sessionId: "s"))
    try audit.append(AuditEntry(action: "vault-move", category: "safeCache", paths: ["/b"], bytes: 500, result: "ok", sessionId: "s"))
    try audit.append(AuditEntry(action: "vault-move", category: "devArtifact", paths: ["/c"], bytes: 200, result: "error: x", sessionId: "s"))
    let summary = ActivityReporter(audit: audit).summary()
    check(summary.totalActions == 2, "failed move excluded")
    check(summary.reclaimedBytes == 1500, "only successful bytes summed")
    check(summary.bytesByCategory["devArtifact"] == 1000, "per-category savings")
}

// MARK: - Secrets scanner

section("SecretsScanner: finds leaked credentials, redacts, ignores clean files")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("config.env"), "AWS_KEY=AKIAIOSFODNN7EXAMPLE\nHOST=localhost")
    makeFile(tmp.appendingPathComponent("key.pem"), "-----BEGIN RSA PRIVATE KEY-----\nMIIabc\n-----END RSA PRIVATE KEY-----")
    makeFile(tmp.appendingPathComponent("readme.md"), "no secrets here, just prose")

    let matches = SecretsScanner().scan(root: tmp)
    check(matches.contains { $0.rule == "AWS access key id" }, "AWS key found")
    check(matches.contains { $0.rule == "Private key block" }, "private key found")
    check(matches.allSatisfy { !$0.preview.contains("AKIAIOSFODNN7EXAMPLE") }, "secret is redacted in preview")
    check(!matches.contains { $0.path.hasSuffix("readme.md") }, "clean file not flagged")
}

// MARK: - Power & snapshots (advisory)

section("PowerAuditor: parses processes that prevent sleep")
do {
    struct Stub: CommandRunner {
        func run(_ tool: String, _ args: [String]) throws -> String {
            """
            Assertion status system-wide:
               PreventUserIdleSystemSleep      1
            Listed by owning process:
               pid 42(coreaudiod): [0x0000000e00000939] PreventUserIdleSystemSleep named: "com.apple.audio"
               pid 99(zoom.us): [0x0000000f0000093a] PreventUserIdleDisplaySleep named: "screen"
            """
        }
    }
    let assertions = PowerAuditor(runner: Stub()).assertionsPreventingSleep()
    check(assertions.contains { $0.process == "coreaudiod" }, "coreaudiod flagged")
    check(assertions.count == 2, "both sleep-preventing assertions parsed")
}

section("LocalSnapshotAuditor: lists tmutil snapshots and derives delete date")
do {
    struct Stub: CommandRunner {
        func run(_ tool: String, _ args: [String]) throws -> String {
            "Snapshots for volume group containing disk /:\ncom.apple.TimeMachine.2026-01-01-120000.local\ncom.apple.TimeMachine.2026-01-02-130000.local"
        }
    }
    let auditor = LocalSnapshotAuditor(runner: Stub())
    let snaps = auditor.snapshots()
    check(snaps.count == 2, "two snapshots listed")
    check(auditor.deletionDate(from: snaps[0]) == "2026-01-01-120000", "deletion date derived")
}

// MARK: - Clutter finder

section("ClutterFinder: old installers and screenshots")
withTempDir { tmp in
    let old = makeFile(tmp.appendingPathComponent("Setup.dmg"), "diskimage")
    try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60 * 86400)], ofItemAtPath: old.path)
    makeFile(tmp.appendingPathComponent("Fresh.dmg"), "new") // recent → excluded
    makeFile(tmp.appendingPathComponent("Screenshot 2026-01-01 at 10.00.00.png"), "img")
    makeFile(tmp.appendingPathComponent("photo.png"), "img") // not a screenshot

    let installers = ClutterFinder().oldInstallers(under: tmp, olderThanDays: 30)
    check(installers.items.map { $0.entry.url.lastPathComponent } == ["Setup.dmg"], "only the old installer")
    let shots = ClutterFinder().screenshots(under: tmp)
    check(shots.items.count == 1 && shots.items.first?.entry.url.lastPathComponent.hasPrefix("Screenshot") == true, "only the screenshot")
}

section("ClutterFinder.largestFiles: biggest files first, respects the minimum, review-only")
withTempDir { tmp in
    let big = makeFile(tmp.appendingPathComponent("movie.mov"), String(repeating: "A", count: 300))
    let mid = makeFile(tmp.appendingPathComponent("clip.mp4"), String(repeating: "B", count: 150))
    _ = big; _ = mid
    makeFile(tmp.appendingPathComponent("tiny.txt"), "x")
    // minBytes 100 keeps the two big files, drops the tiny one; sorted largest-first.
    let plan = ClutterFinder().largestFiles(under: tmp, minBytes: 100, limit: 40)
    check(plan.items.map { $0.entry.url.lastPathComponent } == ["movie.mov", "clip.mp4"], "largest first, tiny excluded by minBytes")
    check(plan.items.allSatisfy { $0.category == .largeOld }, "large files are review-only (explicit selection)")
    check(ClutterFinder().largestFiles(under: tmp, minBytes: 100, limit: 1).items.count == 1, "limit caps the result count")
}

// MARK: - Shredder

section("Shredder: overwrites then removes, refuses missing")
withTempDir { tmp in
    let secret = makeFile(tmp.appendingPathComponent("secret.txt"), "TOP-SECRET-CONTENT")
    try Shredder().overwrite(secret)
    let after = (try? String(contentsOf: secret, encoding: .utf8))
    check(after != "TOP-SECRET-CONTENT", "content overwritten before deletion")
    try Shredder().shred(secret)
    check(!fm.fileExists(atPath: secret.path), "file removed after shred")
    do { try Shredder().shred(tmp.appendingPathComponent("nope")); check(false, "expected throw") }
    catch { check((error as? Shredder.ShredError) == .missing(tmp.appendingPathComponent("nope").path), "missing throws") }
}

// MARK: - Rules engine

section("RulesEngine: matches by age/extension, round-trips as JSON")
withTempDir { tmp in
    let old = makeFile(tmp.appendingPathComponent("old.zip"), "archive")
    try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60 * 86400)], ofItemAtPath: old.path)
    makeFile(tmp.appendingPathComponent("fresh.zip"), "new")
    makeFile(tmp.appendingPathComponent("keep.txt"), "keep")

    let ageRule = MaintenanceRule(name: "old zips", root: tmp.path, criteria: RuleCriteria(olderThanDays: 30, extensions: ["zip"]))
    let plan = RulesEngine().evaluate(ageRule)
    check(plan.items.map { $0.entry.url.lastPathComponent } == ["old.zip"], "only old .zip matched")

    let extRule = MaintenanceRule(name: "all zips", root: tmp.path, criteria: RuleCriteria(extensions: ["zip"]))
    check(RulesEngine().evaluate(extRule).count == 2, "both zips matched by extension")

    let store = tmp.appendingPathComponent("rules.json")
    try RulesEngine.save([ageRule], to: store)
    check(RulesEngine.load(from: store) == [ageRule], "rules JSON round-trips")
}

// MARK: - Energy

section("EnergyMonitor: parses top's power column, handles spaced names")
do {
    let sample = """
    Processes: 400 total, 2 running
    PID    COMMAND          %CPU POWER
    701    Google Chrome    12.5 45.2
    88     WindowServer     8.0  30.1
    1234   kernel_task      3.2  5.0
    """
    let parsed = EnergyMonitor.parse(sample, limit: 8)
    check(parsed.count == 3, "three processes parsed")
    check(parsed.first?.name == "Google Chrome" && parsed.first?.energyImpact == 45.2, "highest-energy first, spaced name intact")
    check(parsed.last?.name == "kernel_task", "sorted by energy descending")
}

section("EnergyLog: aggregates per-process over a window, prunes old")
withTempDir { tmp in
    let log = EnergyLog(url: tmp.appendingPathComponent("energy.json"))
    let now = Date()
    log.append([ProcessEnergy(pid: 1, name: "Chrome", cpuPercent: 10, energyImpact: 20)], now: now.addingTimeInterval(-3600))
    log.append([ProcessEnergy(pid: 1, name: "Chrome", cpuPercent: 10, energyImpact: 30),
                ProcessEnergy(pid: 2, name: "Xcode", cpuPercent: 40, energyImpact: 40)], now: now)
    let usage = log.usage(within: 24 * 3600, now: now)
    check(usage.first?.name == "Chrome" && usage.first?.total == 50, "Chrome summed across samples (20+30)")
    check(usage.contains { $0.name == "Xcode" && $0.total == 40 }, "Xcode aggregated")

    // A sample outside the window is dropped on next append.
    log.append([ProcessEnergy(pid: 3, name: "Old", cpuPercent: 1, energyImpact: 1)], now: now.addingTimeInterval(2 * 24 * 3600))
    check(!log.usage(within: 3600, now: now.addingTimeInterval(2 * 24 * 3600)).contains { $0.name == "Chrome" }, "stale samples pruned")
}

section("ProcessController: refuses process-group and init pids")
check(ProcessController().quit(pid: 0) == false, "pid 0 (process group) refused")
check(ProcessController().quit(pid: 1) == false, "pid 1 (launchd) refused")
check(ProcessController().quit(pid: -1) == false, "negative pid refused")

// MARK: - Rules scheduler (launchd)

section("RulesScheduler: writes a valid LaunchAgent plist, removable")
withTempDir { tmp in
    let scheduler = RulesScheduler(home: tmp)
    check(!scheduler.isInstalled(), "not installed initially")
    let plist = scheduler.plist(executable: "/usr/local/bin/kestrel", everyHours: 12)
    check((plist["ProgramArguments"] as? [String]) == ["/usr/local/bin/kestrel", "rules", "run", "--apply"], "runs rules run --apply")
    check((plist["StartInterval"] as? Int) == 12 * 3600, "interval in seconds")

    _ = try scheduler.writePlist(executable: "/usr/local/bin/kestrel", everyHours: 12)
    check(scheduler.isInstalled(), "plist written")
    // Round-trips as a real plist.
    let data = try Data(contentsOf: scheduler.plistURL)
    let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    check((decoded?["Label"] as? String) == RulesScheduler.label, "label persisted")
    try scheduler.removePlist()
    check(!scheduler.isInstalled(), "plist removed")
}

// MARK: - AI (Gemini)

func awaitResult<T>(_ op: @escaping () async -> T) -> T {
    let sem = DispatchSemaphore(value: 0)
    var out: T!
    Task { out = await op(); sem.signal() }
    sem.wait()
    return out
}

struct StubHTTP: HTTPClient {
    let data: Data
    let status: Int
    func post(url: URL, headers: [String: String], body: Data) async throws -> (data: Data, status: Int) { (data, status) }
}

section("Gemini: parses generateContent, handles empty")
do {
    let ok = Data(#"{"candidates":[{"content":{"parts":[{"text":"Hello from Gemini"}]}}]}"#.utf8)
    check((try? GeminiClient.parseText(ok)) == "Hello from Gemini", "response text parsed")
    let empty = Data(#"{"candidates":[]}"#.utf8)
    check((try? GeminiClient.parseText(empty)) == nil, "empty candidates → error")
}

section("Gemini: generate via stub; refuses without an API key (no egress)")
do {
    let ok = Data(#"{"candidates":[{"content":{"parts":[{"text":"Hi"}]}}]}"#.utf8)
    let text = awaitResult { try? await GeminiClient(apiKey: "k", http: StubHTTP(data: ok, status: 200)).generate("q") }
    check(text == "Hi", "generate returns model text")

    let refused = awaitResult { () -> Bool in
        do { _ = try await GeminiClient(apiKey: "", http: StubHTTP(data: Data(), status: 200)).generate("q"); return false }
        catch { return (error as? GeminiClient.GeminiError) == .noAPIKey }
    }
    check(refused, "no API key → refuses before any request")

    let httpErr = awaitResult { () -> Bool in
        do { _ = try await GeminiClient(apiKey: "k", http: StubHTTP(data: Data(), status: 429)).generate("q"); return false }
        catch { return (error as? GeminiClient.GeminiError) == .http(429) }
    }
    check(httpErr, "non-200 surfaces as http error")
}

section("AIAssistant: cleanup advisor asks for three honest buckets, metadata only")
do {
    // A capturing stub backend so we can assert what leaves the assistant (never file contents).
    final class CapturingLLM: LLMBackend, @unchecked Sendable {
        var lastPrompt = ""
        var lastSystem: String?
        var isConfigured: Bool { true }
        func generate(_ prompt: String, system: String?) async throws -> String {
            lastPrompt = prompt; lastSystem = system; return "advice"
        }
    }
    withTempDir { tmp in
        let nm = tmp.appendingPathComponent("node_modules")
        try? fm.createDirectory(at: nm, withIntermediateDirectories: true)
        makeFile(nm.appendingPathComponent("index.js"), "x")
        let entries = (try? Scanner().scanChildren(of: tmp)) ?? []
        let plan = Planner().plan(entries.map(RuleClassifier().classify))
        let stub = CapturingLLM()
        let assistant = AIAssistant(client: stub, responseLanguage: "Czech")
        let reply = awaitResult { try? await assistant.cleanupAdvice(plan: plan, disk: nil) }
        check(reply == "advice", "advisor returns the backend's reply")
        check(stub.lastPrompt.contains("Safe to reclaim") && stub.lastPrompt.contains("Leave alone"),
              "prompt asks for the three honest buckets")
        check(stub.lastPrompt.contains("no file contents"), "prompt states metadata-only, no contents")
        check(stub.lastSystem?.contains("Czech") == true, "system prompt carries the response language")
    }
}

section("CanaryGuard: plants decoys, verifies clean, trips on modify/delete")
withTempDir { tmp in
    let docs = tmp.appendingPathComponent("Documents")
    let desk = tmp.appendingPathComponent("Desktop")
    try fm.createDirectory(at: docs, withIntermediateDirectories: true)
    try fm.createDirectory(at: desk, withIntermediateDirectories: true)
    let guardService = CanaryGuard(manifestURL: tmp.appendingPathComponent(".kestrel/canary.json"))

    let planted = try guardService.plant(in: [docs, desk, tmp.appendingPathComponent("DoesNotExist")])
    check(planted.count == 2, "plants one decoy per existing directory, skips missing ones")
    check(fm.fileExists(atPath: docs.appendingPathComponent(CanaryGuard.decoyName).path), "decoy written")
    check(guardService.isArmed, "armed after planting")

    let clean = guardService.verify()
    check(clean.checked == 2 && !clean.isTripped, "freshly planted canaries verify clean")

    // Simulate an encryptor rewriting a protected file.
    try Data("encrypted-garbage".utf8).write(to: docs.appendingPathComponent(CanaryGuard.decoyName))
    let tripped = guardService.verify()
    check(tripped.isTripped && tripped.alerts.contains { $0.kind == .modified }, "modified decoy trips the canary")

    // Simulate deletion of a protected file.
    try fm.removeItem(at: desk.appendingPathComponent(CanaryGuard.decoyName))
    let afterDelete = guardService.verify()
    check(afterDelete.alerts.contains { $0.kind == .deleted }, "deleted decoy reported as deleted")

    guardService.disarm()
    check(!guardService.isArmed && !fm.fileExists(atPath: docs.appendingPathComponent(CanaryGuard.decoyName).path),
          "disarm removes decoys and the manifest")
}

// MARK: - System extensions

section("SystemExtensionAuditor: parses systemextensionsctl output")
do {
    let sample = """
    1 extension(s)
    --- com.apple.system_extension.endpoint_security
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    *\t*\tSKMME9E2Y8\tcom.crowdstrike.falcon.Agent (7.11/123)\tFalcon\t[activated enabled]
    """
    let exts = SystemExtensionAuditor.parse(sample)
    check(exts.count == 1, "one extension parsed (got \(exts.count))")
    check(exts.first?.identifier == "com.crowdstrike.falcon.Agent", "identifier parsed")
    check(exts.first?.state == "activated enabled", "state parsed")
    check(exts.first?.name == "Falcon", "name parsed")
}

// MARK: - Trash / Downloads / Mail

section("TrashFinder: lists trash contents as a trash-category plan")
withTempDir { tmp in
    let trash = makeDir(tmp.appendingPathComponent("Trash"))
    makeFile(trash.appendingPathComponent("old.dmg"), "junk")
    makeFile(trash.appendingPathComponent("note.txt"), "x")
    let plan = TrashFinder(locations: [trash]).find()
    check(plan.count == 2, "both trashed items listed")
    check(plan.items.allSatisfy { $0.category == .trash }, "category trash")
}

section("ClutterFinder: old downloads and mail attachments")
withTempDir { tmp in
    let dl = makeDir(tmp.appendingPathComponent("Downloads"))
    let old = makeFile(dl.appendingPathComponent("installer.dmg"), "x")
    try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60 * 86400)], ofItemAtPath: old.path)
    makeFile(dl.appendingPathComponent("fresh.zip"), "x")
    check(ClutterFinder().oldDownloads(under: dl, olderThanDays: 30).items.map { $0.entry.url.lastPathComponent } == ["installer.dmg"], "only old download")

    let mail = makeDir(tmp.appendingPathComponent("Mail"))
    makeFile(mail.appendingPathComponent("V10/Data/Attachments/1/photo.jpg"), "img")
    makeFile(mail.appendingPathComponent("V10/Data/Messages/1.emlx"), "msg")
    let att = ClutterFinder().mailAttachments(under: mail).items.map { $0.entry.url.lastPathComponent }
    check(att == ["photo.jpg"], "only attachment, not the message")

    let msgs = makeDir(tmp.appendingPathComponent("Messages/Attachments"))
    makeFile(msgs.appendingPathComponent("ab/12/video.mov"), "big")
    let mAtt = ClutterFinder().messagesAttachments(under: msgs).items
    check(mAtt.map { $0.entry.url.lastPathComponent } == ["video.mov"], "finds the Messages attachment")
    check(mAtt.allSatisfy { $0.category == .largeOld }, "Messages attachments are review-only")

    let reports = makeDir(tmp.appendingPathComponent("DiagnosticReports"))
    makeFile(reports.appendingPathComponent("App-2026.ips"), "crash")
    let diag = ClutterFinder().diagnosticReports(under: reports).items
    check(diag.count == 1 && diag.first?.category == .logs, "diagnostic report found as a log (safe)")

    let archives = makeDir(tmp.appendingPathComponent("Archives/2026-01-01"))
    try? fm.createDirectory(at: archives.appendingPathComponent("MyApp.xcarchive"), withIntermediateDirectories: true)
    makeFile(archives.appendingPathComponent("MyApp.xcarchive/Info.plist"), "x")
    let arch = ClutterFinder().xcodeArchives(under: tmp.appendingPathComponent("Archives")).items
    check(arch.count == 1 && arch.first?.category == .largeOld, "xcode archive found, review-only (not regeneratable)")
}

// MARK: - Similar images (perceptual hash)

func makePNG(_ url: URL, _ draw: (CGContext) -> Void) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    guard let img = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

section("SimilarImageFinder: groups look-alikes, separates different images")
withTempDir { tmp in
    let leftRight: (CGContext) -> Void = { c in
        c.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); c.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
    }
    let topBottom: (CGContext) -> Void = { c in
        c.setFillColor(red: 0, green: 0, blue: 0, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); c.fill(CGRect(x: 0, y: 32, width: 64, height: 32))
    }
    let a = tmp.appendingPathComponent("a.png"); makePNG(a, leftRight)
    let b = tmp.appendingPathComponent("b.png"); makePNG(b, leftRight)
    let c = tmp.appendingPathComponent("c.png"); makePNG(c, topBottom)
    let entries = [a, b, c].map { Scanner().makeEntry($0) }
    let groups = SimilarImageFinder().find(in: entries)
    check(groups.count == 1, "one similar group (got \(groups.count))")
    let names = Set(groups.first?.map { $0.url.lastPathComponent } ?? [])
    check(names == ["a.png", "b.png"], "a and b grouped, c separate")
}

// MARK: - Reset app / Cloud / Digest

section("AppUninstaller.resetPlan: clears data but keeps the app bundle")
withTempDir { tmp in
    let apps = makeDir(tmp.appendingPathComponent("Applications"))
    let home = makeDir(tmp.appendingPathComponent("home"))
    let app = makeApp(apps, bundleId: "com.test.app")
    makeFile(home.appendingPathComponent("Library/Caches/com.test.app/blob"), "cache")
    makeFile(home.appendingPathComponent("Library/Preferences/com.test.app.plist"), "prefs")

    let plan = try AppUninstaller(home: home).resetPlan(for: app)
    let names = plan.items.map { $0.entry.url.lastPathComponent }
    check(!names.contains("Test.app"), "app bundle kept (not reset)")
    check(names.contains("com.test.app") && names.contains("com.test.app.plist"), "data cleared")
}

section("CloudOffloadFinder: large local files, skips placeholders")
withTempDir { tmp in
    makeFile(tmp.appendingPathComponent("big.mov"), String(repeating: "x", count: 200))
    makeFile(tmp.appendingPathComponent("small.txt"), "x")
    makeFile(tmp.appendingPathComponent("stub.icloud"), String(repeating: "x", count: 200))
    let found = CloudOffloadFinder().find(under: tmp, minSizeBytes: 100).map { $0.url.lastPathComponent }
    check(found == ["big.mov"], "only the large materialized file (got \(found))")
}

section("DigestReporter: combines savings and storage trend")
withTempDir { tmp in
    let audit = AuditLog(url: tmp.appendingPathComponent("audit.log"))
    try audit.append(AuditEntry(action: "vault-move", category: "devArtifact", paths: ["/a"], bytes: 5000, result: "ok"))
    let store = SnapshotStore(directory: tmp.appendingPathComponent("snap"))
    let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    try store.save(DiskSnapshot(date: day1, space: DiskSpace(total: 1000, available: 900), breakdown: ["/x": 10]))
    try store.save(DiskSnapshot(date: day1.addingTimeInterval(2 * 86400), space: DiskSpace(total: 1000, available: 860), breakdown: ["/x": 50]))
    let digest = DigestReporter(audit: audit, snapshots: store).generate()
    check(digest.reclaimedAllTime == 5000, "all-time savings")
    check(digest.dailyGrowthBytes == 20, "growth from snapshots")
    check(digest.recentChanges.first?.path == "/x", "what grew")
}

// MARK: - TCCReader

section("TCCReader: reads grants from a TCC-shaped sqlite db (modern auth_value)")
withTempDir { tmp in
    let db = tmp.appendingPathComponent("TCC.db")
    var handle: OpaquePointer?
    check(sqlite3_open(db.path, &handle) == SQLITE_OK, "open temp db")
    sqlite3_exec(handle, "CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER)", nil, nil, nil)
    sqlite3_exec(handle, "INSERT INTO access VALUES ('kTCCServiceCamera','com.zoom.xos',2)", nil, nil, nil)
    sqlite3_exec(handle, "INSERT INTO access VALUES ('kTCCServiceMicrophone','com.foo.bar',0)", nil, nil, nil)
    sqlite3_close(handle)

    let perms = TCCReader(dbPath: db.path).permissions()
    check(perms.count == 2, "reads both rows")
    check(perms.contains { $0.client == "com.zoom.xos" && $0.allowed }, "camera allowed for zoom")
    check(perms.contains { $0.client == "com.foo.bar" && !$0.allowed }, "mic denied for foo")
    check(TCCReader.friendlyService("kTCCServiceSystemPolicyAllFiles") == "Full Disk Access", "friendly service name")
    check(TCCReader.isSensitive("kTCCServiceCamera") && TCCReader.isSensitive("kTCCServiceSystemPolicyAllFiles"),
          "camera + full-disk-access flagged as sensitive")
    check(!TCCReader.isSensitive("kTCCServiceCalendar") && !TCCReader.isSensitive("kTCCServiceReminders"),
          "calendar/reminders are not flagged sensitive")
}

section("TCCReader: missing db returns nothing, never crashes")
withTempDir { tmp in
    let perms = TCCReader(dbPath: tmp.appendingPathComponent("nope.db").path).permissions()
    check(perms.isEmpty, "no db → empty, honest")
}

// MARK: - MemoryReliever

section("MemoryReliever: locates purge without prompting")
do {
    // purge ships with macOS; the finder should locate it (and returns nil if it's absent).
    check(MemoryReliever.purgePath() == "/usr/sbin/purge" || MemoryReliever.purgePath() == nil,
          "finds the real purge tool or honestly reports it missing")
    let fm = FileManager.default
    check(MemoryReliever.purgePath(fm: fm) != nil || !fm.isExecutableFile(atPath: "/usr/sbin/purge"),
          "purgePath is nil only when purge really isn't executable")
}

// MARK: - AppUpdater

section("AppUpdater: parses outdated casks and trims the revision after a comma")
do {
    struct StubRunner: CommandRunner {
        func run(_ tool: String, _ arguments: [String]) throws -> String {
            if arguments.contains("--version") { return "Homebrew 4.0" }
            return "claude (1.1.9134,87a63a5) != 1.24012.11,09114b6\ndiscord (0.0.335) != 0.0.405"
        }
    }
    let casks = AppUpdater(runner: StubRunner()).outdatedCasks()
    check(casks.count == 2, "parses both lines")
    check(casks.first?.name == "claude", "cask name")
    check(casks.first?.current == "1.1.9134" && casks.first?.latest == "1.24012.11", "revision after comma trimmed")
    check(casks.last?.current == "0.0.335" && casks.last?.latest == "0.0.405", "plain versions unaffected")
    check(AppUpdater.cleanVersion("(1.0,rev)") == "1.0", "cleanVersion strips parens + revision")
    // No brew → no casks (guarded).
    struct NoBrew: CommandRunner { func run(_ t: String, _ a: [String]) throws -> String { "" } }
    check(AppUpdater(runner: NoBrew()).outdatedCasks().isEmpty, "no brew → empty")
}

// MARK: - BandwidthMonitor

section("BandwidthMonitor: parses nettop CSV, skips header, aggregates & sorts")
do {
    let sample = """
    ,bytes_in,bytes_out,
    mDNSResponder.514,180421991,49632120,
    apsd.371,9805,253739,
    airportd.461,0,0,
    com.apple.WebKit.Networking.12345,1000,2000,
    """
    let top = BandwidthMonitor.parse(sample, limit: 10)
    check(top.count == 3, "header + zero-total row dropped")
    check(top.first?.name == "mDNSResponder", "sorted by total, biggest first")
    check(top.first?.total == 180421991 + 49632120, "in+out summed")
    check(top.contains { $0.name == "com.apple.WebKit.Networking" }, "multi-dot name keeps everything but the pid")
    check(!top.contains { $0.name == "airportd" }, "zero-traffic process filtered out")
}

// MARK: - QuarantineReader

section("QuarantineReader: reads the quarantine xattr and scans a folder")
withTempDir { tmp in
    let downloaded = makeFile(tmp.appendingPathComponent("installer.dmg"))
    let clean = makeFile(tmp.appendingPathComponent("notes.txt"))
    let value = "0083;65abcd00;Safari;ABCDEF-1234"
    _ = value.withCString { setxattr(downloaded.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }

    let reader = QuarantineReader()
    let info = reader.read(downloaded)
    check(info?.agent == "Safari", "parses the download agent")
    check(reader.read(clean) == nil, "a clean file has no quarantine info")
    let found = reader.scan(root: tmp)
    check(found.count == 1 && found.first?.path.hasSuffix("installer.dmg") == true, "scan finds only the quarantined file")
}

// MARK: - DriveHealth (SMART parser)

section("DriveHealth: parses the SMART Status line honestly")
check(DriveHealth.parse("   Device / Media Name:      APPLE SSD\n   SMART Status:             Verified\n").status == .verified,
      "Verified → .verified")
check(DriveHealth.parse("   SMART Status:             Failing!\n").status == .failing, "Failing → .failing")
check(DriveHealth.parse("   SMART Status:             Not Supported\n").status == .notSupported, "Not Supported → .notSupported")
check(DriveHealth.parse("   SMART Status:             Something Else\n").status == .unknown, "unexpected value → .unknown")
check(DriveHealth.parse("no smart line here").status == .notSupported, "missing line → .notSupported (never invents health)")
check(DriveHealth.parse("   SMART Status:  Verified\n").raw == "Verified", "keeps the raw reported value")

// MARK: - SelfUpdate (GitHub releases)

section("SelfUpdate: semver comparison")
check(SelfUpdate.isNewer("0.1.1", than: "0.1.0"), "patch bump is newer")
check(SelfUpdate.isNewer("v0.2.0", than: "0.1.9"), "minor bump beats higher patch, ignores v prefix")
check(SelfUpdate.isNewer("1.0.0", than: "0.9.9"), "major bump is newer")
check(!SelfUpdate.isNewer("0.1.0", than: "0.1.0"), "equal is not newer")
check(!SelfUpdate.isNewer("0.1.0", than: "0.1.1"), "older is not newer")
check(SelfUpdate.isNewer("0.1.10", than: "0.1.9"), "numeric (not lexical) component compare")
check(SelfUpdate.cleanTag("v1.2.3") == "1.2.3" && SelfUpdate.cleanTag(" 1.2.3 ") == "1.2.3", "cleanTag strips v and whitespace")

section("SelfUpdate: parses the GitHub release payload")
let releaseJSON = """
{
  "tag_name": "v0.2.0",
  "html_url": "https://github.com/pysdenis/kestrel/releases/tag/v0.2.0",
  "body": "Faster scans and a new icon.",
  "assets": [
    {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
    {"name": "Kestrel-0.2.0.dmg", "browser_download_url": "https://example.com/Kestrel-0.2.0.dmg"}
  ]
}
""".data(using: .utf8)!
if let info = SelfUpdate.parse(releaseJSON) {
    check(info.version == "0.2.0", "version cleaned from tag")
    check(info.notes.contains("Faster scans"), "keeps release notes")
    check(info.downloadURL?.lastPathComponent == "Kestrel-0.2.0.dmg", "prefers the .dmg asset over the .txt")
    check(info.pageURL.absoluteString.hasSuffix("v0.2.0"), "keeps the release page URL")
} else {
    check(false, "parses a well-formed release payload")
}
check(SelfUpdate.parse(Data("{}".utf8)) == nil, "missing tag/url → nil (never invents a release)")
check(SelfUpdate.parse(Data("not json".utf8)) == nil, "garbage → nil")

// MARK: - SecurityPosture (protection readouts)

section("SecurityPosture: honest parsers for FileVault / SIP / Gatekeeper / firewall")
check(SecurityPostureReader.parseFileVault("FileVault is On.") == .on, "FileVault On")
check(SecurityPostureReader.parseFileVault("FileVault is Off.") == .off, "FileVault Off")
check(SecurityPostureReader.parseFileVault("weird") == .unknown, "FileVault unknown → never guesses")
check(SecurityPostureReader.parseSIP("System Integrity Protection status: enabled.") == .on, "SIP enabled")
check(SecurityPostureReader.parseSIP("System Integrity Protection status: disabled.") == .off, "SIP disabled")
check(SecurityPostureReader.parseGatekeeper("assessments enabled") == .on, "Gatekeeper on")
check(SecurityPostureReader.parseGatekeeper("assessments disabled") == .off, "Gatekeeper off")
let fwOn = SecurityPostureReader.firewallStates(from: ["globalstate": 1, "stealthenabled": 1])
check(fwOn.state == .on && fwOn.stealth == .on, "firewall on + stealth on")
let fwBlock = SecurityPostureReader.firewallStates(from: ["globalstate": 2, "stealthenabled": 0])
check(fwBlock.state == .on && fwBlock.stealth == .off, "block-all counts as on; stealth off")
let fwOff = SecurityPostureReader.firewallStates(from: ["globalstate": 0])
check(fwOff.state == .off && fwOff.stealth == .unknown, "firewall off; missing stealth → unknown")
check(SecurityPostureReader.firewallStates(from: nil).state == .unknown, "no plist → unknown (never invents)")
check(SecurityPostureReader.parseAutomaticUpdates(["AutomaticCheckEnabled": true]) == .on, "auto-updates on")
check(SecurityPostureReader.parseAutomaticUpdates(["AutomaticCheckEnabled": false]) == .off, "auto-updates off")
check(SecurityPostureReader.parseAutomaticUpdates([:]) == .unknown, "auto-updates missing → unknown")
check(SecurityPostureReader.parseGuest(["GuestEnabled": true]) == .on, "guest enabled → on (a concern)")
check(SecurityPostureReader.parseGuest(["GuestEnabled": false]) == .off, "guest disabled → off (good)")
check(SecurityPostureReader.parseGuest(nil) == .unknown, "no loginwindow plist → unknown")

// MARK: - PackageCacheFinder (dev caches)

section("PackageCacheFinder: finds known regeneratable caches, ignores source")
withTempDir { home in
    // A real cache location with content.
    let npm = home.appendingPathComponent(".npm/_cacache")
    try? FileManager.default.createDirectory(at: npm, withIntermediateDirectories: true)
    _ = makeFile(npm.appendingPathComponent("blob.bin"), "cached bytes")
    // A path NOT in the candidate list (a source project) must never be picked up.
    let src = home.appendingPathComponent("code/myapp/src")
    try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    _ = makeFile(src.appendingPathComponent("main.swift"), "let x = 1")

    let caches = PackageCacheFinder().find(home: home)
    check(caches.contains { $0.tool == "npm" }, "finds the npm cache")
    check(caches.allSatisfy { $0.size > 0 }, "only lists non-empty caches")
    check(!caches.contains { $0.url.path.contains("/code/myapp") }, "never lists a source folder")
}
check(PackageCacheFinder.candidatePaths.contains { $0.tool == "Gradle" && $0.path == ".gradle/caches" },
      "candidate list is data-driven and auditable")
check(PackageCacheFinder.candidatePaths.contains { $0.path == "Library/Developer/Xcode/iOS DeviceSupport" },
      "covers Xcode iOS DeviceSupport (a top space hog)")
check(PackageCacheFinder.candidatePaths.contains { $0.path == "Library/Developer/CoreSimulator/Caches" },
      "covers simulator caches")
check(Set(PackageCacheFinder.candidatePaths.map(\.path)).count == PackageCacheFinder.candidatePaths.count,
      "no duplicate cache paths")

// MARK: - PrivacyDataFinder (browser traces)

section("PrivacyDataFinder: locates browser caches/history/cookies by size")
withTempDir { home in
    let safariCache = home.appendingPathComponent("Library/Caches/com.apple.Safari")
    try? FileManager.default.createDirectory(at: safariCache, withIntermediateDirectories: true)
    _ = makeFile(safariCache.appendingPathComponent("blob"), "cache bytes here")
    let history = home.appendingPathComponent("Library/Safari/History.db")
    try? FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
    _ = makeFile(history, "sqlite history")

    let items = PrivacyDataFinder().find(home: home)
    check(items.contains { $0.app == "Safari" && $0.kind == .cache }, "finds the Safari cache dir")
    check(items.contains { $0.kind == .history && $0.url.lastPathComponent == "History.db" }, "finds the history file")
    check(items.allSatisfy { $0.size > 0 }, "only non-empty stores are listed")
}
check(PrivacyDataFinder.locations.contains { $0.app == "QuickLook" }, "known locations include the QuickLook thumbnail cache")

// MARK: - Exclusions allowlist (SafetyGuard integration)

section("ExclusionStore + SafetyGuard: user allowlist is honoured everywhere")
withTempDir { tmp in
    let store = ExclusionStore(url: tmp.appendingPathComponent("exclusions.json"))
    check(store.load().isEmpty, "starts empty")
    let keep = tmp.appendingPathComponent("Keep")
    _ = store.add(keep.path)
    _ = store.add(keep.path)  // idempotent
    check(store.load() == [keep.path], "adds once, de-duplicated")

    // Wire into SafetyGuard and confirm the subtree is now protected.
    SafetyGuard.userExclusions = Set(store.load())
    check(SafetyGuard.isProtected(keep), "the excluded folder itself is protected")
    check(SafetyGuard.isProtected(keep.appendingPathComponent("deep/file.txt")), "everything under it is protected")
    check(!SafetyGuard.isProtected(tmp.appendingPathComponent("KeepOther")), "a sibling with a shared prefix is NOT protected")
    check(SafetyGuard.protectionReason(for: keep)?.contains("Excluded by you") == true, "reason names the user exclusion")

    _ = store.remove(keep.path)
    SafetyGuard.userExclusions = Set(store.load())
    check(!SafetyGuard.isProtected(keep), "removing the exclusion lifts protection")
    SafetyGuard.userExclusions = []  // reset shared state for other tests
}

// MARK: - SpaceBreakdown (growth attribution)

section("SpaceBreakdown: sizes curated hog folders, skips missing/empty")
withTempDir { home in
    let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
    try? FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
    _ = makeFile(derived.appendingPathComponent("build.o"), "compiled artifact bytes")
    let trash = home.appendingPathComponent(".Trash")
    try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true) // empty

    let breakdown = SpaceBreakdown.measure(home: home)
    check(breakdown["Xcode DerivedData"] ?? 0 > 0, "measures DerivedData")
    check(breakdown["Trash"] == nil, "empty folder omitted")
    check(breakdown["Caches"] == nil, "missing folder omitted (never invents a size)")
}
check(SpaceBreakdown.locations.contains { $0.label == "iOS backups" }, "curated list includes iOS backups")

// MARK: - APFSCloner (dedupe without deleting)

section("APFSCloner: replaces a copy with a clone, keeping both files identical")
withTempDir { tmp in
    let original = makeFile(tmp.appendingPathComponent("original.bin"), "the very same bytes")
    let copy = makeFile(tmp.appendingPathComponent("copy.bin"), "the very same bytes")
    if APFSCloner.supportsCloning(at: copy) {
        let reclaimed = try APFSCloner().dedupe(original: original, copy: copy)
        check(FileManager.default.fileExists(atPath: original.path), "original still there")
        check(FileManager.default.fileExists(atPath: copy.path), "copy still there (not deleted)")
        check((try? String(contentsOf: copy, encoding: .utf8)) == "the very same bytes", "copy's contents intact")
        check(reclaimed >= 0, "reports reclaimed bytes")
        // Editing the copy must not change the original (copy-on-write independence).
        try "changed".write(to: copy, atomically: true, encoding: .utf8)
        check((try? String(contentsOf: original, encoding: .utf8)) == "the very same bytes", "original unaffected by editing the clone")
        // No temp clone files left behind.
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path))?.filter { $0.hasPrefix(".kestrel-clone-") } ?? []
        check(leftovers.isEmpty, "no temp clone files left behind")
    } else {
        check(true, "volume doesn't support cloning here — skipped")
    }
}

// MARK: - OllamaClient (local, offline AI)

section("OllamaClient: parses chat + model list")
let chatJSON = Data(#"{"model":"llama3.2","message":{"role":"assistant","content":"  Hello from Ollama  "},"done":true}"#.utf8)
check((try? OllamaClient.parseChat(chatJSON)) == "Hello from Ollama", "chat content parsed + trimmed")
check((try? OllamaClient.parseChat(Data(#"{"message":{"content":""}}"#.utf8))) == nil, "empty content → error")
check((try? OllamaClient.parseChat(Data("nope".utf8))) == nil, "garbage → error (never invents a reply)")
let tagsJSON = Data(#"{"models":[{"name":"llama3.2:latest"},{"name":"qwen2.5:7b"}]}"#.utf8)
check(OllamaClient.parseModels(tagsJSON) == ["llama3.2:latest", "qwen2.5:7b"], "lists installed models")
check(OllamaClient.parseModels(Data("{}".utf8)).isEmpty, "no models key → empty")
check(OllamaClient.preferredModel(from: ["qwen2.5-coder:14b", "llama3.2:3b"]) == "llama3.2:3b", "prefers a general model over the heavy coder")
check(OllamaClient.preferredModel(from: ["qwen2.5-coder:14b"]) == "qwen2.5-coder:14b", "falls back to the only model even if heavy")
check(OllamaClient.preferredModel(from: ["llama3.2:3b", "qwen2.5:7b"]) == "qwen2.5:7b", "prefers a stronger multilingual model over a tiny one")
check(OllamaClient.preferredModel(from: ["qwen2.5:7b", "qwen2.5-coder:14b"]) == "qwen2.5:7b", "the qwen2.5:7b prefix never matches qwen2.5-coder:14b")
check(OllamaClient.preferredModel(from: ["qwen2.5:7b", "qwen3:8b"]) == "qwen3:8b", "qwen3:8b outranks the older qwen2.5:7b")
check(OllamaClient.preferredModel(from: ["llama3.2:3b", "qwen3:14b"]) == "llama3.2:3b", "the qwen3:8b prefix never matches the heavy qwen3:14b")
check(OllamaClient.preferredModel(from: []) == nil, "no models → nil")
check(OllamaClient.codingModel(from: ["qwen2.5:7b", "qwen2.5-coder:14b"]) == "qwen2.5-coder:14b", "rule/coding routing prefers the coder model")
check(OllamaClient.codingModel(from: ["qwen2.5:7b", "llama3.2:3b"]) == "qwen2.5:7b", "no coder → best general model")
check(OllamaClient.codingModel(from: []) == nil, "coding model: no models → nil")

section("Category.isClearlySafe: regenerable categories only, never judgment calls")
check(Category.safeCache.isClearlySafe && Category.logs.isClearlySafe && Category.devArtifact.isClearlySafe && Category.trash.isClearlySafe && Category.appLeftover.isClearlySafe, "caches/logs/dev/trash/leftovers are clearly safe")
check(!Category.duplicate.isClearlySafe && !Category.largeOld.isClearlySafe && !Category.privacy.isClearlySafe && !Category.unknown.isClearlySafe, "duplicates/large-old/privacy/unknown need review")
check(OllamaClient.stripReasoning("<think>\nlet me reason\n</think>\n\nThe answer is 42.") == "\n\nThe answer is 42.", "strips a closed <think> block, keeps the answer")
check(OllamaClient.stripReasoning("No reasoning here.") == "No reasoning here.", "leaves normal content untouched")
check(OllamaClient.stripReasoning("<think>unterminated reasoning") == "", "drops an unterminated <think> block")

section("FileSizer: recursive allocated size, files and dirs, skips symlinks")
withTempDir { tmp in
    let dir = tmp.appendingPathComponent("d")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let f1 = makeFile(dir.appendingPathComponent("a.bin"), String(repeating: "x", count: 500))
    makeFile(dir.appendingPathComponent("sub/b.bin"), String(repeating: "y", count: 300))
    // a symlink pointing at a.bin must not be double-counted.
    try? fm.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: f1)
    let dirSize = FileSizer.size(of: dir)
    check(dirSize >= 800, "directory sums its regular files (got \(dirSize))")
    let fileSize = FileSizer.size(of: f1)
    check(fileSize >= 500 && fileSize < dirSize, "a single file returns its own size")
    check(FileSizer.size(of: tmp.appendingPathComponent("nope")) == 0, "missing path → 0, no crash")
}

section("DriveWear.parse: reads NVMe wear from smartctl JSON, honest when absent")
do {
    let json = Data(#"{"nvme_smart_health_information_log":{"percentage_used":7,"data_units_written":123456,"power_on_hours":1500}}"#.utf8)
    let w = DriveWear.parse(json)
    check(w.available && w.percentageUsed == 7 && w.powerOnHours == 1500, "parses percentage_used + power_on_hours")
    check(w.bytesWritten == 123456 * 512_000, "data_units_written converted (×512000 bytes)")
    check(!DriveWear.parse(Data("{}".utf8)).available, "no NVMe log → not available (no invented number)")
}

section("DuplicateAppFinder: version compare + keep-ranking")
do {
    check(DuplicateAppFinder.compareVersions("2.1.0", "2.0.9") == 1, "2.1.0 > 2.0.9")
    check(DuplicateAppFinder.compareVersions("1.0", "1.0.0") == 0, "1.0 == 1.0.0")
    check(DuplicateAppFinder.compareVersions("1.2", "1.10") == -1, "1.2 < 1.10 (numeric, not lexical)")
    let dl = AppCopy(url: URL(fileURLWithPath: "/x/Downloads/A.app"), version: "3.0", size: 100, location: "Downloads")
    let apps = AppCopy(url: URL(fileURLWithPath: "/Applications/A.app"), version: "2.0", size: 100, location: "Applications")
    check(DuplicateAppFinder.rank([dl, apps]).first?.location == "Applications", "keeps the /Applications copy first, even at a lower version")
    let a = AppCopy(url: URL(fileURLWithPath: "/x/A.app"), version: "2.0", size: 1, location: "Downloads")
    let b = AppCopy(url: URL(fileURLWithPath: "/y/A.app"), version: "1.0", size: 1, location: "Desktop")
    check(DuplicateAppFinder.rank([b, a]).first?.version == "2.0", "otherwise keeps the higher version")
}

section("PortAuditor.parse: reads listening ports past the trailing (LISTEN)")
do {
    let sample = """
    COMMAND     PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    node       4821 pysdenis   11u  IPv4 0xabc                0t0  TCP 127.0.0.1:3000 (LISTEN)
    ControlCe   622 pysdenis   10u  IPv4 0xdef                0t0  TCP *:7000 (LISTEN)
    """
    let ports = PortAuditor.parse(sample)
    check(ports.map(\.port) == [3000, 7000], "parses both ports past the (LISTEN) suffix, lowest first")
    check(ports.first?.process == "node" && ports.first?.pid == 4821, "process + pid parsed")
}

section("ConnectionAuditor.parse: established connections, deduped, sorted by process")
do {
    let sample = """
    COMMAND   PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    Safari   900 u 5u IPv4 0x1 0t0 TCP 10.0.0.2:5000->140.82.1.3:443 (ESTABLISHED)
    aria2    100 u 6u IPv4 0x2 0t0 TCP 10.0.0.2:5001->1.1.1.1:443 (ESTABLISHED)
    aria2    100 u 6u IPv4 0x2 0t0 TCP 10.0.0.2:5001->1.1.1.1:443 (ESTABLISHED)
    """
    let conns = ConnectionAuditor.parse(sample)
    check(conns.count == 2, "duplicate rows collapsed (got \(conns.count))")
    check(conns.first?.process == "aria2" && conns.first?.remote == "1.1.1.1:443", "sorted by process, remote parsed")
}

section("VaultVerifier: intact session passes, tampered/missing bytes trip the fire-drill")
withTempDir { tmp in
    let vaultRoot = tmp.appendingPathComponent("vault")
    let vault = VaultService(vaultRoot: vaultRoot)
    let victim = makeFile(tmp.appendingPathComponent("doc.txt"), "important")
    let sid = try vault.beginSession()
    let record = try vault.move(url: victim, session: sid)
    let clean = VaultVerifier(vault: vault).verifyAll()
    check(clean.first?.isRestorable == true, "freshly-vaulted session is restorable")
    // Tamper with the stored bytes.
    try Data("changed".utf8).write(to: URL(fileURLWithPath: record.vaultPath))
    let tampered = VaultVerifier(vault: vault).verifyAll()
    check(tampered.first?.isRestorable == false && tampered.first?.sizeMismatch.count == 1, "size mismatch detected")
    // Remove the stored bytes.
    try fm.removeItem(at: URL(fileURLWithPath: record.vaultPath))
    let gone = VaultVerifier(vault: vault).verifyAll()
    check(gone.first?.missing.count == 1, "missing stored bytes detected")
}

section("DriveWear.bootDevice + read: parse diskutil whole-disk, honest via stub")
do {
    let disk = StubRunner(responses: [
        "diskutil info /": "   Device Node: /dev/disk3s5\n   Part of Whole: disk3\n",
        "smartctl -A -j /dev/disk3": #"{"nvme_smart_health_information_log":{"percentage_used":11,"data_units_written":10,"power_on_hours":42}}"#,
    ])
    check(DriveWear.bootDevice(runner: disk) == "/dev/disk3", "boot device parsed from 'Part of Whole'")
    let w = DriveWear.read(runner: disk)
    check(w.available && w.percentageUsed == 11 && w.powerOnHours == 42, "read wires device → smartctl → parse")
    check(DriveWear.read(runner: StubRunner(responses: [:])).available == false, "no diskutil/smartctl → not available")
}

section("DeviceBackupFinder.readInfo: parses Info.plist fields")
withTempDir { tmp in
    let plist = tmp.appendingPathComponent("Info.plist")
    let dict: [String: Any] = ["Device Name": "Denis's iPhone", "Product Type": "iPhone14,2", "Last Backup Date": Date(timeIntervalSince1970: 1_700_000_000)]
    let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    try data.write(to: plist)
    let info = DeviceBackupFinder.readInfo(plist)
    check(info.name == "Denis's iPhone" && info.product == "iPhone14,2" && info.date != nil, "device name, model, date parsed")
    check(DeviceBackupFinder.readInfo(tmp.appendingPathComponent("nope")).name == nil, "missing plist → nils, no crash")
}

section("WhereFromReader: decodes the kMDItemWhereFroms xattr")
withTempDir { tmp in
    let file = makeFile(tmp.appendingPathComponent("dl.zip"), "x")
    let origins = ["https://example.com/dl.zip", "https://ref.example.com/"]
    let blob = try PropertyListSerialization.data(fromPropertyList: origins, format: .binary, options: 0)
    _ = blob.withUnsafeBytes { setxattr(file.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, blob.count, 0, 0) }
    check(WhereFromReader.origins(of: file) == origins, "reads both origin URLs from the xattr")
    check(WhereFromReader.source(of: makeFile(tmp.appendingPathComponent("plain.txt"), "y")) == nil, "no xattr → nil source")
}

section("SystemTweaker: reads state via runner, snapshots prior value for exact revert")
withTempDir { tmp in
    let store = tmp.appendingPathComponent("tweaks.json")
    let tweak = SystemTweaker.catalog.first { $0.id == "finder.pathbar" }!
    // Runner reports the key currently off ("0"); write/killall succeed (empty output).
    let tw = SystemTweaker(runner: StubRunner(responses: ["defaults read com.apple.finder ShowPathbar": "0"]), storeURL: store)
    check(tw.isEnabled(tweak) == false, "reads current state as off")
    check(tw.hasPrior(tweak) == false, "no prior recorded yet")
    tw.setEnabled(tweak, true)
    check(tw.hasPrior(tweak) == true, "turning on snapshots the prior value")
    tw.revert(tweak)
    check(tw.hasPrior(tweak) == false, "revert clears the prior-value record")
}

// MARK: - Summary

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)

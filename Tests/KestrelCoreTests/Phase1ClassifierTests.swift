import XCTest
@testable import KestrelCore

/// Coverage for the Phase 1 cleaning core: safety blacklist, marker-aware dev-artifact
/// detection, cache/log classification, large & old, duplicates, and the coordinator.
/// Mirrors the dependency-free runner in `Sources/kestrel-tests` for Xcode users.
final class Phase1ClassifierTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("kestrel-p1-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    @discardableResult
    private func file(_ path: String, _ contents: String = "x") throws -> URL {
        let url = tmp.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func dir(_ path: String) throws -> URL {
        let url = tmp.appendingPathComponent(path)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func classifyDir(_ url: URL) -> ClassifiedEntry {
        DevArtifactClassifier().classify(Scanner().makeEntry(url))
    }

    // MARK: - SafetyGuard

    func testSafetyGuardProtectsSensitivePaths() {
        XCTAssertTrue(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/.ssh/id_ed25519")))
        XCTAssertTrue(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/proj/.git")))
        XCTAssertTrue(SafetyGuard.isProtected(URL(fileURLWithPath: "/System/Library/Foo")))
        XCTAssertTrue(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/P.photoslibrary")))
        XCTAssertTrue(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/proj/package-lock.json")))
        XCTAssertFalse(SafetyGuard.isProtected(URL(fileURLWithPath: "/Users/x/Library/Caches/a/blob")))
    }

    func testPlannerDropsProtectedEvenIfClassifiedDeletable() {
        let git = FileEntry(url: tmp.appendingPathComponent(".git"), size: 100, modified: Date(), isDirectory: true)
        let classified = ClassifiedEntry(entry: git, category: .devArtifact, confidence: .high, reason: "misclassified")
        XCTAssertTrue(Planner().plan([classified]).items.isEmpty)
    }

    // MARK: - Dev artifacts

    func testDevArtifactRequiresMarkerForAmbiguousNames() throws {
        XCTAssertEqual(classifyDir(try dir("target")).category, .unknown)
        try file("rust/Cargo.toml", "[package]")
        let confirmed = classifyDir(try dir("rust/target"))
        XCTAssertEqual(confirmed.category, .devArtifact)
        XCTAssertEqual(confirmed.confidence, .high)
    }

    func testDevArtifactTrustsDistinctiveNames() throws {
        XCTAssertEqual(classifyDir(try dir("__pycache__")).confidence, .high)
    }

    func testDevArtifactNeverClaimsSource() throws {
        let src = try file("main.swift", "print()")
        XCTAssertEqual(DevArtifactClassifier().classify(Scanner().makeEntry(src)).category, .unknown)
    }

    // MARK: - Cache / log

    func testCacheAndLogClassification() {
        func c(_ p: String) -> Category {
            CacheLogClassifier().classify(FileEntry(url: URL(fileURLWithPath: p), size: 1, modified: Date(), isDirectory: false)).category
        }
        XCTAssertEqual(c("/Users/x/.npm/_cacache/i/a"), .safeCache)
        XCTAssertEqual(c("/Users/x/Library/Logs/app.log"), .logs)
        XCTAssertEqual(c("/Users/x/proj/debug.log"), .unknown, "stray project log left alone")
    }

    // MARK: - Large & old

    func testLargeOldIsReviewOnly() {
        let bigOld = FileEntry(url: tmp.appendingPathComponent("m.mov"), size: 500_000_000, modified: Date(timeIntervalSinceNow: -400 * 86400), isDirectory: false)
        let hit = LargeOldClassifier().classify(bigOld)
        XCTAssertEqual(hit.category, .largeOld)
        XCTAssertTrue(Planner().plan([hit]).items.isEmpty, "excluded from 'all'")
        XCTAssertEqual(Planner().plan([hit], categories: [.largeOld]).count, 1, "included when named")
    }

    // MARK: - Duplicates

    func testDuplicatesKeepOneOriginal() throws {
        let entries = try ["a.bin", "b.bin", "c.bin"].map { try Scanner().makeEntry(file($0, "same payload")) }
        let dupes = DuplicateFinder().find(in: entries)
        XCTAssertEqual(dupes.count, 2)
        XCTAssertTrue(dupes.allSatisfy { $0.category == .duplicate })
    }

    func testDuplicatesSeparatePartialHashCollisions() throws {
        let entries = try [try Scanner().makeEntry(file("a.bin", "abXX")), try Scanner().makeEntry(file("b.bin", "abYY"))]
        XCTAssertTrue(DuplicateFinder(partialBytes: 2).find(in: entries).isEmpty)
    }

    // MARK: - Coordinator

    func testCoordinatorFindsNestedArtifactsAndSkipsGit() throws {
        try file("project/package.json", #"{"name":"root"}"#)
        try file("project/node_modules/dep.js")
        try file("project/frontend/package.json", #"{"name":"fe"}"#)
        try file("project/frontend/node_modules/dep2.js")
        try file(".git/HEAD", "ref")

        let classified = try ScanCoordinator().scan(root: tmp)
        let devPaths = classified.filter { $0.category == .devArtifact }.map { $0.entry.url.path }
        XCTAssertEqual(devPaths.count, 2)
        XCTAssertTrue(devPaths.contains { $0.contains("frontend/node_modules") })
        XCTAssertFalse(classified.contains { $0.entry.url.path.contains("/.git/") })
    }

    // MARK: - External adapters

    func testDockerPreviewParsesReclaimable() {
        struct Stub: CommandRunner {
            func run(_ tool: String, _ arguments: [String]) throws -> String {
                let key = ([tool] + arguments).joined(separator: " ")
                if key == "docker --version" { return "Docker version 25.0" }
                return "Images\t1.2GB (60%)\nContainers\t0B (0%)\nBuild Cache\t512MB (100%)"
            }
        }
        let p = DockerAdapter(runner: Stub()).preview()
        XCTAssertTrue(p.available)
        XCTAssertEqual(p.reclaimableBytes, 1_712_000_000)
    }

    func testParseHumanBytes() {
        XCTAssertEqual(parseHumanBytes("1.2GB"), 1_200_000_000)
        XCTAssertEqual(parseHumanBytes("1KiB"), 1024)
        XCTAssertNil(parseHumanBytes("nonsense"))
    }
}

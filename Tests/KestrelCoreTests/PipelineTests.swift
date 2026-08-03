import XCTest
@testable import KestrelCore

final class PipelineTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("kestrel-pipe-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func makeDir(_ name: String, file: String) throws -> URL {
        let dir = tmp.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        return dir
    }

    func testPlannerIncludesDevArtifactsAndExcludesUnknown() throws {
        _ = try makeDir("node_modules", file: "index.js")
        try "src".write(to: tmp.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let entries = try Scanner().scanChildren(of: tmp)
        let classified = entries.map(RuleClassifier().classify)
        let plan = Planner().plan(classified)

        let names = plan.items.map { $0.entry.url.lastPathComponent }
        XCTAssertTrue(names.contains("node_modules"), "dev artifact must be planned")
        XCTAssertFalse(names.contains("main.swift"), "unknown source file must never be planned")
    }

    func testDryRunMovesNothing() throws {
        try "{}".write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8) // confirms 'build'
        let dir = try makeDir("build", file: "out.o")
        let entries = try Scanner().scanChildren(of: tmp)
        let plan = Planner().plan(entries.map(RuleClassifier().classify))

        let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
        let audit = AuditLog(url: tmp.appendingPathComponent("audit.log"))
        let result = try CleanupExecutor(vault: vault, audit: audit).execute(plan, apply: false)

        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertNil(result.sessionId)
        XCTAssertTrue(fm.fileExists(atPath: dir.path), "dry-run must not touch the filesystem")
    }

    func testApplyMovesToVaultAndAudits() throws {
        try "[package]".write(to: tmp.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8) // confirms 'target'
        let dir = try makeDir("target", file: "app")
        let entries = try Scanner().scanChildren(of: tmp)
        let plan = Planner().plan(entries.map(RuleClassifier().classify))

        let vault = VaultService(vaultRoot: tmp.appendingPathComponent("vault"))
        let auditURL = tmp.appendingPathComponent("audit.log")
        let audit = AuditLog(url: auditURL)
        let result = try CleanupExecutor(vault: vault, audit: audit).execute(plan, apply: true)

        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.movedCount, 1)
        XCTAssertFalse(fm.fileExists(atPath: dir.path), "applied item must leave its original path")

        let log = try audit.readAll()
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.action, "vault-move")
        XCTAssertEqual(log.first?.result, "ok")
    }
}

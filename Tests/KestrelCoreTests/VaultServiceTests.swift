import XCTest
@testable import KestrelCore

final class VaultServiceTests: XCTestCase {
    var tmp: URL!
    var vaultRoot: URL!
    var vault: VaultService!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("kestrel-test-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        vaultRoot = tmp.appendingPathComponent("vault")
        vault = VaultService(vaultRoot: vaultRoot)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func makeFile(_ name: String, contents: String = "hello") throws -> URL {
        let url = tmp.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testMoveRemovesOriginalAndStoresInVault() throws {
        let file = try makeFile("junk.txt")
        let session = try vault.beginSession()
        let record = try vault.move(url: file, session: session)

        XCTAssertFalse(fm.fileExists(atPath: file.path), "original must be gone after move")
        XCTAssertTrue(fm.fileExists(atPath: record.vaultPath), "file must exist in vault")
        XCTAssertEqual(record.originalPath, file.path)
        XCTAssertGreaterThan(record.size, 0)
    }

    func testUndoRestoresToOriginalPath() throws {
        let file = try makeFile("restore-me.txt", contents: "important")
        let session = try vault.beginSession()
        try vault.move(url: file, session: session)
        XCTAssertFalse(fm.fileExists(atPath: file.path))

        let restored = try vault.undo(session: session)
        XCTAssertEqual(restored, 1)
        XCTAssertTrue(fm.fileExists(atPath: file.path), "file must be back at original path")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "important")
    }

    func testUndoDoesNotOverwriteExistingFile() throws {
        let file = try makeFile("conflict.txt", contents: "original")
        let session = try vault.beginSession()
        try vault.move(url: file, session: session)
        // Recreate a file at the original path.
        try "new".write(to: file, atomically: true, encoding: .utf8)

        _ = try vault.undo(session: session)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "new", "undo must not clobber an existing file")
    }

    func testMoveMissingSourceThrows() throws {
        let session = try vault.beginSession()
        let missing = tmp.appendingPathComponent("nope.txt")
        XCTAssertThrowsError(try vault.move(url: missing, session: session)) { error in
            XCTAssertEqual(error as? VaultError, .sourceMissing(missing.path))
        }
    }

    func testMoveDirectoryComputesRecursiveSize() throws {
        let dir = tmp.appendingPathComponent("node_modules")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "aaaa".write(to: dir.appendingPathComponent("a.js"), atomically: true, encoding: .utf8)
        try "bbbb".write(to: dir.appendingPathComponent("b.js"), atomically: true, encoding: .utf8)

        let session = try vault.beginSession()
        let record = try vault.move(url: dir, session: session)
        XCTAssertEqual(record.size, 8)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
    }

    func testPurgeRemovesOldSessionsOnly() throws {
        let old = try vault.beginSession(id: "old", createdAt: Date(timeIntervalSinceNow: -1000))
        let recent = try vault.beginSession(id: "recent", createdAt: Date())

        let purged = try vault.purge(olderThan: 500)
        XCTAssertEqual(purged.map(\.id), ["old"])

        let remaining = try vault.listSessions().map(\.id)
        XCTAssertEqual(remaining, ["recent"])
        _ = old; _ = recent
    }
}

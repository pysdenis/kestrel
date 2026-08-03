import XCTest
@testable import KestrelCore

final class AuditLogTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("kestrel-audit-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    func testAppendAndReadRoundTrip() throws {
        let log = AuditLog(url: tmp.appendingPathComponent("nested/audit.log"))
        try log.append(AuditEntry(action: "scan", paths: ["/a"], bytes: 10, result: "ok"))
        try log.append(AuditEntry(action: "vault-move", paths: ["/b"], bytes: 20, result: "ok", sessionId: "s1"))

        let all = try log.readAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].action, "scan")
        XCTAssertEqual(all[1].sessionId, "s1")
        XCTAssertEqual(all[1].bytes, 20)
    }

    func testReadEmptyLogReturnsNothing() throws {
        let log = AuditLog(url: tmp.appendingPathComponent("audit.log"))
        XCTAssertEqual(try log.readAll().count, 0)
    }
}

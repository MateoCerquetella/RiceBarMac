import Foundation
import XCTest
@testable import RiceBarMac

final class LegacyMigrationTests: XCTestCase {
    func testDetectionIsReadOnlyAndMigrationPreservesSource() throws {
        let home = try TemporaryHome()
        let source = try home.createDirectory(".ricebar/profiles/Legacy/home")
        try Data("legacy".utf8).write(to: source.appendingPathComponent("config"))
        let service = LegacyMigrationService(home: home.url)

        guard case .available = service.availability() else {
            return XCTFail("Expected a migration offer")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.url.appendingPathComponent(".ricebarmac").path))

        let record = try service.migrate()

        XCTAssertEqual(record.status, .committed)
        XCTAssertEqual(String(data: try Data(contentsOf: source.appendingPathComponent("config")), encoding: .utf8), "legacy")
        XCTAssertEqual(
            String(data: try Data(contentsOf: home.url.appendingPathComponent(".ricebarmac/profiles/Legacy/home/config")), encoding: .utf8),
            "legacy"
        )
    }

    func testExistingCurrentDataProducesConflictWithoutWrites() throws {
        let home = try TemporaryHome()
        _ = try home.write(".ricebar/profiles/Legacy/profile.json", #"{"name":"Legacy"}"#)
        let current = try home.write(".ricebarmac/config.json", "current")
        let service = LegacyMigrationService(home: home.url)

        guard case .conflict = service.availability() else {
            return XCTFail("Expected conflict")
        }
        XCTAssertThrowsError(try service.migrate())
        XCTAssertEqual(String(data: try Data(contentsOf: current), encoding: .utf8), "current")
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.url.appendingPathComponent(".ricebar/profiles/Legacy/profile.json").path))
    }

    func testFinalJournalFailureReportsCommittedMigrationWarning() throws {
        let home = try TemporaryHome()
        let source = try home.createDirectory(".ricebar/profiles/Legacy/home")
        try Data("legacy".utf8).write(to: source.appendingPathComponent("config"))
        let fileSystem = FaultInjectingFileSystemClient()
        fileSystem.failAtMutation = 5
        let service = LegacyMigrationService(home: home.url, fileSystem: fileSystem)

        let record = try service.migrate()

        XCTAssertEqual(record.status, .committedWithWarnings)
        XCTAssertNotNil(record.errorDescription)
        XCTAssertEqual(
            String(
                data: try Data(contentsOf: home.url.appendingPathComponent(".ricebarmac/profiles/Legacy/home/config")),
                encoding: .utf8
            ),
            "legacy"
        )
        XCTAssertEqual(String(data: try Data(contentsOf: source.appendingPathComponent("config")), encoding: .utf8), "legacy")
    }
}

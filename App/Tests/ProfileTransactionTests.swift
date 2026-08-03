import Foundation
import XCTest
@testable import RiceBarMac

final class ProfileTransactionTests: XCTestCase {
    func testApplyBacksUpAndUndoRestoresExactFile() async throws {
        let home = try TemporaryHome()
        let destination = try home.write(".config/app.conf", "original")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let activeStore = MemoryActiveProfileStore("/former/profile")
        let planner = ProfilePlanner(home: home.url, fileSystem: fileSystem)
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, activeStore: activeStore)
        let plan = planner.makePlan(for: descriptor, formerActiveProfilePath: activeStore.loadActiveProfilePath())

        let outcome = try await executor.apply(plan)

        XCTAssertEqual(try fileSystem.state(at: destination).kind, .symbolicLink)
        XCTAssertEqual(activeStore.loadActiveProfilePath(), descriptor.directory.path)
        let backup = URL(fileURLWithPath: plan.actions.last!.backupPath)
        XCTAssertEqual(String(data: try Data(contentsOf: backup), encoding: .utf8), "original")

        let undone = try executor.undoLatest()

        XCTAssertEqual(undone.status, .undone)
        XCTAssertEqual(String(data: try Data(contentsOf: destination), encoding: .utf8), "original")
        let permissions = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(activeStore.loadActiveProfilePath(), "/former/profile")
        XCTAssertThrowsError(try executor.undoLatest())
        XCTAssertEqual(outcome.transaction.id, undone.id)
    }

    func testBrokenSymlinkIsRestoredByUndo() async throws {
        let home = try TemporaryHome()
        let destination = home.url.appendingPathComponent(".config/broken")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: "missing-target")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem).makePlan(for: descriptor, formerActiveProfilePath: nil)

        _ = try await executor.apply(plan)
        _ = try executor.undoLatest()

        XCTAssertEqual(try fileSystem.state(at: destination).kind, .symbolicLink)
        XCTAssertEqual(try fileSystem.state(at: destination).symlinkTarget, "missing-target")
    }

    func testPostApplyUserChangeBlocksUndoAndRetainsBackup() async throws {
        let home = try TemporaryHome()
        let destination = try home.write(".config/app.conf", "original")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem).makePlan(for: descriptor, formerActiveProfilePath: nil)
        _ = try await executor.apply(plan)
        try fileSystem.removeItem(at: destination)
        try Data("user-change".utf8).write(to: destination)

        XCTAssertThrowsError(try executor.undoLatest()) { error in
            XCTAssertTrue(error is TransactionExecutionError)
        }
        XCTAssertEqual(String(data: try Data(contentsOf: destination), encoding: .utf8), "user-change")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.actions.last!.backupPath))
    }

    func testInjectedFailuresRestoreOriginalDestination() async throws {
        for boundary in 1...14 {
            let home = try TemporaryHome()
            let destination = try home.write(".config/app.conf", "original")
            let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
            let fileSystem = FaultInjectingFileSystemClient()
            fileSystem.failAtMutation = boundary
            let planner = ProfilePlanner(home: home.url, fileSystem: fileSystem)
            let plan = planner.makePlan(for: descriptor, formerActiveProfilePath: nil)
            let executor = makeExecutor(home: home.url, fileSystem: fileSystem)

            do {
                _ = try await executor.apply(plan)
            } catch {
                let state = try fileSystem.state(at: destination)
                XCTAssertEqual(state.kind, .regularFile, "boundary \(boundary): \(error)")
                XCTAssertEqual(String(data: try Data(contentsOf: destination), encoding: .utf8), "original", "boundary \(boundary)")
            }
        }
    }

    func testExternalFailureDoesNotRollbackCommittedFilesystem() async throws {
        let home = try TemporaryHome()
        let destination = try home.write(".config/app.conf", "original")
        let originalDescriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let script = try home.write(".ricebarmac/profiles/Test/start.sh", "exit 1")
        var profile = originalDescriptor.profile
        profile.startupScript = script.lastPathComponent
        let descriptor = ProfileDescriptor(profile: profile, directory: originalDescriptor.directory)
        let fileSystem = LiveFileSystemClient()
        let external = RecordingExternalEffectClient(failingKinds: [.startupScript])
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, externalEffects: external)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem).makePlan(for: descriptor, formerActiveProfilePath: nil)

        let outcome = try await executor.apply(plan)

        XCTAssertEqual(outcome.transaction.status, .committedWithWarnings)
        XCTAssertFalse(outcome.warnings.isEmpty)
        XCTAssertEqual(try fileSystem.state(at: destination).kind, .symbolicLink)
    }

    func testFinalJournalFailureReportsWarningWithoutRollingBackCommit() async throws {
        let home = try TemporaryHome()
        let destination = try home.write(".config/app.conf", "original")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let store = FaultInjectingTransactionStore()
        store.failAtSave = 7
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, transactionStore: store)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem).makePlan(for: descriptor, formerActiveProfilePath: nil)

        let outcome = try await executor.apply(plan)

        XCTAssertEqual(outcome.transaction.status, .committedWithWarnings)
        XCTAssertTrue(outcome.warnings.contains(where: { $0.contains("final transaction journal") }))
        XCTAssertEqual(try fileSystem.state(at: destination).kind, .symbolicLink)
        XCTAssertNotNil(try store.latestUndoable())
    }
}

import Foundation
import XCTest
@testable import RiceBarMac

final class ProfileTransactionTests: XCTestCase {
    func testExternalProcessDrainsLargeErrorOutputWithoutBlocking() async throws {
        let home = try TemporaryHome()
        let script = try home.write("noisy-startup.zsh", """
        for i in {1..20000}; do
          print -u2 -- 'RiceBarMac external-effect output must be drained while the process is running.'
        done
        """)
        let effect = ProfileExternalEffect(
            id: UUID(),
            kind: .startupScript,
            path: script.path,
            arguments: []
        )

        try await LiveExternalEffectClient().perform(effect)
    }

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

    func testUndoPreservesFilesAddedToCreatedDirectoryAndRecoveryIsRetryable() async throws {
        let home = try TemporaryHome()
        let generatedDirectory = home.url.appendingPathComponent(".config/generated", isDirectory: true)
        let destination = generatedDirectory.appendingPathComponent("app.conf")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let store = MemoryTransactionStore()
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, transactionStore: store)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem)
            .makePlan(for: descriptor, formerActiveProfilePath: nil)
        let outcome = try await executor.apply(plan)
        let userFile = try home.write(".config/generated/user-created.txt", "keep-me")

        do {
            _ = try executor.undoLatest()
            XCTFail("Undo must not recursively remove a directory containing new user data")
        } catch let error as TransactionExecutionError {
            guard case .recoveryRequired(let paths, _) = error else {
                return XCTFail("Expected recoveryRequired, received \(error)")
            }
            XCTAssertTrue(paths.contains(generatedDirectory.path))
        }

        XCTAssertEqual(String(data: try Data(contentsOf: userFile), encoding: .utf8), "keep-me")
        XCTAssertEqual(try fileSystem.state(at: destination).kind, .absent)
        XCTAssertEqual(try store.incompleteTransactions().first?.status, .recoveryRequired)

        try fileSystem.removeItem(at: userFile)
        let recovered = try executor.recover(transactionID: outcome.transaction.id)

        XCTAssertEqual(recovered.status, .rolledBack)
        XCTAssertTrue(recovered.unresolvedPaths.isEmpty)
        XCTAssertEqual(try fileSystem.state(at: generatedDirectory).kind, .absent)
        XCTAssertTrue(try store.incompleteTransactions().isEmpty)
    }

    func testRecoveryPreservesExternalDirectoryAfterIntentCheckpoint() throws {
        let home = try TemporaryHome()
        let destination = home.url.appendingPathComponent(".config/generated/app.conf")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let store = MemoryTransactionStore()
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, transactionStore: store)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem)
            .makePlan(for: descriptor, formerActiveProfilePath: nil)
        guard let index = plan.actions.firstIndex(where: { $0.kind == .createDirectory }) else {
            return XCTFail("Expected a planned directory creation")
        }
        let createdDirectory = URL(fileURLWithPath: plan.actions[index].destinationPath, isDirectory: true)
        try fileSystem.createDirectory(at: createdDirectory)

        var transaction = ApplyTransaction(plan: plan)
        transaction.status = .executing
        transaction.actions[index].status = .intentRecorded
        try store.save(transaction)

        let recovered = try executor.recover(transactionID: transaction.id)

        XCTAssertEqual(recovered.status, .rolledBack)
        XCTAssertEqual(try fileSystem.state(at: createdDirectory).kind, .directory)
        XCTAssertTrue(try store.incompleteTransactions().isEmpty)
    }

    func testRecoveryCompletesStagedDirectoryMoveAfterCrash() throws {
        let home = try TemporaryHome()
        let destination = home.url.appendingPathComponent(".config/generated/app.conf")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let store = MemoryTransactionStore()
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, transactionStore: store)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem)
            .makePlan(for: descriptor, formerActiveProfilePath: nil)
        guard let index = plan.actions.firstIndex(where: { $0.kind == .createDirectory }) else {
            return XCTFail("Expected a planned directory creation")
        }
        let createdDirectory = URL(fileURLWithPath: plan.actions[index].destinationPath, isDirectory: true)
        try fileSystem.createDirectory(at: createdDirectory)

        var transaction = ApplyTransaction(plan: plan)
        transaction.status = .executing
        transaction.actions[index].status = .staged
        transaction.actions[index].installedFingerprint = try fileSystem.state(at: createdDirectory).fingerprint
        try store.save(transaction)

        let recovered = try executor.recover(transactionID: transaction.id)

        XCTAssertEqual(recovered.status, .rolledBack)
        XCTAssertEqual(try fileSystem.state(at: createdDirectory).kind, .absent)
        XCTAssertTrue(try store.incompleteTransactions().isEmpty)
    }

    func testRecoveryPreservesAmbiguousStageCreatedAfterIntentCheckpoint() throws {
        let home = try TemporaryHome()
        let destination = home.url.appendingPathComponent(".config/generated/app.conf")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let store = MemoryTransactionStore()
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, transactionStore: store)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem)
            .makePlan(for: descriptor, formerActiveProfilePath: nil)
        guard let index = plan.actions.firstIndex(where: { $0.kind == .createDirectory }) else {
            return XCTFail("Expected a planned directory creation")
        }
        let ambiguousStage = URL(fileURLWithPath: plan.actions[index].stagingPath, isDirectory: true)
        try fileSystem.createDirectory(at: ambiguousStage)

        var transaction = ApplyTransaction(plan: plan)
        transaction.status = .executing
        transaction.actions[index].status = .intentRecorded
        try store.save(transaction)

        XCTAssertThrowsError(try executor.recover(transactionID: transaction.id))
        XCTAssertEqual(try fileSystem.state(at: ambiguousStage).kind, .directory)
        XCTAssertEqual(try store.load(id: transaction.id)?.status, .recoveryRequired)
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

    func testStalePlanBeforeFirstMutationRollsBackWithoutRecoveryState() async throws {
        let home = try TemporaryHome()
        let destination = home.url.appendingPathComponent(".config/app.conf")
        let descriptor = try makeProfileDescriptor(home: home.url, replacementDestination: destination)
        let fileSystem = LiveFileSystemClient()
        let store = MemoryTransactionStore()
        let executor = makeExecutor(home: home.url, fileSystem: fileSystem, transactionStore: store)
        let plan = ProfilePlanner(home: home.url, fileSystem: fileSystem).makePlan(for: descriptor, formerActiveProfilePath: nil)
        _ = try home.createDirectory(".config")

        do {
            _ = try await executor.apply(plan)
            XCTFail("Expected stale-plan rejection")
        } catch let error as FileSystemClientError {
            guard case .stalePath = error else {
                return XCTFail("Expected stalePath, received \(error)")
            }
        }

        XCTAssertEqual(try fileSystem.state(at: destination).kind, .absent)
        XCTAssertTrue(try store.incompleteTransactions().isEmpty)
        XCTAssertEqual(try store.loadAll().first?.status, .rolledBack)
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

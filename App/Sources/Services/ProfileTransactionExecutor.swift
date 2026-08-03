import Foundation

enum TransactionExecutionError: LocalizedError {
    case invalidPlan([ProfilePlanIssue])
    case noUndoAvailable
    case transactionNotFound(UUID)
    case recoveryRequired(paths: [String], cause: String)

    var errorDescription: String? {
        switch self {
        case .invalidPlan(let issues):
            return issues.map(\.message).joined(separator: "\n")
        case .noUndoAvailable:
            return "There is no completed profile transaction available to undo."
        case .transactionNotFound(let id):
            return "Transaction \(id.uuidString) was not found."
        case .recoveryRequired(let paths, let cause):
            let pathList = paths.isEmpty ? "unknown paths" : paths.joined(separator: ", ")
            return "Automatic recovery could not finish for \(pathList). \(cause)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .recoveryRequired:
            return "Keep the transaction journal and .ricebarmac-backup files. Open the recovery details before changing the affected paths."
        default:
            return nil
        }
    }
}

final class ProfileTransactionExecutor: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (_ completed: Int, _ total: Int, _ message: String) -> Void

    private let fileSystem: FileSystemClient
    private let transactionStore: TransactionStoring
    private let activeProfileStore: ActiveProfilePersisting
    private let externalEffects: ExternalEffectClient
    private let now: @Sendable () -> Date

    init(
        fileSystem: FileSystemClient,
        transactionStore: TransactionStoring,
        activeProfileStore: ActiveProfilePersisting,
        externalEffects: ExternalEffectClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileSystem = fileSystem
        self.transactionStore = transactionStore
        self.activeProfileStore = activeProfileStore
        self.externalEffects = externalEffects
        self.now = now
    }

    func apply(
        _ plan: ProfileApplyPlan,
        progress: @escaping ProgressHandler = { _, _, _ in }
    ) async throws -> ProfileApplyOutcome {
        guard plan.isValid else { throw TransactionExecutionError.invalidPlan(plan.issues) }
        var transaction = ApplyTransaction(plan: plan, now: now())
        try persist(&transaction, status: .executing)

        do {
            for index in transaction.actions.indices {
                try Task.checkCancellation()
                progress(index, transaction.actions.count, transaction.actions[index].action.displaySummary)
                try executeAction(at: index, transaction: &transaction)
            }
            try persist(&transaction, status: .committed)
            activeProfileStore.saveActiveProfilePath(plan.profileDirectoryPath)
        } catch {
            let original = error
            do {
                try restoreActions(in: &transaction, actionStatus: .rolledBack)
                try persist(&transaction, status: .rolledBack, error: original.localizedDescription)
            } catch let rollbackError {
                let paths = transaction.unresolvedPaths
                try? persist(&transaction, status: .recoveryRequired, error: rollbackError.localizedDescription)
                throw TransactionExecutionError.recoveryRequired(
                    paths: paths,
                    cause: "Apply failed with '\(original.localizedDescription)'; rollback failed with '\(rollbackError.localizedDescription)'."
                )
            }
            throw original
        }

        var warnings: [String] = []
        var checkpointWarning: String?
        for effect in plan.externalEffects {
            if Task.isCancelled {
                let warning = "Skipped \(effect.displaySummary) because cancellation was requested after commit."
                warnings.append(warning)
                transaction.externalEffects.append(
                    ExternalEffectResult(id: effect.id, effect: effect, succeeded: false, errorDescription: warning)
                )
                continue
            }
            do {
                try await externalEffects.perform(effect)
                transaction.externalEffects.append(
                    ExternalEffectResult(id: effect.id, effect: effect, succeeded: true, errorDescription: nil)
                )
            } catch {
                let warning = "\(effect.displaySummary): \(error.localizedDescription)"
                warnings.append(warning)
                transaction.externalEffects.append(
                    ExternalEffectResult(id: effect.id, effect: effect, succeeded: false, errorDescription: error.localizedDescription)
                )
            }
            transaction.updatedAt = now()
            do {
                try transactionStore.save(transaction)
            } catch {
                checkpointWarning = "A post-commit journal checkpoint could not be written: \(error.localizedDescription)"
            }
        }

        if let checkpointWarning {
            warnings.append(checkpointWarning)
        }

        transaction.status = warnings.isEmpty ? .committed : .committedWithWarnings
        transaction.errorDescription = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        transaction.updatedAt = now()
        do {
            try transactionStore.save(transaction)
        } catch {
            let warning = "The profile was committed, but its final transaction journal could not be updated: \(error.localizedDescription)"
            warnings.append(warning)
            transaction.status = .committedWithWarnings
            transaction.errorDescription = warnings.joined(separator: "\n")
        }
        progress(transaction.actions.count, transaction.actions.count, warnings.isEmpty ? "Profile applied" : "Profile applied with warnings")
        return ProfileApplyOutcome(transaction: transaction, warnings: warnings)
    }

    func undoLatest(progress: @escaping ProgressHandler = { _, _, _ in }) throws -> ApplyTransaction {
        guard var transaction = try transactionStore.latestUndoable() else {
            throw TransactionExecutionError.noUndoAvailable
        }
        try persist(&transaction, status: .undoing)
        progress(0, transaction.actions.count, "Preparing Undo")

        do {
            try restoreActions(in: &transaction, actionStatus: .restored) { completed, total, message in
                progress(completed, total, message)
            }
            activeProfileStore.saveActiveProfilePath(transaction.plan.formerActiveProfilePath)
            try persist(&transaction, status: .undone)
            progress(transaction.actions.count, transaction.actions.count, "Undo complete")
            return transaction
        } catch {
            try? persist(&transaction, status: .recoveryRequired, error: error.localizedDescription)
            throw TransactionExecutionError.recoveryRequired(
                paths: transaction.unresolvedPaths,
                cause: error.localizedDescription
            )
        }
    }

    func recover(transactionID: UUID, progress: @escaping ProgressHandler = { _, _, _ in }) throws -> ApplyTransaction {
        guard var transaction = try transactionStore.load(id: transactionID) else {
            throw TransactionExecutionError.transactionNotFound(transactionID)
        }
        do {
            try restoreActions(in: &transaction, actionStatus: .rolledBack) { completed, total, message in
                progress(completed, total, message)
            }
            activeProfileStore.saveActiveProfilePath(transaction.plan.formerActiveProfilePath)
            try persist(&transaction, status: .rolledBack)
            return transaction
        } catch {
            try? persist(&transaction, status: .recoveryRequired, error: error.localizedDescription)
            throw TransactionExecutionError.recoveryRequired(paths: transaction.unresolvedPaths, cause: error.localizedDescription)
        }
    }

    func incompleteTransactions() throws -> [ApplyTransaction] {
        try transactionStore.incompleteTransactions()
    }

    func latestUndoable() throws -> ApplyTransaction? {
        try transactionStore.latestUndoable()
    }

    private func executeAction(at index: Int, transaction: inout ApplyTransaction) throws {
        let action = transaction.actions[index].action
        transaction.actions[index].status = .intentRecorded
        try persist(&transaction)

        let safety = PathSafetyValidator(home: URL(fileURLWithPath: transaction.plan.userHomePath), fileSystem: fileSystem)
        guard try safety.parentFingerprintsStillMatch(action.parentFingerprints) else {
            throw FileSystemClientError.stalePath(action.destinationPath)
        }

        if let sourcePath = action.sourcePath, let expectedSource = action.sourceState {
            let currentSource = try fileSystem.state(at: URL(fileURLWithPath: sourcePath))
            guard statesMatch(currentSource, expectedSource) else {
                throw FileSystemClientError.stalePath(sourcePath)
            }
        }

        let destination = URL(fileURLWithPath: action.destinationPath)
        let backup = URL(fileURLWithPath: action.backupPath)
        let stage = URL(fileURLWithPath: action.stagingPath)
        let currentDestination = try fileSystem.state(at: destination)
        guard statesMatch(currentDestination, action.beforeState) else {
            throw FileSystemClientError.stalePath(destination.path)
        }
        guard try fileSystem.state(at: backup).kind == .absent,
              try fileSystem.state(at: stage).kind == .absent else {
            throw FileSystemClientError.collision(destination.path)
        }

        if action.kind == .createDirectory {
            try fileSystem.createDirectory(at: destination)
            transaction.actions[index].installedFingerprint = try fileSystem.state(at: destination).fingerprint
            transaction.actions[index].status = .replacementInstalled
            try persist(&transaction)
            return
        }

        if action.kind != .remove {
            switch action.kind {
            case .replaceWithSymlink:
                guard let sourcePath = action.sourcePath else {
                    throw FileSystemClientError.unsupportedObject(destination.path)
                }
                try fileSystem.createSymbolicLink(at: stage, pointingTo: URL(fileURLWithPath: sourcePath))
            case .replaceWithCopy:
                guard let sourcePath = action.sourcePath else {
                    throw FileSystemClientError.unsupportedObject(destination.path)
                }
                try fileSystem.copyItem(at: URL(fileURLWithPath: sourcePath), to: stage)
            case .writeData:
                guard let data = action.data else {
                    throw FileSystemClientError.unsupportedObject(destination.path)
                }
                try fileSystem.writeDataAtomically(data, to: stage)
                if let permissions = action.beforeState.permissions {
                    try fileSystem.setPermissions(permissions, at: stage)
                }
            case .createDirectory, .remove:
                break
            }
            transaction.actions[index].status = .staged
            try persist(&transaction)
        }

        if action.beforeState.exists {
            try fileSystem.moveItem(at: destination, to: backup)
            transaction.actions[index].status = .backupCreated
            try persist(&transaction)
        }

        if action.kind != .remove {
            try fileSystem.moveItem(at: stage, to: destination)
        }
        transaction.actions[index].installedFingerprint = try fileSystem.state(at: destination).fingerprint
        transaction.actions[index].status = .replacementInstalled
        try persist(&transaction)
    }

    private func restoreActions(
        in transaction: inout ApplyTransaction,
        actionStatus: TransactionActionRecord.Status,
        progress: ProgressHandler = { _, _, _ in }
    ) throws {
        transaction.status = actionStatus == .restored ? .undoing : .rollingBack
        transaction.updatedAt = now()
        try transactionStore.save(transaction)

        var failures: [String] = []
        let indices = Array(transaction.actions.indices.reversed())

        for (offset, index) in indices.enumerated() {
            let action = transaction.actions[index].action
            progress(offset, indices.count, "Restoring \(action.destinationPath)")
            do {
                try restoreAction(at: index, transaction: &transaction, finalStatus: actionStatus)
            } catch {
                transaction.actions[index].errorDescription = error.localizedDescription
                if !transaction.unresolvedPaths.contains(action.destinationPath) {
                    transaction.unresolvedPaths.append(action.destinationPath)
                }
                failures.append("\(action.destinationPath): \(error.localizedDescription)")
                transaction.updatedAt = now()
                try? transactionStore.save(transaction)
            }
        }

        guard failures.isEmpty else {
            throw TransactionExecutionError.recoveryRequired(
                paths: transaction.unresolvedPaths,
                cause: failures.joined(separator: "\n")
            )
        }
    }

    private func restoreAction(
        at index: Int,
        transaction: inout ApplyTransaction,
        finalStatus: TransactionActionRecord.Status
    ) throws {
        let record = transaction.actions[index]
        let action = record.action
        let destination = URL(fileURLWithPath: action.destinationPath)
        let backup = URL(fileURLWithPath: action.backupPath)
        let stage = URL(fileURLWithPath: action.stagingPath)

        if record.status == .pending {
            transaction.actions[index].status = finalStatus
            transaction.actions[index].errorDescription = nil
            transaction.updatedAt = now()
            try transactionStore.save(transaction)
            return
        }

        if try fileSystem.state(at: stage).exists {
            try fileSystem.removeItem(at: stage)
        }

        let backupExists = try fileSystem.state(at: backup).exists

        if record.status == .intentRecorded,
           record.installedFingerprint == nil,
           !backupExists {
            transaction.actions[index].status = finalStatus
            transaction.actions[index].errorDescription = nil
            transaction.updatedAt = now()
            try transactionStore.save(transaction)
            return
        }

        let current = try fileSystem.state(at: destination)

        if let installed = record.installedFingerprint {
            if action.beforeState.exists && !backupExists {
                throw FileSystemClientError.stalePath(backup.path)
            }
            guard fingerprintsMatch(current.fingerprint, installed) else {
                throw FileSystemClientError.stalePath(destination.path)
            }
            if current.exists {
                try fileSystem.removeItem(at: destination)
            }
        } else if backupExists {
            guard current.kind == .absent else {
                throw FileSystemClientError.stalePath(destination.path)
            }
        } else if !statesMatch(current, action.beforeState) {
            throw FileSystemClientError.stalePath(destination.path)
        }

        if backupExists {
            guard try fileSystem.state(at: destination).kind == .absent else {
                throw FileSystemClientError.stalePath(destination.path)
            }
            try fileSystem.moveItem(at: backup, to: destination)
            let restored = try fileSystem.state(at: destination)
            guard statesMatch(restored, action.beforeState) else {
                throw FileSystemClientError.stalePath(destination.path)
            }
        }

        transaction.actions[index].status = finalStatus
        transaction.actions[index].errorDescription = nil
        transaction.updatedAt = now()
        try transactionStore.save(transaction)
    }

    private func persist(
        _ transaction: inout ApplyTransaction,
        status: ApplyTransaction.Status? = nil,
        error: String? = nil
    ) throws {
        if let status { transaction.status = status }
        transaction.errorDescription = error
        transaction.updatedAt = now()
        try transactionStore.save(transaction)
    }

    private func statesMatch(_ current: FileObjectState, _ expected: FileObjectState) -> Bool {
        fingerprintsMatch(current.fingerprint, expected.fingerprint) && current.permissions == expected.permissions
    }

    private func fingerprintsMatch(_ current: PathFingerprint, _ expected: PathFingerprint) -> Bool {
        guard current.kind == expected.kind,
              current.device == expected.device,
              current.inode == expected.inode,
              current.symlinkTarget == expected.symlinkTarget else {
            return false
        }
        switch expected.kind {
        case .directory, .absent:
            return true
        case .symbolicLink:
            return current.symlinkTarget == expected.symlinkTarget
        case .regularFile, .other:
            return current.size == expected.size && current.modificationDate == expected.modificationDate
        }
    }
}

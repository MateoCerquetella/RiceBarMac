import Foundation

actor ProfileApplicationCoordinator {
    typealias StateHandler = @Sendable (ProfileOperationSnapshot) -> Void

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    private let planner: ProfilePlanner
    private let executor: ProfileTransactionExecutor
    private let activeProfileStore: ActiveProfilePersisting
    private var isBusy = false
    private var waiters: [Waiter] = []
    private var stateHandler: StateHandler?
    private(set) var snapshot: ProfileOperationSnapshot = .idle

    init(
        planner: ProfilePlanner,
        executor: ProfileTransactionExecutor,
        activeProfileStore: ActiveProfilePersisting
    ) {
        self.planner = planner
        self.executor = executor
        self.activeProfileStore = activeProfileStore
    }

    func setStateHandler(_ handler: StateHandler?) {
        stateHandler = handler
        handler?(snapshot)
    }

    func preview(_ descriptor: ProfileDescriptor) async throws -> ProfileApplyPlan {
        let requestID = UUID()
        await acquire(requestID: requestID, operation: "Preview")
        defer { release() }
        try Task.checkCancellation()

        do {
            try ensureRecoveryIsComplete()
        } catch {
            let paths = recoveryPaths(from: error)
            publish(ProfileOperationSnapshot(
                phase: .recoveryRequired,
                message: error.localizedDescription,
                completedActions: 0,
                totalActions: 0,
                queuePosition: nil,
                transactionID: nil,
                affectedPaths: paths
            ))
            throw error
        }

        publish(ProfileOperationSnapshot(
            phase: .previewing,
            message: "Validating \(descriptor.displayName)",
            completedActions: 0,
            totalActions: 0,
            queuePosition: nil,
            transactionID: nil,
            affectedPaths: []
        ))

        let plan = planner.makePlan(
            for: descriptor,
            formerActiveProfilePath: activeProfileStore.loadActiveProfilePath()
        )
        if plan.isValid {
            publish(ProfileOperationSnapshot(
                phase: .ready,
                message: "Preview ready for \(descriptor.displayName)",
                completedActions: 0,
                totalActions: plan.actions.count,
                queuePosition: nil,
                transactionID: plan.id,
                affectedPaths: plan.actions.map(\.destinationPath)
            ))
        } else {
            publish(ProfileOperationSnapshot(
                phase: .failed,
                message: plan.issues.map(\.message).joined(separator: "\n"),
                completedActions: 0,
                totalActions: plan.actions.count,
                queuePosition: nil,
                transactionID: plan.id,
                affectedPaths: plan.issues.compactMap(\.affectedPath)
            ))
        }
        return plan
    }

    func apply(_ plan: ProfileApplyPlan) async throws -> ProfileApplyOutcome {
        let requestID = UUID()
        await acquire(requestID: requestID, operation: "Apply")
        defer { release() }
        try Task.checkCancellation()

        let handler = stateHandler
        let outcome: ProfileApplyOutcome
        do {
            try ensureRecoveryIsComplete()
            publish(ProfileOperationSnapshot(
                phase: .applying,
                message: "Applying \(plan.profileName)",
                completedActions: 0,
                totalActions: plan.actions.count,
                queuePosition: nil,
                transactionID: plan.id,
                affectedPaths: plan.actions.map(\.destinationPath)
            ))
            outcome = try await executor.apply(plan) { completed, total, message in
                handler?(ProfileOperationSnapshot(
                    phase: .applying,
                    message: message,
                    completedActions: completed,
                    totalActions: total,
                    queuePosition: nil,
                    transactionID: plan.id,
                    affectedPaths: plan.actions.map(\.destinationPath)
                ))
            }
        } catch {
            let phase: ProfileOperationSnapshot.Phase
            let paths: [String]
            if let executionError = error as? TransactionExecutionError,
               case .recoveryRequired(let unresolved, _) = executionError {
                phase = .recoveryRequired
                paths = unresolved
            } else {
                phase = .failed
                paths = []
            }
            publish(ProfileOperationSnapshot(
                phase: phase,
                message: error.localizedDescription,
                completedActions: 0,
                totalActions: plan.actions.count,
                queuePosition: nil,
                transactionID: plan.id,
                affectedPaths: paths
            ))
            throw error
        }

        publish(ProfileOperationSnapshot(
            phase: outcome.warnings.isEmpty ? .committed : .warning,
            message: outcome.warnings.isEmpty ? "\(plan.profileName) applied successfully" : outcome.warnings.joined(separator: "\n"),
            completedActions: plan.actions.count,
            totalActions: plan.actions.count,
            queuePosition: nil,
            transactionID: plan.id,
            affectedPaths: plan.actions.map(\.destinationPath)
        ))
        return outcome
    }

    func undoLatest() async throws -> ApplyTransaction {
        let requestID = UUID()
        await acquire(requestID: requestID, operation: "Undo")
        defer { release() }
        try Task.checkCancellation()

        let handler = stateHandler
        do {
            try ensureRecoveryIsComplete()
            publish(ProfileOperationSnapshot(
                phase: .undoing,
                message: "Restoring the previous profile state",
                completedActions: 0,
                totalActions: 0,
                queuePosition: nil,
                transactionID: nil,
                affectedPaths: []
            ))
            let transaction = try executor.undoLatest { completed, total, message in
                handler?(ProfileOperationSnapshot(
                    phase: .undoing,
                    message: message,
                    completedActions: completed,
                    totalActions: total,
                    queuePosition: nil,
                    transactionID: nil,
                    affectedPaths: []
                ))
            }
            publish(ProfileOperationSnapshot(
                phase: .undone,
                message: "Undo complete",
                completedActions: transaction.actions.count,
                totalActions: transaction.actions.count,
                queuePosition: nil,
                transactionID: transaction.id,
                affectedPaths: transaction.actions.map { $0.action.destinationPath }
            ))
            return transaction
        } catch {
            let phase: ProfileOperationSnapshot.Phase
            let paths: [String]
            if let executionError = error as? TransactionExecutionError,
               case .recoveryRequired(let unresolved, _) = executionError {
                phase = .recoveryRequired
                paths = unresolved
            } else {
                phase = .failed
                paths = []
            }
            publish(ProfileOperationSnapshot(
                phase: phase,
                message: error.localizedDescription,
                completedActions: 0,
                totalActions: 0,
                queuePosition: nil,
                transactionID: nil,
                affectedPaths: paths
            ))
            throw error
        }
    }

    func recover(transactionID: UUID) async throws -> ApplyTransaction {
        let requestID = UUID()
        await acquire(requestID: requestID, operation: "Recovery")
        defer { release() }
        try Task.checkCancellation()
        let handler = stateHandler
        do {
            publish(ProfileOperationSnapshot(
                phase: .rollingBack,
                message: "Recovering the interrupted transaction",
                completedActions: 0,
                totalActions: 0,
                queuePosition: nil,
                transactionID: transactionID,
                affectedPaths: []
            ))
            let transaction = try executor.recover(transactionID: transactionID) { completed, total, message in
                handler?(ProfileOperationSnapshot(
                    phase: .rollingBack,
                    message: message,
                    completedActions: completed,
                    totalActions: total,
                    queuePosition: nil,
                    transactionID: transactionID,
                    affectedPaths: []
                ))
            }
            publish(ProfileOperationSnapshot(
                phase: .idle,
                message: "Recovery completed",
                completedActions: transaction.actions.count,
                totalActions: transaction.actions.count,
                queuePosition: nil,
                transactionID: transaction.id,
                affectedPaths: transaction.actions.map { $0.action.destinationPath }
            ))
            return transaction
        } catch {
            let paths: [String]
            if let executionError = error as? TransactionExecutionError,
               case .recoveryRequired(let unresolved, _) = executionError {
                paths = unresolved
            } else {
                paths = []
            }
            publish(ProfileOperationSnapshot(
                phase: .recoveryRequired,
                message: error.localizedDescription,
                completedActions: 0,
                totalActions: 0,
                queuePosition: nil,
                transactionID: transactionID,
                affectedPaths: paths
            ))
            throw error
        }
    }

    func incompleteTransactions() throws -> [ApplyTransaction] {
        try executor.incompleteTransactions()
    }

    func latestUndoable() throws -> ApplyTransaction? {
        try executor.latestUndoable()
    }

    func resetVisibleState() {
        publish(.idle)
    }

    private func acquire(requestID: UUID, operation: String) async {
        if !isBusy {
            isBusy = true
            return
        }
        let position = waiters.count + 1
        publish(ProfileOperationSnapshot(
            phase: .queued,
            message: "\(operation) queued",
            completedActions: 0,
            totalActions: 0,
            queuePosition: position,
            transactionID: requestID,
            affectedPaths: []
        ))
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(id: requestID, continuation: continuation))
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isBusy = false
            return
        }
        let next = waiters.removeFirst()
        next.continuation.resume(returning: ())
    }

    private func publish(_ state: ProfileOperationSnapshot) {
        snapshot = state
        stateHandler?(state)
    }

    private func ensureRecoveryIsComplete() throws {
        let incomplete: [ApplyTransaction]
        do {
            incomplete = try executor.incompleteTransactions()
        } catch {
            throw TransactionExecutionError.recoveryRequired(
                paths: [],
                cause: "Transaction journals could not be inspected: \(error.localizedDescription)"
            )
        }
        guard !incomplete.isEmpty else { return }

        let paths = Set(incomplete.flatMap { transaction in
            transaction.unresolvedPaths.isEmpty
                ? transaction.actions.map { $0.action.destinationPath }
                : transaction.unresolvedPaths
        }).sorted()
        throw TransactionExecutionError.recoveryRequired(
            paths: paths,
            cause: "Finish or resolve the interrupted transaction before starting another profile operation."
        )
    }

    private func recoveryPaths(from error: Error) -> [String] {
        guard let executionError = error as? TransactionExecutionError,
              case .recoveryRequired(let paths, _) = executionError else {
            return []
        }
        return paths
    }
}

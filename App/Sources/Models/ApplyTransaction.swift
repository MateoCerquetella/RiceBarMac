import Foundation

struct TransactionActionRecord: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case intentRecorded
        case staged
        case backupCreated
        case replacementInstalled
        case rolledBack
        case restored
    }

    let id: UUID
    let action: PlannedFileAction
    var status: Status
    var installedFingerprint: PathFingerprint?
    var errorDescription: String?
}

struct ExternalEffectResult: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let effect: ProfileExternalEffect
    let succeeded: Bool
    let errorDescription: String?
}

struct ApplyTransaction: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case planned
        case executing
        case rollingBack
        case rolledBack
        case committed
        case committedWithWarnings
        case undoing
        case undone
        case recoveryRequired
    }

    let id: UUID
    let plan: ProfileApplyPlan
    let createdAt: Date
    var updatedAt: Date
    var status: Status
    var actions: [TransactionActionRecord]
    var externalEffects: [ExternalEffectResult]
    var unresolvedPaths: [String]
    var errorDescription: String?

    init(plan: ProfileApplyPlan, now: Date = Date()) {
        id = plan.id
        self.plan = plan
        createdAt = now
        updatedAt = now
        status = .planned
        actions = plan.actions.map {
            TransactionActionRecord(id: $0.id, action: $0, status: .pending, installedFingerprint: nil, errorDescription: nil)
        }
        externalEffects = []
        unresolvedPaths = []
        errorDescription = nil
    }

    var canUndo: Bool {
        status == .committed || status == .committedWithWarnings
    }
}

struct ProfileOperationSnapshot: Equatable, Sendable {
    enum Phase: String, Sendable {
        case idle
        case previewing
        case ready
        case queued
        case applying
        case rollingBack
        case committed
        case warning
        case failed
        case undoing
        case undone
        case recoveryRequired
    }

    var phase: Phase
    var message: String
    var completedActions: Int
    var totalActions: Int
    var queuePosition: Int?
    var transactionID: UUID?
    var affectedPaths: [String]

    static let idle = ProfileOperationSnapshot(
        phase: .idle,
        message: "Ready",
        completedActions: 0,
        totalActions: 0,
        queuePosition: nil,
        transactionID: nil,
        affectedPaths: []
    )

    var progress: Double {
        guard totalActions > 0 else { return phase == .committed || phase == .undone ? 1 : 0 }
        return min(1, max(0, Double(completedActions) / Double(totalActions)))
    }
}

struct ProfileApplyOutcome: Sendable {
    let transaction: ApplyTransaction
    let warnings: [String]
}

struct InvalidProfileDescriptor: Identifiable, Equatable, Hashable, Sendable {
    var id: String { directory.path }
    let directory: URL
    let source: URL?
    let message: String
}

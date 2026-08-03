import Foundation
import XCTest
@testable import RiceBarMac

final class TemporaryHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RiceBarMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func createDirectory(_ relativePath: String) throws -> URL {
        let result = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    @discardableResult
    func write(_ relativePath: String, _ value: String) throws -> URL {
        let result = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: result.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: result)
        return result
    }
}

enum InjectedFileSystemError: LocalizedError {
    case failure(Int, String)

    var errorDescription: String? {
        switch self {
        case .failure(let boundary, let path):
            return "Injected mutation failure \(boundary) at \(path)"
        }
    }
}

final class FaultInjectingFileSystemClient: FileSystemClient, @unchecked Sendable {
    private let base: FileSystemClient
    private let lock = NSLock()
    private var mutationCount = 0
    private var activeMutations = 0
    private(set) var maximumConcurrentMutations = 0
    var failAtMutation: Int?
    var mutationDelay: TimeInterval = 0
    var afterMutation: (@Sendable (_ count: Int, _ url: URL) throws -> Void)?

    init(base: FileSystemClient = LiveFileSystemClient()) {
        self.base = base
    }

    func state(at url: URL) throws -> FileObjectState { try base.state(at: url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] { try base.contentsOfDirectory(at: url) }
    func enumeratedContents(at url: URL) throws -> [URL] { try base.enumeratedContents(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }

    func createDirectory(at url: URL) throws {
        try mutate(url) { try base.createDirectory(at: url) }
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try mutate(destination) { try base.copyItem(at: source, to: destination) }
    }

    func createSymbolicLink(at destination: URL, pointingTo source: URL) throws {
        try mutate(destination) { try base.createSymbolicLink(at: destination, pointingTo: source) }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try mutate(destination) { try base.moveItem(at: source, to: destination) }
    }

    func removeItem(at url: URL) throws {
        try mutate(url) { try base.removeItem(at: url) }
    }

    func writeDataAtomically(_ data: Data, to url: URL) throws {
        try mutate(url) { try base.writeDataAtomically(data, to: url) }
    }

    func setPermissions(_ permissions: UInt16, at url: URL) throws {
        try mutate(url) { try base.setPermissions(permissions, at: url) }
    }

    private func mutate(_ url: URL, operation: () throws -> Void) throws {
        lock.lock()
        mutationCount += 1
        activeMutations += 1
        maximumConcurrentMutations = max(maximumConcurrentMutations, activeMutations)
        let count = mutationCount
        let shouldFail = failAtMutation == count
        let delay = mutationDelay
        let mutationHook = afterMutation
        lock.unlock()

        defer {
            lock.lock()
            activeMutations -= 1
            lock.unlock()
        }

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        if shouldFail {
            throw InjectedFileSystemError.failure(count, url.path)
        }
        try operation()
        try mutationHook?(count, url)
    }
}

final class MemoryTransactionStore: TransactionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var transactions: [UUID: ApplyTransaction] = [:]

    func save(_ transaction: ApplyTransaction) throws {
        lock.lock()
        transactions[transaction.id] = transaction
        lock.unlock()
    }

    func load(id: UUID) throws -> ApplyTransaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions[id]
    }

    func loadAll() throws -> [ApplyTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return transactions.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func latestUndoable() throws -> ApplyTransaction? {
        try loadAll().first(where: \.canUndo)
    }

    func incompleteTransactions() throws -> [ApplyTransaction] {
        try loadAll().filter {
            [.planned, .executing, .rollingBack, .undoing, .recoveryRequired].contains($0.status)
        }
    }
}

enum InjectedTransactionStoreError: LocalizedError {
    case failure(Int)

    var errorDescription: String? {
        switch self {
        case .failure(let boundary):
            return "Injected transaction-store failure at save \(boundary)"
        }
    }
}

final class FaultInjectingTransactionStore: TransactionStoring, @unchecked Sendable {
    private let base = MemoryTransactionStore()
    private let lock = NSLock()
    private var saveCount = 0
    var failAtSave: Int?

    func save(_ transaction: ApplyTransaction) throws {
        lock.lock()
        saveCount += 1
        let count = saveCount
        let shouldFail = failAtSave == count
        lock.unlock()
        if shouldFail {
            throw InjectedTransactionStoreError.failure(count)
        }
        try base.save(transaction)
    }

    func load(id: UUID) throws -> ApplyTransaction? { try base.load(id: id) }
    func loadAll() throws -> [ApplyTransaction] { try base.loadAll() }
    func latestUndoable() throws -> ApplyTransaction? { try base.latestUndoable() }
    func incompleteTransactions() throws -> [ApplyTransaction] { try base.incompleteTransactions() }
}

final class MemoryActiveProfileStore: ActiveProfilePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ value: String? = nil) {
        self.value = value
    }

    func loadActiveProfilePath() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func saveActiveProfilePath(_ path: String?) {
        lock.lock()
        value = path
        lock.unlock()
    }
}

actor RecordingExternalEffectClient: ExternalEffectClient {
    private var effects: [ProfileExternalEffect] = []
    private let failingKinds: Set<ProfileExternalEffect.Kind>

    init(failingKinds: Set<ProfileExternalEffect.Kind> = []) {
        self.failingKinds = failingKinds
    }

    func perform(_ effect: ProfileExternalEffect) async throws {
        effects.append(effect)
        if failingKinds.contains(effect.kind) {
            throw ExternalEffectError.processFailed(effect.kind.rawValue, 1, "injected")
        }
    }

    func recordedEffects() -> [ProfileExternalEffect] {
        effects
    }
}

func makeProfileDescriptor(home: URL, name: String = "Test", replacementDestination: URL? = nil) throws -> ProfileDescriptor {
    let directory = home.appendingPathComponent(".ricebarmac/profiles/\(name)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("home", isDirectory: true), withIntermediateDirectories: true)
    var profile = Profile(name: name)
    if let destination = replacementDestination {
        let source = directory.appendingPathComponent("replacement.txt")
        try Data("profile-value".utf8).write(to: source)
        profile.replacements = [Profile.Replacement(source: "replacement.txt", destination: destination.path)]
    }
    let data = try JSONEncoder().encode(profile)
    try data.write(to: directory.appendingPathComponent("profile.json"))
    return ProfileDescriptor(profile: profile, directory: directory)
}

func makeExecutor(
    home: URL,
    fileSystem: FileSystemClient,
    transactionStore: TransactionStoring? = nil,
    activeStore: ActiveProfilePersisting = MemoryActiveProfileStore(),
    externalEffects: ExternalEffectClient = RecordingExternalEffectClient()
) -> ProfileTransactionExecutor {
    ProfileTransactionExecutor(
        fileSystem: fileSystem,
        transactionStore: transactionStore ?? TransactionStore(rootURL: home.appendingPathComponent(".ricebarmac"), fileSystem: fileSystem),
        activeProfileStore: activeStore,
        externalEffects: externalEffects
    )
}

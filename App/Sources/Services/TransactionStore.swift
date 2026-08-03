import Foundation

enum TransactionStoreError: LocalizedError {
    case invalidJournal(String, Error)
    case journalWriteFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .invalidJournal(let path, let error):
            return "Invalid transaction journal at \(path): \(error.localizedDescription)"
        case .journalWriteFailed(let path, let error):
            return "Could not persist the transaction journal at \(path): \(error.localizedDescription)"
        }
    }
}

protocol TransactionStoring: Sendable {
    func save(_ transaction: ApplyTransaction) throws
    func load(id: UUID) throws -> ApplyTransaction?
    func loadAll() throws -> [ApplyTransaction]
    func latestUndoable() throws -> ApplyTransaction?
    func incompleteTransactions() throws -> [ApplyTransaction]
}

protocol ActiveProfilePersisting: Sendable {
    func loadActiveProfilePath() -> String?
    func saveActiveProfilePath(_ path: String?)
}

final class UserDefaultsActiveProfileStore: ActiveProfilePersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "ActiveProfileDirectoryPath") {
        self.defaults = defaults
        self.key = key
    }

    func loadActiveProfilePath() -> String? {
        defaults.string(forKey: key)
    }

    func saveActiveProfilePath(_ path: String?) {
        if let path {
            defaults.set(path, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

final class VolatileActiveProfileStore: ActiveProfilePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    func loadActiveProfilePath() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return path
    }

    func saveActiveProfilePath(_ path: String?) {
        lock.lock()
        self.path = path
        lock.unlock()
    }
}

final class TransactionStore: TransactionStoring, @unchecked Sendable {
    let transactionsURL: URL

    private let fileSystem: FileSystemClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL, fileSystem: FileSystemClient) {
        transactionsURL = rootURL.appendingPathComponent("transactions", isDirectory: true)
        self.fileSystem = fileSystem
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate.bitPattern)
        }
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let bitPattern = try container.decode(UInt64.self)
            return Date(timeIntervalSinceReferenceDate: TimeInterval(bitPattern: bitPattern))
        }
    }

    func journalURL(for id: UUID) -> URL {
        transactionsURL.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    func save(_ transaction: ApplyTransaction) throws {
        do {
            try ensureDirectoryHierarchy(transactionsURL)
            let data = try encoder.encode(transaction)
            _ = try decoder.decode(ApplyTransaction.self, from: data)
            try fileSystem.writeDataAtomically(data, to: journalURL(for: transaction.id))
        } catch {
            throw TransactionStoreError.journalWriteFailed(journalURL(for: transaction.id).path, error)
        }
    }

    func load(id: UUID) throws -> ApplyTransaction? {
        let url = journalURL(for: id)
        guard try fileSystem.state(at: url).exists else { return nil }
        return try decode(at: url)
    }

    func loadAll() throws -> [ApplyTransaction] {
        guard try fileSystem.state(at: transactionsURL).kind == .directory else { return [] }
        return try fileSystem.contentsOfDirectory(at: transactionsURL)
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { try decode(at: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func latestUndoable() throws -> ApplyTransaction? {
        try loadAll().first(where: \.canUndo)
    }

    func incompleteTransactions() throws -> [ApplyTransaction] {
        try loadAll().filter {
            switch $0.status {
            case .planned, .executing, .rollingBack, .undoing, .recoveryRequired:
                return true
            case .rolledBack, .committed, .committedWithWarnings, .undone:
                return false
            }
        }
    }

    private func decode(at url: URL) throws -> ApplyTransaction {
        do {
            let data = try fileSystem.readData(at: url)
            return try decoder.decode(ApplyTransaction.self, from: data)
        } catch {
            throw TransactionStoreError.invalidJournal(url.path, error)
        }
    }

    private func ensureDirectoryHierarchy(_ directory: URL) throws {
        let state = try fileSystem.state(at: directory)
        if state.kind == .directory { return }
        if state.exists {
            throw FileSystemClientError.parentIsNotDirectory(directory.path)
        }
        let parent = directory.deletingLastPathComponent()
        if parent.path != directory.path {
            try ensureDirectoryHierarchy(parent)
        }
        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            if try fileSystem.state(at: directory).kind != .directory {
                throw error
            }
        }
    }
}

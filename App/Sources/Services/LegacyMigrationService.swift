import Foundation

enum LegacyMigrationAvailability: Equatable, Sendable {
    case none
    case available(source: URL)
    case conflict(source: URL, destination: URL, entries: [String])
}

struct LegacyMigrationRecord: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case executing
        case committed
        case committedWithWarnings
        case failed
    }

    let id: UUID
    let sourcePath: String
    let destinationPath: String
    let stagingPath: String
    let createdAt: Date
    var updatedAt: Date
    var status: Status
    var errorDescription: String?
}

enum LegacyMigrationError: LocalizedError {
    case conflict([String])
    case unsafeLegacySymlink(String)
    case invalidStagedData(String)
    case failed(String, Error)

    var errorDescription: String? {
        switch self {
        case .conflict(let entries):
            return "Current and legacy configuration conflict: \(entries.joined(separator: ", ")). Neither location was changed."
        case .unsafeLegacySymlink(let path):
            return "Legacy data contains a symlink that escapes the user home: \(path)"
        case .invalidStagedData(let reason):
            return "The staged legacy configuration is invalid: \(reason)"
        case .failed(let operation, let error):
            return "Legacy migration failed during \(operation): \(error.localizedDescription)"
        }
    }
}

final class LegacyMigrationService: @unchecked Sendable {
    let legacyRoot: URL
    let currentRoot: URL

    private let home: URL
    private let fileSystem: FileSystemClient
    private let now: @Sendable () -> Date
    private let nextID: @Sendable () -> UUID

    init(
        home: URL = Constants.userHome,
        fileSystem: FileSystemClient = LiveFileSystemClient(),
        now: @escaping @Sendable () -> Date = { Date() },
        nextID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.home = home.standardizedFileURL
        legacyRoot = home.appendingPathComponent(".ricebar", isDirectory: true).standardizedFileURL
        currentRoot = home.appendingPathComponent(".ricebarmac", isDirectory: true).standardizedFileURL
        self.fileSystem = fileSystem
        self.now = now
        self.nextID = nextID
    }

    func availability() -> LegacyMigrationAvailability {
        do {
            guard try fileSystem.state(at: legacyRoot).kind == .directory else { return .none }
            let legacyEntries = try fileSystem.contentsOfDirectory(at: legacyRoot)
            guard !legacyEntries.isEmpty else { return .none }

            let currentState = try fileSystem.state(at: currentRoot)
            guard currentState.kind == .absent else {
                let currentEntries = currentState.kind == .directory ? try fileSystem.contentsOfDirectory(at: currentRoot) : [currentRoot]
                let conflicts = currentEntries.map(\.lastPathComponent).sorted()
                return .conflict(source: legacyRoot, destination: currentRoot, entries: conflicts)
            }
            return .available(source: legacyRoot)
        } catch {
            return .conflict(source: legacyRoot, destination: currentRoot, entries: [error.localizedDescription])
        }
    }

    func migrate() throws -> LegacyMigrationRecord {
        switch availability() {
        case .none:
            throw LegacyMigrationError.invalidStagedData("No legacy .ricebar directory was found.")
        case .conflict(_, _, let entries):
            throw LegacyMigrationError.conflict(entries)
        case .available:
            break
        }

        try validateLegacySymlinks()

        let id = nextID()
        let stage = home.appendingPathComponent(".ricebarmac-migration-stage-\(id.uuidString.lowercased())", isDirectory: true)
        let journalDirectory = home.appendingPathComponent(".ricebarmac-migrations", isDirectory: true)
        let journalURL = journalDirectory.appendingPathComponent("\(id.uuidString.lowercased()).json")

        guard try fileSystem.state(at: stage).kind == .absent else {
            throw FileSystemClientError.collision(stage.path)
        }

        var record = LegacyMigrationRecord(
            id: id,
            sourcePath: legacyRoot.path,
            destinationPath: currentRoot.path,
            stagingPath: stage.path,
            createdAt: now(),
            updatedAt: now(),
            status: .executing,
            errorDescription: nil
        )

        try ensureDirectoryHierarchy(journalDirectory)
        try save(record, to: journalURL)

        do {
            try fileSystem.copyItem(at: legacyRoot, to: stage)
            try validateStagedRoot(stage)
            guard try fileSystem.state(at: currentRoot).kind == .absent else {
                throw LegacyMigrationError.conflict([currentRoot.path])
            }
            try fileSystem.moveItem(at: stage, to: currentRoot)
        } catch {
            try? fileSystem.removeItem(at: stage)
            record.status = .failed
            record.updatedAt = now()
            record.errorDescription = error.localizedDescription
            try? save(record, to: journalURL)
            throw LegacyMigrationError.failed("staging or commit", error)
        }

        record.status = .committed
        record.updatedAt = now()
        do {
            try save(record, to: journalURL)
        } catch {
            record.status = .committedWithWarnings
            record.updatedAt = now()
            record.errorDescription = "Legacy data was installed, but the final migration journal checkpoint failed: \(error.localizedDescription)"
            try? save(record, to: journalURL)
        }
        return record
    }

    private func validateLegacySymlinks() throws {
        let validator = PathSafetyValidator(home: home, fileSystem: fileSystem)
        for url in try fileSystem.enumeratedContents(at: legacyRoot) {
            let state = try fileSystem.state(at: url)
            guard state.kind == .symbolicLink else { continue }
            let resolved = try validator.resolveSymlink(at: url)
            guard resolved.path == home.path || validator.isStrictlyInsideHome(resolved) else {
                throw LegacyMigrationError.unsafeLegacySymlink(url.path)
            }
        }
    }

    private func validateStagedRoot(_ stage: URL) throws {
        guard try fileSystem.state(at: stage).kind == .directory else {
            throw LegacyMigrationError.invalidStagedData("The staged root is not a directory.")
        }
        let entries = try fileSystem.contentsOfDirectory(at: stage)
        guard !entries.isEmpty else {
            throw LegacyMigrationError.invalidStagedData("The staged root is empty.")
        }
        let config = stage.appendingPathComponent("config.json")
        if try fileSystem.state(at: config).exists {
            do {
                _ = try JSONDecoder().decode(RiceBarConfig.self, from: fileSystem.readData(at: config))
            } catch {
                throw LegacyMigrationError.invalidStagedData("config.json: \(error.localizedDescription)")
            }
        }
    }

    private func save(_ record: LegacyMigrationRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try fileSystem.writeDataAtomically(try encoder.encode(record), to: url)
    }

    private func ensureDirectoryHierarchy(_ directory: URL) throws {
        let state = try fileSystem.state(at: directory)
        if state.kind == .directory { return }
        if state.exists { throw FileSystemClientError.parentIsNotDirectory(directory.path) }
        let parent = directory.deletingLastPathComponent()
        if parent.path != directory.path { try ensureDirectoryHierarchy(parent) }
        try fileSystem.createDirectory(at: directory)
    }
}

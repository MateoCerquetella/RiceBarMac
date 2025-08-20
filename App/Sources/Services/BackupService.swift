import Foundation

enum BackupServiceError: LocalizedError {
    case backupAlreadyExists
    case sourceNotFound
    case backupFailed(Error)
    case restoreFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .backupAlreadyExists:
            return "Backup already exists"
        case .sourceNotFound:
            return "Source directory not found"
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        case .restoreFailed(let error):
            return "Restore failed: \(error.localizedDescription)"
        }
    }
}

final class BackupService: ObservableObject {
    static let shared = BackupService()
    
    private let fileManager = FileManager.default
    private let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
    
    private init() {}
    
    /// Checks if this is the first time RiceBarMac is being run
    var isFirstRun: Bool {
        let firstRunFlag = Constants.backupsRoot.appendingPathComponent(".first-run-flag")
        return !fileManager.fileExists(atPath: firstRunFlag.path)
    }
    
    /// Creates a backup of the current .config directory on first run
    func createInitialBackupIfNeeded() throws {
        guard isFirstRun else {
            print("Not first run, skipping initial backup")
            return
        }
        
        print("First run detected, creating initial backup...")
        
        let configSource = homeDirectory.appendingPathComponent(".config")
        let backupDestination = Constants.backupsRoot.appendingPathComponent(".config.bkp")
        
        // Check if .config exists
        guard fileManager.fileExists(atPath: configSource.path) else {
            print("No .config directory found, skipping backup")
            try markFirstRunComplete()
            return
        }
        
        // Check if backup already exists
        if fileManager.fileExists(atPath: backupDestination.path) {
            print("Backup already exists at \(backupDestination.path)")
            try markFirstRunComplete()
            return
        }
        
        // Create backup
        do {
            try createBackup(from: configSource, to: backupDestination)
            print("✅ Initial backup created successfully at: \(backupDestination.path)")
            try markFirstRunComplete()
        } catch {
            print("❌ Failed to create initial backup: \(error.localizedDescription)")
            throw BackupServiceError.backupFailed(error)
        }
    }
    
    /// Creates a backup of the specified directory
    func createBackup(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        
        // Ensure backup directory exists
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), 
                                      withIntermediateDirectories: true)
        
        // Remove existing backup if it exists
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        
        // Copy the directory
        try fileManager.copyItem(at: source, to: destination)
        
        // Set backup metadata
        let metadata = BackupMetadata(
            timestamp: Date(),
            sourcePath: source.path,
            backupPath: destination.path,
            version: "1.0"
        )
        
        let metadataURL = destination.appendingPathComponent(".ricebar-backup-info.json")
        try saveBackupMetadata(metadata, to: metadataURL)
    }
    
    /// Restores a backup to the original location
    func restoreBackup(from backupPath: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        
        // Check if backup exists
        guard fileManager.fileExists(atPath: backupPath.path) else {
            throw BackupServiceError.sourceNotFound
        }
        
        // Create destination directory if it doesn't exist
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), 
                                      withIntermediateDirectories: true)
        
        // Remove existing destination if it exists
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        
        // Copy backup to destination
        try fileManager.copyItem(at: backupPath, to: destination)
        
        print("✅ Backup restored successfully to: \(destination.path)")
    }
    
    /// Lists all available backups
    func listBackups() -> [BackupInfo] {
        let fileManager = FileManager.default
        var backups: [BackupInfo] = []
        
        guard let enumerator = fileManager.enumerator(at: Constants.backupsRoot, 
                                                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                                                    options: [.skipsHiddenFiles]) else {
            return backups
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.hasSuffix(".bkp") {
                let metadataURL = fileURL.appendingPathComponent(".ricebar-backup-info.json")
                
                if let metadata = loadBackupMetadata(from: metadataURL) {
                    backups.append(BackupInfo(
                        path: fileURL,
                        metadata: metadata,
                        size: Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    ))
                }
            }
        }
        
        return backups.sorted { $0.metadata.timestamp > $1.metadata.timestamp }
    }
    
    /// Gets the initial backup path
    var initialBackupPath: URL? {
        let path = Constants.backupsRoot.appendingPathComponent(".config.bkp")
        return fileManager.fileExists(atPath: path.path) ? path : nil
    }
    
    // MARK: - Private Methods
    
    private func markFirstRunComplete() throws {
        let flagFile = Constants.backupsRoot.appendingPathComponent(".first-run-flag")
        try "First run completed on \(Date())".write(to: flagFile, atomically: true, encoding: .utf8)
    }
    
    private func saveBackupMetadata(_ metadata: BackupMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(metadata)
        try data.write(to: url)
    }
    
    private func loadBackupMetadata(from url: URL) -> BackupMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(BackupMetadata.self, from: data)
    }
}

// MARK: - Data Models

struct BackupMetadata: Codable {
    let timestamp: Date
    let sourcePath: String
    let backupPath: String
    let version: String
}

struct BackupInfo {
    let path: URL
    let metadata: BackupMetadata
    let size: Int64
    
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Backup from \(formatter.string(from: metadata.timestamp))"
    }
    
    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

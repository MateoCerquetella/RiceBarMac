import Foundation
import Combine

enum ConfigServiceError: LocalizedError {
    case configDirectoryCreationFailed(Error)
    case configFileReadFailed(Error)
    case configFileWriteFailed(Error)
    case invalidConfigFormat(Error)
    case configChangedExternally
    case rollbackFailed(original: Error, rollback: Error)

    var errorDescription: String? {
        switch self {
        case .configDirectoryCreationFailed(let error):
            return "Failed to create the configuration directory: \(error.localizedDescription)"
        case .configFileReadFailed(let error):
            return "Failed to read the configuration file: \(error.localizedDescription)"
        case .configFileWriteFailed(let error):
            return "Failed to save the configuration file: \(error.localizedDescription)"
        case .invalidConfigFormat(let error):
            return "The configuration file is invalid and was left unchanged: \(error.localizedDescription)"
        case .configChangedExternally:
            return "The configuration changed on disk and was left unchanged. Reload it before saving new settings."
        case .rollbackFailed(let original, let rollback):
            return "Saving failed (\(original.localizedDescription)) and restoring the previous configuration also failed (\(rollback.localizedDescription))."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidConfigFormat:
            return "Fix or move ~/.ricebarmac/config.json, then choose Reload Profiles. RiceBarMac will not overwrite the malformed file."
        case .configChangedExternally:
            return "Choose Reload Profiles to load the on-disk configuration before changing settings again."
        case .rollbackFailed:
            return "Open ~/.ricebarmac and preserve every .ricebarmac-backup file before making another change."
        default:
            return "Check permissions for ~/.ricebarmac and try again."
        }
    }
}

enum ConfigLoadState: Equatable {
    case missing
    case loaded
    case invalid(message: String)
}

final class ConfigService: ObservableObject {
    @Published var config: RiceBarConfig
    @Published var shortcutsUpdated = false
    @Published private(set) var loadState: ConfigLoadState
    @Published private(set) var lastError: ConfigServiceError? = nil
    @Published private(set) var lastBackupURL: URL? = nil

    let rootURL: URL
    let configURL: URL

    private let fileSystem: FileSystemClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var expectedConfigState: FileObjectState

    static let shared = ConfigService()

    init(
        rootURL: URL = Constants.ricebarRoot,
        fileSystem: FileSystemClient = LiveFileSystemClient()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.configURL = rootURL.appendingPathComponent("config.json")
        self.fileSystem = fileSystem

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        do {
            let state = try fileSystem.state(at: self.configURL)
            expectedConfigState = state
            if state.kind == .absent {
                config = .default
                loadState = .missing
                lastError = nil
            } else {
                let data = try fileSystem.readData(at: self.configURL)
                do {
                    config = try decoder.decode(RiceBarConfig.self, from: data)
                    loadState = .loaded
                    lastError = nil
                } catch {
                    config = .default
                    loadState = .invalid(message: error.localizedDescription)
                    lastError = .invalidConfigFormat(error)
                }
            }
        } catch {
            expectedConfigState = .absent
            config = .default
            loadState = .invalid(message: error.localizedDescription)
            lastError = .configFileReadFailed(error)
        }
    }

    @discardableResult
    func saveConfig() -> Bool {
        // Never replace a file that failed to load. The user must repair or
        // move it explicitly so an in-memory default cannot erase unknown data.
        if case .invalid = loadState {
            return false
        }

        do {
            let currentState = try fileSystem.state(at: configURL)
            guard currentState == expectedConfigState else {
                throw ConfigServiceError.configChangedExternally
            }
            let data = try encoder.encode(config)
            _ = try decoder.decode(RiceBarConfig.self, from: data)
            try ensureDirectoryHierarchy(rootURL)

            let identifier = UUID().uuidString.lowercased()
            let stageURL = rootURL.appendingPathComponent(".config.json.ricebarmac-stage-\(identifier)")
            let backupURL = rootURL.appendingPathComponent(".config.json.ricebarmac-backup-\(identifier)")

            guard try fileSystem.state(at: stageURL).kind == .absent,
                  try fileSystem.state(at: backupURL).kind == .absent else {
                throw FileSystemClientError.collision(stageURL.path)
            }

            try fileSystem.writeDataAtomically(data, to: stageURL)
            let stagedState = try fileSystem.state(at: stageURL)
            var movedOriginal = false

            do {
                guard try fileSystem.state(at: configURL) == expectedConfigState else {
                    throw ConfigServiceError.configChangedExternally
                }
                if expectedConfigState.exists {
                    try fileSystem.moveItem(at: configURL, to: backupURL)
                    movedOriginal = true
                    guard try fileSystem.state(at: backupURL) == expectedConfigState,
                          try fileSystem.state(at: configURL).kind == .absent else {
                        throw ConfigServiceError.configChangedExternally
                    }
                }
                guard try fileSystem.state(at: configURL).kind == .absent else {
                    throw ConfigServiceError.configChangedExternally
                }
                try fileSystem.moveItem(at: stageURL, to: configURL)
                guard try fileSystem.state(at: configURL) == stagedState else {
                    throw ConfigServiceError.configChangedExternally
                }
                expectedConfigState = stagedState
                lastBackupURL = movedOriginal ? backupURL : nil
                loadState = .loaded
                lastError = nil
                return true
            } catch {
                try? fileSystem.removeItem(at: stageURL)
                if movedOriginal {
                    do {
                        guard try fileSystem.state(at: configURL).kind == .absent else {
                            throw FileSystemClientError.stalePath(configURL.path)
                        }
                        guard try fileSystem.state(at: backupURL) == expectedConfigState else {
                            throw FileSystemClientError.stalePath(backupURL.path)
                        }
                        try fileSystem.moveItem(at: backupURL, to: configURL)
                    } catch let rollbackError {
                        lastBackupURL = backupURL
                        let wrapped = ConfigServiceError.rollbackFailed(original: error, rollback: rollbackError)
                        lastError = wrapped
                        loadState = .invalid(message: wrapped.localizedDescription)
                        return false
                    }
                }
                throw error
            }
        } catch let error as ConfigServiceError {
            lastError = error
            if case .configChangedExternally = error {
                loadState = .invalid(message: error.localizedDescription)
            }
            return false
        } catch {
            lastError = .configFileWriteFailed(error)
            return false
        }
    }

    func reloadConfig() {
        do {
            let state = try fileSystem.state(at: configURL)
            expectedConfigState = state
            guard state.exists else {
                config = .default
                loadState = .missing
                lastError = nil
                return
            }
            let data = try fileSystem.readData(at: configURL)
            do {
                config = try decoder.decode(RiceBarConfig.self, from: data)
                loadState = .loaded
                lastError = nil
            } catch {
                loadState = .invalid(message: error.localizedDescription)
                lastError = .invalidConfigFormat(error)
            }
        } catch {
            loadState = .invalid(message: error.localizedDescription)
            lastError = .configFileReadFailed(error)
        }
    }

    func resetToDefaults() {
        let previous = config
        config = .default
        if !saveConfig() {
            config = previous
        }
    }

    func updateShortcut(for key: String, to value: String) {
        let previous = config
        config.shortcuts.profileShortcuts[key] = value
        if saveConfig() {
            shortcutsUpdated.toggle()
        } else {
            config = previous
        }
    }

    func updateNavigationShortcut(_ keyPath: WritableKeyPath<NavigationShortcuts, String>, to value: String) {
        let previous = config
        config.shortcuts.navigationShortcuts[keyPath: keyPath] = value
        if saveConfig() {
            shortcutsUpdated.toggle()
        } else {
            config = previous
        }
    }

    func updateQuickActionShortcut(_ keyPath: WritableKeyPath<QuickActionShortcuts, String>, to value: String) {
        let previous = config
        config.shortcuts.quickActions[keyPath: keyPath] = value
        if saveConfig() {
            shortcutsUpdated.toggle()
        } else {
            config = previous
        }
    }

    func updateGeneralSetting<T>(_ keyPath: WritableKeyPath<GeneralConfig, T>, to value: T) {
        let previous = config
        config.general[keyPath: keyPath] = value
        if !saveConfig() {
            config = previous
        }
    }

    func updateAppearanceSetting<T>(_ keyPath: WritableKeyPath<AppearanceConfig, T>, to value: T) {
        let previous = config
        config.appearance[keyPath: keyPath] = value
        if !saveConfig() {
            config = previous
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
                throw ConfigServiceError.configDirectoryCreationFailed(error)
            }
        }
    }
}

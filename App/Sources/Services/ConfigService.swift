import Foundation
import Combine

enum ConfigServiceError: LocalizedError {
    case configDirectoryCreationFailed
    case configFileReadFailed(Error)
    case configFileWriteFailed(Error)
    case invalidConfigFormat
    
    var errorDescription: String? {
        switch self {
        case .configDirectoryCreationFailed:
            return "Failed to create configuration directory"
        case .configFileReadFailed(let error):
            return "Failed to read configuration file: \(error.localizedDescription)"
        case .configFileWriteFailed(let error):
            return "Failed to write configuration file: \(error.localizedDescription)"
        case .invalidConfigFormat:
            return "Configuration file format is invalid"
        }
    }
}

final class ConfigService: ObservableObject {
    @Published var config: RiceBarConfig
    @Published var shortcutsUpdated = false
    
    private let configURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    static let shared = ConfigService()
    
    private init() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let riceBarURL = homeURL.appendingPathComponent(".ricebar")
        self.configURL = riceBarURL.appendingPathComponent("config.json")
        
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            try FileManager.default.createDirectory(at: riceBarURL, withIntermediateDirectories: true)
        } catch {
            print("Warning: Could not create .ricebar directory: \(error)")
        }
        
        self.config = Self.loadConfig(from: configURL) ?? .default
        
        saveConfig()
    }
    
    func saveConfig() {
        do {
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
    
    func reloadConfig() {
        if let loadedConfig = Self.loadConfig(from: configURL) {
            DispatchQueue.main.async {
                self.config = loadedConfig
            }
        }
    }
    
    func resetToDefaults() {
        DispatchQueue.main.async {
            self.config = .default
            self.saveConfig()
        }
    }
    
    func updateShortcut(for key: String, to value: String) {
        DispatchQueue.main.async {
            self.config.shortcuts.profileShortcuts[key] = value
            self.saveConfig()
            self.shortcutsUpdated.toggle() // Trigger notification
        }
    }
    
    func updateNavigationShortcut(_ keyPath: WritableKeyPath<NavigationShortcuts, String>, to value: String) {
        DispatchQueue.main.async {
            self.config.shortcuts.navigationShortcuts[keyPath: keyPath] = value
            self.saveConfig()
            self.shortcutsUpdated.toggle() // Trigger notification
        }
    }
    
    func updateQuickActionShortcut(_ keyPath: WritableKeyPath<QuickActionShortcuts, String>, to value: String) {
        DispatchQueue.main.async {
            self.config.shortcuts.quickActions[keyPath: keyPath] = value
            self.saveConfig()
            self.shortcutsUpdated.toggle() // Trigger notification
        }
    }
    
    func updateGeneralSetting<T>(_ keyPath: WritableKeyPath<GeneralConfig, T>, to value: T) {
        DispatchQueue.main.async {
            self.config.general[keyPath: keyPath] = value
            self.saveConfig()
        }
    }
    
    func updateAppearanceSetting<T>(_ keyPath: WritableKeyPath<AppearanceConfig, T>, to value: T) {
        DispatchQueue.main.async {
            self.config.appearance[keyPath: keyPath] = value
            self.saveConfig()
        }
    }
    
    
    private static func loadConfig(from url: URL) -> RiceBarConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(RiceBarConfig.self, from: data)
        } catch {
            print("Failed to load config: \(error)")
            return nil
        }
    }
}
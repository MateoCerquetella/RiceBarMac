import Foundation
import AppKit


enum Constants {
    
    
    static let appName = "RiceBarMac"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.ricebar.RiceBarMac"
    
    
    static let profileFileCandidates: [String] = [
        "profile.yml",
        "profile.yaml", 
        "profile.json"
    ]
    
    static let wallpaperExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "gif", "bmp", "tiff"
    ]
    
    static let preferredWallpaperPrefixes: [String] = [
        "wallpaper", "background", "bg", "desktop"
    ]
    
    
    private static let ricebarRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".ricebarmac", isDirectory: true)
    
    static let profilesRoot = ricebarRoot
        .appendingPathComponent("profiles", isDirectory: true)
    
    static let backupsRoot = ricebarRoot
        .appendingPathComponent("backups", isDirectory: true)
    
    static let cacheRoot = ricebarRoot
        .appendingPathComponent("cache", isDirectory: true)
    
    static let tempRoot = ricebarRoot
        .appendingPathComponent("temp", isDirectory: true)
    
    static let managedDirectories = [
        ricebarRoot, profilesRoot, backupsRoot, cacheRoot, tempRoot
    ]
    
    
    static let alacrittyDirRelative = ".config/alacritty"
    
    static let alacrittyYml = "alacritty.yml"
    
    static let alacrittyToml = "alacritty.toml"
    
    enum TerminalType: String, CaseIterable {
        case alacritty = "alacritty"
        case terminalApp = "terminal"
        case iterm2 = "iterm2"
        case kitty = "kitty"
        case wezterm = "wezterm"
        
        var displayName: String {
            switch self {
            case .alacritty: return "Alacritty"
            case .terminalApp: return "Terminal.app"
            case .iterm2: return "iTerm2"
            case .kitty: return "Kitty"
            case .wezterm: return "WezTerm"
            }
        }
    }
    
    
    static let vscodeConfigDir = "Library/Application Support/Code/User"
    
    static let vscodeSettings = "settings.json"
    
    static let vscodeKeybindings = "keybindings.json"
    
    static let vscodeSnippetsDir = "snippets"
    
    static let cursorConfigDir = "Library/Application Support/Cursor/User"
    
    static let cursorSettings = "settings.json"
    
    static let cursorKeybindings = "keybindings.json"
    
    static let cursorSnippetsDir = "snippets"
    
    enum IDEType: String, CaseIterable {
        case vscode = "vscode"
        case cursor = "cursor"
        
        var displayName: String {
            switch self {
            case .vscode: return "Visual Studio Code"
            case .cursor: return "Cursor"
            }
        }
        
        var configDirectory: String {
            switch self {
            case .vscode: return Constants.vscodeConfigDir
            case .cursor: return Constants.cursorConfigDir
            }
        }
        
        var settingsFile: String {
            switch self {
            case .vscode: return Constants.vscodeSettings
            case .cursor: return Constants.cursorSettings
            }
        }
        
        var keybindingsFile: String {
            switch self {
            case .vscode: return Constants.vscodeKeybindings
            case .cursor: return Constants.cursorKeybindings
            }
        }
        
        var snippetsDirectory: String {
            switch self {
            case .vscode: return Constants.vscodeSnippetsDir
            case .cursor: return Constants.cursorSnippetsDir
            }
        }
    }
    
    
    struct DiscoveredTheme {
        let name: String
        let displayName: String
        let extensionId: String?
        let source: ThemeSource
        
        enum ThemeSource {
            case builtin
            case extensionSource(path: String)
        }
    }
    
    
    static let snapshotSkipPatterns: [String] = [
        ".DS_Store",
        "*.bak",
        "*.tmp",
        "*.log",
        "alacritty.ricebar-backup-*",
        ".ricebar-*"
    ]
    
    static let snapshotSkipDirectories: [String] = [
        ".git",
        "node_modules",
        ".cache",
        ".npm",
        ".yarn"
    ]
    
    static let unsafeWritePaths: [String] = [
        "/System",
        "/Library/System",
        "/usr/bin",
        "/usr/sbin",
        "/bin",
        "/sbin",
        "/Applications/Utilities",
        "/private/etc"
    ]
    
    
    static let maxCacheAge: TimeInterval = 300 // 5 minutes
    
    static let fileWatchDebounceInterval: TimeInterval = 0.4
    
    static let recentApplyWindow: TimeInterval = 2.0
    
    static let maxBackupFiles = 10
    
    static let templateRenderTimeout: TimeInterval = 30.0
    
    
    enum MenuKeyEquivalents {
        static let newEmptyProfile = "e"
        static let newFromCurrent = "n"
        static let reloadProfiles = "r"
        static let openFolder = "o"
        static let quit = "q"
    }
    
    enum StatusBarIcon {
        static let systemName = "🍚"  // Rice bowl emoji
        static let accessibilityDescription = "RiceBar"
        static let menuBarLength = NSStatusItem.squareLength
    }
    
    
    enum HotkeyModifiers {
        static let control = ["ctrl", "control"]
        static let command = ["cmd", "command"]
        static let option = ["opt", "option", "alt"]
        static let shift = ["shift"]
    }
    
    enum SpecialKeys {
        static let arrows = ["left", "right", "up", "down"]
        static let function = ["f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]
        static let control = ["space", "tab", "return", "enter", "escape", "esc", "delete"]
    }
    
    
    static let maxProfileNameLength = 50
    
    static let invalidProfileNameCharacters: CharacterSet = {
        var set = CharacterSet(charactersIn: "/\\:*?\"<>|")
        set.insert(charactersIn: "\0\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{20}\u{21}\u{22}\u{23}\u{24}\u{25}\u{26}\u{27}\u{28}\u{29}\u{30}\u{31}")
        return set
    }()
    
    static let reservedProfileNames: Set<String> = [
        "default", "system", "temp", "backup", "cache", "current", "active"
    ]
    
    
    enum ErrorMessages {
        static let profileNotFound = "Profile not found"
        static let profileAlreadyExists = "A profile with this name already exists"
        static let invalidProfileName = "Invalid profile name"
        static let cannotDeleteActiveProfile = "Cannot delete the currently active profile"
        static let fileNotFound = "File not found"
        static let permissionDenied = "Permission denied"
        static let templateRenderingFailed = "Template rendering failed"
        static let wallpaperSetFailed = "Failed to set wallpaper"
        static let hotKeyRegistrationFailed = "Failed to register hotkey"
        static let launchAtLoginFailed = "Failed to configure launch at login"
    }
    
    
    enum SuccessMessages {
        static let profileCreated = "Profile created successfully"
        static let profileDeleted = "Profile deleted successfully"
        static let profileApplied = "Profile applied successfully"
        static let wallpaperUpdated = "Wallpaper updated successfully"
        static let settingsUpdated = "Settings updated successfully"
    }
    
    
    static let templateExtension = ".template"
    
    enum TemplateVariables {
        static let variablePrefix = "{{"
        static let variableSuffix = "}}"
        
        static let standardVariables = [
            "wallpaperPath",
            "profileName",
            "homeDirectory",
            "configDirectory"
        ]
        
        static let paletteVariableCount = 10
    }
    
    
    enum ConfigFormat: String, CaseIterable {
        case json = "json"
        case yaml = "yaml"
        case yml = "yml"
        case toml = "toml"
        
        var displayName: String {
            switch self {
            case .json: return "JSON"
            case .yaml, .yml: return "YAML"
            case .toml: return "TOML"
            }
        }
        
        var fileExtension: String {
            return rawValue
        }
    }
    
    
    static func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default
        
        for directory in managedDirectories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
    
    static func isValidProfileName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty && trimmed.count <= maxProfileNameLength else {
            return false
        }
        
        guard trimmed.rangeOfCharacter(from: invalidProfileNameCharacters) == nil else {
            return false
        }
        
        guard !reservedProfileNames.contains(trimmed.lowercased()) else {
            return false
        }
        
        return true
    }
    
    static func sanitizeProfileName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "-")
            .replacingOccurrences(of: "?", with: "-")
            .replacingOccurrences(of: "\"", with: "-")
            .replacingOccurrences(of: "<", with: "-")
            .replacingOccurrences(of: ">", with: "-")
            .replacingOccurrences(of: "|", with: "-")
    }
}


@available(*, deprecated, message: "Use Constants.profilesRoot, Constants.backupsRoot, etc. instead")
enum ConfigAccess {
    static let defaultRoot = Constants.profilesRoot
    static let backupsRoot = Constants.backupsRoot
    static let cacheRoot = Constants.cacheRoot
    
    static func ensureDirectoriesExist() throws {
        try Constants.ensureDirectoriesExist()
    }
}


@available(*, deprecated, message: "Use Constants instead")
enum AppConstants {
    static let profileFileCandidates = Constants.profileFileCandidates
    static let wallpaperExtensions = Constants.wallpaperExtensions
    static let preferredWallpaperPrefixes = Constants.preferredWallpaperPrefixes
    static let alacrittyDirRelative = Constants.alacrittyDirRelative
    static let alacrittyYml = Constants.alacrittyYml
    static let alacrittyToml = Constants.alacrittyToml
}
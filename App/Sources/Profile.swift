import Foundation


enum ProfileValidationError: LocalizedError {
    case invalidProfileName
    case invalidHotkey
    case directoryNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidProfileName:
            return "Invalid profile name"
        case .invalidHotkey:
            return "Invalid hotkey format"
        case .directoryNotFound(let path):
            return "Profile directory not found: \(path)"
        }
    }
}

struct Profile: Codable, Equatable, Hashable {
    var name: String {
        didSet {
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/", with: "-")
        }
    }
    var order: Int = 0
    var hotkey: String? // e.g. ctrl+cmd+1

    var wallpaper: String? // relative path

    struct Terminal: Codable, Equatable, Hashable {
        enum Kind: String, Codable, Equatable, Hashable, CaseIterable { 
            case alacritty, terminalApp, iterm2 
            
            var displayName: String {
                switch self {
                case .alacritty: return "Alacritty"
                case .terminalApp: return "Terminal.app"
                case .iterm2: return "iTerm2"
                }
            }
        }
        
        enum ThemeSource: String, Codable, Equatable, Hashable {
            case builtin = "builtin"      // Built-in theme name
            case file = "file"            // Relative path to config file
            case url = "url"              // URL to download theme from
            
            var displayName: String {
                switch self {
                case .builtin: return "Built-in"
                case .file: return "File"
                case .url: return "URL"
                }
            }
        }
        
        var kind: Kind
        var theme: String? // theme name, relative path, or URL
        var themeSource: ThemeSource? = .builtin
        var fontSize: Int? = 12
        var fontFamily: String? = "SF Mono"
        var opacity: Double? = 1.0
        
        init(kind: Kind) {
            self.kind = kind
            self.themeSource = .builtin
        }
    }
    var terminal: Terminal?
    
    struct IDE: Codable, Equatable, Hashable {
        enum Kind: String, Codable, Equatable, Hashable { 
            case vscode, cursor 
            
            var displayName: String {
                switch self {
                case .vscode: return "VS Code"
                case .cursor: return "Cursor"
                }
            }
        }
        
        enum ThemeSource: String, Codable, Equatable, Hashable {
            case builtin = "builtin"      // Built-in theme name
            case extensionTheme = "extension"  // Extension-provided theme
            case file = "file"            // Relative path to custom theme
            
            var displayName: String {
                switch self {
                case .builtin: return "Built-in"
                case .extensionTheme: return "Extension"
                case .file: return "File"
                }
            }
        }
        
        var kind: Kind
        var theme: String? // theme name, extension name, or relative path
        var themeSource: ThemeSource? = .builtin
        var extensions: [String]? // list of extension IDs to install
        var fontSize: Int? = 14
        var fontFamily: String? = "SF Mono"
        var wordWrap: Bool? = true
        
        init(kind: Kind) {
            self.kind = kind
            self.themeSource = .builtin
        }
    }
    var ide: IDE?

    struct Replacement: Codable, Equatable, Hashable {
        var source: String // relative path within profile dir
        var destination: String // absolute path, supports ~ expansion
    }
    var replacements: [Replacement]? = []

    var startupScript: String? // relative path
    
    struct SystemTheme: Codable, Equatable, Hashable {
        enum Appearance: String, Codable, CaseIterable {
            case light = "light"
            case dark = "dark"
            case auto = "auto"
            
            var displayName: String {
                switch self {
                case .light: return "Light"
                case .dark: return "Dark"
                case .auto: return "Auto"
                }
            }
        }
        
        var appearance: Appearance? = .auto
        var accentColor: String? // macOS accent color name
        var menuBarStyle: String? // "transparent", "opaque", etc.
        var dockPosition: String? // "bottom", "left", "right"
        var dockSize: String? // "small", "medium", "large"
        
        init() {
            self.appearance = .auto
        }
    }
    var systemTheme: SystemTheme?
    
    func validate() throws {
        guard !name.isEmpty else {
            throw ProfileValidationError.invalidProfileName
        }
        
        if let hotkey = hotkey {
            let parts = hotkey.lowercased().split(separator: "+")
            guard parts.count >= 2 else {
                throw ProfileValidationError.invalidHotkey
            }
        }
        
        // Validate terminal theme configuration
        if let terminal = terminal {
            if let theme = terminal.theme, theme.isEmpty {
                throw ProfileValidationError.invalidProfileName // Could add specific theme validation errors
            }
            
            if let fontSize = terminal.fontSize, fontSize < 8 || fontSize > 72 {
                throw ProfileValidationError.invalidProfileName // Font size validation
            }
            
            if let opacity = terminal.opacity, opacity < 0.1 || opacity > 1.0 {
                throw ProfileValidationError.invalidProfileName // Opacity validation
            }
        }
        
        // Validate IDE theme configuration
        if let ide = ide {
            if let theme = ide.theme, theme.isEmpty {
                throw ProfileValidationError.invalidProfileName
            }
            
            if let fontSize = ide.fontSize, fontSize < 8 || fontSize > 72 {
                throw ProfileValidationError.invalidProfileName
            }
        }
    }
    
    init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }
}

struct ProfileDescriptor: Hashable, Equatable {
    let profile: Profile
    let directory: URL
    
    var displayName: String {
        return profile.name.isEmpty ? directory.lastPathComponent : profile.name
    }
    
    var id: String {
        return directory.lastPathComponent
    }
    
    func validate() throws {
        try profile.validate()
        
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ProfileValidationError.directoryNotFound(directory.path)
        }
    }
}

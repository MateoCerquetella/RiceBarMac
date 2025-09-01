import Foundation
import Combine
import AppKit

// MARK: - Theme Models

enum ThemeType: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case highContrast = "high-contrast"
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .highContrast: return "High Contrast"
        }
    }
    
    var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .highContrast: return "circle.lefthalf.filled"
        }
    }
}

struct IDETheme: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let type: ThemeType
    let ideType: Constants.IDEType
    let source: Profile.IDE.ThemeSource
}

struct TerminalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let type: ThemeType
    let terminalType: Profile.Terminal.Kind
    let source: Profile.Terminal.ThemeSource
    let filePath: String? // For file-based themes
}

struct SystemTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let appearance: Profile.SystemTheme.Appearance
    let accentColors: [String] // Available accent colors
}

enum ThemeServiceError: LocalizedError {
    case settingsFileNotFound
    case invalidSettingsFormat
    case themeNotFound
    case applicationNotInstalled(Constants.IDEType)
    
    var errorDescription: String? {
        switch self {
        case .settingsFileNotFound:
            return "Settings file not found"
        case .invalidSettingsFormat:
            return "Invalid settings file format"
        case .themeNotFound:
            return "Theme not found"
        case .applicationNotInstalled(let ideType):
            return "\(ideType.displayName) is not installed"
        }
    }
}

final class ThemeService: ObservableObject {
    static let shared = ThemeService()
    
    @Published var availableIDEThemes: [IDETheme] = []
    @Published var availableTerminalThemes: [TerminalTheme] = []
    @Published var availableSystemThemes: [SystemTheme] = []
    
    @Published var currentVSCodeTheme: String?
    @Published var currentCursorTheme: String?
    @Published var currentTerminalTheme: String?
    @Published var currentSystemAppearance: Profile.SystemTheme.Appearance = .auto
    
    @Published var isLoading = false
    
    private let fileManager = FileManager.default
    
    private init() {
        refreshAllThemes()
        detectCurrentThemes()
    }
    
    // MARK: - Public Methods
    
    func refreshAllThemes() {
        isLoading = true
        
        Task {
            let (ideThemes, terminalThemes, systemThemes) = await loadAllAvailableThemes()
            
            await MainActor.run {
                self.availableIDEThemes = ideThemes.sorted { $0.displayName < $1.displayName }
                self.availableTerminalThemes = terminalThemes.sorted { $0.displayName < $1.displayName }
                self.availableSystemThemes = systemThemes.sorted { $0.displayName < $1.displayName }
                self.isLoading = false
            }
        }
    }
    
    func refreshAvailableThemes() {
        refreshAllThemes()
    }
    
    func detectCurrentThemes() {
        Task {
            let vscodeTheme = await getCurrentTheme(for: .vscode)
            let cursorTheme = await getCurrentTheme(for: .cursor)
            let terminalTheme = await getCurrentTerminalTheme()
            let systemAppearance = await getCurrentSystemAppearance()
            
            await MainActor.run {
                self.currentVSCodeTheme = vscodeTheme
                self.currentCursorTheme = cursorTheme
                self.currentTerminalTheme = terminalTheme
                self.currentSystemAppearance = systemAppearance
            }
        }
    }
    
    func getCurrentTheme(for ideType: Constants.IDEType) async -> String? {
        let settingsPath = ideType.settingsPath.expandingTildeInPath
        guard fileManager.fileExists(atPath: settingsPath) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let theme = json["workbench.colorTheme"] as? String {
                return theme
            }
        } catch {
            print("Error reading \(ideType.displayName) settings: \(error)")
        }
        
        return nil
    }
    
    func applyTheme(_ theme: IDETheme) async throws {
        let settingsPath = theme.ideType.settingsPath.expandingTildeInPath
        let settingsURL = URL(fileURLWithPath: settingsPath)
        
        // Ensure directory exists
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), 
                                      withIntermediateDirectories: true)
        
        var settings: [String: Any] = [:]
        
        // Read existing settings if they exist
        if fileManager.fileExists(atPath: settingsPath) {
            do {
                let data = try Data(contentsOf: settingsURL)
                if let existingSettings = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings = existingSettings
                }
            } catch {
                print("Warning: Could not read existing settings, creating new file")
            }
        }
        
        // Update theme setting
        settings["workbench.colorTheme"] = theme.name
        
        // Write back to file
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL)
        
        // Update current theme cache
        await MainActor.run {
            switch theme.ideType {
            case .vscode:
                self.currentVSCodeTheme = theme.name
            case .cursor:
                self.currentCursorTheme = theme.name
            }
        }
    }
    
    func isIDEInstalled(_ ideType: Constants.IDEType) -> Bool {
        let settingsDirectory = URL(fileURLWithPath: ideType.settingsPath.expandingTildeInPath)
            .deletingLastPathComponent()
        return fileManager.fileExists(atPath: settingsDirectory.path)
    }
    
    func getInstalledIDEs() -> [Constants.IDEType] {
        return Constants.IDEType.allCases.filter { isIDEInstalled($0) }
    }
    
    // MARK: - Terminal Theme Methods
    
    func getCurrentTerminalTheme() async -> String? {
        // Check Alacritty config
        let alacrittyPath = "~/.config/alacritty/alacritty.yml".expandingTildeInPath
        if fileManager.fileExists(atPath: alacrittyPath) {
            // Parse YAML for theme info - simplified for now
            return "Default"
        }
        return nil
    }
    
    func applyTerminalTheme(_ theme: TerminalTheme) async throws {
        switch theme.terminalType {
        case .alacritty:
            try await applyAlacrittyTheme(theme)
        case .terminalApp:
            try await applyTerminalAppTheme(theme)
        case .iterm2:
            try await applyITerm2Theme(theme)
        }
        
        await MainActor.run {
            self.currentTerminalTheme = theme.name
        }
    }
    
    // MARK: - System Theme Methods
    
    func getCurrentSystemAppearance() async -> Profile.SystemTheme.Appearance {
        // Get system appearance using NSApplication
        return await MainActor.run {
            if NSApp.effectiveAppearance.bestMatch(from: [NSAppearance.Name.darkAqua, NSAppearance.Name.aqua]) == NSAppearance.Name.darkAqua {
                return .dark
            } else {
                return .light
            }
        }
    }
    
    func applySystemTheme(_ theme: SystemTheme) async throws {
        // Apply system appearance changes
        // This would require more sophisticated AppleScript execution
        // For now, just update our cache
        await MainActor.run {
            self.currentSystemAppearance = theme.appearance
        }
    }
    
    // MARK: - Profile Theme Application
    
    func applyProfileThemes(_ profile: Profile) async throws {
        // Apply IDE theme
        if let ide = profile.ide, let themeName = ide.theme {
            if let theme = availableIDEThemes.first(where: { $0.name == themeName && $0.ideType.rawValue == ide.kind.rawValue }) {
                try await applyTheme(theme)
            }
        }
        
        // Apply terminal theme
        if let terminal = profile.terminal, let themeName = terminal.theme {
            if let theme = availableTerminalThemes.first(where: { $0.name == themeName && $0.terminalType == terminal.kind }) {
                try await applyTerminalTheme(theme)
            }
        }
        
        // Apply system theme
        if let systemTheme = profile.systemTheme {
            if let theme = availableSystemThemes.first(where: { $0.appearance == systemTheme.appearance }) {
                try await applySystemTheme(theme)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadAllAvailableThemes() async -> ([IDETheme], [TerminalTheme], [SystemTheme]) {
        let ideThemes = await loadIDEThemes()
        let terminalThemes = await loadTerminalThemes()
        let systemThemes = await loadSystemThemes()
        
        return (ideThemes, terminalThemes, systemThemes)
    }
    
    private func loadIDEThemes() async -> [IDETheme] {
        var themes: [IDETheme] = []
        
        // Add built-in IDE themes
        themes.append(contentsOf: getBuiltInIDEThemes())
        
        // Scan for installed extension themes
        for ideType in Constants.IDEType.allCases where isIDEInstalled(ideType) {
            themes.append(contentsOf: await scanInstalledIDEThemes(for: ideType))
        }
        
        return themes
    }
    
    private func loadTerminalThemes() async -> [TerminalTheme] {
        var themes: [TerminalTheme] = []
        
        // Add built-in terminal themes
        themes.append(contentsOf: getBuiltInTerminalThemes())
        
        return themes
    }
    
    private func loadSystemThemes() async -> [SystemTheme] {
        return getBuiltInSystemThemes()
    }
    
    private func getBuiltInIDEThemes() -> [IDETheme] {
        let builtInThemes: [(String, String, ThemeType)] = [
            // VS Code built-in themes
            ("Default Dark+", "Default Dark+", .dark),
            ("Default Light+", "Default Light+", .light),
            ("Dark+ (default dark)", "Dark+ (default dark)", .dark),
            ("Light+ (default light)", "Light+ (default light)", .light),
            ("Dark (Visual Studio)", "Dark (Visual Studio)", .dark),
            ("Light (Visual Studio)", "Light (Visual Studio)", .light),
            ("Monokai", "Monokai", .dark),
            ("Solarized Light", "Solarized Light", .light),
            ("Solarized Dark", "Solarized Dark", .dark),
            ("Quiet Light", "Quiet Light", .light),
            ("Red", "Red", .dark),
            ("Kimbie Dark", "Kimbie Dark", .dark),
            ("Abyss", "Abyss", .dark),
            ("Tomorrow Night Blue", "Tomorrow Night Blue", .dark),
            ("High Contrast", "High Contrast", .highContrast)
        ]
        
        var themes: [IDETheme] = []
        
        for ideType in Constants.IDEType.allCases where isIDEInstalled(ideType) {
            for (id, displayName, type) in builtInThemes {
                themes.append(IDETheme(
                    id: "\(ideType.rawValue)-\(id)",
                    name: id,
                    displayName: displayName,
                    type: type,
                    ideType: ideType,
                    source: .builtin
                ))
            }
        }
        
        return themes
    }
    
    private func getBuiltInTerminalThemes() -> [TerminalTheme] {
        let builtInThemes: [(String, String, ThemeType)] = [
            ("Default", "Default", .light),
            ("Dark", "Dark", .dark),
            ("Solarized Light", "Solarized Light", .light),
            ("Solarized Dark", "Solarized Dark", .dark),
            ("Dracula", "Dracula", .dark),
            ("Monokai", "Monokai", .dark),
            ("One Dark", "One Dark", .dark),
            ("One Light", "One Light", .light),
            ("Gruvbox Light", "Gruvbox Light", .light),
            ("Gruvbox Dark", "Gruvbox Dark", .dark)
        ]
        
        var themes: [TerminalTheme] = []
        
        for terminalType in Profile.Terminal.Kind.allCases {
            for (id, displayName, type) in builtInThemes {
                themes.append(TerminalTheme(
                    id: "\(terminalType.rawValue)-\(id)",
                    name: id,
                    displayName: displayName,
                    type: type,
                    terminalType: terminalType,
                    source: .builtin,
                    filePath: nil
                ))
            }
        }
        
        return themes
    }
    
    private func getBuiltInSystemThemes() -> [SystemTheme] {
        return [
            SystemTheme(
                id: "light",
                name: "Light",
                displayName: "Light",
                appearance: .light,
                accentColors: ["Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite"]
            ),
            SystemTheme(
                id: "dark",
                name: "Dark",
                displayName: "Dark",
                appearance: .dark,
                accentColors: ["Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite"]
            ),
            SystemTheme(
                id: "auto",
                name: "Auto",
                displayName: "Auto",
                appearance: .auto,
                accentColors: ["Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite"]
            )
        ]
    }
    
    private func scanInstalledIDEThemes(for ideType: Constants.IDEType) async -> [IDETheme] {
        // This would scan the extensions directory for installed theme extensions
        // For now, return empty array - can be implemented later for full theme discovery
        return []
    }
    
    // MARK: - Terminal Theme Implementation Methods
    
    private func applyAlacrittyTheme(_ theme: TerminalTheme) async throws {
        let configPath = "~/.config/alacritty/alacritty.yml".expandingTildeInPath
        let configURL = URL(fileURLWithPath: configPath)
        
        // Create config directory if needed
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), 
                                      withIntermediateDirectories: true)
        
        // For now, create a basic config with theme
        let config = """
        # Alacritty configuration
        colors:
          primary:
            background: '\(theme.type == .dark ? "0x1e1e1e" : "0xffffff")'
            foreground: '\(theme.type == .dark ? "0xd4d4d4" : "0x000000")'
        
        font:
          normal:
            family: SF Mono
          size: 12.0
        
        window:
          opacity: 1.0
        """
        
        try config.write(to: configURL, atomically: true, encoding: .utf8)
    }
    
    private func applyTerminalAppTheme(_ theme: TerminalTheme) async throws {
        // Terminal.app theme application would use AppleScript
        // For now, just log the theme name
        print("Would apply Terminal.app theme: \(theme.name)")
    }
    
    private func applyITerm2Theme(_ theme: TerminalTheme) async throws {
        // iTerm2 theme application would modify preferences
        // For now, just log the theme name
        print("Would apply iTerm2 theme: \(theme.name)")
    }
}

private extension String {
    var expandingTildeInPath: String {
        return NSString(string: self).expandingTildeInPath
    }
}
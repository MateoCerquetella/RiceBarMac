import Foundation
import AppKit
import ServiceManagement
import HotKey
import Combine


enum SystemServiceError: LocalizedError {
    case hotKeyParsingFailed(String)
    case hotKeyRegistrationFailed(String)
    case launchAtLoginFailed
    case launchAtLoginDisableFailed
    case launchAtLoginRequiresApproval
    case launchAtLoginNotFound
    case unsupportedVersion
    
    var errorDescription: String? {
        switch self {
        case .hotKeyParsingFailed(let keyString):
            return "Failed to parse hotkey: \(keyString)"
        case .hotKeyRegistrationFailed(let keyString):
            return "Failed to register hotkey: \(keyString)"
        case .launchAtLoginFailed:
            return "Failed to enable launch at login"
        case .launchAtLoginDisableFailed:
            return "Failed to disable launch at login"
        case .launchAtLoginRequiresApproval:
            return "Launch at login requires approval in System Settings"
        case .launchAtLoginNotFound:
            return "App not found for launch at login"
        case .unsupportedVersion:
            return "Launch at login requires macOS 13.0 or later"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .unsupportedVersion, .launchAtLoginFailed, .launchAtLoginDisableFailed:
            return "You can manually add RiceBarMac to your login items in System Preferences > Users & Groups > Login Items"
        default:
            return nil
        }
    }
}


final class SystemService: ObservableObject {
    
    
    @Published private(set) var registeredHotKeys: [String] = []
    @Published private(set) var isLaunchAtLoginEnabled = false
    @Published private(set) var launchAtLoginError: Error?
    
    
    private var hotkeys: [HotKey] = []
    
    
    static let shared = SystemService()
    
    private init() {
        updateLaunchAtLoginStatus()
        syncConfigWithSystem()
        
        // Initialize error state on startup
        if #unavailable(macOS 13.0) {
            DispatchQueue.main.async {
                self.launchAtLoginError = SystemServiceError.unsupportedVersion
            }
        }
    }
    
    
    func registerHotKeys(profiles: [ProfileDescriptor], onTrigger: @escaping (ProfileDescriptor) -> Void) {
        clearHotKeys()
        
        var registeredKeys: [String] = []
        let config = ConfigService.shared.config
        
        // Register profile shortcuts (1-9)
        for (index, descriptor) in profiles.prefix(9).enumerated() {
            let profileKey = "profile\(index + 1)"
            guard let shortcutString = config.shortcuts.profileShortcuts[profileKey] else { 
                print("No shortcut configured for \(profileKey)")
                continue 
            }
            
            do {
                let combo = try parseKeyCombo(shortcutString)
                let hotKey = HotKey(keyCombo: combo)
                
                hotKey.keyDownHandler = { 
                    print("Profile hotkey triggered: \(shortcutString) → \(descriptor.profile.name)")
                    onTrigger(descriptor) 
                }
                
                hotkeys.append(hotKey)
                registeredKeys.append("\(shortcutString) → \(descriptor.profile.name)")
                print("Successfully registered hotkey: \(shortcutString) → \(descriptor.profile.name)")
                
            } catch {
                print("Failed to register profile hotkey '\(shortcutString)' for \(descriptor.profile.name): \(error)")
                continue
            }
        }
        
        // Register individual profile hotkeys
        for descriptor in profiles {
            guard let comboString = descriptor.profile.hotkey else { continue }
            
            do {
                let combo = try parseKeyCombo(comboString)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = { 
                    print("Individual profile hotkey triggered: \(comboString) → \(descriptor.profile.name)")
                    onTrigger(descriptor) 
                }
                hotkeys.append(hotKey)
                registeredKeys.append("\(comboString) → \(descriptor.profile.name)")
                print("Successfully registered individual hotkey: \(comboString) → \(descriptor.profile.name)")
                
            } catch {
                print("Failed to register individual hotkey '\(comboString)' for \(descriptor.profile.name): \(error)")
            }
        }
        
        DispatchQueue.main.async {
            self.registeredHotKeys = registeredKeys
            print("Total registered hotkeys: \(registeredKeys.count)")
        }
    }
    
    func registerNavigationHotKeys(onNextProfile: @escaping () -> Void, onPreviousProfile: @escaping () -> Void, onReloadProfiles: @escaping () -> Void) {
        let config = ConfigService.shared.config
        
        // Register Next Profile hotkey
        let nextProfileShortcut = config.shortcuts.navigationShortcuts.nextProfile
        if !nextProfileShortcut.isEmpty {
            do {
                let combo = try parseKeyCombo(nextProfileShortcut)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = {
                    print("Next profile hotkey triggered: \(nextProfileShortcut)")
                    onNextProfile()
                }
                hotkeys.append(hotKey)
                print("Successfully registered navigation hotkey: \(nextProfileShortcut) → Next Profile")
            } catch {
                print("Failed to register next profile hotkey '\(nextProfileShortcut)': \(error)")
            }
        }
        
        // Register Previous Profile hotkey
        let previousProfileShortcut = config.shortcuts.navigationShortcuts.previousProfile
        if !previousProfileShortcut.isEmpty {
            do {
                let combo = try parseKeyCombo(previousProfileShortcut)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = {
                    print("Previous profile hotkey triggered: \(previousProfileShortcut)")
                    onPreviousProfile()
                }
                hotkeys.append(hotKey)
                print("Successfully registered navigation hotkey: \(previousProfileShortcut) → Previous Profile")
            } catch {
                print("Failed to register previous profile hotkey '\(previousProfileShortcut)': \(error)")
            }
        }
        
        // Register Reload Profiles hotkey
        let reloadProfilesShortcut = config.shortcuts.navigationShortcuts.reloadProfiles
        if !reloadProfilesShortcut.isEmpty {
            do {
                let combo = try parseKeyCombo(reloadProfilesShortcut)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = {
                    print("Reload profiles hotkey triggered: \(reloadProfilesShortcut)")
                    onReloadProfiles()
                }
                hotkeys.append(hotKey)
                print("Successfully registered navigation hotkey: \(reloadProfilesShortcut) → Reload Profiles")
            } catch {
                print("Failed to register reload profiles hotkey '\(reloadProfilesShortcut)': \(error)")
            }
        }
    }
    
    func clearHotKeys() {
        hotkeys.removeAll()
        DispatchQueue.main.async {
            self.registeredHotKeys = []
        }
    }
    
    func validateHotKey(_ keyString: String) -> Bool {
        do {
            _ = try parseKeyCombo(keyString)
            return true
        } catch {
            return false
        }
    }
    
    func testShortcut(_ shortcut: String) {
        _ = validateHotKey(shortcut)
    }
    
    
    func updateLaunchAtLoginStatus() {
        let enabled: Bool
        var error: Error?
        
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            
            switch status {
            case .enabled:
                enabled = true
                error = nil  // Clear any previous errors
            case .notRegistered:
                enabled = false
                error = nil  // Not an error, just not registered yet
            case .notFound:
                enabled = false
                error = SystemServiceError.launchAtLoginNotFound
            case .requiresApproval:
                enabled = false
                error = SystemServiceError.launchAtLoginRequiresApproval
            @unknown default:
                enabled = false
                error = SystemServiceError.launchAtLoginFailed
            }
        } else {
            enabled = false
            error = SystemServiceError.unsupportedVersion
        }
        
        DispatchQueue.main.async {
            let wasEnabled = self.isLaunchAtLoginEnabled
            self.isLaunchAtLoginEnabled = enabled
            self.launchAtLoginError = error
            
            // Sync config if status changed
            if wasEnabled != enabled {
                ConfigService.shared.updateGeneralSetting(\.launchAtLogin, to: enabled)
            }
        }
    }
    
    func toggleLaunchAtLogin() throws {
        if isLaunchAtLoginEnabled {
            try disableLaunchAtLogin()
        } else {
            try enableLaunchAtLogin()
        }
    }
    
    func enableLaunchAtLogin() throws {
        guard #available(macOS 13.0, *) else {
            DispatchQueue.main.async {
                self.launchAtLoginError = SystemServiceError.unsupportedVersion
            }
            throw SystemServiceError.unsupportedVersion
        }
        
        do {
            try SMAppService.mainApp.register()
            DispatchQueue.main.async {
                self.launchAtLoginError = nil
            }
            updateLaunchAtLoginStatus()
        } catch {
            let serviceError = SystemServiceError.launchAtLoginFailed
            DispatchQueue.main.async {
                self.launchAtLoginError = serviceError
            }
            throw serviceError
        }
    }
    
    func disableLaunchAtLogin() throws {
        guard #available(macOS 13.0, *) else {
            DispatchQueue.main.async {
                self.launchAtLoginError = SystemServiceError.unsupportedVersion
            }
            throw SystemServiceError.unsupportedVersion
        }
        
        do {
            try SMAppService.mainApp.unregister()
            DispatchQueue.main.async {
                self.launchAtLoginError = nil
            }
            updateLaunchAtLoginStatus()
        } catch {
            let serviceError = SystemServiceError.launchAtLoginDisableFailed
            DispatchQueue.main.async {
                self.launchAtLoginError = serviceError
            }
            throw serviceError
        }
    }
    
    func setLaunchAtLogin(enabled: Bool) throws {
        if enabled != isLaunchAtLoginEnabled {
            try toggleLaunchAtLogin()
        }
    }
    
    private func syncConfigWithSystem() {
        // Sync the config with the actual system status
        ConfigService.shared.updateGeneralSetting(\.launchAtLogin, to: isLaunchAtLoginEnabled)
    }
    
    func setDockVisibility() {
        // Always set as accessory app (menu bar only, never shows in dock)
        NSApp.setActivationPolicy(.accessory)
    }
}


private extension SystemService {
    
    func parseKeyCombo(_ string: String) throws -> KeyCombo {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedString.lowercased().split(separator: "+").map { 
            String($0).trimmingCharacters(in: .whitespacesAndNewlines) 
        }
        
        guard !parts.isEmpty else { 
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?
        
        for part in parts {
            switch part {
            case "ctrl", "control": 
                modifiers.insert(.control)
            case "cmd", "command", "⌘": 
                modifiers.insert(.command)
            case "opt", "option", "alt", "⌥": 
                modifiers.insert(.option)
            case "shift", "⇧": 
                modifiers.insert(.shift)
            case "fn", "function":
                modifiers.insert(.function)
            default: 
                // Only set keyString if it hasn't been set yet (last non-modifier wins)
                if keyString == nil || !isModifierString(part) {
                    keyString = part
                }
            }
        }
        
        guard let finalKeyString = keyString, !finalKeyString.isEmpty else { 
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        guard let key = mapKey(finalKeyString) else { 
            throw SystemServiceError.hotKeyParsingFailed("\(string) - unrecognized key: '\(finalKeyString)'") 
        }
        
        return KeyCombo(key: key, modifiers: modifiers)
    }
    
    private func isModifierString(_ string: String) -> Bool {
        let modifierStrings = ["ctrl", "control", "cmd", "command", "⌘", "opt", "option", "alt", "⌥", "shift", "⇧", "fn", "function"]
        return modifierStrings.contains(string.lowercased())
    }
    
    func mapKey(_ s: String) -> Key? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle numbers
        if let number = Int(trimmed), (0...9).contains(number) {
            switch number {
            case 0: return .zero
            case 1: return .one
            case 2: return .two
            case 3: return .three
            case 4: return .four
            case 5: return .five
            case 6: return .six
            case 7: return .seven
            case 8: return .eight
            case 9: return .nine
            default: break
            }
        }
        
        // Handle single character keys
        if trimmed.count == 1, let c = trimmed.uppercased().unicodeScalars.first {
            switch c {
            case "A": return .a
            case "B": return .b
            case "C": return .c
            case "D": return .d
            case "E": return .e
            case "F": return .f
            case "G": return .g
            case "H": return .h
            case "I": return .i
            case "J": return .j
            case "K": return .k
            case "L": return .l
            case "M": return .m
            case "N": return .n
            case "O": return .o
            case "P": return .p
            case "Q": return .q
            case "R": return .r
            case "S": return .s
            case "T": return .t
            case "U": return .u
            case "V": return .v
            case "W": return .w
            case "X": return .x
            case "Y": return .y
            case "Z": return .z
            case "[": return .leftBracket
            case "]": return .rightBracket
            case "\\": return .backslash
            case ";": return .semicolon
            case "'": return .quote
            case ",": return .comma
            case ".": return .period
            case "/": return .slash
            case "`": return .grave
            case "-": return .minus
            case "=": return .equal
            default: break
            }
        }
        
        // Handle special keys and aliases
        switch trimmed.uppercased() {
        case "SPACE", " ": return .space
        case "TAB": return .tab
        case "RETURN", "ENTER": return .return
        case "ESCAPE", "ESC": return .escape
        case "DELETE", "DEL", "BACKSPACE": return .delete
        case "UP", "UPARROW": return .upArrow
        case "DOWN", "DOWNARROW": return .downArrow
        case "LEFT", "LEFTARROW": return .leftArrow
        case "RIGHT", "RIGHTARROW": return .rightArrow
        case "HOME": return .home
        case "END": return .end
        case "PAGEUP", "PGUP": return .pageUp
        case "PAGEDOWN", "PGDN": return .pageDown
        case "F1": return .f1
        case "F2": return .f2
        case "F3": return .f3
        case "F4": return .f4
        case "F5": return .f5
        case "F6": return .f6
        case "F7": return .f7
        case "F8": return .f8
        case "F9": return .f9
        case "F10": return .f10
        case "F11": return .f11
        case "F12": return .f12
        // Additional common special characters
        case "[", "LEFTBRACKET": return .leftBracket
        case "]", "RIGHTBRACKET": return .rightBracket
        case "\\", "BACKSLASH": return .backslash
        case ";", "SEMICOLON": return .semicolon
        case "'", "QUOTE", "APOSTROPHE": return .quote
        case ",", "COMMA": return .comma
        case ".", "PERIOD", "DOT": return .period
        case "/", "SLASH": return .slash
        case "`", "GRAVE", "BACKTICK": return .grave
        case "-", "MINUS", "DASH", "HYPHEN": return .minus
        case "=", "EQUAL", "EQUALS": return .equal
        default: return nil
        }
    }
}
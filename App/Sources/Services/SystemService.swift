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
        
        for (index, descriptor) in profiles.prefix(9).enumerated() {
            let profileKey = "profile\(index + 1)"
            guard let shortcutString = config.shortcuts.profileShortcuts[profileKey] else { continue }
            
            do {
                let combo = try parseKeyCombo(shortcutString)
                let hotKey = HotKey(keyCombo: combo)
                
                hotKey.keyDownHandler = { 
                    onTrigger(descriptor) 
                }
                
                hotkeys.append(hotKey)
                registeredKeys.append("\(shortcutString) → \(descriptor.profile.name)")
                
            } catch {
                continue
            }
        }
        
        for descriptor in profiles {
            guard let comboString = descriptor.profile.hotkey else { continue }
            
            do {
                let combo = try parseKeyCombo(comboString)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = { 
                    onTrigger(descriptor) 
                }
                hotkeys.append(hotKey)
                registeredKeys.append("\(comboString) → \(descriptor.profile.name)")
                
            } catch {
            }
        }
        
        DispatchQueue.main.async {
            self.registeredHotKeys = registeredKeys
        }
    }
    
    func registerNavigationHotKeys(onNextProfile: @escaping () -> Void, onPreviousProfile: @escaping () -> Void, onReloadProfiles: @escaping () -> Void) {
        let config = ConfigService.shared.config
        
        print("🔧 Registering navigation hotkeys...")
        
        // Test the shortcuts first
        print("🧪 Testing shortcuts:")
        testShortcut(config.shortcuts.navigationShortcuts.nextProfile)
        testShortcut(config.shortcuts.navigationShortcuts.previousProfile)
        testShortcut(config.shortcuts.navigationShortcuts.reloadProfiles)
        
        // Register Next Profile hotkey
        if !config.shortcuts.navigationShortcuts.nextProfile.isEmpty {
            print("📱 Next Profile shortcut: \(config.shortcuts.navigationShortcuts.nextProfile)")
            do {
                let combo = try parseKeyCombo(config.shortcuts.navigationShortcuts.nextProfile)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = {
                    print("🎯 Next Profile hotkey triggered!")
                    onNextProfile()
                }
                hotkeys.append(hotKey)
                print("✅ Next Profile hotkey registered successfully")
            } catch {
                print("❌ Failed to register Next Profile hotkey: \(error)")
            }
        } else {
            print("⚠️ Next Profile shortcut is empty")
        }
        
        // Register Previous Profile hotkey
        if !config.shortcuts.navigationShortcuts.previousProfile.isEmpty {
            print("📱 Previous Profile shortcut: \(config.shortcuts.navigationShortcuts.previousProfile)")
            do {
                let combo = try parseKeyCombo(config.shortcuts.navigationShortcuts.previousProfile)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = {
                    print("🎯 Previous Profile hotkey triggered!")
                    onPreviousProfile()
                }
                hotkeys.append(hotKey)
                print("✅ Previous Profile hotkey registered successfully")
            } catch {
                print("❌ Failed to register Previous Profile hotkey: \(error)")
            }
        } else {
            print("⚠️ Previous Profile shortcut is empty")
        }
        
        // Register Reload Profiles hotkey
        if !config.shortcuts.navigationShortcuts.reloadProfiles.isEmpty {
            print("📱 Reload Profiles shortcut: \(config.shortcuts.navigationShortcuts.reloadProfiles)")
            do {
                let combo = try parseKeyCombo(config.shortcuts.navigationShortcuts.reloadProfiles)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = {
                    print("🎯 Reload Profiles hotkey triggered!")
                    onReloadProfiles()
                }
                hotkeys.append(hotKey)
                print("✅ Reload Profiles hotkey registered successfully")
            } catch {
                print("❌ Failed to register Reload Profiles hotkey: \(error)")
            }
        } else {
            print("⚠️ Reload Profiles shortcut is empty")
        }
        
        print("🔧 Navigation hotkeys registration complete. Total hotkeys: \(hotkeys.count)")
    }
    
    func clearHotKeys() {
        hotkeys.removeAll()
        DispatchQueue.main.async {
            self.registeredHotKeys = []
        }
    }
    
    func validateHotKey(_ keyString: String) -> Bool {
        print("🔍 Validating hotkey: '\(keyString)'")
        do {
            let combo = try parseKeyCombo(keyString)
            print("✅ Hotkey validation successful: \(combo)")
            return true
        } catch {
            print("❌ Hotkey validation failed: \(error)")
            return false
        }
    }
    
    func testShortcut(_ shortcut: String) {
        print("🧪 Testing shortcut: '\(shortcut)'")
        if validateHotKey(shortcut) {
            print("✅ Shortcut is valid")
        } else {
            print("❌ Shortcut is invalid")
        }
    }
    
    
    func updateLaunchAtLoginStatus() {
        let enabled: Bool
        var error: Error?
        
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            print("SMAppService status: \(status)")
            
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
            print("Attempting to register launch at login...")
            try SMAppService.mainApp.register()
            print("Launch at login registration successful")
            DispatchQueue.main.async {
                self.launchAtLoginError = nil
            }
            updateLaunchAtLoginStatus()
        } catch {
            print("Launch at login registration failed: \(error)")
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
        print("🔍 Parsing key combo: '\(string)'")
        let parts = string.lowercased().split(separator: "+").map { String($0) }
        print("🔍 Parts: \(parts)")
        guard !parts.isEmpty else { 
            print("❌ Empty key combo")
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?
        
        for part in parts {
            print("🔍 Processing part: '\(part)'")
            switch part {
            case "ctrl", "control": 
                modifiers.insert(.control)
                print("🔍 Added control modifier")
            case "cmd", "command": 
                modifiers.insert(.command)
                print("🔍 Added command modifier")
            case "opt", "option", "alt": 
                modifiers.insert(.option)
                print("🔍 Added option modifier")
            case "shift": 
                modifiers.insert(.shift)
                print("🔍 Added shift modifier")
            default: 
                keyString = part
                print("🔍 Key string: '\(part)'")
            }
        }
        
        guard let keyString = keyString else { 
            print("❌ No key string found")
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        guard let key = mapKey(keyString) else { 
            print("❌ Failed to map key: '\(keyString)'")
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        print("✅ Successfully parsed key combo: \(key) with modifiers: \(modifiers)")
        return KeyCombo(key: key, modifiers: modifiers)
    }
    
    func mapKey(_ s: String) -> Key? {
        if let number = Int(s), (0...9).contains(number) {
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
        
        if s.count == 1, let c = s.uppercased().unicodeScalars.first {
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
        
        switch s.uppercased() {
        case "SPACE": return .space
        case "TAB": return .tab
        case "RETURN", "ENTER": return .return
        case "ESCAPE", "ESC": return .escape
        case "DELETE", "DEL": return .delete
        case "UP": return .upArrow
        case "DOWN": return .downArrow
        case "LEFT": return .leftArrow
        case "RIGHT": return .rightArrow
        case "HOME": return .home
        case "END": return .end
        case "PAGEUP": return .pageUp
        case "PAGEDOWN": return .pageDown
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
        default: return nil
        }
    }
}
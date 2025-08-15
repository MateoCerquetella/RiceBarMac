import Foundation
import AppKit
import ServiceManagement
import HotKey
import Combine

// MARK: - System Service Errors

enum SystemServiceError: LocalizedError {
    case hotKeyParsingFailed(String)
    case hotKeyRegistrationFailed(String)
    case launchAtLoginFailed
    case launchAtLoginDisableFailed
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

// MARK: - System Service

/// Consolidated service for system-level operations including hotkey management 
/// and launch at login functionality.
final class SystemService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var registeredHotKeys: [String] = []
    @Published private(set) var isLaunchAtLoginEnabled = false
    
    // MARK: - Private Properties
    
    private var hotkeys: [HotKey] = []
    
    // MARK: - Singleton
    
    static let shared = SystemService()
    
    private init() {
        updateLaunchAtLoginStatus()
    }
    
    // MARK: - HotKey Management
    
    /// Registers hotkeys for the given profiles
    /// - Parameters:
    ///   - profiles: Array of profile descriptors with hotkey configurations
    ///   - onTrigger: Closure called when a hotkey is triggered
    func registerHotKeys(profiles: [ProfileDescriptor], onTrigger: @escaping (ProfileDescriptor) -> Void) {
        // Clear existing hotkeys
        clearHotKeys()
        
        var registeredKeys: [String] = []
        
        for descriptor in profiles {
            guard let comboString = descriptor.profile.hotkey else { continue }
            
            do {
                let combo = try parseKeyCombo(comboString)
                let hotKey = HotKey(keyCombo: combo)
                hotKey.keyDownHandler = { onTrigger(descriptor) }
                hotkeys.append(hotKey)
                registeredKeys.append(comboString)
                
                LoggerService.info("Registered hotkey '\(comboString)' for profile '\(descriptor.profile.name)'")
            } catch {
                LoggerService.error("Failed to register hotkey '\(comboString)' for profile '\(descriptor.profile.name)': \(error)")
            }
        }
        
        DispatchQueue.main.async {
            self.registeredHotKeys = registeredKeys
        }
    }
    
    /// Clears all registered hotkeys
    func clearHotKeys() {
        hotkeys.removeAll()
        DispatchQueue.main.async {
            self.registeredHotKeys = []
        }
    }
    
    /// Validates if a hotkey string can be parsed successfully
    /// - Parameter keyString: The hotkey string to validate (e.g., "cmd+shift+1")
    /// - Returns: True if the hotkey string is valid
    func validateHotKey(_ keyString: String) -> Bool {
        do {
            _ = try parseKeyCombo(keyString)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Launch at Login Management
    
    /// Checks if the app is currently set to launch at login
    func updateLaunchAtLoginStatus() {
        let enabled: Bool
        if #available(macOS 13.0, *) {
            enabled = SMAppService.mainApp.status == .enabled
        } else {
            // For older macOS versions, we can't reliably check without deprecated APIs
            enabled = false
        }
        
        DispatchQueue.main.async {
            self.isLaunchAtLoginEnabled = enabled
        }
    }
    
    /// Toggles launch at login setting
    func toggleLaunchAtLogin() throws {
        if isLaunchAtLoginEnabled {
            try disableLaunchAtLogin()
        } else {
            try enableLaunchAtLogin()
        }
    }
    
    /// Enables launch at login
    func enableLaunchAtLogin() throws {
        guard #available(macOS 13.0, *) else {
            throw SystemServiceError.unsupportedVersion
        }
        
        do {
            try SMAppService.mainApp.register()
            updateLaunchAtLoginStatus()
            LoggerService.info("Launch at login enabled successfully")
        } catch {
            LoggerService.error("Failed to enable launch at login: \(error)")
            throw SystemServiceError.launchAtLoginFailed
        }
    }
    
    /// Disables launch at login
    func disableLaunchAtLogin() throws {
        guard #available(macOS 13.0, *) else {
            throw SystemServiceError.unsupportedVersion
        }
        
        do {
            try SMAppService.mainApp.unregister()
            updateLaunchAtLoginStatus()
            LoggerService.info("Launch at login disabled successfully")
        } catch {
            LoggerService.error("Failed to disable launch at login: \(error)")
            throw SystemServiceError.launchAtLoginDisableFailed
        }
    }
    
    /// Sets launch at login to a specific state
    /// - Parameter enabled: Whether launch at login should be enabled
    func setLaunchAtLogin(enabled: Bool) throws {
        if enabled != isLaunchAtLoginEnabled {
            try toggleLaunchAtLogin()
        }
    }
}

// MARK: - Private Implementation

private extension SystemService {
    
    /// Parses a hotkey string into a KeyCombo
    /// - Parameter string: String like "ctrl+cmd+1" or "cmd+option+a"
    /// - Returns: KeyCombo object for hotkey registration
    /// - Throws: SystemServiceError if parsing fails
    func parseKeyCombo(_ string: String) throws -> KeyCombo {
        let parts = string.lowercased().split(separator: "+").map { String($0) }
        guard !parts.isEmpty else { 
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?
        
        for part in parts {
            switch part {
            case "ctrl", "control": 
                modifiers.insert(.control)
            case "cmd", "command": 
                modifiers.insert(.command)
            case "opt", "option", "alt": 
                modifiers.insert(.option)
            case "shift": 
                modifiers.insert(.shift)
            default: 
                keyString = part
            }
        }
        
        guard let keyString = keyString else { 
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        guard let key = mapKey(keyString) else { 
            throw SystemServiceError.hotKeyParsingFailed(string) 
        }
        
        return KeyCombo(key: key, modifiers: modifiers)
    }
    
    /// Maps a string to a Key enum value
    /// - Parameter s: String representation of a key
    /// - Returns: Key enum value or nil if not found
    func mapKey(_ s: String) -> Key? {
        // Handle numbers
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
        
        // Handle letters
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
            default: break
            }
        }
        
        // Handle special keys
        switch s {
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "up": return .upArrow
        case "down": return .downArrow
        case "space": return .space
        case "tab": return .tab
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        case "delete": return .delete
        case "f1": return .f1
        case "f2": return .f2
        case "f3": return .f3
        case "f4": return .f4
        case "f5": return .f5
        case "f6": return .f6
        case "f7": return .f7
        case "f8": return .f8
        case "f9": return .f9
        case "f10": return .f10
        case "f11": return .f11
        case "f12": return .f12
        default: return nil
        }
    }
}
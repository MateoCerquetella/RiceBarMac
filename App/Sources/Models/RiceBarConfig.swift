import Foundation

struct RiceBarConfig: Codable {
    var shortcuts: ShortcutConfig
    var general: GeneralConfig
    var appearance: AppearanceConfig
    
    static let `default` = RiceBarConfig(
        shortcuts: ShortcutConfig(),
        general: GeneralConfig(),
        appearance: AppearanceConfig()
    )
}

struct ShortcutConfig: Codable {
    var profileShortcuts: [String: String]
    var navigationShortcuts: NavigationShortcuts
    var quickActions: QuickActionShortcuts
    
    init() {
        self.profileShortcuts = [
            "profile1": "",
            "profile2": "",
            "profile3": "",
            "profile4": "",
            "profile5": "",
            "profile6": "",
            "profile7": "",
            "profile8": "",
            "profile9": ""
        ]
        self.navigationShortcuts = NavigationShortcuts()
        self.quickActions = QuickActionShortcuts()
    }
}

struct NavigationShortcuts: Codable {
    var nextProfile: String
    var previousProfile: String
    var openProfilesFolder: String
    var reloadProfiles: String
    
    init() {
        self.nextProfile = ""
        self.previousProfile = ""
        self.openProfilesFolder = ""
        self.reloadProfiles = ""
    }
}

struct QuickActionShortcuts: Codable {
    var createEmptyProfile: String
    var createFromCurrentSetup: String
    var openSettings: String
    var quitApp: String
    
    init() {
        self.createEmptyProfile = ""
        self.createFromCurrentSetup = ""
        self.openSettings = ""
        self.quitApp = ""
    }
}

struct GeneralConfig: Codable {
    var launchAtLogin: Bool
    var autoReloadProfiles: Bool
    var showNotifications: Bool
    
    init() {
        self.launchAtLogin = false
        self.autoReloadProfiles = true
        self.showNotifications = true
    }
}

struct AppearanceConfig: Codable {
    var menuBarIcon: String
    var showProfileCountInMenu: Bool
    var showShortcutsInMenu: Bool
    var menuItemStyle: MenuItemStyle
    
    init() {
        self.menuBarIcon = "🍚"
        self.showProfileCountInMenu = true
        self.showShortcutsInMenu = true
        self.menuItemStyle = .compact
    }
}

enum MenuItemStyle: String, Codable, CaseIterable {
    case compact = "compact"
    case detailed = "detailed"
    
    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .detailed: return "Detailed"
        }
    }
}



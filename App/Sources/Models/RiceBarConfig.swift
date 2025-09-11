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
            "profile1": "cmd+1",
            "profile2": "cmd+2",
            "profile3": "cmd+3",
            "profile4": "cmd+4",
            "profile5": "cmd+5",
            "profile6": "cmd+6",
            "profile7": "cmd+7",
            "profile8": "cmd+8",
            "profile9": "cmd+9"
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
        self.nextProfile = "cmd+]"
        self.previousProfile = "cmd+["
        self.openProfilesFolder = "cmd+o"
        self.reloadProfiles = "cmd+r"
    }
}

struct QuickActionShortcuts: Codable {
    var createEmptyProfile: String
    var createFromCurrentSetup: String
    var openSettings: String
    var quitApp: String
    
    init() {
        self.createEmptyProfile = "cmd+e"
        self.createFromCurrentSetup = "cmd+n"
        self.openSettings = "cmd+,"
        self.quitApp = "cmd+q"
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



import Foundation

struct RiceBarConfig: Codable, Equatable, Sendable {
    var shortcuts: ShortcutConfig
    var general: GeneralConfig
    var appearance: AppearanceConfig
    
    static let `default` = RiceBarConfig(
        shortcuts: ShortcutConfig(),
        general: GeneralConfig(),
        appearance: AppearanceConfig()
    )

    private enum CodingKeys: String, CodingKey {
        case shortcuts, general, appearance
    }

    init(
        shortcuts: ShortcutConfig = ShortcutConfig(),
        general: GeneralConfig = GeneralConfig(),
        appearance: AppearanceConfig = AppearanceConfig()
    ) {
        self.shortcuts = shortcuts
        self.general = general
        self.appearance = appearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shortcuts = try container.decodeIfPresent(ShortcutConfig.self, forKey: .shortcuts) ?? ShortcutConfig()
        general = try container.decodeIfPresent(GeneralConfig.self, forKey: .general) ?? GeneralConfig()
        appearance = try container.decodeIfPresent(AppearanceConfig.self, forKey: .appearance) ?? AppearanceConfig()
    }
}

struct ShortcutConfig: Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case profileShortcuts, navigationShortcuts, quickActions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var mergedShortcuts = ShortcutConfig().profileShortcuts
        let decodedShortcuts = try container.decodeIfPresent([String: String].self, forKey: .profileShortcuts) ?? [:]
        for (key, value) in decodedShortcuts {
            mergedShortcuts[key] = value
        }
        profileShortcuts = mergedShortcuts
        navigationShortcuts = try container.decodeIfPresent(NavigationShortcuts.self, forKey: .navigationShortcuts) ?? NavigationShortcuts()
        quickActions = try container.decodeIfPresent(QuickActionShortcuts.self, forKey: .quickActions) ?? QuickActionShortcuts()
    }
}

struct NavigationShortcuts: Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case nextProfile, previousProfile, openProfilesFolder, reloadProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextProfile = try container.decodeIfPresent(String.self, forKey: .nextProfile) ?? ""
        previousProfile = try container.decodeIfPresent(String.self, forKey: .previousProfile) ?? ""
        openProfilesFolder = try container.decodeIfPresent(String.self, forKey: .openProfilesFolder) ?? ""
        reloadProfiles = try container.decodeIfPresent(String.self, forKey: .reloadProfiles) ?? ""
    }
}

struct QuickActionShortcuts: Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case createEmptyProfile, createFromCurrentSetup, openSettings, quitApp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createEmptyProfile = try container.decodeIfPresent(String.self, forKey: .createEmptyProfile) ?? ""
        createFromCurrentSetup = try container.decodeIfPresent(String.self, forKey: .createFromCurrentSetup) ?? ""
        openSettings = try container.decodeIfPresent(String.self, forKey: .openSettings) ?? ""
        quitApp = try container.decodeIfPresent(String.self, forKey: .quitApp) ?? ""
    }
}

struct GeneralConfig: Codable, Equatable, Sendable {
    var launchAtLogin: Bool
    var autoReloadProfiles: Bool
    var showNotifications: Bool
    
    init() {
        self.launchAtLogin = false
        self.autoReloadProfiles = true
        self.showNotifications = true
    }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, autoReloadProfiles, showNotifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        autoReloadProfiles = try container.decodeIfPresent(Bool.self, forKey: .autoReloadProfiles) ?? true
        showNotifications = try container.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? true
    }
}

struct AppearanceConfig: Codable, Equatable, Sendable {
    var menuBarIcon: String
    var showProfileCountInMenu: Bool
    var showShortcutsInMenu: Bool
    var menuItemStyle: MenuItemStyle
    
    init() {
        self.menuBarIcon = "RB"
        self.showProfileCountInMenu = true
        self.showShortcutsInMenu = true
        self.menuItemStyle = .compact
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarIcon, showProfileCountInMenu, showShortcutsInMenu, menuItemStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarIcon = try container.decodeIfPresent(String.self, forKey: .menuBarIcon) ?? "RB"
        showProfileCountInMenu = try container.decodeIfPresent(Bool.self, forKey: .showProfileCountInMenu) ?? true
        showShortcutsInMenu = try container.decodeIfPresent(Bool.self, forKey: .showShortcutsInMenu) ?? true
        let style = try container.decodeIfPresent(String.self, forKey: .menuItemStyle)
        menuItemStyle = style.flatMap(MenuItemStyle.init(rawValue:)) ?? .compact
    }
}

enum MenuItemStyle: String, Codable, CaseIterable, Sendable {
    case compact = "compact"
    case detailed = "detailed"
    
    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .detailed: return "Detailed"
        }
    }
}

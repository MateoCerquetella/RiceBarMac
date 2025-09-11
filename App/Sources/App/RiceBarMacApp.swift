import SwiftUI
import AppKit
import Combine

@main
struct RiceBarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    
    
    private let profileService = ProfileService.shared
    private let systemService = SystemService.shared
    private let fileSystemService = FileSystemService.shared
    private let configService = ConfigService.shared
    
    
    private lazy var statusBarViewModel = StatusBarViewModel(
        profileService: profileService,
        systemService: systemService,
        fileSystemService: fileSystemService
    )
    
    
    private var statusBarController: StatusBarController?
    
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupControllers()
        setupInitialState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanupServices()
    }
    
    
    private func setupServices() {
        do {
            try Constants.ensureDirectoriesExist()
        } catch {
            print("Warning: Could not create directories: \(error)")
        }
    }
    
    
    private func setupControllers() {
        statusBarController = StatusBarController(viewModel: statusBarViewModel)
    }
    
    private func setupInitialState() {
        statusBarViewModel.refreshData()
        
        // Ensure app never appears in dock
        systemService.setDockVisibility()
        
        // Initialize launch at login based on config if different from system
        let config = configService.config
        if config.general.launchAtLogin != systemService.isLaunchAtLoginEnabled {
            try? systemService.setLaunchAtLogin(enabled: config.general.launchAtLogin)
        }
    }
    
    private func cleanupServices() {
        systemService.clearHotKeys()
    }
}

struct SettingsView: View {
    var body: some View {
        SettingsWindowView()
            .navigationTitle(Constants.appName)
    }
}

// MARK: - Settings Views

struct SettingsWindowView: View {
    @StateObject private var configService = ConfigService.shared
    @StateObject private var systemService = SystemService.shared
    @StateObject private var viewModel = StatusBarViewModel(
        profileService: ProfileService.shared,
        systemService: SystemService.shared,
        fileSystemService: FileSystemService.shared
    )
    
    @State private var selectedTab = SettingsTab.general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case shortcuts = "Shortcuts"
        case appearance = "Appearance"
        case about = "About"
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .shortcuts: return "keyboard"
            case .appearance: return "paintbrush"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        HSplitView {
            // Sidebar
            VStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 20)
                            
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .medium))
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
                
                Spacer()
            }
            .frame(width: 200)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Content
            Group {
                switch selectedTab {
                case .general:
                    SettingsGeneralTabView(viewModel: viewModel, configService: configService)
                case .shortcuts:
                    SettingsShortcutsTabView(configService: configService, systemService: systemService)
                case .appearance:
                    SettingsAppearanceTabView(configService: configService)
                case .about:
                    SettingsAboutTabView()
                }
            }
            .padding(24)
            .frame(minWidth: 500, maxWidth: .infinity, minHeight: 400)
        }
        .frame(width: 700, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SettingsGeneralTabView: View {
    @ObservedObject var viewModel: StatusBarViewModel
    @ObservedObject var configService: ConfigService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "gear")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("General")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Text("Configure general application behavior")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Startup")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Toggle("Launch at login", isOn: Binding(
                                        get: { viewModel.isLaunchAtLoginEnabled },
                                        set: { _ in
                                            Task {
                                                await viewModel.toggleLaunchAtLogin()
                                            }
                                        }
                                    ))
                                    .disabled(viewModel.launchAtLoginError != nil)
                                    
                                    Spacer()
                                    
                                    if viewModel.launchAtLoginError != nil {
                                        Text("🚫")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                
                                if let error = viewModel.launchAtLoginError {
                                    Text(userFriendlyErrorMessage(for: error))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 20)
                                }
                            }
                            
                            Toggle("Auto-reload profiles", isOn: Binding(
                                get: { configService.config.general.autoReloadProfiles },
                                set: { newValue in
                                    configService.updateGeneralSetting(\.autoReloadProfiles, to: newValue)
                                }
                            ))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notifications")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Toggle("Show notifications", isOn: Binding(
                            get: { configService.config.general.showNotifications },
                            set: { newValue in
                                configService.updateGeneralSetting(\.showNotifications, to: newValue)
                            }
                        ))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Profile Management")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text("Active Profile:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(viewModel.activeProfileName ?? "None")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Total Profiles:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(viewModel.profiles.count)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Registered Hotkeys:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(viewModel.registeredHotKeys.count)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 12) {
                            Button("Open Profiles Folder") {
                                viewModel.openProfilesFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Reload Profiles") {
                                viewModel.refreshData()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    private func userFriendlyErrorMessage(for error: Error) -> String {
        if let systemError = error as? SystemServiceError {
            switch systemError {
            case .unsupportedVersion:
                return "Requires macOS 13.0 or later"
            case .launchAtLoginFailed:
                return "Failed to enable launch at login"
            case .launchAtLoginDisableFailed:
                return "Failed to disable launch at login"
            case .launchAtLoginRequiresApproval:
                return "Requires approval in System Settings > General > Login Items"
            case .launchAtLoginNotFound:
                return "App registration not found"
            default:
                return systemError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

struct SettingsShortcutsTabView: View {
    @ObservedObject var configService: ConfigService
    @ObservedObject var systemService: SystemService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("Keyboard Shortcuts")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Text("Configure keyboard shortcuts for quick access to profiles and actions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Profile Shortcuts")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Text("Quickly switch to specific profiles using keyboard shortcuts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            ForEach(1...9, id: \.self) { profileNumber in
                                let key = "profile\(profileNumber)"
                                SimpleShortcutField(
                                    label: "Profile \(profileNumber)",
                                    shortcut: configService.config.shortcuts.profileShortcuts[key] ?? "",
                                    onChanged: { newValue in
                                        configService.updateShortcut(for: key, to: newValue)
                                    }
                                )
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Navigation")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Text("Navigate between profiles and manage your setup")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            SimpleShortcutField(
                                label: "Next Profile",
                                shortcut: configService.config.shortcuts.navigationShortcuts.nextProfile,
                                onChanged: { newValue in
                                    configService.updateNavigationShortcut(\.nextProfile, to: newValue)
                                }
                            )
                            
                            SimpleShortcutField(
                                label: "Previous Profile",
                                shortcut: configService.config.shortcuts.navigationShortcuts.previousProfile,
                                onChanged: { newValue in
                                    configService.updateNavigationShortcut(\.previousProfile, to: newValue)
                                }
                            )
                            
                            SimpleShortcutField(
                                label: "Open Profiles Folder",
                                shortcut: configService.config.shortcuts.navigationShortcuts.openProfilesFolder,
                                onChanged: { newValue in
                                    configService.updateNavigationShortcut(\.openProfilesFolder, to: newValue)
                                }
                            )
                            
                            SimpleShortcutField(
                                label: "Reload Profiles",
                                shortcut: configService.config.shortcuts.navigationShortcuts.reloadProfiles,
                                onChanged: { newValue in
                                    configService.updateNavigationShortcut(\.reloadProfiles, to: newValue)
                                }
                            )
                        }
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reset Shortcuts")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                Text("Restore all keyboard shortcuts to their default values")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Reset to Defaults") {
                                resetToDefaults()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status")
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("Registered Hotkeys:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(systemService.registeredHotKeys.count)")
                                    .foregroundColor(.secondary)
                            }
                            
                            if !systemService.registeredHotKeys.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(systemService.registeredHotKeys, id: \.self) { hotkey in
                                        Text("• \(hotkey)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    private func resetToDefaults() {
        let defaultConfig = RiceBarConfig.default
        
        for (key, value) in defaultConfig.shortcuts.profileShortcuts {
            configService.updateShortcut(for: key, to: value)
        }
        
        configService.updateNavigationShortcut(\.nextProfile, to: defaultConfig.shortcuts.navigationShortcuts.nextProfile)
        configService.updateNavigationShortcut(\.previousProfile, to: defaultConfig.shortcuts.navigationShortcuts.previousProfile)
        configService.updateNavigationShortcut(\.openProfilesFolder, to: defaultConfig.shortcuts.navigationShortcuts.openProfilesFolder)
        configService.updateNavigationShortcut(\.reloadProfiles, to: defaultConfig.shortcuts.navigationShortcuts.reloadProfiles)
        
        configService.updateQuickActionShortcut(\.createEmptyProfile, to: defaultConfig.shortcuts.quickActions.createEmptyProfile)
        configService.updateQuickActionShortcut(\.createFromCurrentSetup, to: defaultConfig.shortcuts.quickActions.createFromCurrentSetup)
        configService.updateQuickActionShortcut(\.openSettings, to: defaultConfig.shortcuts.quickActions.openSettings)
        configService.updateQuickActionShortcut(\.quitApp, to: defaultConfig.shortcuts.quickActions.quitApp)
    }
}

struct SimpleShortcutField: View {
    let label: String
    let shortcut: String
    let onChanged: (String) -> Void
    
    @State private var editableShortcut: String = ""
    @State private var isEditing: Bool = false
    
    private func formatShortcut(_ shortcut: String) -> String {
        return shortcut
            .replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "opt", with: "⌥")
            .replacingOccurrences(of: "ctrl", with: "⌃")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "+", with: "")
    }
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 160, alignment: .leading)
            
            if isEditing {
                TextField("Enter shortcut", text: $editableShortcut)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        onChanged(editableShortcut)
                        isEditing = false
                    }
                    .onAppear {
                        editableShortcut = shortcut
                    }
                
                Button("Save") {
                    onChanged(editableShortcut)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                
                Button("Cancel") {
                    isEditing = false
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: {
                    isEditing = true
                }) {
                    HStack {
                        Text(shortcut.isEmpty ? "None" : formatShortcut(shortcut))
                            .foregroundColor(shortcut.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if !shortcut.isEmpty {
                            Button(action: {
                                onChanged("")
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                .frame(width: 200)
            }
        }
    }
}

struct SettingsAppearanceTabView: View {
    @ObservedObject var configService: ConfigService
    
    private let emojiOptions = ["🍚", "⚙️", "🔧", "⭐", "🎯", "🚀", "💎", "🔥", "⚡", "🌟"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "paintbrush")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("Appearance")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Text("Customize the look and feel of RiceBarMac")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Menu Bar Icon")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Text("Choose an icon to display in the menu bar")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(50)), count: 5), spacing: 12) {
                            ForEach(emojiOptions, id: \.self) { emoji in
                                Button(action: {
                                    configService.updateAppearanceSetting(\.menuBarIcon, to: emoji)
                                }) {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(configService.config.appearance.menuBarIcon == emoji ? 
                                                     Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(configService.config.appearance.menuBarIcon == emoji ? 
                                                       Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        HStack {
                            Text("Current:")
                                .fontWeight(.medium)
                            Text(configService.config.appearance.menuBarIcon)
                                .font(.title2)
                            Spacer()
                        }
                    }
                    
                }
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
}

struct SettingsAboutTabView: View {
    @State private var showingSystemInfo = false
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    
    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.mateocerquetella.RiceBarMac"
    }
    
    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("About RiceBarMac")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Text("Learn more about this application and its developer")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack {
                            Text("🍚")
                                .font(.system(size: 80))
                                .frame(width: 100, height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("RiceBarMac")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("The elegant profile manager for macOS")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Version:")
                                        .fontWeight(.medium)
                                        .frame(width: 80, alignment: .leading)
                                    Text(appVersion)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Copy") {
                                        copyVersionInfo()
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                                
                                HStack {
                                    Text("Build:")
                                        .fontWeight(.medium)
                                        .frame(width: 80, alignment: .leading)
                                    Text(buildNumber)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Text("Bundle ID:")
                                        .fontWeight(.medium)
                                        .frame(width: 80, alignment: .leading)
                                    Text(bundleIdentifier)
                                        .foregroundColor(.secondary)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Developer")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack(alignment: .top, spacing: 16) {
                            VStack {
                                Text("MC")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Mateo Cerquetella")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("Software Developer & Designer")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("Passionate about creating beautiful, functional software that enhances productivity and user experience. Specializing in macOS development with SwiftUI and AppKit.")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                
                                HStack(spacing: 16) {
                                    Link("GitHub", destination: URL(string: "https://github.com/mateocerquetella")!)
                                        .font(.subheadline)
                                    
                                    Link("LinkedIn", destination: URL(string: "https://linkedin.com/in/mateocerquetella")!)
                                        .font(.subheadline)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Built With")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            technologyItem("SwiftUI", description: "Modern declarative UI framework", icon: "swift")
                            technologyItem("AppKit", description: "macOS native application framework", icon: "macwindow")
                            technologyItem("ServiceManagement", description: "Launch at login functionality", icon: "gear")
                            technologyItem("HotKey", description: "Global keyboard shortcuts", icon: "keyboard")
                        }
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Legal")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Copyright © 2025 Mateo Cerquetella. All rights reserved.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("This software is provided 'as is' without warranty of any kind. Use at your own risk.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func technologyItem(_ name: String, description: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func systemInfoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            
            Spacer()
        }
    }
    
    private func copyVersionInfo() {
        let versionInfo = """
        RiceBarMac \(appVersion) (Build \(buildNumber))
        Bundle ID: \(bundleIdentifier)
        macOS: \(macOSVersion)
        Architecture: \(getCurrentArchitecture())
        """
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(versionInfo, forType: .string)
    }
    
    private func getCurrentArchitecture() -> String {
        #if arch(x86_64)
        return "Intel x86_64"
        #elseif arch(arm64)
        return "Apple Silicon (ARM64)"
        #else
        return "Unknown"
        #endif
    }
    
    private func getSystemMemory() -> String {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(physicalMemory))
    }
}
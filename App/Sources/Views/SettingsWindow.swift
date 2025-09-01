import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var configService = ConfigService.shared
    @ObservedObject var systemService = SystemService.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ProfileManagementView()
                .tabItem {
                    Image(systemName: "folder")
                    Text("Profiles")
                }
                .tag(0)
            
            ShortcutsSettingsView()
                .tabItem {
                    Image(systemName: "keyboard")
                    Text("Shortcuts")
                }
                .tag(1)
            
            GeneralSettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("General")
                }
                .tag(2)
        }
        .frame(minWidth: 750, idealWidth: 1600, maxWidth: .infinity, minHeight: 650, idealHeight: 1000, maxHeight: .infinity)
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var configService = ConfigService.shared
    @ObservedObject var systemService = SystemService.shared
    @State private var editingShortcut: String?
    @State private var tempShortcut = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyboard Shortcuts")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Set up keyboard shortcuts for quick profile switching and navigation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            
                GroupBox {
                    VStack(spacing: 12) {
                        ForEach(1...9, id: \.self) { number in
                            HStack(spacing: 12) {
                                            Text("Profile \(number)")
                .font(.system(.body, weight: .medium))
                .frame(width: 100, alignment: .leading)
                            
                            if editingShortcut == "profile\(number)" {
                                ShortcutCaptureView(shortcut: $tempShortcut, onCapture: { capturedShortcut in
                                    tempShortcut = capturedShortcut
                                    saveShortcut(for: "profile\(number)")
                                }, autoSave: true)
                                .frame(width: 180, height: 32)
                                
                                Button("Cancel") {
                                    editingShortcut = nil
                                }
                                .buttonStyle(.bordered)
                            } else {
                                let currentShortcut = configService.config.shortcuts.profileShortcuts["profile\(number)"] ?? ""
                                
                                HStack {
                                    if currentShortcut.isEmpty {
                                        Text("Not set")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(6)
                                    } else {
                                        ShortcutBadge(shortcut: currentShortcut)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 4) {
                                        if !currentShortcut.isEmpty {
                                            Button("Remove") {
                                                configService.updateShortcut(for: "profile\(number)", to: "")
                                            }
                                            .buttonStyle(.borderless)
                                            .foregroundColor(.red)
                                            .font(.caption)
                                        }
                                        
                                        Button("Edit") {
                                            editingShortcut = "profile\(number)"
                                            tempShortcut = currentShortcut
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
                GroupBox {
                    VStack(spacing: 12) {
                    ShortcutRow(title: "Next Profile", 
                              value: configService.config.shortcuts.navigationShortcuts.nextProfile,
                              isEditing: editingShortcut == "nextProfile",
                              tempValue: $tempShortcut) {
                        editingShortcut = "nextProfile"
                        tempShortcut = configService.config.shortcuts.navigationShortcuts.nextProfile
                    } onSave: {
                        configService.updateNavigationShortcut(\.nextProfile, to: tempShortcut)
                        editingShortcut = nil
                    } onCancel: {
                        editingShortcut = nil
                    } onRemove: {
                        configService.updateNavigationShortcut(\.nextProfile, to: "")
                    }
                    
                    ShortcutRow(title: "Previous Profile", 
                              value: configService.config.shortcuts.navigationShortcuts.previousProfile,
                              isEditing: editingShortcut == "previousProfile",
                              tempValue: $tempShortcut) {
                        editingShortcut = "previousProfile"
                        tempShortcut = configService.config.shortcuts.navigationShortcuts.previousProfile
                    } onSave: {
                        configService.updateNavigationShortcut(\.previousProfile, to: tempShortcut)
                        editingShortcut = nil
                    } onCancel: {
                        editingShortcut = nil
                    } onRemove: {
                        configService.updateNavigationShortcut(\.previousProfile, to: "")
                    }
                    
                    ShortcutRow(title: "Reload Profiles", 
                              value: configService.config.shortcuts.navigationShortcuts.reloadProfiles,
                              isEditing: editingShortcut == "reloadProfiles",
                              tempValue: $tempShortcut) {
                        editingShortcut = "reloadProfiles"
                        tempShortcut = configService.config.shortcuts.navigationShortcuts.reloadProfiles
                    } onSave: {
                        configService.updateNavigationShortcut(\.reloadProfiles, to: tempShortcut)
                        editingShortcut = nil
                    } onCancel: {
                        editingShortcut = nil
                    } onRemove: {
                        configService.updateNavigationShortcut(\.reloadProfiles, to: "")
                    }
                    }
                    .padding(.vertical, 12)
                } label: {
                    HStack {
                        Text("Navigation Shortcuts")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
                
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        configService.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            .padding(24)
        }
    }
    
    private func saveShortcut(for key: String) {
        if tempShortcut.isEmpty || systemService.validateHotKey(tempShortcut) {
            configService.updateShortcut(for: key, to: tempShortcut)
            editingShortcut = nil
        }
    }
}

struct ShortcutRow: View {
    let title: String
    let value: String
    let isEditing: Bool
    @Binding var tempValue: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, weight: .medium))
                .frame(width: 140, alignment: .leading)
            
            if isEditing {
                ShortcutCaptureView(shortcut: $tempValue, onCapture: { capturedShortcut in
                    tempValue = capturedShortcut
                    onSave()
                }, autoSave: true)
                .frame(width: 180, height: 32)
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            } else {
                HStack {
                    if value.isEmpty {
                        Text("Not set")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                    } else {
                        ShortcutBadge(shortcut: value)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        if !value.isEmpty {
                            Button("Remove", action: onRemove)
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        Button("Edit", action: onEdit)
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var configService = ConfigService.shared
    @ObservedObject var systemService = SystemService.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("General Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Configure general app behavior and startup options.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { systemService.isLaunchAtLoginEnabled },
                        set: { newValue in
                            do {
                                try systemService.setLaunchAtLogin(enabled: newValue)
                                configService.updateGeneralSetting(\.launchAtLogin, to: newValue)
                            } catch {
                                print("Failed to set launch at login: \(error)")
                            }
                        }
                    ))
                    
                        Toggle("Show in Dock", isOn: Binding(
                            get: { configService.config.general.showInDock },
                            set: { newValue in
                                configService.updateGeneralSetting(\.showInDock, to: newValue)
                                systemService.setDockVisibility(visible: newValue)
                            }
                        ))
                    }
                    .padding(.vertical, 12)
                } label: {
                    HStack {
                        Text("Startup")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
            
            }
            .padding(24)
        }
    }
}

struct ProfileManagementView: View {
    @ObservedObject private var profileService = ProfileService.shared
    @State private var selectedProfileDescriptor: ProfileDescriptor?
    
    var body: some View {
        HStack(spacing: 0) {
            ProfileSidebarView(
                selectedProfileDescriptor: $selectedProfileDescriptor,
                profileService: profileService
            )
            .frame(minWidth: 280, idealWidth: 350, maxWidth: 500)
            
            Divider()
            
            if let descriptor = selectedProfileDescriptor {
                ProfileConfigurationView(profileDescriptor: descriptor)
            } else {
                ProfileEmptyStateView()
            }
        }
        .onAppear {
            profileService.reload()
        }
    }
}

struct ProfileSidebarView: View {
    @Binding var selectedProfileDescriptor: ProfileDescriptor?
    @ObservedObject var profileService: ProfileService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Profiles")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Select a profile to configure themes and settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(profileService.profiles, id: \.id) { descriptor in
                        ProfileRowView(
                            descriptor: descriptor,
                            isSelected: selectedProfileDescriptor?.id == descriptor.id,
                            isActive: profileService.activeProfile?.id == descriptor.id
                        ) {
                            selectedProfileDescriptor = descriptor
                        }
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button("Create New Profile") {
                    // TODO: Implement profile creation
                }
                .buttonStyle(.borderedProminent)
                
                Button("Open Profiles Folder") {
                    profileService.openProfilesFolder()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

struct ProfileEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select a Profile")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text("Choose a profile from the sidebar to configure its themes and settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProfileRowView: View {
    let descriptor: ProfileDescriptor
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(descriptor.displayName)
                            .font(.system(.body, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Spacer()
                    }
                    
                    if let hotkey = descriptor.profile.hotkey {
                        Text(hotkey)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProfileConfigurationView: View {
    let profileDescriptor: ProfileDescriptor
    @ObservedObject private var themeService = ThemeService.shared
    @State private var selectedIDETheme: IDETheme?
    @State private var selectedTerminalTheme: TerminalTheme?
    @State private var selectedSystemTheme: SystemTheme?
    @State private var selectedThemeCategory: ThemeCategory = .ide
    
    enum ThemeCategory: String, CaseIterable {
        case ide = "IDE"
        case terminal = "Terminal"
        case system = "System"
        
        var displayName: String { rawValue }
        var iconName: String {
            switch self {
            case .ide: return "chevron.left.forwardslash.chevron.right"
            case .terminal: return "terminal"
            case .system: return "gear"
            }
        }
    }
    @State private var selectedIDEType: Constants.IDEType = .vscode
    @State private var profile: Profile
    
    init(profileDescriptor: ProfileDescriptor) {
        self.profileDescriptor = profileDescriptor
        self._profile = State(initialValue: profileDescriptor.profile)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Profile Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(profileDescriptor.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button("Apply Profile") {
                            applyProfile()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Text("Configure themes and settings for this profile.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Profile Basic Settings
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Name:")
                                .frame(width: 100, alignment: .leading)
                            TextField("Profile Name", text: Binding(
                                get: { profile.name },
                                set: { profile.name = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Hotkey:")
                                .frame(width: 100, alignment: .leading)
                            TextField("e.g., cmd+1", text: Binding(
                                get: { profile.hotkey ?? "" },
                                set: { profile.hotkey = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    Text("Basic Settings")
                        .font(.headline)
                }
                .padding(.horizontal)
                
                // Comprehensive Theme Configuration Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        // Theme Category Picker
                        HStack {
                            Text("Category:")
                                .font(.system(.body, weight: .medium))
                                .frame(width: 100, alignment: .leading)
                            
                            Picker("Theme Category", selection: $selectedThemeCategory) {
                                ForEach(ThemeCategory.allCases, id: \.self) { category in
                                    HStack {
                                        Image(systemName: category.iconName)
                                        Text(category.displayName)
                                    }.tag(category)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                            
                            Spacer()
                        }
                        
                        // Current Theme Status
                        HStack {
                            Image(systemName: selectedThemeCategory.iconName)
                                .foregroundColor(.accentColor)
                            Text("Current Theme:")
                                .font(.system(.body, weight: .medium))
                            
                            Text(getCurrentThemeText())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(getCurrentThemeText() == "Not set" ? Color.gray.opacity(0.1) : Color.accentColor.opacity(0.1))
                                .cornerRadius(6)
                                .foregroundColor(getCurrentThemeText() == "Not set" ? .secondary : .primary)
                                .italic(getCurrentThemeText() == "Not set")
                            
                            Spacer()
                        }
                        
                        Divider()
                        
                        // Dynamic Theme Configuration Based on Category
                        switch selectedThemeCategory {
                        case .ide:
                            IDEThemeConfigurationView()
                        case .terminal:
                            TerminalThemeConfigurationView()
                        case .system:
                            SystemThemeConfigurationView()
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    HStack {
                        Text("\(selectedThemeCategory.displayName) Themes")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Refresh") {
                            themeService.refreshAllThemes()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
                
                // Save Changes
                HStack {
                    Spacer()
                    
                    Button("Save Profile") {
                        saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onAppear {
            themeService.refreshAllThemes()
            // Set initial IDE type based on profile's IDE config
            if let ideConfig = profile.ide {
                selectedIDEType = ideConfig.kind == .vscode ? .vscode : .cursor
            }
        }
    }
    
    private func getCurrentThemeText() -> String {
        switch selectedThemeCategory {
        case .ide:
            if let ideConfig = profile.ide, let theme = ideConfig.theme {
                return theme
            }
            return "Not set"
        case .terminal:
            if let terminalConfig = profile.terminal, let theme = terminalConfig.theme {
                return theme
            }
            return "Not set"
        case .system:
            if let systemConfig = profile.systemTheme {
                return systemConfig.appearance?.displayName ?? "Not set"
            }
            return "Not set"
        }
    }
    
    private var filteredIDEThemes: [IDETheme] {
        themeService.availableIDEThemes.filter { theme in
            theme.ideType == selectedIDEType
        }
    }
    
    // MARK: - Theme Configuration Views
    
    @ViewBuilder
    private func IDEThemeConfigurationView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("IDE:")
                    .font(.system(.body, weight: .medium))
                    .frame(width: 100, alignment: .leading)
                
                Picker("IDE", selection: $selectedIDEType) {
                    ForEach(Constants.IDEType.allCases, id: \.self) { ideType in
                        HStack {
                            Image(systemName: ideType == .vscode ? "chevron.left.forwardslash.chevron.right" : "cursorarrow.rays")
                            Text(ideType.displayName)
                        }.tag(ideType)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                
                Spacer()
            }
            
            // Theme Selection Grid
            if themeService.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading themes...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120, maximum: 140))
                ], spacing: 12) {
                    ForEach(filteredIDEThemes) { theme in
                        IDEThemeCard(theme: theme, isSelected: selectedIDETheme?.id == theme.id) {
                            selectedIDETheme = theme
                        }
                    }
                }
            }
            
            if let selectedTheme = selectedIDETheme {
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected: \(selectedTheme.displayName)")
                            .font(.system(.body, weight: .medium))
                        Text("\(selectedTheme.type.displayName) theme")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Set as Profile Theme") {
                        setIDEThemeForProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    @ViewBuilder
    private func TerminalThemeConfigurationView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Terminal:")
                    .font(.system(.body, weight: .medium))
                    .frame(width: 100, alignment: .leading)
                
                Picker("Terminal", selection: Binding(
                    get: { profile.terminal?.kind ?? .alacritty },
                    set: { newKind in
                        if profile.terminal == nil {
                            profile.terminal = Profile.Terminal(kind: newKind)
                        } else {
                            profile.terminal?.kind = newKind
                        }
                    }
                )) {
                    ForEach([Profile.Terminal.Kind.alacritty, .terminalApp, .iterm2], id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                
                Spacer()
            }
            
            // Terminal Theme Selection Grid
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160, maximum: 180))
            ], spacing: 16) {
                ForEach(filteredTerminalThemes) { theme in
                    TerminalThemeCard(theme: theme, isSelected: selectedTerminalTheme?.id == theme.id) {
                        selectedTerminalTheme = theme
                    }
                }
            }
            
            if let selectedTheme = selectedTerminalTheme {
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected: \(selectedTheme.displayName)")
                            .font(.system(.body, weight: .medium))
                        Text("\(selectedTheme.type.displayName) theme")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Set as Terminal Theme") {
                        setTerminalThemeForProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    @ViewBuilder
    private func SystemThemeConfigurationView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // System Theme Selection
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160, maximum: 180))
            ], spacing: 16) {
                ForEach(themeService.availableSystemThemes) { theme in
                    SystemThemeCard(theme: theme, isSelected: selectedSystemTheme?.id == theme.id) {
                        selectedSystemTheme = theme
                    }
                }
            }
            
            if let selectedTheme = selectedSystemTheme {
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected: \(selectedTheme.displayName)")
                            .font(.system(.body, weight: .medium))
                        Text("\(selectedTheme.appearance.displayName) appearance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Set as System Theme") {
                        setSystemThemeForProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private var filteredTerminalThemes: [TerminalTheme] {
        let selectedKind = profile.terminal?.kind ?? .alacritty
        return themeService.availableTerminalThemes.filter { theme in
            theme.terminalType == selectedKind
        }
    }
    
    // MARK: - Theme Setting Methods
    
    private func setIDEThemeForProfile() {
        guard let theme = selectedIDETheme else { return }
        
        let ideKind: Profile.IDE.Kind = selectedIDEType == .vscode ? .vscode : .cursor
        
        if profile.ide?.kind == ideKind {
            profile.ide?.theme = theme.name
        } else {
            profile.ide = Profile.IDE(kind: ideKind)
            profile.ide?.theme = theme.name
        }
    }
    
    private func setTerminalThemeForProfile() {
        guard let theme = selectedTerminalTheme else { return }
        
        if profile.terminal == nil {
            profile.terminal = Profile.Terminal(kind: theme.terminalType)
        }
        profile.terminal?.theme = theme.name
    }
    
    private func setSystemThemeForProfile() {
        guard let theme = selectedSystemTheme else { return }
        
        if profile.systemTheme == nil {
            profile.systemTheme = Profile.SystemTheme()
        }
        profile.systemTheme?.appearance = theme.appearance
    }
    
    private func saveProfile() {
        do {
            try ProfileService.shared.saveProfile(profile, at: profileDescriptor.directory)
        } catch {
            print("Error saving profile: \(error)")
        }
    }
    
    private func applyProfile() {
        do {
            try ProfileService.shared.applyProfile(profileDescriptor)
        } catch {
            print("Error applying profile: \(error)")
        }
    }
}

// MARK: - Theme Card Views

struct IDEThemeCard: View {
    let theme: IDETheme
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: theme.type.iconName)
                        .foregroundColor(theme.type == .light ? .orange : theme.type == .dark ? .blue : .purple)
                    Spacer()
                    Image(systemName: theme.ideType == .vscode ? "chevron.left.forwardslash.chevron.right" : "cursorarrow.rays")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                Text(theme.displayName)
                    .font(.system(.body, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Text(theme.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct TerminalThemeCard: View {
    let theme: TerminalTheme
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: theme.type.iconName)
                        .foregroundColor(theme.type == .light ? .orange : theme.type == .dark ? .blue : .purple)
                    Spacer()
                    Image(systemName: "terminal")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                Text(theme.displayName)
                    .font(.system(.caption, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                Text(theme.terminalType.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SystemThemeCard: View {
    let theme: SystemTheme
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: theme.appearance == .light ? "sun.max" : theme.appearance == .dark ? "moon" : "circle.lefthalf.filled")
                        .foregroundColor(theme.appearance == .light ? .orange : theme.appearance == .dark ? .blue : .purple)
                    Spacer()
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                Text(theme.displayName)
                    .font(.system(.caption, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                Text(theme.appearance.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}


struct ShortcutBadge: View {
    let shortcut: String
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(shortcutKeys, id: \.self) { key in
                Text(key)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
        }
    }
    
    private var shortcutKeys: [String] {
        shortcut.split(separator: "+").map { key in
            let keyString = String(key).trimmingCharacters(in: .whitespaces)
            switch keyString.lowercased() {
            case "cmd": return "⌘"
            case "ctrl": return "⌃"
            case "opt", "option": return "⌥"
            case "shift": return "⇧"
            case "return": return "↩"
            case "tab": return "⇥"
            case "space": return "␣"
            case "delete": return "⌫"
            case "escape": return "⎋"
            case "left": return "←"
            case "right": return "→"
            case "up": return "↑"
            case "down": return "↓"
            default: return keyString.uppercased()
            }
        }
    }
}

#Preview {
    SettingsWindow()
}
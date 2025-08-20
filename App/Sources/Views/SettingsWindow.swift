import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var configService = ConfigService.shared
    @ObservedObject var systemService = SystemService.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ShortcutsSettingsView()
                .tabItem {
                    Image(systemName: "keyboard")
                    Text("Shortcuts")
                }
                .tag(0)
            
            GeneralSettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("General")
                }
                .tag(1)
            
            AppearanceSettingsView()
                .tabItem {
                    Image(systemName: "paintbrush")
                    Text("Appearance")
                }
                .tag(2)
        }
        .frame(width: 500, height: 400)
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var configService = ConfigService.shared
    @ObservedObject var systemService = SystemService.shared
    @State private var editingShortcut: String?
    @State private var tempShortcut = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.title2)
                .fontWeight(.semibold)
            
            GroupBox("Profile Shortcuts") {
                VStack(spacing: 8) {
                    ForEach(1...9, id: \.self) { number in
                        HStack {
                            Text("Profile \(number):")
                                .frame(width: 100, alignment: .leading)
                            
                            if editingShortcut == "profile\(number)" {
                                ShortcutCaptureView(shortcut: $tempShortcut, onCapture: { capturedShortcut in
                                    tempShortcut = capturedShortcut
                                    saveShortcut(for: "profile\(number)")
                                }, autoSave: true)
                                .frame(width: 150, height: 24)
                                
                                Button("Cancel") {
                                    editingShortcut = nil
                                }
                                .buttonStyle(.bordered)
                            } else {
                                let currentShortcut = configService.config.shortcuts.profileShortcuts["profile\(number)"] ?? ""
                                if currentShortcut.isEmpty {
                                    Text("No shortcut")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .italic()
                                } else {
                                    Text(currentShortcut)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    if !currentShortcut.isEmpty {
                                        Button("Remove") {
                                            configService.updateShortcut(for: "profile\(number)", to: "")
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.red)
                                    }
                                    
                                    Button("Edit") {
                                        editingShortcut = "profile\(number)"
                                        tempShortcut = currentShortcut
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            GroupBox("Navigation Shortcuts") {
                VStack(spacing: 8) {
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
                .padding(.vertical, 8)
            }
            
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    configService.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
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
        HStack {
            Text("\(title):")
                .frame(width: 120, alignment: .leading)
            
            if isEditing {
                ShortcutCaptureView(shortcut: $tempValue, onCapture: { capturedShortcut in
                    tempValue = capturedShortcut
                    onSave()
                }, autoSave: true)
                .frame(width: 150, height: 24)
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            } else {
                if value.isEmpty {
                    Text("No shortcut")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if !value.isEmpty {
                        Button("Remove", action: onRemove)
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                    }
                    
                    Button("Edit", action: onEdit)
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var configService = ConfigService.shared
    @ObservedObject var systemService = SystemService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            GroupBox("Startup") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { systemService.isLaunchAtLoginEnabled },
                        set: { newValue in
                            try? systemService.setLaunchAtLogin(enabled: newValue)
                        }
                    ))
                    
                    Toggle("Show in Dock", isOn: Binding(
                        get: { configService.config.general.showInDock },
                        set: { configService.updateGeneralSetting(\.showInDock, to: $0) }
                    ))
                }
                .padding(.vertical, 8)
            }
            
            GroupBox("Behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-reload profiles", isOn: Binding(
                        get: { configService.config.general.autoReloadProfiles },
                        set: { configService.updateGeneralSetting(\.autoReloadProfiles, to: $0) }
                    ))
                    
                    Toggle("Show notifications", isOn: Binding(
                        get: { configService.config.general.showNotifications },
                        set: { configService.updateGeneralSetting(\.showNotifications, to: $0) }
                    ))
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var configService = ConfigService.shared
    @State private var customIcon = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            GroupBox("Menu Bar") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Menu bar icon:")
                        TextField("Icon", text: Binding(
                            get: { configService.config.appearance.menuBarIcon },
                            set: { configService.updateAppearanceSetting(\.menuBarIcon, to: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                    }
                    
                    Toggle("Show profile count in menu", isOn: Binding(
                        get: { configService.config.appearance.showProfileCountInMenu },
                        set: { configService.updateAppearanceSetting(\.showProfileCountInMenu, to: $0) }
                    ))
                    
                    Toggle("Show shortcuts in menu", isOn: Binding(
                        get: { configService.config.appearance.showShortcutsInMenu },
                        set: { configService.updateAppearanceSetting(\.showShortcutsInMenu, to: $0) }
                    ))
                }
                .padding(.vertical, 8)
            }
            
            GroupBox("Menu Style") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Menu item style:", selection: Binding(
                        get: { configService.config.appearance.menuItemStyle },
                        set: { configService.updateAppearanceSetting(\.menuItemStyle, to: $0) }
                    )) {
                        ForEach(MenuItemStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsWindow()
}
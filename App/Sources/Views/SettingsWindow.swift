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
            
        }
        .frame(minWidth: 480, idealWidth: 520, maxWidth: 800, minHeight: 400, idealHeight: 450, maxHeight: 800)
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
                                    .frame(width: 80, alignment: .leading)
                            
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
            .padding(20)
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
            .padding(20)
        }
    }
}


struct ShortcutBadge: View {
    let shortcut: String
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(shortcutKeys, id: \.self) { key in
                Text(key)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
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
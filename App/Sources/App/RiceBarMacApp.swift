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
        
        // Apply dock visibility setting
        let config = configService.config
        systemService.setDockVisibility(visible: config.general.showInDock)
        
        // Initialize launch at login based on config if different from system
        if config.general.launchAtLogin != systemService.isLaunchAtLoginEnabled {
            try? systemService.setLaunchAtLogin(enabled: config.general.launchAtLogin)
        }
    }
    
    private func cleanupServices() {
        systemService.clearHotKeys()
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = StatusBarViewModel(
        profileService: ProfileService.shared,
        systemService: SystemService.shared,
        fileSystemService: FileSystemService.shared
    )
    
    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Profile Information") {
                    VStack(alignment: .leading, spacing: 8) {
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
                        
                        Divider()
                        
                        Button("Open Profiles Folder") {
                            viewModel.openProfilesFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Reload Profiles") {
                            viewModel.refreshData()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                }
                
                GroupBox("System Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch at Login", isOn: Binding(
                            get: { viewModel.isLaunchAtLoginEnabled },
                            set: { _ in
                                Task {
                                    await viewModel.toggleLaunchAtLogin()
                                }
                            }
                        ))
                        
                        HStack {
                            Text("Registered Hotkeys:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(viewModel.registeredHotKeys.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }
                
                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Version:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Build:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
        .navigationTitle(Constants.appName)
    }
}
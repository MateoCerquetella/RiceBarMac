import SwiftUI
import AppKit
import Combine

/// Main application entry point with dependency injection architecture
@main
struct RiceBarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// Application delegate managing the app lifecycle and dependency injection
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Services (Dependency Injection Container)
    
    private let profileService = ProfileService.shared
    private let systemService = SystemService.shared
    private let fileSystemService = FileSystemService.shared
    
    // MARK: - ViewModels
    
    private lazy var statusBarViewModel = StatusBarViewModel(
        profileService: profileService,
        systemService: systemService,
        fileSystemService: fileSystemService
    )
    
    // MARK: - Controllers
    
    private var statusBarController: StatusBarController?
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupControllers()
        setupInitialState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanupServices()
    }
    
    // MARK: - Setup Methods
    
    private func setupServices() {
        // Ensure required directories exist
        do {
            try Constants.ensureDirectoriesExist()
        } catch {
            LoggerService.error("Failed to create required directories: \(error)")
        }
        
        LoggerService.info("\(Constants.appName) services initialized")
    }
    
    private func setupControllers() {
        statusBarController = StatusBarController(viewModel: statusBarViewModel)
        LoggerService.info("Status bar controller initialized")
    }
    
    private func setupInitialState() {
        // Initial data load
        statusBarViewModel.refreshData()
        LoggerService.info("\(Constants.appName) startup completed")
    }
    
    private func cleanupServices() {
        // Cleanup any resources
        systemService.clearHotKeys()
        LoggerService.info("\(Constants.appName) cleanup completed")
    }
}

/// Settings view with dependency injection support
struct SettingsView: View {
    @StateObject private var viewModel = StatusBarViewModel(
        profileService: ProfileService.shared,
        systemService: SystemService.shared,
        fileSystemService: FileSystemService.shared
    )
    
    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 16) {
                // Profile Management Section
                GroupBox("Profile Management") {
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
                
                // System Settings Section
                GroupBox("System Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch at Login", isOn: .constant(viewModel.isLaunchAtLoginEnabled))
                            .onTapGesture {
                                Task {
                                    await viewModel.toggleLaunchAtLogin()
                                }
                            }
                        
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
                
                // About Section
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
        .padding(20)
        .frame(width: 500, height: 400)
        .navigationTitle(Constants.appName)
    }
}
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
    private let backupService = BackupService.shared
    
    
    private lazy var statusBarViewModel = StatusBarViewModel(
        profileService: profileService,
        systemService: systemService,
        fileSystemService: fileSystemService
    )
    
    
    private var statusBarController: StatusBarController?
    
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        createInitialBackup()
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
    
    private func createInitialBackup() {
        do {
            try backupService.createInitialBackupIfNeeded()
        } catch {
            print("Warning: Failed to create initial backup: \(error.localizedDescription)")
            // Don't fail the app launch if backup fails
        }
    }
    
    private func setupControllers() {
        statusBarController = StatusBarController(viewModel: statusBarViewModel)
    }
    
    private func setupInitialState() {
        statusBarViewModel.refreshData()
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
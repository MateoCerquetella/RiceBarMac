import Foundation
import AppKit
import SwiftUI
import Combine
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - Status Bar View Model

/// MVVM ViewModel for the status bar controller
/// Manages state and business logic for the menu bar interface
final class StatusBarViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var profiles: [ProfileDescriptor] = []
    @Published private(set) var activeProfile: ProfileDescriptor?
    @Published private(set) var isApplying = false
    @Published private(set) var isLaunchAtLoginEnabled = false
    @Published private(set) var registeredHotKeys: [String] = []
    
    // MARK: - Services
    
    private let profileService: ProfileService
    private let systemService: SystemService
    private let fileSystemService: FileSystemService
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(
        profileService: ProfileService = .shared,
        systemService: SystemService = .shared,
        fileSystemService: FileSystemService = .shared
    ) {
        self.profileService = profileService
        self.systemService = systemService
        self.fileSystemService = fileSystemService
        
        setupBindings()
        refreshData()
        registerHotKeys()
    }
    
    // MARK: - Data Binding
    
    private func setupBindings() {
        // Bind profile service state
        profileService.$profiles
            .receive(on: DispatchQueue.main)
            .assign(to: \.profiles, on: self)
            .store(in: &cancellables)
        
        profileService.$activeProfile
            .receive(on: DispatchQueue.main)
            .assign(to: \.activeProfile, on: self)
            .store(in: &cancellables)
        
        profileService.$isApplying
            .receive(on: DispatchQueue.main)
            .assign(to: \.isApplying, on: self)
            .store(in: &cancellables)
        
        // Bind system service state
        systemService.$isLaunchAtLoginEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLaunchAtLoginEnabled, on: self)
            .store(in: &cancellables)
        
        systemService.$registeredHotKeys
            .receive(on: DispatchQueue.main)
            .assign(to: \.registeredHotKeys, on: self)
            .store(in: &cancellables)
        
        // Re-register hotkeys when profiles change
        profileService.$profiles
            .sink { [weak self] _ in
                self?.registerHotKeys()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Management
    
    /// Refreshes all data from services
    func refreshData() {
        profileService.reload()
        systemService.updateLaunchAtLoginStatus()
    }
    
    /// Registers hotkeys for all profiles
    private func registerHotKeys() {
        systemService.registerHotKeys(profiles: profiles) { [weak self] descriptor in
            self?.applyProfile(descriptor)
        }
    }
    
    // MARK: - Profile Operations
    
    /// Applies a profile to the system
    /// - Parameter descriptor: Profile descriptor to apply
    func applyProfile(_ descriptor: ProfileDescriptor) {
        // Prevent concurrent applications
        guard !isApplying else {
            LoggerService.info("Profile application already in progress, skipping")
            return
        }
        
        Task {
            do {
                try await profileService.applyProfileAsync(descriptor, cleanConfig: false)
            } catch {
                LoggerService.error("Profile apply failed: \(error)")
                _ = await MainActor.run {
                    Task { await showError(error) }
                }
            }
        }
    }
    
    /// Reapplies the currently active profile
    func reapplyActiveProfile() {
        guard let active = activeProfile else { return }
        applyProfile(active)
    }
    
    /// Creates a new profile from the current system configuration
    /// - Parameter name: Name for the new profile
    func createProfileFromCurrent(name: String) async throws -> ProfileDescriptor {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let descriptor = try profileService.createProfileFromCurrent(name: name)
                    profileService.setActiveProfile(descriptor)
                    continuation.resume(returning: descriptor)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Creates a new empty profile
    /// - Parameter name: Name for the new profile
    func createEmptyProfile(name: String) async throws -> ProfileDescriptor {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let descriptor = try profileService.createEmptyProfile(name: name)
                    profileService.setActiveProfile(descriptor)
                    continuation.resume(returning: descriptor)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Copies an existing profile
    /// - Parameters:
    ///   - descriptor: Profile to copy
    ///   - newName: Name for the copied profile
    func copyProfile(_ descriptor: ProfileDescriptor, to newName: String) async throws -> ProfileDescriptor {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let newDescriptor = try profileService.copyProfile(descriptor, to: newName)
                    continuation.resume(returning: newDescriptor)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Deletes a profile
    /// - Parameter descriptor: Profile to delete
    func deleteProfile(_ descriptor: ProfileDescriptor) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    try profileService.deleteProfile(descriptor)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Updates wallpaper for a profile
    /// - Parameters:
    ///   - descriptor: Profile to update
    ///   - sourceURL: Source wallpaper file URL
    func updateWallpaper(for descriptor: ProfileDescriptor, from sourceURL: URL) async throws -> ProfileDescriptor {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let updated = try profileService.updateWallpaper(for: descriptor, from: sourceURL)
                    continuation.resume(returning: updated)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - System Operations
    
    /// Opens the profiles folder in Finder
    func openProfilesFolder() {
        profileService.openProfilesFolder()
    }
    
    /// Opens a specific profile folder in Finder
    /// - Parameter descriptor: Profile descriptor
    func openProfileFolder(_ descriptor: ProfileDescriptor) {
        NSWorkspace.shared.open(descriptor.directory)
    }
    
    /// Toggles launch at login setting
    func toggleLaunchAtLogin() async {
        do {
            try systemService.toggleLaunchAtLogin()
        } catch {
            LoggerService.error("Failed to toggle launch at login: \(error)")
            await showError(error)
        }
    }
    
    // MARK: - UI Helpers
    
    /// Returns sorted profiles for display
    var sortedProfiles: [ProfileDescriptor] {
        return profiles.sorted { $0.profile.order < $1.profile.order }
    }
    
    /// Checks if a profile is currently active
    /// - Parameter descriptor: Profile to check
    /// - Returns: True if the profile is active
    func isProfileActive(_ descriptor: ProfileDescriptor) -> Bool {
        return activeProfile?.directory == descriptor.directory
    }
    
    /// Returns the active profile name for display
    var activeProfileName: String? {
        return activeProfile?.profile.name
    }
    
    /// Returns display title for the menu
    var menuTitle: String {
        return activeProfileName ?? "Select a profile"
    }
    
    // MARK: - File Operations
    
    /// Shows a file picker for wallpaper selection
    /// - Parameter completion: Completion handler with selected URL
    func pickWallpaperFile(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        
        #if canImport(UniformTypeIdentifiers)
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        #else
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic"]
        #endif
        
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
    
    // MARK: - Alert Helpers
    
    /// Shows an error alert
    /// - Parameter error: Error to display
    @MainActor
    private func showError(_ error: Error) async {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = error.localizedDescription
        
        // Add recovery suggestion if available
        if let localizableError = error as? LocalizedError,
           let suggestion = localizableError.recoverySuggestion {
            alert.informativeText += "\n\n\(suggestion)"
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Shows a confirmation dialog for profile deletion
    /// - Parameter profileName: Name of the profile to delete
    /// - Returns: True if user confirmed deletion
    @MainActor
    func confirmDeleteProfile(_ profileName: String) async -> Bool {
        // First confirmation dialog
        let firstAlert = NSAlert()
        firstAlert.messageText = "Delete Profile"
        firstAlert.informativeText = "Are you sure you want to delete the profile '\(profileName)'?\n\nThis action cannot be undone. The profile folder will be moved to the Trash."
        firstAlert.alertStyle = .warning
        firstAlert.addButton(withTitle: "Delete")
        firstAlert.addButton(withTitle: "Cancel")
        
        let firstResponse = firstAlert.runModal()
        guard firstResponse == .alertFirstButtonReturn else { return false }
        
        // Second confirmation dialog - more explicit
        let secondAlert = NSAlert()
        secondAlert.messageText = "Confirm Deletion"
        secondAlert.informativeText = "This will permanently move the profile '\(profileName)' and all its contents to the Trash.\n\n⚠️ This action cannot be undone.\n\nAre you absolutely sure you want to continue?"
        secondAlert.alertStyle = .critical
        secondAlert.addButton(withTitle: "Yes, Delete Profile")
        secondAlert.addButton(withTitle: "Cancel")
        
        let secondResponse = secondAlert.runModal()
        return secondResponse == .alertFirstButtonReturn
    }
    
    /// Shows a dialog to get profile name from user
    /// - Parameters:
    ///   - title: Dialog title
    ///   - message: Dialog message
    ///   - placeholder: Placeholder text for input field
    /// - Returns: User input string or nil if cancelled
    @MainActor
    func promptForProfileName(title: String, message: String, placeholder: String) async -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = placeholder
        alert.accessoryView = input
        
        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? input.stringValue : nil
    }
    
    /// Shows a success message
    /// - Parameters:
    ///   - title: Alert title
    ///   - message: Alert message
    @MainActor
    func showSuccess(title: String, message: String) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Menu Construction Helpers

extension StatusBarViewModel {
    
    /// Creates menu items for profile management
    func createProfileMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        if profiles.isEmpty {
            let empty = NSMenuItem(title: "No profiles found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            items.append(empty)
        } else {
            for descriptor in sortedProfiles {
                let item = createProfileMenuItem(for: descriptor)
                items.append(item)
            }
        }
        
        return items
    }
    
    /// Creates a menu item for a specific profile
    private func createProfileMenuItem(for descriptor: ProfileDescriptor) -> NSMenuItem {
        let title = descriptor.profile.name
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = descriptor
        
        if let hotkeyText = descriptor.profile.hotkey {
            item.toolTip = "Hotkey: \(hotkeyText)"
        }
        
        let isActive = isProfileActive(descriptor)
        if isActive {
            item.state = .on
        }
        
        // Add submenu with profile actions
        let submenu = NSMenu()
        
        if isActive {
            // Active profile specific actions
            let reapply = NSMenuItem(title: "Reapply", action: nil, keyEquivalent: "")
            submenu.addItem(reapply)
            
            let setWallpaper = NSMenuItem(title: "Set Wallpaper…", action: nil, keyEquivalent: "")
            submenu.addItem(setWallpaper)
            
            submenu.addItem(.separator())
        }
        
        // Common actions for all profiles
        let openFolder = NSMenuItem(title: "Open Profile Folder", action: nil, keyEquivalent: "")
        openFolder.representedObject = descriptor
        submenu.addItem(openFolder)
        
        submenu.addItem(.separator())
        
        let deleteProfile = NSMenuItem(title: "Delete Profile…", action: nil, keyEquivalent: "")
        deleteProfile.representedObject = descriptor
        submenu.addItem(deleteProfile)
        
        item.submenu = submenu
        return item
    }
    
    /// Creates general action menu items
    func createActionMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        // Profile creation actions
        let newEmpty = NSMenuItem(title: "Create Empty Profile…", action: nil, keyEquivalent: "e")
        items.append(newEmpty)
        
        let snapshot = NSMenuItem(title: "Create Profile From Current…", action: nil, keyEquivalent: "n")
        items.append(snapshot)
        
        items.append(.separator())
        
        // General actions
        let reload = NSMenuItem(title: "Reload Profiles", action: nil, keyEquivalent: "r")
        items.append(reload)
        
        let open = NSMenuItem(title: "Open Profiles Folder", action: nil, keyEquivalent: "o")
        items.append(open)
        
        items.append(.separator())
        
        // Settings
        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
        launchAtLogin.state = isLaunchAtLoginEnabled ? .on : .off
        items.append(launchAtLogin)
        
        items.append(.separator())
        
        // Quit
        let quit = NSMenuItem(title: "Quit RiceBarMac", action: nil, keyEquivalent: "q")
        items.append(quit)
        
        return items
    }
}
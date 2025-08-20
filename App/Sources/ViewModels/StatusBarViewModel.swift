import Foundation
import AppKit
import SwiftUI
import Combine
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif


final class StatusBarViewModel: ObservableObject {
    
    
    @Published private(set) var profiles: [ProfileDescriptor] = []
    @Published private(set) var activeProfile: ProfileDescriptor?
    @Published private(set) var isApplying = false
    @Published private(set) var isLaunchAtLoginEnabled = false
    @Published private(set) var registeredHotKeys: [String] = []
    
    
    private let profileService: ProfileService
    private let systemService: SystemService
    private let fileSystemService: FileSystemService
    
    
    private var cancellables = Set<AnyCancellable>()
    
    
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
    
    
    private func setupBindings() {
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
        
        systemService.$isLaunchAtLoginEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLaunchAtLoginEnabled, on: self)
            .store(in: &cancellables)
        
        systemService.$registeredHotKeys
            .receive(on: DispatchQueue.main)
            .assign(to: \.registeredHotKeys, on: self)
            .store(in: &cancellables)
        
        profileService.$profiles
            .sink { [weak self] _ in
                self?.registerHotKeys()
            }
            .store(in: &cancellables)
    }
    
    
    func refreshData() {
        profileService.reload()
        systemService.updateLaunchAtLoginStatus()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let active = self.activeProfile {
                if let updatedProfile = self.profiles.first(where: { $0.directory == active.directory }) {
                    self.applyProfile(updatedProfile)
                } else {
                }
            } else {
            }
        }
    }
    
    private func registerHotKeys() {
        systemService.registerHotKeys(profiles: profiles) { [weak self] descriptor in
            self?.applyProfile(descriptor)
        }
    }
    
    
    private var currentApplicationTask: Task<Void, Never>?
    
    func applyProfile(_ descriptor: ProfileDescriptor) {
        
        if let current = activeProfile, current.directory == descriptor.directory {
            if ApplyActivity.recentlyApplied(within: 2.0) {
                return
            }
        }
        
        currentApplicationTask?.cancel()
        
        profileService.setActiveProfile(descriptor)
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        
        currentApplicationTask = Task.detached(priority: .userInitiated) {
            do {
                try await self.profileService.applyProfileAsync(descriptor, cleanConfig: false)
            } catch {
                if Task.isCancelled {
                } else {
                    await self.showError(error)
                }
            }
            
            await MainActor.run {
                self.currentApplicationTask = nil
            }
        }
    }
    
    func reapplyActiveProfile() {
        guard let active = activeProfile else { return }
        applyProfile(active)
    }
    
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
    
    
    func openProfilesFolder() {
        profileService.openProfilesFolder()
    }
    
    func openProfileFolder(_ descriptor: ProfileDescriptor) {
        NSWorkspace.shared.open(descriptor.directory)
    }
    
    func toggleLaunchAtLogin() async {
        do {
            try systemService.toggleLaunchAtLogin()
        } catch {
            await showError(error)
        }
    }
    
    
    var sortedProfiles: [ProfileDescriptor] {
        return profiles.sorted { $0.profile.order < $1.profile.order }
    }
    
    func isProfileActive(_ descriptor: ProfileDescriptor) -> Bool {
        guard let active = activeProfile else {
            return false
        }
        
        let pathMatch = active.directory.path == descriptor.directory.path
        let nameMatch = active.profile.name == descriptor.profile.name
        let isActive = pathMatch && nameMatch
        
        return isActive
    }
    
    var activeProfileName: String? {
        return activeProfile?.profile.name
    }
    
    var menuTitle: String {
        return activeProfileName ?? "Select a profile"
    }
    
    
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
    
    
    @MainActor
    private func showError(_ error: Error) async {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = error.localizedDescription
        
        if let localizableError = error as? LocalizedError,
           let suggestion = localizableError.recoverySuggestion {
            alert.informativeText += "\n\n\(suggestion)"
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @MainActor
    func confirmDeleteProfile(_ profileName: String) async -> Bool {
        let firstAlert = NSAlert()
        firstAlert.messageText = "Delete Profile"
        firstAlert.informativeText = "Are you sure you want to delete the profile '\(profileName)'?\n\nThis action cannot be undone. The profile folder will be moved to the Trash."
        firstAlert.alertStyle = .warning
        firstAlert.addButton(withTitle: "Delete")
        firstAlert.addButton(withTitle: "Cancel")
        
        let firstResponse = firstAlert.runModal()
        guard firstResponse == .alertFirstButtonReturn else { return false }
        
        let secondAlert = NSAlert()
        secondAlert.messageText = "Confirm Deletion"
        secondAlert.informativeText = "This will permanently move the profile '\(profileName)' and all its contents to the Trash.\n\n⚠️ This action cannot be undone.\n\nAre you absolutely sure you want to continue?"
        secondAlert.alertStyle = .critical
        secondAlert.addButton(withTitle: "Yes, Delete Profile")
        secondAlert.addButton(withTitle: "Cancel")
        
        let secondResponse = secondAlert.runModal()
        return secondResponse == .alertFirstButtonReturn
    }
    
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


extension StatusBarViewModel {
    
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
        
        let submenu = NSMenu()
        
        if isActive {
            let reapply = NSMenuItem(title: "Reapply", action: nil, keyEquivalent: "")
            submenu.addItem(reapply)
            
            let setWallpaper = NSMenuItem(title: "Set Wallpaper…", action: nil, keyEquivalent: "")
            submenu.addItem(setWallpaper)
            
            submenu.addItem(.separator())
        }
        
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
    
    func createActionMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        let newEmpty = NSMenuItem(title: "Create Empty Profile…", action: nil, keyEquivalent: "e")
        items.append(newEmpty)
        
        let snapshot = NSMenuItem(title: "Create Profile From Current…", action: nil, keyEquivalent: "n")
        items.append(snapshot)
        
        items.append(.separator())
        
        let reload = NSMenuItem(title: "Reload Profiles", action: nil, keyEquivalent: "r")
        items.append(reload)
        
        let open = NSMenuItem(title: "Open Profiles Folder", action: nil, keyEquivalent: "o")
        items.append(open)
        
        items.append(.separator())
        
        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
        launchAtLogin.state = isLaunchAtLoginEnabled ? .on : .off
        items.append(launchAtLogin)
        
        items.append(.separator())
        
        let quit = NSMenuItem(title: "Quit RiceBarMac", action: nil, keyEquivalent: "q")
        items.append(quit)
        
        return items
    }
}
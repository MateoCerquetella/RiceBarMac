import Foundation
import AppKit
import SwiftUI
import Combine
import UserNotifications
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif


final class StatusBarViewModel: ObservableObject {
    
    
    @Published private(set) var profiles: [ProfileDescriptor] = []
    @Published private(set) var activeProfile: ProfileDescriptor?
    @Published private(set) var isApplying = false
    @Published private(set) var isLaunchAtLoginEnabled = false
    @Published private(set) var launchAtLoginError: Error?
    @Published private(set) var registeredHotKeys: [String] = []
    @Published private(set) var invalidProfiles: [InvalidProfileDescriptor] = []
    @Published private(set) var operationState: ProfileOperationSnapshot = .idle
    @Published private(set) var previewPlan: ProfileApplyPlan?
    @Published private(set) var recoveryTransactions: [ApplyTransaction] = []
    @Published private(set) var canUndo = false
    @Published private(set) var migrationAvailability: LegacyMigrationAvailability = .none
    @Published private(set) var configError: ConfigServiceError?
    
    
    private let profileService: ProfileService
    private let systemService: SystemService
    private let configService: ConfigService
    
    
    private var cancellables = Set<AnyCancellable>()

    static let shared = StatusBarViewModel()
    
    
    init(
        profileService: ProfileService = .shared,
        systemService: SystemService = .shared,
        configService: ConfigService = .shared
    ) {
        self.profileService = profileService
        self.systemService = systemService
        self.configService = configService
        
        setupBindings()
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

        profileService.$invalidProfiles
            .receive(on: DispatchQueue.main)
            .assign(to: \.invalidProfiles, on: self)
            .store(in: &cancellables)

        profileService.$operationState
            .receive(on: DispatchQueue.main)
            .assign(to: \.operationState, on: self)
            .store(in: &cancellables)

        profileService.$recoveryTransactions
            .receive(on: DispatchQueue.main)
            .assign(to: \.recoveryTransactions, on: self)
            .store(in: &cancellables)

        profileService.$canUndo
            .receive(on: DispatchQueue.main)
            .assign(to: \.canUndo, on: self)
            .store(in: &cancellables)

        profileService.$migrationAvailability
            .receive(on: DispatchQueue.main)
            .assign(to: \.migrationAvailability, on: self)
            .store(in: &cancellables)

        configService.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: \.configError, on: self)
            .store(in: &cancellables)
        
        systemService.$isLaunchAtLoginEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLaunchAtLoginEnabled, on: self)
            .store(in: &cancellables)
        
        systemService.$launchAtLoginError
            .receive(on: DispatchQueue.main)
            .assign(to: \.launchAtLoginError, on: self)
            .store(in: &cancellables)
        
        systemService.$registeredHotKeys
            .receive(on: DispatchQueue.main)
            .assign(to: \.registeredHotKeys, on: self)
            .store(in: &cancellables)
        
        profileService.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profiles in
                self?.registerHotKeys(profiles: profiles)
            }
            .store(in: &cancellables)
        
        // Listen for shortcut updates and re-register hotkeys
        configService.$shortcutsUpdated
            .sink { [weak self] _ in
                self?.registerHotKeys()
            }
            .store(in: &cancellables)

        configService.$config
            .map { $0.general.autoReloadProfiles }
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.profileService.configureWatching(enabled: enabled)
            }
            .store(in: &cancellables)
    }
    
    
    func refreshData() {
        profileService.reload()
        systemService.updateLaunchAtLoginStatus()
    }
    
    private func registerHotKeys(profiles: [ProfileDescriptor]? = nil) {
        let profilesToRegister = profiles ?? self.profiles
        systemService.registerHotKeys(profiles: profilesToRegister) { [weak self] descriptor in
            self?.applyProfile(descriptor)
        }
        
        systemService.registerNavigationHotKeys(
            onNextProfile: { [weak self] in
                self?.switchToNextProfile()
            },
            onPreviousProfile: { [weak self] in
                self?.switchToPreviousProfile()
            },
            onReloadProfiles: { [weak self] in
                self?.refreshData()
            }
        )
    }
    
    func switchToNextProfile() {
        let sortedProfiles = sortedProfiles
        guard !sortedProfiles.isEmpty else { return }
        
        if let currentIndex = sortedProfiles.firstIndex(where: { isProfileActive($0) }) {
            let nextIndex = (currentIndex + 1) % sortedProfiles.count
            let nextProfile = sortedProfiles[nextIndex]
            applyProfile(nextProfile)
        } else {
            applyProfile(sortedProfiles[0])
        }
    }
    
    func switchToPreviousProfile() {
        let sortedProfiles = sortedProfiles
        guard !sortedProfiles.isEmpty else { return }
        
        if let currentIndex = sortedProfiles.firstIndex(where: { isProfileActive($0) }) {
            let prevIndex = currentIndex == 0 ? sortedProfiles.count - 1 : currentIndex - 1
            let prevProfile = sortedProfiles[prevIndex]
            applyProfile(prevProfile)
        } else {
            applyProfile(sortedProfiles.last!)
        }
    }
    
    
    func applyProfile(_ descriptor: ProfileDescriptor) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let plan = try await self.profileService.previewProfile(descriptor)
                self.previewPlan = plan
                guard plan.isValid else {
                    throw ProfilePlanningError(issues: plan.issues)
                }
                guard await self.confirmApply(plan) else {
                    self.previewPlan = nil
                    return
                }
                let outcome = try await self.profileService.applyPlan(plan)
                self.previewPlan = nil
                if outcome.warnings.isEmpty {
                    self.postNotification(title: "Profile Applied", body: "\(plan.profileName) is now active.")
                } else {
                    await self.showWarning(title: "Applied with Warnings", message: outcome.warnings.joined(separator: "\n"))
                }
            } catch {
                if Task.isCancelled {
                    self.previewPlan = nil
                } else if self.operationState.phase != .recoveryRequired {
                    self.previewPlan = nil
                    await self.showError(error)
                }
            }
        }
    }

    func undoLastApply() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.profileService.undoLastApply()
                self.postNotification(title: "Profile Restored", body: "The previous filesystem state was restored.")
            } catch {
                await self.showError(error)
            }
        }
    }

    func migrateLegacyConfiguration() {
        Task { @MainActor [weak self] in
            guard let self, self.confirmLegacyMigration() else { return }
            do {
                let record = try self.profileService.migrateLegacyConfiguration()
                if let warning = record.errorDescription {
                    await self.showWarning(title: "Migration Completed with Warning", message: warning)
                } else {
                    self.postNotification(title: "Migration Complete", body: "Legacy .ricebar data was copied safely. The original remains available.")
                }
            } catch {
                await self.showError(error)
            }
        }
    }

    func recover(_ transaction: ApplyTransaction) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.profileService.recover(transactionID: transaction.id)
            } catch {
                await self.showError(error)
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
            let enabled = try systemService.toggleLaunchAtLogin()
            configService.updateGeneralSetting(\.launchAtLogin, to: enabled)
        } catch {
            // Error is already tracked in systemService.launchAtLoginError
            // Don't show additional dialog - UI will display the error state
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

    var hasLegacyMigration: Bool {
        if case .none = migrationAvailability { return false }
        return true
    }

    var hasRecoveryBlocker: Bool {
        !recoveryTransactions.isEmpty || operationState.phase == .recoveryRequired
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
    func showError(_ error: Error) async {
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
    private func showWarning(title: String, message: String) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private func confirmApply(_ plan: ProfileApplyPlan) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Preview \(plan.profileName)"
        alert.informativeText = "Review the exact plan below. No files have been changed. Replaced items will be moved to the listed backups."
        alert.alertStyle = plan.warnings.isEmpty ? .informational : .warning
        let applyButton = alert.addButton(withTitle: "Apply")
        applyButton.keyEquivalent = "\r"
        applyButton.setAccessibilityIdentifier("confirm-profile-apply")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("cancel-profile-apply")

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 280))
        textView.string = plan.previewText
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.setAccessibilityLabel("Profile apply plan")

        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        alert.accessoryView = scrollView

        if let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: parentWindow) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        }

        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func confirmLegacyMigration() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch migrationAvailability {
        case .none:
            alert.messageText = "No Legacy Configuration"
            alert.informativeText = "No usable ~/.ricebar configuration was found."
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return false
        case .available(let source):
            alert.messageText = "Migrate Legacy Configuration?"
            alert.informativeText = "RiceBarMac will validate and copy \(source.path) into the current format. The original remains untouched."
            alert.addButton(withTitle: "Migrate")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        case .conflict(let source, let destination, let entries):
            alert.messageText = "Migration Conflict"
            alert.informativeText = "Both \(source.path) and \(destination.path) contain data. Nothing was changed. Conflicting current entries: \(entries.joined(separator: ", "))."
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return false
        }
    }

    private func postNotification(title: String, body: String) {
        guard configService.config.general.showNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
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
    
    func saveCurrentConfig() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.profileService.saveCurrentConfigToActiveProfile()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func saveCurrentConfigToProfile(_ descriptor: ProfileDescriptor) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.profileService.saveCurrentConfigToSpecificProfile(descriptor)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

import AppKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import SwiftUI
import Combine

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let viewModel: StatusBarViewModel
    private var cancellables = Set<AnyCancellable>()
    private let configService = ConfigService.shared

    init(viewModel: StatusBarViewModel = .shared) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: Constants.StatusBarIcon.menuBarLength)
        updateMenuBarIcon()
        
        setupBindings()
        constructMenu()
    }

    private func setupBindings() {
        viewModel.$profiles
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .removeDuplicates { $0.count == $1.count && $0.map(\.directory) == $1.map(\.directory) }
            .sink { [weak self] profiles in
                self?.constructMenu()
            }
            .store(in: &cancellables)
        
        viewModel.$activeProfile
            .removeDuplicates { 
                if $0 == nil && $1 == nil { return true }
                if $0 == nil || $1 == nil { return false }
                return $0!.directory == $1!.directory
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeProfile in
                // Reconstruct entire menu when active profile changes
                self?.constructMenu()
            }
            .store(in: &cancellables)
        
        viewModel.$isLaunchAtLoginEnabled
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateLaunchAtLoginCheckmark()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            viewModel.$operationState,
            viewModel.$canUndo,
            viewModel.$invalidProfiles,
            viewModel.$recoveryTransactions
        )
        .debounce(for: .milliseconds(75), scheduler: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.constructMenu()
        }
        .store(in: &cancellables)

        viewModel.$migrationAvailability
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.constructMenu() }
            .store(in: &cancellables)
        
        // Listen for appearance config changes
        configService.$config
            .map(\.appearance.menuBarIcon)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)
    }
    
    private func constructMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Create title view with unique ID to force recreation
        let titleItem = NSMenuItem()
        let titleView = TitleMenuView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: titleView)
        
        // Force the hosting view to update
        hostingView.rootView = titleView
        titleItem.view = hostingView
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())
        

        // Keep only essential actions - remove profile manager UI

        let profileItems = createProfileMenuItems()
        for item in profileItems {
            menu.addItem(item)
        }

        menu.addItem(.separator())
        
        let actionItems = createActionMenuItems()
        for item in actionItems {
            menu.addItem(item)
        }

        statusItem.menu = menu
    }
    
    private func updateActiveProfileCheckmarks() {
        guard let menu = statusItem.menu else { 
            return 
        }
        
        for item in menu.items {
            if let descriptor = item.representedObject as? ProfileDescriptor {
                let isActive = viewModel.isProfileActive(descriptor)
                let newState: NSControl.StateValue = isActive ? .on : .off
                
                item.state = newState
            }
        }
        
    }
    
    private func updateLaunchAtLoginCheckmark() {
        guard let menu = statusItem.menu else { return }
        
        for item in menu.items {
            if item.title == "Launch at Login" {
                item.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
                break
            }
        }
    }
    
    private func updateMenuBarIcon() {
        statusItem.button?.title = configService.config.appearance.menuBarIcon
        statusItem.button?.setAccessibilityLabel("RiceBarMac profile switcher")
    }
    
    private func createProfileMenuItems() -> [NSMenuItem] {
        var result: [NSMenuItem] = []
        if viewModel.profiles.isEmpty {
            let empty = NSMenuItem(title: viewModel.invalidProfiles.isEmpty ? "No profiles found" : "No valid profiles found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            result.append(empty)
        }

        result.append(contentsOf: viewModel.sortedProfiles.enumerated().map { (index, descriptor) in
            let title = descriptor.profile.name
            let profileKey = "profile\(index + 1)"
            let configShortcut = configService.config.shortcuts.profileShortcuts[profileKey] ?? ""
            
            var keyEquivalent = ""
            var modifierMask: NSEvent.ModifierFlags = []
            
            if index < 9, let parsedShortcut = parseMenuShortcut(configShortcut) {
                keyEquivalent = parsedShortcut.key
                modifierMask = parsedShortcut.modifiers
            }
            
            let item = NSMenuItem(title: title, action: #selector(applyProfileMenu(_:)), keyEquivalent: keyEquivalent)
            item.target = self
            item.representedObject = descriptor
            item.keyEquivalentModifierMask = modifierMask
            item.isEnabled = !viewModel.isApplying && !viewModel.hasRecoveryBlocker
            
            var tooltipParts: [String] = []
            if !configShortcut.isEmpty {
                tooltipParts.append("Shortcut: \(configShortcut)")
            }
            if let hotkeyText = descriptor.profile.hotkey {
                tooltipParts.append("Hotkey: \(hotkeyText)")
            }
            if !tooltipParts.isEmpty {
                item.toolTip = tooltipParts.joined(separator: " | ")
            }
            
            let isActive = viewModel.isProfileActive(descriptor)
            item.state = isActive ? .on : .off
            
            let submenu = createProfileSubmenu(for: descriptor, isActive: isActive)
            item.submenu = submenu
            
            return item
        })

        if !viewModel.invalidProfiles.isEmpty {
            result.append(.separator())
            let heading = NSMenuItem(title: "Invalid Profiles", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            result.append(heading)
            for invalid in viewModel.invalidProfiles {
                let item = NSMenuItem(title: "⚠︎ \(invalid.directory.lastPathComponent)", action: nil, keyEquivalent: "")
                item.toolTip = invalid.message
                item.isEnabled = false
                result.append(item)
            }
        }
        return result
    }
    
    private func createProfileSubmenu(for descriptor: ProfileDescriptor, isActive: Bool) -> NSMenu {
        let submenu = NSMenu()

        let preview = NSMenuItem(
            title: isActive ? "Preview Reapply…" : "Preview and Apply…",
            action: #selector(applyProfileMenu(_:)),
            keyEquivalent: ""
        )
        preview.target = self
        preview.representedObject = descriptor
        preview.isEnabled = !viewModel.isApplying && !viewModel.hasRecoveryBlocker
        submenu.addItem(preview)
        submenu.addItem(.separator())
        
        if isActive {
            let setWallpaper = NSMenuItem(title: "Set Wallpaper…", action: #selector(pickWallpaperForActive), keyEquivalent: "")
            setWallpaper.target = self
            submenu.addItem(setWallpaper)
            
            submenu.addItem(.separator())
        }
        
        // Save Current Config should be available for all profiles
        let saveConfig = NSMenuItem(title: "Save Current Config to This Profile", action: #selector(saveCurrentConfigToProfile(_:)), keyEquivalent: "")
        saveConfig.target = self
        saveConfig.representedObject = descriptor
        submenu.addItem(saveConfig)
        
        submenu.addItem(.separator())
        
        let openFolder = NSMenuItem(title: "Open Profile Folder", action: #selector(openProfileFolder(_:)), keyEquivalent: "")
        openFolder.target = self
        openFolder.representedObject = descriptor
        submenu.addItem(openFolder)
        
        submenu.addItem(.separator())
        
        let deleteProfile = NSMenuItem(title: "Delete Profile…", action: #selector(deleteProfile(_:)), keyEquivalent: "")
        deleteProfile.target = self
        deleteProfile.representedObject = descriptor
        submenu.addItem(deleteProfile)
        
        return submenu
    }
    
    private func createActionMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        let operation = NSMenuItem(title: viewModel.operationState.message, action: nil, keyEquivalent: "")
        operation.isEnabled = false
        items.append(operation)

        if let position = viewModel.operationState.queuePosition {
            let queued = NSMenuItem(title: "Queue position: \(position)", action: nil, keyEquivalent: "")
            queued.isEnabled = false
            items.append(queued)
        }

        let undo = NSMenuItem(title: "Undo Last Apply", action: #selector(undoLastApply), keyEquivalent: "")
        undo.target = self
        undo.isEnabled = viewModel.canUndo && !viewModel.isApplying && !viewModel.hasRecoveryBlocker
        items.append(undo)

        if viewModel.hasLegacyMigration {
            let migrate = NSMenuItem(title: "Migrate Legacy Configuration…", action: #selector(migrateLegacyConfiguration), keyEquivalent: "")
            migrate.target = self
            migrate.isEnabled = !viewModel.isApplying
            items.append(migrate)
        }

        for transaction in viewModel.recoveryTransactions {
            let recovery = NSMenuItem(title: "Recover \(transaction.plan.profileName)…", action: #selector(recoverTransaction(_:)), keyEquivalent: "")
            recovery.target = self
            recovery.representedObject = transaction
            recovery.isEnabled = !viewModel.isApplying
            items.append(recovery)
        }

        items.append(.separator())
        
        let createProfileMenu = NSMenuItem(title: "Create Profile", action: nil, keyEquivalent: "")
        let createSubmenu = NSMenu()
        
        let newEmpty = NSMenuItem(title: "Empty Profile…", action: #selector(promptCreateEmpty), keyEquivalent: "")
        newEmpty.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.quickActions.createEmptyProfile) {
            newEmpty.keyEquivalent = parsed.key
            newEmpty.keyEquivalentModifierMask = parsed.modifiers
        }
        createSubmenu.addItem(newEmpty)
        
        let snapshot = NSMenuItem(title: "From Current Setup…", action: #selector(promptCreateFromCurrent), keyEquivalent: "")
        snapshot.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.quickActions.createFromCurrentSetup) {
            snapshot.keyEquivalent = parsed.key
            snapshot.keyEquivalentModifierMask = parsed.modifiers
        }
        createSubmenu.addItem(snapshot)
        
        createProfileMenu.submenu = createSubmenu
        items.append(createProfileMenu)
        
        items.append(.separator())
        
        let nextProfile = NSMenuItem(title: "Next Profile", action: #selector(switchToNextProfile), keyEquivalent: "")
        nextProfile.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.navigationShortcuts.nextProfile) {
            nextProfile.keyEquivalent = parsed.key
            nextProfile.keyEquivalentModifierMask = parsed.modifiers
        }
        items.append(nextProfile)
        
        let prevProfile = NSMenuItem(title: "Previous Profile", action: #selector(switchToPreviousProfile), keyEquivalent: "")
        prevProfile.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.navigationShortcuts.previousProfile) {
            prevProfile.keyEquivalent = parsed.key
            prevProfile.keyEquivalentModifierMask = parsed.modifiers
        }
        items.append(prevProfile)
        
        items.append(.separator())
        
        let reload = NSMenuItem(title: "Reload Profiles", action: #selector(reloadProfiles), keyEquivalent: "")
        reload.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.navigationShortcuts.reloadProfiles) {
            reload.keyEquivalent = parsed.key
            reload.keyEquivalentModifierMask = parsed.modifiers
        }
        items.append(reload)
        
        let open = NSMenuItem(title: "Open Profiles Folder", action: #selector(openProfilesFolder), keyEquivalent: "")
        open.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.navigationShortcuts.openProfilesFolder) {
            open.keyEquivalent = parsed.key
            open.keyEquivalentModifierMask = parsed.modifiers
        }
        items.append(open)
        
        items.append(.separator())
        
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.quickActions.openSettings) {
            settings.keyEquivalent = parsed.key
            settings.keyEquivalentModifierMask = parsed.modifiers
        }
        items.append(settings)
        
        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
        items.append(launchAtLogin)
        
        items.append(.separator())
        
        let quit = NSMenuItem(title: "Quit \(Constants.appName)", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        if let parsed = parseMenuShortcut(configService.config.shortcuts.quickActions.quitApp) {
            quit.keyEquivalent = parsed.key
            quit.keyEquivalentModifierMask = parsed.modifiers
        }
        items.append(quit)
        
        return items
    }

    @objc private func applyProfileMenu(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        
        
        viewModel.applyProfile(descriptor)
    }

    @objc private func undoLastApply() {
        viewModel.undoLastApply()
    }

    @objc private func migrateLegacyConfiguration() {
        viewModel.migrateLegacyConfiguration()
    }

    @objc private func recoverTransaction(_ sender: NSMenuItem) {
        guard let transaction = sender.representedObject as? ApplyTransaction else { return }
        viewModel.recover(transaction)
    }

    @objc private func openProfilesFolder() {
        viewModel.openProfilesFolder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
    
    @objc private func toggleLaunchAtLogin() {
        Task {
            await viewModel.toggleLaunchAtLogin()
            
            // Update checkmark immediately after toggle for immediate visual feedback
            await MainActor.run {
                self.updateLaunchAtLoginCheckmark()
            }
        }
    }
    
    @objc private func promptCreateEmpty() {
        Task { @MainActor in
            guard let name = await viewModel.promptForProfileName(
                title: "Create Empty Profile",
                message: "Enter a name for the new empty profile.",
                placeholder: "New profile name"
            ) else { return }
            
            do {
                _ = try await viewModel.createEmptyProfile(name: name)
                await viewModel.showSuccess(title: "Profile Created", message: "Empty profile created successfully.")
            } catch {
                await viewModel.showError(error)
            }
        }
    }
    
    @objc private func switchToNextProfile() {
        viewModel.switchToNextProfile()
    }
    
    @objc private func switchToPreviousProfile() {
        viewModel.switchToPreviousProfile()
    }
    
    @objc private func reloadProfiles() {
        viewModel.refreshData()
    }
    
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func promptCopyCurrentProfile() {
        guard let current = viewModel.activeProfile else { return }
        
        Task { @MainActor in
            guard let name = await viewModel.promptForProfileName(
                title: "Duplicate Profile",
                message: "Enter a name for the copied profile.",
                placeholder: "New profile name"
            ) else { return }
            
            do {
                _ = try await viewModel.copyProfile(current, to: name)
                await viewModel.showSuccess(title: "Profile Copied", message: "Profile copied successfully.")
            } catch {
                await viewModel.showError(error)
            }
        }
    }

    @objc private func promptCreateFromCurrent() {
        Task { @MainActor in
            guard let name = await viewModel.promptForProfileName(
                title: "Create Profile From Current",
                message: "Enter a name for the new profile. Your current ~/.config will be captured into it.",
                placeholder: "New profile name"
            ) else { return }
            
            do {
                _ = try await viewModel.createProfileFromCurrent(name: name)
                await viewModel.showSuccess(title: "Profile Created", message: "Profile created from current configuration.")
            } catch {
                await viewModel.showError(error)
            }
        }
    }

    @objc private func reapplyActive() {
        viewModel.reapplyActiveProfile()
    }

    @objc private func openActiveProfileFolder() {
        guard let active = viewModel.activeProfile else { return }
        viewModel.openProfileFolder(active)
    }

    @objc private func pickWallpaperForActive() {
        guard let active = viewModel.activeProfile else { return }
        
        viewModel.pickWallpaperFile { [weak self] url in
            guard let self, let url else { return }
            
            Task { @MainActor [self] in
                do {
                    let updated = try await self.viewModel.updateWallpaper(for: active, from: url)
                    self.viewModel.applyProfile(updated)
                } catch {
                    await self.viewModel.showError(error)
                }
            }
        }
    }
    
    @objc private func saveCurrentConfig() {
        Task { @MainActor in
            do {
                try await viewModel.saveCurrentConfig()
                await viewModel.showSuccess(
                    title: "Config Saved",
                    message: "Current IDE settings have been saved to the active profile."
                )
            } catch {
                // Create a custom error for showError
                let saveError = ProfileServiceError.fileOperationFailed("Save current config", error)
                await viewModel.showError(saveError)
            }
        }
    }
    
    @objc private func saveCurrentConfigToProfile(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        
        Task { @MainActor in
            do {
                try await viewModel.saveCurrentConfigToProfile(descriptor)
                await viewModel.showSuccess(
                    title: "Config Saved",
                    message: "Current IDE settings have been saved to '\(descriptor.profile.name)' profile."
                )
            } catch {
                let saveError = ProfileServiceError.fileOperationFailed("Save current config to profile", error)
                await viewModel.showError(saveError)
            }
        }
    }

    @objc private func deleteProfile(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        
        Task { @MainActor in
            let confirmed = await viewModel.confirmDeleteProfile(descriptor.profile.name)
            guard confirmed else { return }
            
            do {
                try await viewModel.deleteProfile(descriptor)
                await viewModel.showSuccess(
                    title: "Profile Deleted",
                    message: "The profile '\(descriptor.profile.name)' has been moved to the Trash."
                )
            } catch {
                await viewModel.showError(error)
            }
        }
    }

    @objc private func openProfileFolder(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        viewModel.openProfileFolder(descriptor)
    }

    // Removed unused profile management methods
    
    // Settings UI removed - profiles are managed through menu only
    
    private func parseMenuShortcut(_ shortcut: String) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let parts = shortcut.lowercased().split(separator: "+").map { String($0) }
        guard !parts.isEmpty else { return nil }
        
        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?
        
        for part in parts {
            switch part {
            case "ctrl", "control": 
                modifiers.insert(.control)
            case "cmd", "command": 
                modifiers.insert(.command)
            case "opt", "option", "alt": 
                modifiers.insert(.option)
            case "shift": 
                modifiers.insert(.shift)
            default: 
                keyString = part
            }
        }
        
        guard let key = keyString else { return nil }
        
        if key == "]" || key == "[" {
            return (key: key, modifiers: modifiers)
        }
        
        if key.count == 1, let first = key.first, first.isLetter {
            return (key: key.lowercased(), modifiers: modifiers)
        }
        
        if let number = Int(key), (1...9).contains(number) {
            return (key: "\(number)", modifiers: modifiers)
        }
        
        switch key {
        case "0": return (key: "0", modifiers: modifiers)
        case "r": return (key: "r", modifiers: modifiers)
        case "o": return (key: "o", modifiers: modifiers)
        case "e": return (key: "e", modifiers: modifiers)
        case "n": return (key: "n", modifiers: modifiers)
        case "q": return (key: "q", modifiers: modifiers)
        case ",": return (key: ",", modifiers: modifiers)
        default: return nil
        }
    }
}

private struct TitleMenuView: View {
    @ObservedObject var viewModel: StatusBarViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RiceBarMac")
                    .font(.headline)
                if viewModel.isApplying {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                        Text("Applying...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Show active profile status - force refresh by accessing properties directly  
            HStack {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if viewModel.isApplying {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
    
    private var statusText: String {
        if let activeProfile = viewModel.activeProfile {
            return "Active: \(activeProfile.profile.name)"
        } else {
            return "Select a profile"
        }
    }
}

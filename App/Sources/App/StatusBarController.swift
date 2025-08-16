import AppKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import SwiftUI
import Combine

/// Controls the menu bar interface and user interactions
/// Refactored to use MVVM architecture with StatusBarViewModel
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let viewModel: StatusBarViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: StatusBarViewModel = StatusBarViewModel()) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: Constants.StatusBarIcon.menuBarLength)
        statusItem.button?.image = NSImage(systemSymbolName: Constants.StatusBarIcon.systemName, accessibilityDescription: Constants.StatusBarIcon.accessibilityDescription)
        
        setupBindings()
        constructMenu()
    }

    private func setupBindings() {
        // Rebuild menu when profiles or state changes
        Publishers.CombineLatest4(
            viewModel.$profiles,
            viewModel.$activeProfile,
            viewModel.$isApplying,
            viewModel.$isLaunchAtLoginEnabled
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.constructMenu()
        }
        .store(in: &cancellables)
    }
    
    private func constructMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Title item
        let titleItem = NSMenuItem()
        titleItem.view = NSHostingView(rootView: TitleMenuView(
            activeName: viewModel.activeProfileName,
            isApplying: viewModel.isApplying
        ))
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // Profile items
        let profileItems = createProfileMenuItems()
        for item in profileItems {
            menu.addItem(item)
        }

        menu.addItem(.separator())
        
        // Action items
        let actionItems = createActionMenuItems()
        for item in actionItems {
            menu.addItem(item)
        }

        statusItem.menu = menu
    }
    
    private func createProfileMenuItems() -> [NSMenuItem] {
        if viewModel.profiles.isEmpty {
            let empty = NSMenuItem(title: "No profiles found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return [empty]
        }
        
        return viewModel.sortedProfiles.map { descriptor in
            let title = descriptor.profile.name
            let item = NSMenuItem(title: title, action: #selector(applyProfileMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = descriptor
            
            if let hotkeyText = descriptor.profile.hotkey {
                item.toolTip = "Hotkey: \(hotkeyText)"
            }
            
            let isActive = viewModel.isProfileActive(descriptor)
            if isActive {
                item.state = .on
            }
            
            // Add submenu with profile actions
            let submenu = createProfileSubmenu(for: descriptor, isActive: isActive)
            item.submenu = submenu
            
            return item
        }
    }
    
    private func createProfileSubmenu(for descriptor: ProfileDescriptor, isActive: Bool) -> NSMenu {
        let submenu = NSMenu()
        
        if isActive {
            // Active profile specific actions
            let reapply = NSMenuItem(title: "Reapply", action: #selector(reapplyActive), keyEquivalent: "")
            reapply.target = self
            submenu.addItem(reapply)
            
            let setWallpaper = NSMenuItem(title: "Set Wallpaper…", action: #selector(pickWallpaperForActive), keyEquivalent: "")
            setWallpaper.target = self
            submenu.addItem(setWallpaper)
            
            submenu.addItem(.separator())
        }
        
        // Common actions for all profiles
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
        
        // Profile creation actions
        let newEmpty = NSMenuItem(title: "Create Empty Profile…", action: #selector(promptCreateEmpty), keyEquivalent: Constants.MenuKeyEquivalents.newEmptyProfile)
        newEmpty.target = self
        items.append(newEmpty)
        
        let snapshot = NSMenuItem(title: "Create Profile From Current…", action: #selector(promptCreateFromCurrent), keyEquivalent: Constants.MenuKeyEquivalents.newFromCurrent)
        snapshot.target = self
        items.append(snapshot)
        
        items.append(.separator())
        
        // General actions
        let reload = NSMenuItem(title: "Reload Profiles", action: #selector(reloadProfiles), keyEquivalent: Constants.MenuKeyEquivalents.reloadProfiles)
        reload.target = self
        items.append(reload)
        
        let open = NSMenuItem(title: "Open Profiles Folder", action: #selector(openProfilesFolder), keyEquivalent: Constants.MenuKeyEquivalents.openFolder)
        open.target = self
        items.append(open)
        
        items.append(.separator())
        
        // Settings
        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
        items.append(launchAtLogin)
        
        items.append(.separator())
        
        // Quit
        let quit = NSMenuItem(title: "Quit \(Constants.appName)", action: #selector(quit), keyEquivalent: Constants.MenuKeyEquivalents.quit)
        quit.target = self
        items.append(quit)
        
        return items
    }

    @objc private func applyProfileMenu(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        
        // Only apply if not already applying (prevent race condition)
        guard !viewModel.isApplying else {
            LoggerService.info("Profile application already in progress, ignoring click")
            return
        }
        
        // Immediate visual feedback while the menu is open
        if let items = statusItem.menu?.items {
            for item in items where item.action == #selector(applyProfileMenu(_:)) {
                item.state = (item === sender) ? .on : .off
            }
        }
        
        viewModel.applyProfile(descriptor)
    }

    @objc private func reloadProfiles() {
        viewModel.refreshData()
    }

    @objc private func openProfilesFolder() {
        viewModel.openProfilesFolder()
    }

    @objc private func toggleLaunchAtLogin() {
        Task {
            await viewModel.toggleLaunchAtLogin()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
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
                LoggerService.error("Failed to copy profile: \(error)")
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
                LoggerService.error("Failed to create profile from current: \(error)")
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
            guard let url = url else { return }
            
            Task { @MainActor in
                do {
                    let updated = try await self?.viewModel.updateWallpaper(for: active, from: url)
                    if let updated = updated {
                        self?.viewModel.applyProfile(updated)
                    }
                } catch {
                    LoggerService.error("Failed to update wallpaper: \(error)")
                }
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
                LoggerService.error("Failed to delete profile: \(error)")
            }
        }
    }

    @objc private func openProfileFolder(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        viewModel.openProfileFolder(descriptor)
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
                LoggerService.error("Failed to create empty profile: \(error)")
            }
        }
    }
}

private struct TitleMenuView: View {
    var activeName: String?
    var isApplying: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RiceBarMac")
                    .font(.headline)
                if isApplying {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                }
            }
            if let activeName, !activeName.isEmpty {
                Text("Active: \(activeName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Select a profile")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}

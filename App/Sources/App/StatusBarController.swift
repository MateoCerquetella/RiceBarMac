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

    init(viewModel: StatusBarViewModel = StatusBarViewModel()) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: Constants.StatusBarIcon.menuBarLength)
        statusItem.button?.image = NSImage(systemSymbolName: Constants.StatusBarIcon.systemName, accessibilityDescription: Constants.StatusBarIcon.accessibilityDescription)
        
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
                self?.updateActiveProfileCheckmarks()
            }
            .store(in: &cancellables)
        
        viewModel.$isLaunchAtLoginEnabled
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateLaunchAtLoginCheckmark()
            }
            .store(in: &cancellables)
    }
    
    private func constructMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem()
        titleItem.view = NSHostingView(rootView: TitleMenuView(viewModel: viewModel))
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

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
        
        DispatchQueue.main.async {
            self.updateActiveProfileCheckmarks()
        }
    }
    
    private func updateActiveProfileCheckmarks() {
        guard let menu = statusItem.menu else { 
            return 
        }
        
        var profileItemsFound = 0
        
        for (index, item) in menu.items.enumerated() {
            if let descriptor = item.representedObject as? ProfileDescriptor {
                profileItemsFound += 1
                let isActive = viewModel.isProfileActive(descriptor)
                let currentState = item.state
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
    
    private func createProfileMenuItems() -> [NSMenuItem] {
        if viewModel.profiles.isEmpty {
            let empty = NSMenuItem(title: "No profiles found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return [empty]
        }
        
        return viewModel.sortedProfiles.enumerated().map { (index, descriptor) in
            let title = descriptor.profile.name
            let keyEquivalent = index < 9 ? "\(index + 1)" : ""
            let item = NSMenuItem(title: title, action: #selector(applyProfileMenu(_:)), keyEquivalent: keyEquivalent)
            item.target = self
            item.representedObject = descriptor
            
            if index < 9 {
                item.keyEquivalentModifierMask = .command
            }
            
            if let hotkeyText = descriptor.profile.hotkey {
                item.toolTip = "Hotkey: \(hotkeyText) | Shortcut: ⌘\(index + 1)"
            } else if index < 9 {
                item.toolTip = "Shortcut: ⌘\(index + 1)"
            }
            
            let isActive = viewModel.isProfileActive(descriptor)
            item.state = isActive ? .on : .off
            
            let submenu = createProfileSubmenu(for: descriptor, isActive: isActive)
            item.submenu = submenu
            
            return item
        }
    }
    
    private func createProfileSubmenu(for descriptor: ProfileDescriptor, isActive: Bool) -> NSMenu {
        let submenu = NSMenu()
        
        if isActive {
            let reapply = NSMenuItem(title: "Reapply", action: #selector(reapplyActive), keyEquivalent: "")
            reapply.target = self
            submenu.addItem(reapply)
            
            let setWallpaper = NSMenuItem(title: "Set Wallpaper…", action: #selector(pickWallpaperForActive), keyEquivalent: "")
            setWallpaper.target = self
            submenu.addItem(setWallpaper)
            
            submenu.addItem(.separator())
        }
        
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
        
        let createProfileMenu = NSMenuItem(title: "Create Profile", action: nil, keyEquivalent: "")
        let createSubmenu = NSMenu()
        
        let newEmpty = NSMenuItem(title: "Empty Profile…", action: #selector(promptCreateEmpty), keyEquivalent: Constants.MenuKeyEquivalents.newEmptyProfile)
        newEmpty.target = self
        createSubmenu.addItem(newEmpty)
        
        let snapshot = NSMenuItem(title: "From Current Setup…", action: #selector(promptCreateFromCurrent), keyEquivalent: Constants.MenuKeyEquivalents.newFromCurrent)
        snapshot.target = self
        createSubmenu.addItem(snapshot)
        
        createProfileMenu.submenu = createSubmenu
        items.append(createProfileMenu)
        
        items.append(.separator())
        
        let nextProfile = NSMenuItem(title: "Next Profile", action: #selector(switchToNextProfile), keyEquivalent: "]")
        nextProfile.target = self
        nextProfile.keyEquivalentModifierMask = .command
        items.append(nextProfile)
        
        let prevProfile = NSMenuItem(title: "Previous Profile", action: #selector(switchToPreviousProfile), keyEquivalent: "[")
        prevProfile.target = self
        prevProfile.keyEquivalentModifierMask = .command
        items.append(prevProfile)
        
        items.append(.separator())
        
        let reload = NSMenuItem(title: "Reload Profiles", action: #selector(reloadProfiles), keyEquivalent: Constants.MenuKeyEquivalents.reloadProfiles)
        reload.target = self
        items.append(reload)
        
        let open = NSMenuItem(title: "Open Profiles Folder", action: #selector(openProfilesFolder), keyEquivalent: Constants.MenuKeyEquivalents.openFolder)
        open.target = self
        items.append(open)
        
        items.append(.separator())
        
        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
        items.append(launchAtLogin)
        
        items.append(.separator())
        
        let quit = NSMenuItem(title: "Quit \(Constants.appName)", action: #selector(quit), keyEquivalent: Constants.MenuKeyEquivalents.quit)
        quit.target = self
        items.append(quit)
        
        return items
    }

    @objc private func applyProfileMenu(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        
        
        viewModel.applyProfile(descriptor)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateActiveProfileCheckmarks()
        }
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
            }
        }
    }
    
    @objc private func switchToNextProfile() {
        let profiles = viewModel.sortedProfiles
        guard !profiles.isEmpty else { return }
        
        if let currentIndex = profiles.firstIndex(where: { viewModel.isProfileActive($0) }) {
            let nextIndex = (currentIndex + 1) % profiles.count
            let nextProfile = profiles[nextIndex]
            viewModel.applyProfile(nextProfile)
        } else {
            viewModel.applyProfile(profiles[0])
        }
    }
    
    @objc private func switchToPreviousProfile() {
        let profiles = viewModel.sortedProfiles
        guard !profiles.isEmpty else { return }
        
        if let currentIndex = profiles.firstIndex(where: { viewModel.isProfileActive($0) }) {
            let prevIndex = currentIndex == 0 ? profiles.count - 1 : currentIndex - 1
            let prevProfile = profiles[prevIndex]
            viewModel.applyProfile(prevProfile)
        } else {
            viewModel.applyProfile(profiles.last!)
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
            if let activeName = viewModel.activeProfileName, !activeName.isEmpty {
                HStack {
                    Text("Active: \(activeName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if viewModel.isApplying {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
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

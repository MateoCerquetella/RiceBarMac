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
    // Removed settings UI components

    init(viewModel: StatusBarViewModel = StatusBarViewModel()) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: Constants.StatusBarIcon.menuBarLength)
        statusItem.button?.title = Constants.StatusBarIcon.systemName
        
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
        
        let config = ConfigService.shared.config
        
        return viewModel.sortedProfiles.enumerated().map { (index, descriptor) in
            let title = descriptor.profile.name
            let profileKey = "profile\(index + 1)"
            let configShortcut = config.shortcuts.profileShortcuts[profileKey] ?? ""
            
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
        
        // Simplified menu - keep only essential actions
        let snapshot = NSMenuItem(title: "Create from Current Setup", action: #selector(promptCreateFromCurrent), keyEquivalent: "n")
        snapshot.target = self
        items.append(snapshot)
        
        items.append(.separator())
        
        let open = NSMenuItem(title: "Open Profiles Folder", action: #selector(openProfilesFolder), keyEquivalent: "o")
        open.target = self
        items.append(open)
        
        items.append(.separator())
        
        let quit = NSMenuItem(title: "Quit \(Constants.appName)", action: #selector(quit), keyEquivalent: "q")
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

    @objc private func openProfilesFolder() {
        viewModel.openProfilesFolder()
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

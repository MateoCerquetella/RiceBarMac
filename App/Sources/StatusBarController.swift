import AppKit
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "RiceBar")
        constructMenu()
        HotKeyManager.shared.registerHotKeys(profiles: ProfileManager.shared.profiles) { [weak self] descriptor in
            self?.apply(descriptor)
        }
        ProfileWatcher.shared.onProfilesChanged = { [weak self] _ in self?.reloadProfiles() }
        ProfileWatcher.shared.onActiveProfileChanged = { [weak self] _ in
            guard let active = ActiveProfileStore.shared.activeProfile else { return }
            // Auto-apply when files inside the active profile change
            if ApplyActivity.isApplying || ApplyActivity.recentlyApplied() { return }
            ApplyActivity.begin()
            defer { ApplyActivity.end() }
            do { try ProfileApplier.shared.apply(descriptor: active, cleanConfig: false) } catch { }
        }
        ProfileWatcher.shared.startWatching()
    }

    private func constructMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem()
        let activeName = ActiveProfileStore.shared.activeProfile?.profile.name
        titleItem.view = NSHostingView(rootView: TitleMenuView(activeName: activeName))
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        if ProfileManager.shared.profiles.isEmpty {
            let empty = NSMenuItem(title: "No profiles found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for descriptor in ProfileManager.shared.profiles.sorted(by: { $0.profile.order < $1.profile.order }) {
                let title = descriptor.profile.name
                let item = NSMenuItem(title: title, action: #selector(applyProfileMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = descriptor
                if let hotkeyText = descriptor.profile.hotkey {
                    item.keyEquivalent = ""
                    item.toolTip = "Hotkey: \(hotkeyText)"
                }
                if ActiveProfileStore.shared.activeProfile?.directory == descriptor.directory {
                    item.state = .on
                    // Add a submenu with quick actions
                    let sub = NSMenu()
                    let reapply = NSMenuItem(title: "Reapply", action: #selector(reapplyActive), keyEquivalent: "")
                    reapply.target = self
                    sub.addItem(reapply)
                    let openFolder = NSMenuItem(title: "Open Profile Folder", action: #selector(openActiveProfileFolder), keyEquivalent: "")
                    openFolder.target = self
                    sub.addItem(openFolder)
                    let setWallpaper = NSMenuItem(title: "Set Wallpaper…", action: #selector(pickWallpaperForActive), keyEquivalent: "")
                    setWallpaper.target = self
                    sub.addItem(setWallpaper)
                    item.submenu = sub
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        // Section: Create new profiles
        let newEmpty = NSMenuItem(title: "Create Empty Profile…", action: #selector(promptCreateEmpty), keyEquivalent: "e")
        newEmpty.target = self
        menu.addItem(newEmpty)
        let snapshotItem = NSMenuItem(title: "Create Profile From Current…", action: #selector(promptCreateFromCurrent), keyEquivalent: "n")
        snapshotItem.target = self
        menu.addItem(snapshotItem)
        
        let reload = NSMenuItem(title: "Reload Profiles", action: #selector(reloadProfiles), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)
        let open = NSMenuItem(title: "Open Profiles Folder", action: #selector(openProfilesFolder), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit RiceBarMac", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func applyProfileMenu(_ sender: NSMenuItem) {
        guard let descriptor = sender.representedObject as? ProfileDescriptor else { return }
        // Immediate visual feedback while the menu is open
        if let items = statusItem.menu?.items {
            for item in items where item.action == #selector(applyProfileMenu(_:)) {
                item.state = (item === sender) ? .on : .off
            }
        }
        apply(descriptor)
    }

    private func apply(_ descriptor: ProfileDescriptor) {
        // Run apply in background to keep menu responsive, then refresh UI on main
        DispatchQueue.global(qos: .userInitiated).async {
            do { try ProfileApplier.shared.apply(descriptor: descriptor, cleanConfig: false) } catch {
                DispatchQueue.main.async { NSAlert(error: error).runModal() }
                return
            }
            // Small delay to avoid immediately undoing by watcher bounce
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.constructMenu() }
        }
    }

    @objc private func reloadProfiles() {
        ProfileManager.shared.reload()
        constructMenu()
        HotKeyManager.shared.registerHotKeys(profiles: ProfileManager.shared.profiles) { [weak self] descriptor in
            self?.apply(descriptor)
        }
        // watcher is persistent; it will trigger this reload when changes happen
    }

    @objc private func openProfilesFolder() {
        ProfileManager.shared.openProfilesFolder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func promptCopyCurrentProfile() {
        guard let current = ActiveProfileStore.shared.activeProfile else { return }
        let alert = NSAlert()
        alert.messageText = "Duplicate Profile"
        alert.informativeText = "Enter a name for the copied profile."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "New profile name"
        alert.accessoryView = input
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }
        let name = input.stringValue
        do {
            let newDesc = try ProfileManager.shared.copyProfile(current, to: name)
            ActiveProfileStore.shared.setActive(newDesc)
            reloadProfiles()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func promptCreateFromCurrent() {
        let alert = NSAlert()
        alert.messageText = "Create Profile From Current"
        alert.informativeText = "Enter a name for the new profile. Your current ~/.config will be captured into it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "New profile name"
        alert.accessoryView = input
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }
        let name = input.stringValue
        do {
            let newDesc = try ProfileManager.shared.createProfileFromCurrent(name: name)
            ActiveProfileStore.shared.setActive(newDesc)
            reloadProfiles()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func reapplyActive() {
        guard let active = ActiveProfileStore.shared.activeProfile else { return }
        apply(active)
    }

    @objc private func openActiveProfileFolder() {
        guard let dir = ActiveProfileStore.shared.activeProfile?.directory else { return }
        NSWorkspace.shared.open(dir)
    }

    @objc private func pickWallpaperForActive() {
        guard let active = ActiveProfileStore.shared.activeProfile else { return }
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                let updated = try ProfileManager.shared.updateWallpaper(for: active, from: url)
                ActiveProfileStore.shared.setActive(updated)
                try ProfileApplier.shared.apply(descriptor: updated, cleanConfig: false)
                self.constructMenu()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func promptCreateEmpty() {
        let alert = NSAlert()
        alert.messageText = "Create Empty Profile"
        alert.informativeText = "Enter a name for the new empty profile."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "New profile name"
        alert.accessoryView = input
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }
        let name = input.stringValue
        do {
            let newDesc = try ProfileManager.shared.createEmptyProfile(name: name)
            ActiveProfileStore.shared.setActive(newDesc)
            reloadProfiles()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private struct TitleMenuView: View {
    var activeName: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RiceBarMac")
                .font(.headline)
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

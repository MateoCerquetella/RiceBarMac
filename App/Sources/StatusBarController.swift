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
    }

    private func constructMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem()
        titleItem.view = NSHostingView(rootView: TitleMenuView())
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
                    item.keyEquivalent = "" // don't set here, global handled separately
                    item.toolTip = "Hotkey: \(hotkeyText)"
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
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
        apply(descriptor)
    }

    private func apply(_ descriptor: ProfileDescriptor) {
        Task { @MainActor in
            do {
                try ProfileApplier.shared.apply(descriptor: descriptor)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func reloadProfiles() {
        ProfileManager.shared.reload()
        constructMenu()
        HotKeyManager.shared.registerHotKeys(profiles: ProfileManager.shared.profiles) { [weak self] descriptor in
            self?.apply(descriptor)
        }
    }

    @objc private func openProfilesFolder() {
        ProfileManager.shared.openProfilesFolder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private struct TitleMenuView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RiceBarMac")
                .font(.headline)
            Text("Switch your desktop profiles")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}

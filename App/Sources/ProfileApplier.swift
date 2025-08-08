import Foundation
import AppKit

enum ProfileApplyError: Error { case fileNotFound(String) }

final class ProfileApplier {
    static let shared = ProfileApplier()

    private init() {}

    func apply(descriptor: ProfileDescriptor) throws {
        try apply(descriptor: descriptor, cleanConfig: false)
    }

    func apply(descriptor: ProfileDescriptor, cleanConfig: Bool) throws {
        if ApplyActivity.isApplying { return }
        ApplyActivity.begin()
        defer { ApplyActivity.end() }
        var actions: [ApplyAction] = []
        let profile = descriptor.profile
        // Mark active early so file watcher reacts to the correct directory
        ActiveProfileStore.shared.setActive(descriptor)
        if let wallpaperRel = profile.wallpaper {
            let url = descriptor.directory.appendingPathComponent(wallpaperRel)
            // Ensure wallpaper changes run on main thread (AppKit)
            DispatchQueue.main.sync {
                do { try self.applyWallpaper(url: url) } catch { }
            }
        }
        // Render templates into home/ first
        TemplateEngine.renderTemplates(for: descriptor)

        let targetHome = URL(fileURLWithPath: NSHomeDirectory())
        if cleanConfig {
            try backupAndCleanConfig(atHome: targetHome)
        }

        if let replacements = profile.replacements, !replacements.isEmpty {
            for repl in replacements {
                let src = descriptor.directory.appendingPathComponent(repl.source)
                let dst = URL(fileURLWithPath: (repl.destination as NSString).expandingTildeInPath)
                let action = try replaceFile(source: src, destination: dst)
                actions.append(action)
            }
        } else {
            let homeOverlay = descriptor.directory.appendingPathComponent("home", isDirectory: true)
            if FileManager.default.fileExists(atPath: homeOverlay.path) {
                let overlayActions = try overlayDirectory(from: homeOverlay, to: targetHome)
                actions.append(contentsOf: overlayActions)
            }
        }
        if let term = profile.terminal {
            // Avoid blocking the UI while reloading terminal config
            try applyTerminalConfig(term, base: descriptor.directory)
        }
        if let scriptRel = profile.startupScript {
            let scriptURL = descriptor.directory.appendingPathComponent(scriptRel)
            try runScript(scriptURL)
        }
        ApplyRecordStore.save(ApplyRecord(timestamp: Date(), actions: actions), to: descriptor.directory)
    }

    private func backupAndCleanConfig(atHome home: URL) throws {
        let fm = FileManager.default
        let configDir = home.appendingPathComponent(".config", isDirectory: true)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: configDir.path, isDirectory: &isDir), isDir.boolValue {
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = home.appendingPathComponent(".config.ricebar-backup-\(timestamp)", isDirectory: true)
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: configDir, to: backup)
        }
        // Recreate empty .config for overlay
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
    }


    func revertLastApply(for descriptor: ProfileDescriptor) throws {
        guard let record = ApplyRecordStore.load(from: descriptor.directory) else { return }
        let fm = FileManager.default
        for action in record.actions {
            let dest = URL(fileURLWithPath: action.destination)
            if let backup = action.backup.map({ URL(fileURLWithPath: $0) }), fm.fileExists(atPath: backup.path) {
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                try fm.moveItem(at: backup, to: dest)
            } else {
                try? fm.removeItem(at: dest)
            }
        }
    }

    func snapshotCurrent(to descriptor: ProfileDescriptor) throws {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let src = home.appendingPathComponent(".config", isDirectory: true)
        let dst = descriptor.directory.appendingPathComponent("home/.config", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
            try copyDirectoryRecursively(from: src, to: dst)
        }
        // You can add additional dotfiles/directories here if needed
    }

    private func copyDirectoryRecursively(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard let rawEnum = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        let enumerator = rawEnum as! FileManager.DirectoryEnumerator
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            let name = fileURL.lastPathComponent
            if shouldSkipInSnapshot(name: name) {
                if isDir.boolValue { enumerator.skipDescendants() }
                continue
            }
            let rel = fileURL.path.replacingOccurrences(of: src.path + "/", with: "")
            let target = dst.appendingPathComponent(rel)
            if isDir.boolValue {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try ensureParentDirectory(for: target)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: fileURL, to: target)
            }
        }
    }

    private func shouldSkipInSnapshot(name: String) -> Bool {
        if name == ".DS_Store" { return true }
        if name.hasSuffix(".bak") { return true }
        if name.hasPrefix("alacritty.ricebar-backup-") { return true }
        return false
    }

    private func applyWallpaper(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProfileApplyError.fileNotFound(url.path) }
        var lastError: Error?
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                lastError = error
            }
        }
        if lastError != nil {
            // Fallback via AppleScript to set all desktops
            let script = """
            tell application "System Events"
              tell every desktop
                set picture to "\(url.path)"
              end tell
            end tell
            """
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&errorDict)
            }
        }
    }

    @discardableResult
    private func replaceFile(source: URL, destination: URL) throws -> ApplyAction {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw ProfileApplyError.fileNotFound(source.path) }
        try ensureParentDirectory(for: destination)
        var backupPath: String? = nil
        var kind: ApplyAction.Kind = .created
        if fm.fileExists(atPath: destination.path) {
            // Skip heavy work if content is identical
            if fm.contentsEqual(atPath: source.path, andPath: destination.path) {
                return ApplyAction(kind: .updated, source: source.path, destination: destination.path, backup: nil)
            }
            let backup = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".bak")
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: destination, to: backup)
            backupPath = backup.path
            kind = .updated
        }
        try fm.copyItem(at: source, to: destination)
        touchIfNeededForReload(destination)
        return ApplyAction(kind: kind, source: source.path, destination: destination.path, backup: backupPath)
    }

    private func ensureParentDirectory(for url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func overlayDirectory(from sourceDir: URL, to targetDir: URL) throws -> [ApplyAction] {
        let fm = FileManager.default
        var actions: [ApplyAction] = []
        // IMPORTANT: do NOT skip hidden files; we need to copy `.config/**` and other dotfiles
        guard let rawEnum = fm.enumerator(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return actions }
        let enumerator = rawEnum as! FileManager.DirectoryEnumerator
        for case let fileURL as URL in enumerator {
            let relPath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
            let dstURL = targetDir.appendingPathComponent(relPath)
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            let name = fileURL.lastPathComponent
            if isDir.boolValue {
                if shouldSkipInSnapshot(name: name) {
                    enumerator.skipDescendants()
                    continue
                }
                autoreleasepool { try? fm.createDirectory(at: dstURL, withIntermediateDirectories: true) }
            } else {
                if shouldSkipInSnapshot(name: name) { continue }
                autoreleasepool {
                    if let action = try? replaceFile(source: fileURL, destination: dstURL) {
                        actions.append(action)
                    }
                }
            }
        }
        return actions
    }

    private func touchIfNeededForReload(_ destination: URL) {
        let path = destination.path
        guard path.contains("/.config/alacritty/") else { return }
        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path)
        // Nudge both common config filenames so Alacritty notices
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let ymlPath = home.appendingPathComponent(".config/alacritty/alacritty.yml").path
        let tomlPath = home.appendingPathComponent(".config/alacritty/alacritty.toml").path
        if FileManager.default.fileExists(atPath: ymlPath) {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: ymlPath)
        }
        if FileManager.default.fileExists(atPath: tomlPath) {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: tomlPath)
        }
        // Ask a running Alacritty to reload its config if available
        ReloadHelper.reloadAlacritty()
    }

    private func applyTerminalConfig(_ terminal: Profile.Terminal, base: URL) throws {
        switch terminal.kind {
        case .alacritty:
            let home = URL(fileURLWithPath: NSHomeDirectory())
            if let themeRel = terminal.theme {
                let src = base.appendingPathComponent(themeRel)
                let keptExt = try copyAlacrittyConfig(from: src, toHome: home)
                archiveAlternateAlacrittyConfig(keepExt: keptExt, home: home)
            } else if let auto = findDefaultAlacrittyTheme(in: base) {
                let keptExt = try copyAlacrittyConfig(from: auto, toHome: home)
                archiveAlternateAlacrittyConfig(keepExt: keptExt, home: home)
            }
        case .terminalApp:
            break
        case .iterm2:
            break
        }
    }

    private func findDefaultAlacrittyTheme(in base: URL) -> URL? {
        let fm = FileManager.default
        let candidates = [
            base.appendingPathComponent("alacritty.yml"),
            base.appendingPathComponent("alacritty.toml"),
            base.appendingPathComponent("alacritty/alacritty.yml"),
            base.appendingPathComponent("alacritty/alacritty.toml"),
        ]
        for url in candidates {
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    @discardableResult
    private func copyAlacrittyConfig(from src: URL, toHome home: URL) throws -> String {
        let ext = src.pathExtension.lowercased()
        let dstName = (ext == "toml") ? "alacritty.toml" : "alacritty.yml"
        let dst = home.appendingPathComponent(".config/alacritty/\(dstName)")
        _ = try replaceFile(source: src, destination: dst)
        return (ext == "toml") ? "toml" : "yml"
    }

    private func archiveAlternateAlacrittyConfig(keepExt: String, home: URL) {
        let fm = FileManager.default
        let dir = home.appendingPathComponent(".config/alacritty", isDirectory: true)
        let altName = (keepExt == "toml") ? "alacritty.yml" : "alacritty.toml"
        let alt = dir.appendingPathComponent(altName)
        guard fm.fileExists(atPath: alt.path) else { return }
        // Move to backups folder to avoid Alacritty loading the wrong file
        try? fm.createDirectory(at: ConfigAccess.backupsRoot, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = ConfigAccess.backupsRoot.appendingPathComponent("alacritty_\(altName).\(timestamp)")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: alt, to: backup)
    }

    private func runScript(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProfileApplyError.fileNotFound(url.path) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\"\(url.path)\""]
        try process.run()
    }
}

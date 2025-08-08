import Foundation
import AppKit

enum ProfileApplyError: Error { case fileNotFound(String) }

final class ProfileApplier {
    static let shared = ProfileApplier()

    private init() {}

    func apply(descriptor: ProfileDescriptor) throws {
        let profile = descriptor.profile
        if let wallpaperRel = profile.wallpaper {
            let url = descriptor.directory.appendingPathComponent(wallpaperRel)
            try applyWallpaper(url: url)
        }
        if let replacements = profile.replacements {
            for repl in replacements {
                let src = descriptor.directory.appendingPathComponent(repl.source)
                let dst = URL(fileURLWithPath: (repl.destination as NSString).expandingTildeInPath)
                try replaceFile(source: src, destination: dst)
            }
        }
        if let term = profile.terminal {
            try applyTerminalConfig(term, base: descriptor.directory)
        }
        if let scriptRel = profile.startupScript {
            let scriptURL = descriptor.directory.appendingPathComponent(scriptRel)
            try runScript(scriptURL)
        }
    }

    private func applyWallpaper(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProfileApplyError.fileNotFound(url.path) }
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    private func replaceFile(source: URL, destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw ProfileApplyError.fileNotFound(source.path) }
        let fm = FileManager.default
        let destDir = destination.deletingLastPathComponent()
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            let backup = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".bak")
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: destination, to: backup)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private func applyTerminalConfig(_ terminal: Profile.Terminal, base: URL) throws {
        switch terminal.kind {
        case .alacritty:
            guard let themeRel = terminal.theme else { return }
            let src = base.appendingPathComponent(themeRel)
            let dst = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/alacritty/alacritty.yml")
            try replaceFile(source: src, destination: dst)
        case .terminalApp:
            // TODO: Import .terminal theme via AppleScript if needed
            break
        case .iterm2:
            // TODO: Import .itermcolors via AppleScript if needed
            break
        }
    }

    private func runScript(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProfileApplyError.fileNotFound(url.path) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\"\(url.path)\""]
        try process.run()
    }
}

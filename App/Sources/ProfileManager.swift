import Foundation
import AppKit
#if canImport(Yams)
import Yams
#endif

final class ProfileManager {
    static let shared = ProfileManager()

    private(set) var profiles: [ProfileDescriptor] = []

    private init() {
        ensureProfilesRoot()
        reload()
    }

    func reload() {
        let root = profilesRoot()
        let fm = FileManager.default
        var loaded: [ProfileDescriptor] = []
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for url in items {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false else { continue }
                if let profile = loadProfile(at: url) {
                    loaded.append(ProfileDescriptor(profile: profile, directory: url))
                } else {
                    let defaults = defaultProfile(for: url)
                    loaded.append(ProfileDescriptor(profile: defaults, directory: url))
                }
            }
        }
        profiles = loaded
    }

    func openProfilesFolder() {
        NSWorkspace.shared.open(profilesRoot())
    }

    func copyProfile(_ descriptor: ProfileDescriptor, to newName: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !sanitized.isEmpty else { throw NSError(domain: "RiceBarMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid profile name"]) }
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw NSError(domain: "RiceBarMac", code: 2, userInfo: [NSLocalizedDescriptionKey: "A profile with this name already exists"]) }
        try fm.copyItem(at: descriptor.directory, to: dest)
        // Remove transient files in the copy
        let transient = [".ricebar-last-apply.json"]
        for name in transient {
            let p = dest.appendingPathComponent(name)
            try? fm.removeItem(at: p)
        }
        reload()
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return ProfileDescriptor(profile: defaultProfile(for: dest), directory: dest)
    }

    func createProfileFromCurrent(name: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !sanitized.isEmpty else { throw NSError(domain: "RiceBarMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid profile name"]) }
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw NSError(domain: "RiceBarMac", code: 2, userInfo: [NSLocalizedDescriptionKey: "A profile with this name already exists"]) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let descriptor = ProfileDescriptor(profile: Profile(name: sanitized), directory: dest)
        // Snapshot current ~/.config into home/.config
        try ProfileApplier.shared.snapshotCurrent(to: descriptor)
        // Save a minimal profile.json for clarity
        let jsonURL = dest.appendingPathComponent("profile.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(descriptor.profile) {
            try? data.write(to: jsonURL, options: .atomic)
        }
        reload()
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return descriptor
    }

    func createEmptyProfile(name: String) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !sanitized.isEmpty else { throw NSError(domain: "RiceBarMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid profile name"]) }
        let dest = profilesRoot().appendingPathComponent(sanitized, isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            throw NSError(domain: "RiceBarMac", code: 2, userInfo: [NSLocalizedDescriptionKey: "A profile with this name already exists"]) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        // Create empty home dir
        try fm.createDirectory(at: dest.appendingPathComponent("home", isDirectory: true), withIntermediateDirectories: true)
        // Save minimal profile.json
        let descriptor = ProfileDescriptor(profile: Profile(name: sanitized), directory: dest)
        let jsonURL = dest.appendingPathComponent("profile.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(descriptor.profile) {
            try? data.write(to: jsonURL, options: .atomic)
        }
        reload()
        if let newDesc = profiles.first(where: { $0.directory == dest }) {
            return newDesc
        }
        return descriptor
    }

    // MARK: - Save/Update Profile Metadata

    func saveProfile(_ profile: Profile, at directory: URL) throws {
        let jsonURL = directory.appendingPathComponent("profile.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(profile)
        try data.write(to: jsonURL, options: .atomic)
    }

    func updateWallpaper(for descriptor: ProfileDescriptor, from sourceURL: URL) throws -> ProfileDescriptor {
        let fm = FileManager.default
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let baseName = "wallpaper"
        var dest = descriptor.directory.appendingPathComponent("\(baseName).\(ext)")
        var idx = 2
        while fm.fileExists(atPath: dest.path) {
            dest = descriptor.directory.appendingPathComponent("\(baseName)-\(idx).\(ext)")
            idx += 1
        }
        try fm.copyItem(at: sourceURL, to: dest)
        var updated = descriptor.profile
        updated.wallpaper = dest.lastPathComponent
        try saveProfile(updated, at: descriptor.directory)
        reload()
        let newDesc = profiles.first(where: { $0.directory == descriptor.directory }) ?? ProfileDescriptor(profile: updated, directory: descriptor.directory)
        return newDesc
    }

    private func profilesRoot() -> URL {
        return ConfigAccess.defaultRoot
    }

    private func ensureProfilesRoot() {
        let root = profilesRoot()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func loadProfile(at directory: URL) -> Profile? {
        let candidates = ["profile.yml", "profile.yaml", "profile.json"]
        for name in candidates {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    if name.hasSuffix(".json") {
                        var p = try JSONDecoder().decode(Profile.self, from: data)
                        if p.wallpaper == nil, let auto = firstImage(in: directory) { p.wallpaper = auto.lastPathComponent }
                        if p.hotkey == nil, let hk = readHotkey(at: directory) { p.hotkey = hk }
                        return p
                    } else {
                        #if canImport(Yams)
                        let str = String(decoding: data, as: UTF8.self)
                        var p = try YAMLDecoder().decode(Profile.self, from: str)
                        if p.wallpaper == nil, let auto = firstImage(in: directory) { p.wallpaper = auto.lastPathComponent }
                        if p.hotkey == nil, let hk = readHotkey(at: directory) { p.hotkey = hk }
                        return p
                        #else
                        var p = try JSONDecoder().decode(Profile.self, from: data)
                        if p.wallpaper == nil, let auto = firstImage(in: directory) { p.wallpaper = auto.lastPathComponent }
                        if p.hotkey == nil, let hk = readHotkey(at: directory) { p.hotkey = hk }
                        return p
                        #endif
                    }
                } catch {
                    print("Failed to load profile at \(directory.lastPathComponent): \(error)")
                }
            }
        }
        return nil
    }

    private func defaultProfile(for directory: URL) -> Profile {
        var p = Profile(name: directory.lastPathComponent)
        if let hk = readHotkey(at: directory) { p.hotkey = hk }
        if let wp = firstImage(in: directory) { p.wallpaper = wp.lastPathComponent }
        return p
    }

    private func readHotkey(at directory: URL) -> String? {
        let url = directory.appendingPathComponent("hotkey.txt")
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstImage(in directory: URL) -> URL? {
        let fm = FileManager.default
        let exts = ["png", "jpg", "jpeg", "heic"]
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: []) else { return nil }
        // Prefer files named like wallpaper/background/bg first
        let preferredPrefixes = ["wallpaper", "background", "bg"]
        if let preferred = items.first(where: { url in
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return exts.contains(url.pathExtension.lowercased()) && preferredPrefixes.contains(where: { name.hasPrefix($0) })
        }) {
            return preferred
        }
        // Otherwise first image
        return items.first { exts.contains($0.pathExtension.lowercased()) }
    }
}

import Foundation
import AppKit
#if canImport(Yams)
import Yams
#endif

final class ProfileManager {
    static let shared = ProfileManager()

    private(set) var profiles: [ProfileDescriptor] = []

    private init() {
        reload()
    }

    func reload() {
        let root = profilesRoot()
        let fm = FileManager.default
        var loaded: [ProfileDescriptor] = []
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for url in items {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false else { continue }
                if let profile = loadProfile(at: url) {
                    loaded.append(ProfileDescriptor(profile: profile, directory: url))
                }
            }
        }
        profiles = loaded
    }

    func openProfilesFolder() {
        NSWorkspace.shared.open(profilesRoot())
    }

    private func profilesRoot() -> URL {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "devMode") {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/macRice", isDirectory: true)
        }
        #endif
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/macRice", isDirectory: true)
    }

    private func loadProfile(at directory: URL) -> Profile? {
        let candidates = ["profile.yml", "profile.yaml", "profile.json"]
        for name in candidates {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    if name.hasSuffix(".json") {
                        return try JSONDecoder().decode(Profile.self, from: data)
                    } else {
                        #if canImport(Yams)
                        let str = String(decoding: data, as: UTF8.self)
                        return try YAMLDecoder().decode(Profile.self, from: str)
                        #else
                        return try JSONDecoder().decode(Profile.self, from: data) // fallback if YAML unavailable
                        #endif
                    }
                } catch {
                    print("Failed to load profile at \(directory.lastPathComponent): \(error)")
                }
            }
        }
        return nil
    }
}

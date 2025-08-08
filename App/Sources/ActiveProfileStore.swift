import Foundation
#if canImport(Yams)
import Yams
#endif

final class ActiveProfileStore {
    static let shared = ActiveProfileStore()

    private let userDefaultsKey = "ActiveProfileDirectoryPath"
    private(set) var activeProfile: ProfileDescriptor?

    private init() {
        if let path = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                if let profile = ProfileManager.shared.profiles.first(where: { $0.directory == url }) {
                    activeProfile = profile
                } else if let loaded = try? Self.loadDescriptor(from: url) {
                    activeProfile = loaded
                }
            }
        }
    }

    func setActive(_ descriptor: ProfileDescriptor) {
        activeProfile = descriptor
        UserDefaults.standard.set(descriptor.directory.path, forKey: userDefaultsKey)
    }

    private static func loadDescriptor(from url: URL) throws -> ProfileDescriptor? {
        let fm = FileManager.default
        let jsonURL = url.appendingPathComponent("profile.json")
        let ymlURL = url.appendingPathComponent("profile.yml")
        let yamlURL = url.appendingPathComponent("profile.yaml")
        if fm.fileExists(atPath: jsonURL.path) {
            let data = try Data(contentsOf: jsonURL)
            let profile = try JSONDecoder().decode(Profile.self, from: data)
            return ProfileDescriptor(profile: profile, directory: url)
        }
        #if canImport(Yams)
        if fm.fileExists(atPath: ymlURL.path) || fm.fileExists(atPath: yamlURL.path) {
            let yurl = fm.fileExists(atPath: ymlURL.path) ? ymlURL : yamlURL
            let str = try String(contentsOf: yurl, encoding: .utf8)
            let profile = try YAMLDecoder().decode(Profile.self, from: str)
            return ProfileDescriptor(profile: profile, directory: url)
        }
        #endif
        // If there is no explicit profile file, fallback to defaults (name + inferred hotkey/wallpaper)
        var p = Profile(name: url.lastPathComponent)
        return ProfileDescriptor(profile: p, directory: url)
    }
}



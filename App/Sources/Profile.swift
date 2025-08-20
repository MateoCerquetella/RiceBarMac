import Foundation


enum ProfileValidationError: LocalizedError {
    case invalidProfileName
    case invalidHotkey
    case directoryNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidProfileName:
            return "Invalid profile name"
        case .invalidHotkey:
            return "Invalid hotkey format"
        case .directoryNotFound(let path):
            return "Profile directory not found: \(path)"
        }
    }
}

struct Profile: Codable, Equatable, Hashable {
    var name: String {
        didSet {
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/", with: "-")
        }
    }
    var order: Int = 0
    var hotkey: String? // e.g. ctrl+cmd+1

    var wallpaper: String? // relative path

    struct Terminal: Codable, Equatable, Hashable {
        enum Kind: String, Codable, Equatable, Hashable { case alacritty, terminalApp, iterm2 }
        var kind: Kind
        var theme: String? // relative path or theme name
    }
    var terminal: Terminal?
    
    struct IDE: Codable, Equatable, Hashable {
        enum Kind: String, Codable, Equatable, Hashable { case vscode, cursor }
        var kind: Kind
        var theme: String? // relative path to settings.json or theme name
        var extensions: [String]? // list of extension IDs to install
    }
    var ide: IDE?

    struct Replacement: Codable, Equatable, Hashable {
        var source: String // relative path within profile dir
        var destination: String // absolute path, supports ~ expansion
    }
    var replacements: [Replacement]? = []

    var startupScript: String? // relative path
    
    func validate() throws {
        guard !name.isEmpty else {
            throw ProfileValidationError.invalidProfileName
        }
        
        if let hotkey = hotkey {
            let parts = hotkey.lowercased().split(separator: "+")
            guard parts.count >= 2 else {
                throw ProfileValidationError.invalidHotkey
            }
        }
    }
    
    init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }
}

struct ProfileDescriptor: Hashable, Equatable {
    let profile: Profile
    let directory: URL
    
    var displayName: String {
        return profile.name.isEmpty ? directory.lastPathComponent : profile.name
    }
    
    var id: String {
        return directory.lastPathComponent
    }
    
    func validate() throws {
        try profile.validate()
        
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ProfileValidationError.directoryNotFound(directory.path)
        }
    }
}

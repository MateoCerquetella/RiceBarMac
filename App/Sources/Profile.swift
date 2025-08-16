import Foundation

// MARK: - Profile Validation Errors

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
            // Ensure profile names are filesystem-safe
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
    
    /// Validates the profile configuration
    func validate() throws {
        guard !name.isEmpty else {
            throw ProfileValidationError.invalidProfileName
        }
        
        // Validate hotkey format if provided
        if let hotkey = hotkey {
            let parts = hotkey.lowercased().split(separator: "+")
            guard parts.count >= 2 else {
                throw ProfileValidationError.invalidHotkey
            }
        }
    }
    
    /// Creates a profile with safe defaults
    init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
    }
}

struct ProfileDescriptor: Hashable, Equatable {
    let profile: Profile
    let directory: URL
    
    /// The display name for the profile
    var displayName: String {
        return profile.name.isEmpty ? directory.lastPathComponent : profile.name
    }
    
    /// The profile's unique identifier
    var id: String {
        return directory.lastPathComponent
    }
    
    /// Validates the profile descriptor
    func validate() throws {
        try profile.validate()
        
        // Ensure directory exists
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ProfileValidationError.directoryNotFound(directory.path)
        }
    }
}

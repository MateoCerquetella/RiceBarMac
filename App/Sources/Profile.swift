import Foundation

struct Profile: Codable, Equatable, Hashable {
    var name: String
    var order: Int = 0
    var hotkey: String? // e.g. ctrl+cmd+1

    var wallpaper: String? // relative path

    struct Terminal: Codable, Equatable, Hashable {
        enum Kind: String, Codable, Equatable, Hashable { case alacritty, terminalApp, iterm2 }
        var kind: Kind
        var theme: String? // relative path or theme name
    }
    var terminal: Terminal?

    struct Replacement: Codable, Equatable, Hashable {
        var source: String // relative path within profile dir
        var destination: String // absolute path, supports ~ expansion
    }
    var replacements: [Replacement]? = []

    var startupScript: String? // relative path
}

struct ProfileDescriptor: Hashable, Equatable {
    let profile: Profile
    let directory: URL
}

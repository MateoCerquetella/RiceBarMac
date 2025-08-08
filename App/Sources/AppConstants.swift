import Foundation

/// Centralized constants and shared values used across the app.
enum AppConstants {
    static let profileFileCandidates: [String] = [
        "profile.yml",
        "profile.yaml",
        "profile.json",
    ]

    static let wallpaperExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
    static let preferredWallpaperPrefixes: [String] = ["wallpaper", "background", "bg"]

    static let alacrittyDirRelative = ".config/alacritty"
    static let alacrittyYml = "alacritty.yml"
    static let alacrittyToml = "alacritty.toml"
}



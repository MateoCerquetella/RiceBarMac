import Foundation

enum ConfigAccess {
    static let defaultRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".ricebar", isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)

    static let backupsRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".ricebar", isDirectory: true)
        .appendingPathComponent("backups", isDirectory: true)

    static let cacheRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".ricebar", isDirectory: true)
        .appendingPathComponent("cache", isDirectory: true)
}

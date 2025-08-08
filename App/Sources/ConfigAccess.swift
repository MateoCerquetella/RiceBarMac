import Foundation

enum ConfigAccess {
    static let defaultRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/macRice", isDirectory: true)
}

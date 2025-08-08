import Foundation

enum ApplyActivity {
    private static var applyingCount: Int = 0
    private static var lastEnd: Date?

    static var isApplying: Bool { applyingCount > 0 }

    static func begin() {
        applyingCount += 1
    }

    static func end() {
        applyingCount = max(0, applyingCount - 1)
        lastEnd = Date()
    }

    static func recentlyApplied(within seconds: TimeInterval = 1.0) -> Bool {
        guard let t = lastEnd else { return false }
        return Date().timeIntervalSince(t) < seconds
    }
}



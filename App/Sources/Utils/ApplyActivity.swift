import Foundation

enum ApplyActivity {
    private static let queue = DispatchQueue(label: "com.ricebar.apply-activity", qos: .userInitiated)
    private static var applyingCount: Int = 0
    private static var lastEnd: Date?

    static var isApplying: Bool { 
        return queue.sync { applyingCount > 0 }
    }

    static func begin() {
        queue.sync {
            applyingCount += 1
        }
    }

    static func end() {
        queue.sync {
            applyingCount = max(0, applyingCount - 1)
            lastEnd = Date()
        }
    }

    static func recentlyApplied(within seconds: TimeInterval = 1.0) -> Bool {
        return queue.sync {
            guard let t = lastEnd else { return false }
            return Date().timeIntervalSince(t) < seconds
        }
    }
}



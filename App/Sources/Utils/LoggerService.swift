import Foundation
import OSLog

/// Lightweight logger wrapper to centralize app logging.
enum LoggerService {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ricebar.RiceBarMac"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
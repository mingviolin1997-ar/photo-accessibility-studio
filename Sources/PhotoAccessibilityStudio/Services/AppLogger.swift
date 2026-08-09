import Foundation
import os

final class AppLogger {
    static let shared = AppLogger()
    private let logger = Logger(subsystem: "com.mingkong.PhotoAccessibilityStudio", category: "app")

    func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

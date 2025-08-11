import Foundation
import OSLog

/// Central logging gate to suppress verbose/noisy logs in production.
/// Toggle at runtime via UserDefaults key "App.VerboseLogs" (Bool).
/// Defaults to false. Enable temporarily by running:
///   defaults write com.example.Web App.VerboseLogs -bool YES
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.Web"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    static var isVerboseEnabled: Bool {
        UserDefaults.standard.bool(forKey: "App.VerboseLogs")
    }

    static func debug(_ message: String) {
        guard isVerboseEnabled else { return }
        logger.debug("\(message)")
    }

    static func info(_ message: String) {
        guard isVerboseEnabled else { return }
        logger.info("\(message)")
    }

    static func warn(_ message: String) {
        logger.warning("\(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message)")
    }
}



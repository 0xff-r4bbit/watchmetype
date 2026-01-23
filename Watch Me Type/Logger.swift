import Foundation
import os.log

/// Log severity levels for the application
enum LogLevel: Int, Comparable {
    case none = 0      // No logging
    case error = 1     // Errors only
    case warning = 2   // Warnings and errors
    case info = 3      // Info, warnings, and errors
    case debug = 4     // Debug output (development)
    case verbose = 5   // Extremely detailed (character-by-character)

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Centralized logging system with configurable log levels
/// Uses os_log for proper system integration on macOS
final class AppLogger {
    static let shared = AppLogger()

    /// Current log level - DEBUG builds default to .debug, RELEASE builds to .error
    #if DEBUG
    var currentLevel: LogLevel = .debug
    #else
    var currentLevel: LogLevel = .error
    #endif

    private let osLog: OSLog

    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.watchmetype"
        osLog = OSLog(subsystem: subsystem, category: "App")
    }

    /// Main logging function with automatic file/line/function capture
    func log(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level <= currentLevel else { return }

        let filename = (file as NSString).lastPathComponent
        let logMessage = "[\(filename):\(line)] \(message())"

        switch level {
        case .error:
            os_log(.error, log: osLog, "%{public}@", logMessage)
        case .warning:
            os_log(.info, log: osLog, "%{public}@", logMessage)
        case .info, .debug, .verbose:
            os_log(.debug, log: osLog, "%{public}@", logMessage)
        case .none:
            break
        }
    }

    // MARK: - Convenience Methods

    func error(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .error, file: file, function: function, line: line)
    }

    func warning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .warning, file: file, function: function, line: line)
    }

    func info(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .info, file: file, function: function, line: line)
    }

    func debug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .debug, file: file, function: function, line: line)
    }

    func verbose(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message(), level: .verbose, file: file, function: function, line: line)
    }
}

// MARK: - Global Convenience Function

/// Global logging function for easy access throughout the app
/// Usage: appLog("Message here", level: .debug)
func appLog(_ message: @autoclosure () -> String, level: LogLevel = .debug, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.log(message(), level: level, file: file, function: function, line: line)
}

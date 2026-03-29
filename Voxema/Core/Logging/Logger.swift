import os

/// Structured logging for Voxema.
///
/// ## Privacy contract
/// The `message` parameter is `StaticString` to enforce that log templates are
/// compile-time constants. Callers cannot construct dynamic strings containing
/// transcript text, speaker names, or other meeting content and pass them as the
/// message argument — the compiler rejects any non-literal expression.
///
/// The optional `context` parameter accepts structural metadata only:
/// stage names, model names, status codes, counts. Never meeting content.
///
/// ## Usage
/// ```swift
/// let log = VoxemaLogger.make(category: "capture")
/// log.info("recording started")
/// log.error("permission denied", "permission=screen-recording")
/// ```
public struct VoxemaLogger: Sendable {

    private static let subsystem = "com.voxema.app"
    private let logger: os.Logger

    private init(category: String) {
        self.logger = os.Logger(subsystem: Self.subsystem, category: category)
    }

    /// Returns a configured logger for the given functional category.
    public static func make(category: String) -> VoxemaLogger {
        VoxemaLogger(category: category)
    }

    public func debug(_ message: StaticString, _ context: String = "") {
        if context.isEmpty {
            logger.debug("\(message.description, privacy: .public)")
        } else {
            logger.debug("\(message.description, privacy: .public) | \(context, privacy: .public)")
        }
    }

    public func info(_ message: StaticString, _ context: String = "") {
        if context.isEmpty {
            logger.info("\(message.description, privacy: .public)")
        } else {
            logger.info("\(message.description, privacy: .public) | \(context, privacy: .public)")
        }
    }

    public func warning(_ message: StaticString, _ context: String = "") {
        if context.isEmpty {
            logger.warning("\(message.description, privacy: .public)")
        } else {
            logger.warning("\(message.description, privacy: .public) | \(context, privacy: .public)")
        }
    }

    public func error(_ message: StaticString, _ context: String = "") {
        if context.isEmpty {
            logger.error("\(message.description, privacy: .public)")
        } else {
            logger.error("\(message.description, privacy: .public) | \(context, privacy: .public)")
        }
    }
}

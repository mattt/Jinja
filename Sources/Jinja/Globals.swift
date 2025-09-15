import Foundation

struct Exception: Error {
    var message: String?
}

/// Built-in global functions available in the Jinja environment.
public enum Globals: Sendable {
    public static let builtIn: [String: Value] = [
        "raise_exception": .function(raiseException)
    ]

    /// Raises an exception with an optional custom message.
    ///
    /// This is useful for debugging templates or enforcing constraints.
    ///
    /// - Parameters:
    ///   - args: Function arguments. First argument should be the error message (optional).
    ///   - kwargs: Keyword arguments (unused).
    ///   - env: The current environment.
    /// - Throws: JinjaError.runtime with the provided message or a default message.
    /// - Returns: Never returns a value as it always throws.
    @discardableResult
    public static func raiseException(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        let arguments = try resolveCallArguments(
            args: args,
            kwargs: kwargs,
            parameters: ["message"],
            defaults: ["message": .null]
        )

        if case let .string(message)? = arguments["message"] {
            throw Exception(message: message)
        } else {
            throw Exception()
        }
    }
}

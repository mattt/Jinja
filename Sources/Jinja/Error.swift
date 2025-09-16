/// Error during tokenization of template source.
public struct TokenizationError: Error, Sendable {
    public let message: String
    public let position: Int?

    public init(_ message: String, at position: Int? = nil) {
        self.message = message
        self.position = position
    }
}

/// Error during parsing of tokens into AST.
public struct ParseError: Error, Sendable {
    public let message: String
    public let expectedTokens: Set<String>?
    public let actualToken: String?

    public init(_ message: String, expected: Set<String>? = nil, actual: String? = nil) {
        self.message = message
        self.expectedTokens = expected
        self.actualToken = actual
    }
}

/// Error during template execution or evaluation.
public struct RuntimeError: Error, Sendable {
    public let message: String
    public let context: String?

    public init(_ message: String, context: String? = nil) {
        self.message = message
        self.context = context
    }
}

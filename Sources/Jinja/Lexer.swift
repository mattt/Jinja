import Foundation

// MARK: - Token

/// A lexical token produced by parsing Jinja template source code.
public struct Token: Sendable, Hashable {
    /// The specific type of token representing different syntactic elements.
    public enum Kind: Sendable, Hashable, CaseIterable {
        /// Plain text content outside of Jinja template constructs.
        case text
        /// Expression content within `{{ }}` delimiters.
        case expression
        /// Statement content within `{% %}` delimiters.
        case statement
        /// String literal value enclosed in quotes.
        case string
        /// Numeric literal value.
        case number
        /// Boolean literal (`true` or `false`).
        case boolean
        /// Null literal value.
        case null
        /// Variable or function identifier.
        case identifier
        /// Opening parenthesis `(`.
        case openParen
        /// Closing parenthesis `)`.
        case closeParen
        /// Opening square bracket `[`.
        case openBracket
        /// Closing square bracket `]`.
        case closeBracket
        /// Opening curly brace `{`.
        case openBrace
        /// Closing curly brace `}`.
        case closeBrace
        /// Comma separator `,`.
        case comma
        /// Dot accessor `.`.
        case dot
        /// Colon separator `:`.
        case colon
        /// Pipe operator `|` for filters.
        case pipe
        /// Assignment operator `=`.
        case equals
        /// Addition operator `+`.
        case plus
        /// Subtraction operator `-`.
        case minus
        /// Multiplication operator `*`.
        case multiply
        /// Division operator `/`.
        case divide
        /// Modulo operator `%`.
        case modulo
        /// String concatenation operator `~`.
        case concat
        /// Equality comparison operator `==`.
        case equal
        /// Inequality comparison operator `!=`.
        case notEqual
        /// Less than comparison operator `<`.
        case less
        /// Less than or equal comparison operator `<=`.
        case lessEqual
        /// Greater than comparison operator `>`.
        case greater
        /// Greater than or equal comparison operator `>=`.
        case greaterEqual
        /// Logical AND operator `and`.
        case and
        /// Logical OR operator `or`.
        case or
        /// Logical NOT operator `not`.
        case not
        /// Membership test operator `in`.
        case `in`
        /// Negative membership test operator `not in`.
        case notIn
        /// Identity test operator `is`.
        case `is`
        /// Conditional statement keyword `if`.
        case `if`
        /// Alternative conditional keyword `else`.
        case `else`
        /// Chained conditional keyword `elif`.
        case elif
        /// End of conditional block keyword `endif`.
        case endif
        /// Loop statement keyword `for`.
        case `for`
        /// End of loop block keyword `endfor`.
        case endfor
        /// Variable assignment keyword `set`.
        case set
        /// Macro definition keyword `macro`.
        case macro
        /// End of macro block keyword `endmacro`.
        case endmacro
        /// End of file marker.
        case eof
    }

    /// The classification of this token.
    public let kind: Kind

    /// The raw text content of this token from the source.
    public let value: String

    /// The character position of this token in the original source text.
    public let position: Int
}

// MARK: - Lexer

/// Tokenizes Jinja template source code into a sequence of tokens.
public enum Lexer: Sendable {
    private static let keywords: [String: Token.Kind] = [
        "if": .`if`, "else": .`else`, "elif": .elif, "endif": .endif,
        "for": .`for`, "endfor": .endfor, "in": .`in`, "not": .not,
        "and": .and, "or": .or, "is": .`is`, "set": .set,
        "macro": .macro, "endmacro": .endmacro,
        "true": .boolean, "false": .boolean, "none": .null,
    ]

    private static let operators: [String: Token.Kind] = [
        "+": .plus, "-": .minus, "*": .multiply, "/": .divide, "%": .modulo, "~": .concat,
        "==": .equal, "!=": .notEqual, "<": .less, "<=": .lessEqual,
        ">": .greater, ">=": .greaterEqual, "=": .equals, "|": .pipe,
    ]

    /// Tokenizes a template source string into an array of tokens.
    public static func tokenize(_ source: String) throws -> [Token] {
        let preprocessed = preprocess(source)

        // Rough estimate for better array allocation
        let estimatedCapacity = preprocessed.count / 4

        // Use UTF-8 view for efficient scanning
        return try preprocessed.utf8.withContiguousStorageIfAvailable { buffer in
            try tokenize(
                from: buffer,
                count: buffer.count,
                estimatedCapacity: estimatedCapacity,
                tokenExtractor: extractTokenFromBuffer
            )
        }
            ?? {
                let utf8Array = Array(preprocessed.utf8)
                return try utf8Array.withUnsafeBufferPointer { buffer in
                    try tokenize(
                        from: buffer,
                        count: buffer.count,
                        estimatedCapacity: estimatedCapacity,
                        tokenExtractor: extractTokenFromBuffer
                    )
                }
            }()
    }

    private static func tokenize<S>(
        from source: S,
        count: Int,
        estimatedCapacity: Int,
        tokenExtractor: (S, Int) throws -> (Token, Int)
    ) throws -> [Token] {
        var tokens: [Token] = []
        tokens.reserveCapacity(estimatedCapacity)

        var position = 0
        while position < count {
            let (token, newPosition) = try tokenExtractor(source, position)
            tokens.append(token)
            position = newPosition

            if token.kind == .eof {
                break
            }
        }

        // Always add EOF token if not already present
        if tokens.isEmpty || tokens.last?.kind != .eof {
            tokens.append(Token(kind: .eof, value: "", position: position))
        }

        return tokens
    }

    private static func preprocess(_ template: String) -> String {
        // Optimized preprocessing with single pass
        var result = template

        // Remove comments efficiently
        result = result.replacing(#/{#.*?#}/#, with: "")

        // Handle whitespace control
        result = result.replacing(#/-%}\s*/#, with: "%}")
        result = result.replacing(#/\s*{%-/#, with: "{%")
        result = result.replacing(#/-}}\s*/#, with: "}}")
        result = result.replacing(#/\s*{{-/#, with: "{{")

        return result
    }

    private static func extractTokenFromBuffer(
        _ buffer: UnsafeBufferPointer<UInt8>, at position: Int
    ) throws -> (
        Token, Int
    ) {
        guard position < buffer.count else {
            return (Token(kind: .eof, value: "", position: position), position)
        }

        let char = buffer[position]

        // Template delimiters - check for {{ and {%
        if char == 0x7B && position + 1 < buffer.count {  // '{'
            let nextChar = buffer[position + 1]
            if nextChar == 0x7B {  // '{' -> "{{"
                return try extractExpressionTokenFromBuffer(buffer, at: position)
            } else if nextChar == 0x25 {  // '%' -> "{%"
                return try extractStatementTokenFromBuffer(buffer, at: position)
            }
        }

        // Text content - scan until template delimiter
        if char != 0x7B {  // not '{'
            return extractTextTokenFromBuffer(buffer, at: position)
        }

        // Single character tokens
        switch char {
        case 0x28: return (Token(kind: .openParen, value: "(", position: position), position + 1)  // '('
        case 0x29: return (Token(kind: .closeParen, value: ")", position: position), position + 1)  // ')'
        case 0x5B:
            return (Token(kind: .openBracket, value: "[", position: position), position + 1)  // '['
        case 0x5D:
            return (Token(kind: .closeBracket, value: "]", position: position), position + 1)  // ']'
        case 0x7B: return (Token(kind: .openBrace, value: "{", position: position), position + 1)  // '{'
        case 0x7D: return (Token(kind: .closeBrace, value: "}", position: position), position + 1)  // '}'
        case 0x2C: return (Token(kind: .comma, value: ",", position: position), position + 1)  // ','
        case 0x2E: return (Token(kind: .dot, value: ".", position: position), position + 1)  // '.'
        case 0x3A: return (Token(kind: .colon, value: ":", position: position), position + 1)  // ':'
        case 0x7C: return (Token(kind: .pipe, value: "|", position: position), position + 1)  // '|'
        default: break
        }

        // Multi-character operators
        for length in [2, 1] {
            if position + length <= buffer.count {
                let opBytes = buffer[position..<position + length]
                let op = String(decoding: opBytes, as: UTF8.self)
                if let tokenKind = operators[op] {
                    return (
                        Token(kind: tokenKind, value: op, position: position), position + length
                    )
                }
            }
        }

        // String literals
        if char == 0x27 || char == 0x22 {  // "'" or '"'
            return try extractStringTokenFromBuffer(buffer, at: position, delimiter: char)
        }

        // Numbers
        if char >= 0x30 && char <= 0x39 {  // '0'-'9'
            return extractNumberTokenFromBuffer(buffer, at: position)
        }

        // Identifiers and keywords
        if (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A) || char == 0x5F {  // A-Z, a-z, _
            return extractIdentifierTokenFromBuffer(buffer, at: position)
        }

        throw JinjaError.lexer(
            "Unexpected character '\(String(decoding: [char], as: UTF8.self))' at position \(position)"
        )
    }

    private static func extractExpressionTokenFromBuffer(
        _ buffer: UnsafeBufferPointer<UInt8>, at position: Int
    ) throws
        -> (
            Token, Int
        )
    {
        // Find closing "}}" while respecting string literals
        var pos = position + 2
        var inString = false
        var stringChar: UInt8 = 0

        while pos < buffer.count - 1 {
            let char = buffer[pos]

            // Handle string literals
            if !inString && (char == 0x27 || char == 0x22) {  // ' or "
                inString = true
                stringChar = char
            } else if inString && char == stringChar {
                // Check for escaped quotes
                if pos > 0 && buffer[pos - 1] == 0x5C {  // backslash
                    // This is an escaped quote, continue
                } else {
                    inString = false
                }
            } else if !inString && char == 0x7D && buffer[pos + 1] == 0x7D {  // "}}"
                let contentBytes = buffer[(position + 2)..<pos]
                let content = String(decoding: contentBytes, as: UTF8.self).trimmingCharacters(
                    in: .whitespaces)
                return (Token(kind: .expression, value: content, position: position), pos + 2)
            }

            pos += 1
        }

        throw JinjaError.lexer("Unclosed expression at position \(position)")
    }

    private static func extractStatementTokenFromBuffer(
        _ buffer: UnsafeBufferPointer<UInt8>, at position: Int
    ) throws
        -> (
            Token, Int
        )
    {
        // Find closing "%}" while respecting string literals
        var pos = position + 2
        var inString = false
        var stringChar: UInt8 = 0

        while pos < buffer.count - 1 {
            let char = buffer[pos]

            // Handle string literals
            if !inString && (char == 0x27 || char == 0x22) {  // ' or "
                inString = true
                stringChar = char
            } else if inString && char == stringChar {
                // Check for escaped quotes
                if pos > 0 && buffer[pos - 1] == 0x5C {  // backslash
                    // This is an escaped quote, continue
                } else {
                    inString = false
                }
            } else if !inString && char == 0x25 && buffer[pos + 1] == 0x7D {  // "%}"
                let contentBytes = buffer[(position + 2)..<pos]
                let content = String(decoding: contentBytes, as: UTF8.self).trimmingCharacters(
                    in: .whitespaces)
                return (Token(kind: .statement, value: content, position: position), pos + 2)
            }

            pos += 1
        }

        throw JinjaError.lexer("Unclosed statement at position \(position)")
    }

    private static func extractTextTokenFromBuffer(
        _ buffer: UnsafeBufferPointer<UInt8>, at position: Int
    ) -> (
        Token, Int
    ) {
        var pos = position

        while pos < buffer.count {
            if pos < buffer.count - 1 && buffer[pos] == 0x7B
                && (buffer[pos + 1] == 0x7B || buffer[pos + 1] == 0x25)
            {
                break
            }
            pos += 1
        }

        let valueBytes = buffer[position..<pos]
        let value = String(decoding: valueBytes, as: UTF8.self)
        return (Token(kind: .text, value: value, position: position), pos)
    }

    private static func extractStringTokenFromBuffer(
        _ buffer: UnsafeBufferPointer<UInt8>, at position: Int, delimiter: UInt8
    ) throws -> (Token, Int) {
        var pos = position + 1
        var value = ""

        while pos < buffer.count {
            let char = buffer[pos]

            if char == delimiter {
                return (Token(kind: .string, value: value, position: position), pos + 1)
            }

            if char == 0x5C && pos + 1 < buffer.count {  // '\'
                pos += 1
                let escaped = buffer[pos]
                switch escaped {
                case 0x6E: value += "\n"  // 'n'
                case 0x74: value += "\t"  // 't'
                case 0x72: value += "\r"  // 'r'
                case 0x5C: value += "\\"  // '\'
                case 0x22: value += "\""  // '"'
                case 0x27: value += "'"  // "'"
                default: value += String(decoding: [escaped], as: UTF8.self)
                }
            } else {
                value += String(decoding: [char], as: UTF8.self)
            }

            pos += 1
        }

        throw JinjaError.lexer("Unclosed string at position \(position)")
    }

    private static func extractNumberTokenFromBuffer(
        _ buffer: UnsafeBufferPointer<UInt8>, at position: Int
    ) -> (Token, Int) {
        var pos = position
        var hasDot = false

        while pos < buffer.count {
            let char = buffer[pos]
            if char >= 0x30 && char <= 0x39 {  // '0'-'9'
                pos += 1
            } else if char == 0x2E && !hasDot {  // '.'
                hasDot = true
                pos += 1
            } else {
                break
            }
        }

        let valueBytes = buffer[position..<pos]
        let value = String(decoding: valueBytes, as: UTF8.self)
        return (Token(kind: .number, value: value, position: position), pos)
    }

    private static func extractIdentifierTokenFromBuffer(
        _ buffer: UnsafeBufferPointer<UInt8>, at position: Int
    ) -> (Token, Int) {
        var pos = position

        while pos < buffer.count {
            let char = buffer[pos]
            if (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A)
                || (char >= 0x30 && char <= 0x39) || char == 0x5F
            {  // A-Z, a-z, 0-9, _
                pos += 1
            } else {
                break
            }
        }

        let valueBytes = buffer[position..<pos]
        let value = String(decoding: valueBytes, as: UTF8.self)
        let tokenKind = keywords[value] ?? .identifier
        return (Token(kind: tokenKind, value: value, position: position), pos)
    }

}

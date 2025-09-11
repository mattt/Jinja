import Foundation

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
        // Find closing "}}"
        var pos = position + 2

        while pos < buffer.count - 1 {
            if buffer[pos] == 0x7D && buffer[pos + 1] == 0x7D {  // "}}"
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
        // Find closing "%}"
        var pos = position + 2

        while pos < buffer.count - 1 {
            if buffer[pos] == 0x25 && buffer[pos + 1] == 0x7D {  // "%}"
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

// MARK: -

private func isWhitespace(_ byte: UInt8) -> Bool {
    // ASCII whitespace: space, tab, newline, carriage return, form feed, vertical tab
    return byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
        || byte == 0x0B
}

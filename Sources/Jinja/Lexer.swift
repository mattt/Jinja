/// Tokenizes Jinja template source code into a sequence of tokens.
public enum Lexer: Sendable {
    private static let keywords: [String: Token.Kind] = [
        "if": .`if`, "else": .`else`, "elif": .elif, "endif": .endif,
        "for": .`for`, "endfor": .endfor, "in": .`in`, "not": .not,
        "and": .and, "or": .or, "is": .`is`, "set": .set, "endset": .endset,
        "macro": .macro, "endmacro": .endmacro,
        "true": .boolean, "false": .boolean,
        "null": .null, "none": .null,
        "break": .`break`, "continue": .`continue`,
        "call": .call, "endcall": .endcall,
        "filter": .filter, "endfilter": .endfilter,

        // Python-compatible keywords
        "True": .boolean, "False": .boolean, "None": .null,
    ]

    private static let operators: [String: Token.Kind] = [
        "+": .plus, "-": .minus, "*": .multiply, "/": .divide,
        "//": .floorDivide, "**": .power,
        "%": .modulo, "~": .concat,
        "==": .equal, "!=": .notEqual, "<": .less, "<=": .lessEqual,
        ">": .greater, ">=": .greaterEqual, "=": .equals, "|": .pipe,
    ]

    /// Tokenizes a template source string into an array of tokens.
    ///
    /// - Parameter source: The Jinja template source code to tokenize
    /// - Returns: An array of tokens representing the lexical structure
    /// - Throws: `JinjaError.lexer` if the source contains invalid syntax
    public static func tokenize(_ source: String) throws
        -> [Token]
    {
        var tokens: [Token] = []
        tokens.reserveCapacity(source.count / 4)

        var position = source.startIndex
        var inTag = false
        var curlyBracketDepth = 0
        var stripNextWhitespace = false

        while position < source.endIndex {
            if inTag {
                position = skipWhitespace(in: source, at: position)
                if position >= source.endIndex {
                    break
                }
            }

            let (token, newPosition, shouldStripWhitespace) = try extractToken(
                from: source, at: position, inTag: inTag, curlyBracketDepth: curlyBracketDepth,
                stripNextWhitespace: stripNextWhitespace
            )

            switch token.kind {
            case .openExpression, .openStatement:
                inTag = true
                curlyBracketDepth = 0
            case .closeExpression, .closeStatement:
                inTag = false
                stripNextWhitespace = shouldStripWhitespace
            case .openBrace:
                curlyBracketDepth += 1
            case .closeBrace:
                curlyBracketDepth -= 1
            default:
                break
            }

            if token.kind == .text, token.value.isEmpty {
                position = newPosition
                continue
            }

            tokens.append(token)
            position = newPosition

            if token.kind == .eof {
                break
            }
        }

        if tokens.isEmpty || tokens.last?.kind != .eof {
            let charPosition = source.distance(from: source.startIndex, to: position)
            tokens.append(Token(kind: .eof, value: "", position: charPosition))
        }

        return tokens
    }

    private static func skipWhitespace(
        in source: String, at position: String.Index
    ) -> String.Index {
        var pos = position
        while pos < source.endIndex {
            let char = source[pos]
            if char.isWhitespace {
                pos = source.index(after: pos)
            } else {
                break
            }
        }
        return pos
    }

    private static func extractToken(
        from source: String,
        at position: String.Index,
        inTag: Bool,
        curlyBracketDepth: Int = 0,
        stripNextWhitespace: Bool = false
    ) throws -> (Token, String.Index, Bool) {
        guard position < source.endIndex else {
            let charPosition = source.distance(from: source.startIndex, to: position)
            return (Token(kind: .eof, value: "", position: charPosition), position, false)
        }

        let char = source[position]
        let charPosition = source.distance(from: source.startIndex, to: position)

        // Template delimiters - check for {{-, {{, {%-, {%, and {#
        if char == "{" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex {
                let nextChar = source[nextIndex]
                if nextChar == "{" {  // "{{" or "{{-"
                    let endIndex = source.index(after: nextIndex)

                    // Check if there's a following "-" for whitespace stripping
                    var hasStripLeft = false
                    var finalEndIndex = endIndex
                    if endIndex < source.endIndex && source[endIndex] == "-" {
                        hasStripLeft = true
                        finalEndIndex = source.index(after: endIndex)
                    }

                    return (
                        Token(kind: .openExpression, value: "{{", position: charPosition),
                        finalEndIndex,
                        hasStripLeft
                    )
                } else if nextChar == "%" {  // "{%" or "{%-"
                    let endIndex = source.index(after: nextIndex)

                    // Check if there's a following "-" for whitespace stripping
                    var hasStripLeft = false
                    var finalEndIndex = endIndex
                    if endIndex < source.endIndex && source[endIndex] == "-" {
                        hasStripLeft = true
                        finalEndIndex = source.index(after: endIndex)
                    }

                    return (
                        Token(kind: .openStatement, value: "{%", position: charPosition),
                        finalEndIndex,
                        hasStripLeft
                    )
                } else if nextChar == "#" {  // "{#"
                    let (token, newPos) = try extractCommentToken(from: source, at: position)
                    return (token, newPos, false)
                }
            }
        }

        // Check for closing delimiters with whitespace stripping
        if char == "-" && inTag {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex {
                let nextChar = source[nextIndex]
                if nextChar == "}" {
                    let afterNext = source.index(after: nextIndex)
                    if afterNext < source.endIndex && source[afterNext] == "}"
                        && curlyBracketDepth == 0
                    {
                        // "-}}" - expression close with right strip
                        let endIndex = source.index(after: afterNext)
                        return (
                            Token(kind: .closeExpression, value: "}}", position: charPosition),
                            endIndex,
                            true
                        )
                    }
                } else if nextChar == "%" {
                    let afterNext = source.index(after: nextIndex)
                    if afterNext < source.endIndex && source[afterNext] == "}" {
                        // "-%}" - statement close with right strip
                        let endIndex = source.index(after: afterNext)
                        return (
                            Token(kind: .closeStatement, value: "%}", position: charPosition),
                            endIndex,
                            true
                        )
                    }
                }
            }
        }

        if char == "}" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex && source[nextIndex] == "}" && curlyBracketDepth == 0 {
                let endIndex = source.index(after: nextIndex)
                return (
                    Token(kind: .closeExpression, value: "}}", position: charPosition),
                    endIndex,
                    false
                )
            }
        }
        if char == "%" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex && source[nextIndex] == "}" {
                let endIndex = source.index(after: nextIndex)
                return (
                    Token(kind: .closeStatement, value: "%}", position: charPosition),
                    endIndex,
                    false
                )
            }
        }

        if !inTag {
            let (token, newPos) = extractTextToken(
                from: source, at: position, stripLeadingWhitespace: stripNextWhitespace)
            return (token, newPos, false)
        }

        // Single character tokens
        let nextIndex = source.index(after: position)
        switch char {
        case "(":
            return (
                Token(
                    kind: .openParen, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case ")":
            return (
                Token(
                    kind: .closeParen, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case "[":
            return (
                Token(
                    kind: .openBracket, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case "]":
            return (
                Token(
                    kind: .closeBracket, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case "{":
            return (
                Token(
                    kind: .openBrace, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case "}":
            return (
                Token(
                    kind: .closeBrace, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case ",":
            return (
                Token(
                    kind: .comma, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case ".":
            return (
                Token(
                    kind: .dot, value: String(source[position..<nextIndex]), position: charPosition),
                nextIndex,
                false
            )
        case ":":
            return (
                Token(
                    kind: .colon, value: String(source[position..<nextIndex]),
                    position: charPosition),
                nextIndex,
                false
            )
        case "|":
            return (
                Token(
                    kind: .pipe, value: String(source[position..<nextIndex]), position: charPosition
                ),
                nextIndex,
                false
            )
        default: break
        }

        // Multi-character operators
        for length in [2, 1] {
            var endIndex = position
            for _ in 0..<length {
                guard endIndex < source.endIndex else { break }
                endIndex = source.index(after: endIndex)
            }
            if endIndex <= source.endIndex {
                let op = String(source[position..<endIndex])

                // Skip minus operator if it could be part of a closing delimiter
                if op == "-" && inTag {
                    let nextIndex = source.index(after: position)
                    if nextIndex < source.endIndex {
                        let nextChar = source[nextIndex]
                        if nextChar == "%" || nextChar == "}" {
                            continue  // Skip this operator, it's part of a delimiter
                        }
                    }
                }

                if let tokenKind = operators[op] {
                    return (
                        Token(kind: tokenKind, value: op, position: charPosition),
                        endIndex,
                        false
                    )
                }
            }
        }

        // String literals
        if char == "'" || char == "\"" {
            let (token, newPos) = try extractStringToken(
                from: source, at: position, delimiter: char)
            return (token, newPos, false)
        }

        // Numbers
        if char.isNumber {
            let (token, newPos) = extractNumberToken(from: source, at: position)
            return (token, newPos, false)
        }

        // Identifiers and keywords
        if char.isLetter || char == "_" {
            let (token, newPos) = extractIdentifierToken(from: source, at: position)
            return (token, newPos, false)
        }

        throw JinjaError.lexer(
            "Unexpected character '\(char)' at position \(charPosition)"
        )
    }

    private static func extractTextToken(
        from source: String,
        at position: String.Index,
        stripLeadingWhitespace: Bool = false
    ) -> (Token, String.Index) {
        var pos = position
        var startPos = position

        // Skip leading whitespace if requested
        if stripLeadingWhitespace {
            while pos < source.endIndex && source[pos].isWhitespace {
                pos = source.index(after: pos)
            }
            startPos = pos
        }

        while pos < source.endIndex {
            let char = source[pos]
            let nextIndex = source.index(after: pos)

            if nextIndex <= source.endIndex {
                if char == "{" && nextIndex < source.endIndex {
                    let nextChar = source[nextIndex]
                    if nextChar == "{" || nextChar == "%" || nextChar == "#" {
                        break
                    }
                }
                if char == "}" && nextIndex < source.endIndex && source[nextIndex] == "}" {
                    break
                }
                if char == "%" && nextIndex < source.endIndex && source[nextIndex] == "}" {
                    break
                }
                if char == "#" && nextIndex < source.endIndex && source[nextIndex] == "}" {
                    break
                }
            }
            pos = nextIndex
        }

        let charPosition = source.distance(from: source.startIndex, to: position)
        return (
            Token(kind: .text, value: String(source[startPos..<pos]), position: charPosition), pos
        )
    }

    private static func extractStringToken(
        from source: String, at position: String.Index, delimiter: Character
    ) throws -> (Token, String.Index) {
        var pos = source.index(after: position)
        var value = ""
        let charPosition = source.distance(from: source.startIndex, to: position)

        while pos < source.endIndex {
            let char = source[pos]

            if char == delimiter {
                let nextPos = source.index(after: pos)
                return (Token(kind: .string, value: value, position: charPosition), nextPos)
            }

            if char == "\\" {
                pos = source.index(after: pos)
                if pos < source.endIndex {
                    let escaped = source[pos]
                    switch escaped {
                    case "n": value += "\n"
                    case "t": value += "\t"
                    case "r": value += "\r"
                    case "b": value += "\u{8}"  // backspace
                    case "f": value += "\u{C}"  // form feed
                    case "v": value += "\u{B}"  // vertical tab
                    case "\\": value += "\\"
                    case "\"": value += "\""
                    case "'": value += "'"
                    default:
                        value += String(escaped)
                    }
                }
            } else {
                value += String(char)
            }

            pos = source.index(after: pos)
        }

        throw JinjaError.lexer("Unclosed string at position \(charPosition)")
    }

    private static func extractNumberToken(
        from source: String,
        at position: String.Index
    ) -> (Token, String.Index) {
        var pos = position
        var hasDot = false
        let startPos = position

        while pos < source.endIndex {
            let char = source[pos]
            if char.isNumber {
                pos = source.index(after: pos)
            } else if char == "." && !hasDot {
                hasDot = true
                pos = source.index(after: pos)
            } else {
                break
            }
        }

        let charPosition = source.distance(from: source.startIndex, to: position)
        return (Token(kind: .number, value: source[startPos..<pos], position: charPosition), pos)
    }

    private static func extractIdentifierToken(
        from source: String, at position: String.Index
    ) -> (Token, String.Index) {
        var pos = position
        let startPos = position

        while pos < source.endIndex {
            let char = source[pos]
            if char.isLetter || char.isNumber || char == "_" {
                pos = source.index(after: pos)
            } else {
                break
            }
        }

        let value = String(source[startPos..<pos])
        let tokenKind = keywords[value] ?? .identifier
        let charPosition = source.distance(from: source.startIndex, to: position)
        return (Token(kind: tokenKind, value: source[startPos..<pos], position: charPosition), pos)
    }

    private static func extractCommentToken(
        from source: String,
        at position: String.Index
    ) throws -> (Token, String.Index) {
        // Skip the opening {#
        var pos = source.index(position, offsetBy: 2)
        var value = ""
        let charPosition = source.distance(from: source.startIndex, to: position)

        while pos < source.endIndex {
            let char = source[pos]
            let nextIndex = source.index(after: pos)

            if nextIndex < source.endIndex && char == "#" && source[nextIndex] == "}" {
                let endPos = source.index(after: nextIndex)
                return (Token(kind: .comment, value: value, position: charPosition), endPos)
            }

            value += String(char)
            pos = nextIndex
        }

        throw JinjaError.lexer("Unclosed comment at position \(charPosition)")
    }

}

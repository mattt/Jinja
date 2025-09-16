/// Tokenizes Jinja template source code into a sequence of tokens.
public struct Lexer: Sendable {
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
    
    // Instance properties to hold lexer state
    private let source: String
    private var position: String.Index
    private var inTag: Bool
    private var curlyBracketDepth: Int
    private var stripNextWhitespace: Bool
    
    private init(source: String) {
        self.source = source
        self.position = source.startIndex
        self.inTag = false
        self.curlyBracketDepth = 0
        self.stripNextWhitespace = false
    }

    /// Tokenizes a template source string into an array of tokens.
    ///
    /// - Parameter source: The Jinja template source code to tokenize
    /// - Returns: An array of tokens representing the lexical structure
    /// - Throws: `JinjaError.lexer` if the source contains invalid syntax
    public static func tokenize(_ source: String) throws -> [Token] {
        var lexer = Lexer(source: source)
        return try lexer.tokenize()
    }
    
    /// Instance method to tokenize the source string.
    private mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        tokens.reserveCapacity(source.count / 4)

        while position < source.endIndex {
            if inTag {
                skipWhitespace()
                if position >= source.endIndex {
                    break
                }
            }

            let (token, shouldStripWhitespace) = try extractToken()

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
                continue
            }

            tokens.append(token)

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

    private mutating func skipWhitespace() {
        while position < source.endIndex {
            let char = source[position]
            if char.isWhitespace {
                position = source.index(after: position)
            } else {
                break
            }
        }
    }

    private mutating func extractToken() throws -> (Token, Bool) {
        guard position < source.endIndex else {
            let charPosition = source.distance(from: source.startIndex, to: position)
            return (Token(kind: .eof, value: "", position: charPosition), false)
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
                    if endIndex < source.endIndex && source[endIndex] == "-" {
                        hasStripLeft = true
                        position = source.index(after: endIndex)
                    } else {
                        position = endIndex
                    }

                    return (
                        Token(kind: .openExpression, value: "{{", position: charPosition),
                        hasStripLeft
                    )
                } else if nextChar == "%" {  // "{%" or "{%-"
                    let endIndex = source.index(after: nextIndex)

                    // Check if there's a following "-" for whitespace stripping
                    var hasStripLeft = false
                    if endIndex < source.endIndex && source[endIndex] == "-" {
                        hasStripLeft = true
                        position = source.index(after: endIndex)
                    } else {
                        position = endIndex
                    }

                    return (
                        Token(kind: .openStatement, value: "{%", position: charPosition),
                        hasStripLeft
                    )
                } else if nextChar == "#" {  // "{#"
                    let (token, shouldStrip) = try extractCommentToken()
                    return (token, shouldStrip)
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
                        position = source.index(after: afterNext)
                        return (
                            Token(kind: .closeExpression, value: "}}", position: charPosition),
                            true
                        )
                    }
                } else if nextChar == "%" {
                    let afterNext = source.index(after: nextIndex)
                    if afterNext < source.endIndex && source[afterNext] == "}" {
                        // "-%}" - statement close with right strip
                        position = source.index(after: afterNext)
                        return (
                            Token(kind: .closeStatement, value: "%}", position: charPosition),
                            true
                        )
                    }
                }
            }
        }

        if char == "}" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex && source[nextIndex] == "}" && curlyBracketDepth == 0 {
                position = source.index(after: nextIndex)
                return (
                    Token(kind: .closeExpression, value: "}}", position: charPosition),
                    false
                )
            }
        }
        if char == "%" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex && source[nextIndex] == "}" {
                position = source.index(after: nextIndex)
                return (
                    Token(kind: .closeStatement, value: "%}", position: charPosition),
                    false
                )
            }
        }

        if !inTag {
            let (token, shouldStrip) = extractTextToken(stripLeadingWhitespace: stripNextWhitespace)
            return (token, shouldStrip)
        }

        // Single character tokens
        let nextIndex = source.index(after: position)
        switch char {
        case "(":
            let token = Token(kind: .openParen, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case ")":
            let token = Token(kind: .closeParen, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case "[":
            let token = Token(kind: .openBracket, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case "]":
            let token = Token(kind: .closeBracket, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case "{":
            let token = Token(kind: .openBrace, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case "}":
            let token = Token(kind: .closeBrace, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case ",":
            let token = Token(kind: .comma, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case ".":
            let token = Token(kind: .dot, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case ":":
            let token = Token(kind: .colon, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
        case "|":
            let token = Token(kind: .pipe, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return (token, false)
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

                if let tokenKind = Self.operators[op] {
                    let token = Token(kind: tokenKind, value: op, position: charPosition)
                    position = endIndex
                    return (token, false)
                }
            }
        }

        // String literals
        if char == "'" || char == "\"" {
            let (token, shouldStrip) = try extractStringToken(delimiter: char)
            return (token, shouldStrip)
        }

        // Numbers
        if char.isNumber {
            let (token, shouldStrip) = extractNumberToken()
            return (token, shouldStrip)
        }

        // Identifiers and keywords
        if char.isLetter || char == "_" {
            let (token, shouldStrip) = extractIdentifierToken()
            return (token, shouldStrip)
        }

        throw JinjaError.lexer(
            "Unexpected character '\(char)' at position \(charPosition)"
        )
    }

    private mutating func extractTextToken(stripLeadingWhitespace: Bool = false) -> (Token, Bool) {
        let startPosition = position
        var startPos = position

        // Skip leading whitespace if requested
        if stripLeadingWhitespace {
            while position < source.endIndex && source[position].isWhitespace {
                position = source.index(after: position)
            }
            startPos = position
        }

        while position < source.endIndex {
            let char = source[position]
            let nextIndex = source.index(after: position)

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
            position = nextIndex
        }

        let charPosition = source.distance(from: source.startIndex, to: startPosition)
        return (Token(kind: .text, value: String(source[startPos..<position]), position: charPosition), false)
    }

    private mutating func extractStringToken(delimiter: Character) throws -> (Token, Bool) {
        let startPosition = position
        position = source.index(after: position)
        var value = ""
        let charPosition = source.distance(from: source.startIndex, to: startPosition)

        while position < source.endIndex {
            let char = source[position]

            if char == delimiter {
                position = source.index(after: position)
                return (Token(kind: .string, value: value, position: charPosition), false)
            }

            if char == "\\" {
                position = source.index(after: position)
                if position < source.endIndex {
                    let escaped = source[position]
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

            position = source.index(after: position)
        }

        throw JinjaError.lexer("Unclosed string at position \(charPosition)")
    }

    private mutating func extractNumberToken() -> (Token, Bool) {
        let startPos = position
        var hasDot = false
        let charPosition = source.distance(from: source.startIndex, to: position)

        while position < source.endIndex {
            let char = source[position]
            if char.isNumber {
                position = source.index(after: position)
            } else if char == "." && !hasDot {
                hasDot = true
                position = source.index(after: position)
            } else {
                break
            }
        }

        return (Token(kind: .number, value: String(source[startPos..<position]), position: charPosition), false)
    }

    private mutating func extractIdentifierToken() -> (Token, Bool) {
        let startPos = position
        let charPosition = source.distance(from: source.startIndex, to: position)

        while position < source.endIndex {
            let char = source[position]
            if char.isLetter || char.isNumber || char == "_" {
                position = source.index(after: position)
            } else {
                break
            }
        }

        let value = String(source[startPos..<position])
        let tokenKind = Self.keywords[value] ?? .identifier
        return (Token(kind: tokenKind, value: value, position: charPosition), false)
    }

    private mutating func extractCommentToken() throws -> (Token, Bool) {
        let startPosition = position
        // Skip the opening {#
        position = source.index(position, offsetBy: 2)
        var value = ""
        let charPosition = source.distance(from: source.startIndex, to: startPosition)

        while position < source.endIndex {
            let char = source[position]
            let nextIndex = source.index(after: position)

            if nextIndex < source.endIndex && char == "#" && source[nextIndex] == "}" {
                position = source.index(after: nextIndex)
                return (Token(kind: .comment, value: value, position: charPosition), false)
            }

            value += String(char)
            position = nextIndex
        }

        throw JinjaError.lexer("Unclosed comment at position \(charPosition)")
    }

}

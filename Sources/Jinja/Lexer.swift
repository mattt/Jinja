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
    
    private init(source: String) {
        self.source = source
        self.position = source.startIndex
        self.inTag = false
        self.curlyBracketDepth = 0
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

            let token = try extractToken()

            switch token.kind {
            case .openExpression, .openStatement:
                inTag = true
                curlyBracketDepth = 0
            case .closeExpression, .closeStatement:
                inTag = false
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

    private mutating func extractToken() throws -> Token {
        guard position < source.endIndex else {
            let charPosition = source.distance(from: source.startIndex, to: position)
            return Token(kind: .eof, value: "", position: charPosition)
        }

        let char = source[position]
        let charPosition = source.distance(from: source.startIndex, to: position)

        // Template delimiters - check for {{, {%, and {#
        if char == "{" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex {
                let nextChar = source[nextIndex]
                if nextChar == "{" {  // "{{"
                    position = source.index(after: nextIndex)
                    return Token(kind: .openExpression, value: "{{", position: charPosition)
                } else if nextChar == "%" {  // "{%"
                    position = source.index(after: nextIndex)
                    return Token(kind: .openStatement, value: "{%", position: charPosition)
                } else if nextChar == "#" {  // "{#"
                    return try extractCommentToken()
                }
            }
        }

        // Check for closing delimiters
        if char == "}" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex && source[nextIndex] == "}" && curlyBracketDepth == 0 {
                position = source.index(after: nextIndex)
                return Token(kind: .closeExpression, value: "}}", position: charPosition)
            }
        }
        if char == "%" {
            let nextIndex = source.index(after: position)
            if nextIndex < source.endIndex && source[nextIndex] == "}" {
                position = source.index(after: nextIndex)
                return Token(kind: .closeStatement, value: "%}", position: charPosition)
            }
        }

        if !inTag {
            return extractTextToken()
        }

        // Single character tokens
        let nextIndex = source.index(after: position)
        switch char {
        case "(":
            let token = Token(kind: .openParen, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case ")":
            let token = Token(kind: .closeParen, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case "[":
            let token = Token(kind: .openBracket, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case "]":
            let token = Token(kind: .closeBracket, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case "{":
            let token = Token(kind: .openBrace, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case "}":
            let token = Token(kind: .closeBrace, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case ",":
            let token = Token(kind: .comma, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case ".":
            let token = Token(kind: .dot, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case ":":
            let token = Token(kind: .colon, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
        case "|":
            let token = Token(kind: .pipe, value: String(source[position..<nextIndex]), position: charPosition)
            position = nextIndex
            return token
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
                    return token
                }
            }
        }

        // String literals
        if char == "'" || char == "\"" {
            return try extractStringToken(delimiter: char)
        }

        // Numbers
        if char.isNumber {
            return extractNumberToken()
        }

        // Identifiers and keywords
        if char.isLetter || char == "_" {
            return extractIdentifierToken()
        }

        throw JinjaError.lexer(
            "Unexpected character '\(char)' at position \(charPosition)"
        )
    }

    private mutating func extractTextToken() -> Token {
        let startPosition = position
        let charPosition = source.distance(from: source.startIndex, to: position)

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

        return Token(kind: .text, value: String(source[startPosition..<position]), position: charPosition)
    }

    private mutating func extractStringToken(delimiter: Character) throws -> Token {
        let startPosition = position
        position = source.index(after: position)
        var value = ""
        let charPosition = source.distance(from: source.startIndex, to: startPosition)

        while position < source.endIndex {
            let char = source[position]

            if char == delimiter {
                position = source.index(after: position)
                return Token(kind: .string, value: value, position: charPosition)
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

    private mutating func extractNumberToken() -> Token {
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

        return Token(kind: .number, value: String(source[startPos..<position]), position: charPosition)
    }

    private mutating func extractIdentifierToken() -> Token {
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
        return Token(kind: tokenKind, value: value, position: charPosition)
    }

    private mutating func extractCommentToken() throws -> Token {
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
                return Token(kind: .comment, value: value, position: charPosition)
            }

            value += String(char)
            position = nextIndex
        }

        throw JinjaError.lexer("Unclosed comment at position \(charPosition)")
    }

}

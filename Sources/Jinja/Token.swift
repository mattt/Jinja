public struct Token: Sendable {
    public enum Kind: Sendable {
        case text, expression, statement
        case string, number, boolean, null, identifier
        case openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace
        case comma, dot, colon, pipe, equals
        case plus, minus, multiply, divide, modulo, concat
        case equal, notEqual, less, lessEqual, greater, greaterEqual
        case and, or, not, `in`, notIn, `is`
        case `if`, `else`, elif, endif, `for`, endfor, set, macro, endmacro
        case eof
    }
    public let kind: Kind
    public let value: String
    public let position: Int
}

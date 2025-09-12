import Foundation
import OrderedCollections

/// Parses tokens into an abstract syntax tree for Jinja templates.
public struct Parser: Sendable {
    private let tokens: [Token]
    private var current: Int = 0

    private init(tokens: [Token]) {
        self.tokens = tokens
    }

    /// Parses tokens into an abstract syntax tree of nodes.
    public static func parse(_ tokens: [Token], optimize: Bool = true) throws -> [Node] {
        var parser = Parser(tokens: tokens)
        var nodes: [Node] = []
        nodes.reserveCapacity(tokens.count / 3)  // Rough estimate

        while !parser.isAtEnd {
            let node = try parser.parseNode()

            // Text node coalescing: merge adjacent text nodes
            if case .text(let newText) = node,
                case .text(let existingText)? = nodes.last
            {
                // Replace the last node with merged text
                nodes[nodes.count - 1] = .text(existingText + newText)
            } else if case .text(let text) = node, text.isEmpty {
                // do not add empty text nodes
            } else {
                nodes.append(node)
            }
        }

        // Ensure no unclosed control structures remain
        // Lexer would have provided matching end tokens; reaching here means blocks closed
        // Apply constant folding optimization
        return optimize ? parser.optimizeNodes(nodes) : nodes
    }

    /// Apply constant folding and other compile-time optimizations
    private func optimizeNodes(_ nodes: [Node]) -> [Node] {
        return nodes.map { node in
            switch node {
            case let .expression(expr):
                return .expression(optimizeExpression(expr))
            case let .statement(stmt):
                return .statement(optimizeStatement(stmt))
            case .text:
                return node  // Text nodes are already optimized through coalescing
            }
        }
    }

    /// Optimize expressions through constant folding
    private func optimizeExpression(_ expr: Expression) -> Expression {
        switch expr {
        case let .binary(.add, .integer(left), .integer(right)):
            return .integer(left + right)
        case let .binary(.add, .number(left), .number(right)):
            return .number(left + right)
        case let .binary(.subtract, .integer(left), .integer(right)):
            return .integer(left - right)
        case let .binary(.subtract, .number(left), .number(right)):
            return .number(left - right)
        case let .binary(.multiply, .integer(left), .integer(right)):
            return .integer(left * right)
        case let .binary(.multiply, .number(left), .number(right)):
            return .number(left * right)
        case let .binary(.concat, .string(left), .string(right)):
            return .string(left + right)
        case let .unary(.not, .boolean(value)):
            return .boolean(!value)
        case let .unary(.minus, .integer(value)):
            return .integer(-value)
        case let .unary(.minus, .number(value)):
            return .number(-value)
        default:
            return expr
        }
    }

    /// Optimize statements
    private func optimizeStatement(_ stmt: Statement) -> Statement {
        switch stmt {
        case let .if(condition, body, alternate):
            let optimizedCondition = optimizeExpression(condition)
            let optimizedBody = optimizeNodes(body)
            let optimizedAlternate = optimizeNodes(alternate)

            // If condition is constant true, return only the body
            if case .boolean(true) = optimizedCondition {
                return .program(optimizedBody)
            }

            // If condition is constant false, return only the alternate
            if case .boolean(false) = optimizedCondition {
                return .program(optimizedAlternate)
            }

            // If body is empty and alternate is empty, return empty program
            if optimizedBody.isEmpty && optimizedAlternate.isEmpty {
                return .program([])
            }

            return .if(optimizedCondition, optimizedBody, optimizedAlternate)

        case let .for(loopVar, iterable, body, elseBody, test):
            let optimizedIterable = optimizeExpression(iterable)
            let optimizedBody = optimizeNodes(body)
            let optimizedElseBody = optimizeNodes(elseBody)
            let optimizedTest = test.map(optimizeExpression)

            // If iterable is an empty array, return only the else body
            if case .array(let elements) = optimizedIterable, elements.isEmpty {
                return .program(optimizedElseBody)
            }

            // If body is empty and else body is empty, return empty program
            if optimizedBody.isEmpty && optimizedElseBody.isEmpty {
                return .program([])
            }

            return .for(
                loopVar, optimizedIterable, optimizedBody, optimizedElseBody, test: optimizedTest)

        case let .set(identifier, expression):
            return .set(identifier, optimizeExpression(expression))

        case let .macro(name, args, defaults, body):
            return .macro(name, args, defaults, optimizeNodes(body))

        case let .program(nodes):
            return .program(optimizeNodes(nodes))
        }
    }

    // Parse nodes until we hit one of the specified statement keywords
    private mutating func parseNodesUntil(_ keywords: Set<String>) throws -> [Node] {
        var nodes: [Node] = []

        while !isAtEnd {
            if check(.openStatement) {
                let nextToken = tokens[current + 1]
                if nextToken.kind == .identifier, keywords.contains(nextToken.value) {
                    break
                }
            }

            let node = try parseNode()

            // Text node coalescing: merge adjacent text nodes
            if case .text(let newText) = node,
                case .text(let existingText)? = nodes.last
            {
                // Replace the last node with merged text
                nodes[nodes.count - 1] = .text(existingText + newText)
            } else {
                nodes.append(node)
            }
        }

        return nodes
    }

    // Parse a complete if/elif/else/endif structure
    private mutating func parseIfStatement() throws -> Statement {
        let condition = try parseExpression()
        try consume(.closeStatement, message: "Expected '%}' after if condition.")
        let body = try parseNodesUntil(["elif", "else", "endif"])

        var alternate: [Node] = []

        if match(.openStatement) {
            if peekKeyword("elif") {
                advance()
                alternate.append(.statement(try parseIfStatement()))
            } else if peekKeyword("else") {
                advance()
                try consume(.closeStatement, message: "Expected '%}' after else.")
                alternate = try parseNodesUntil(["endif"])
                try consume(.openStatement, message: "Expected '{%' for endif.")
                try consumeIdentifier("endif")
                try consume(.closeStatement, message: "Expected '%}' after endif.")
            } else {
                try consumeIdentifier("endif")
                try consume(.closeStatement, message: "Expected '%}' after endif.")
            }
        } else {
            throw JinjaError.parser("Unclosed if statement")
        }

        return .if(condition, body, alternate)
    }

    // Parse a complete for/endfor structure
    private mutating func parseForStatement() throws -> Statement {
        var loopVarParts: [String] = []
        repeat {
            loopVarParts.append(try consumeIdentifier())
        } while match(.comma)

        let loopVar: LoopVar
        if loopVarParts.count == 1 {
            loopVar = .single(loopVarParts[0])
        } else {
            loopVar = .tuple(loopVarParts)
        }

        try consumeIdentifier("in")

        let iterableExpr = try parseExpression()
        var testExpr: Expression?

        if matchKeyword("if") {
            testExpr = try parseExpression()
        }

        try consume(.closeStatement, message: "Expected '%}' after for loop.")

        let body = try parseNodesUntil(["else", "endfor"])
        var elseBody: [Node] = []

        if match(.openStatement) {
            if matchKeyword("else") {
                try consume(.closeStatement, message: "Expected '%}' after else.")
                elseBody = try parseNodesUntil(["endfor"])
                try consume(.openStatement, message: "Expected '{%' for endfor.")
                try consumeIdentifier("endfor")
                try consume(.closeStatement, message: "Expected '%}' after endfor.")
            } else {
                try consumeIdentifier("endfor")
                try consume(.closeStatement, message: "Expected '%}' after endfor.")
            }
        } else {
            throw JinjaError.parser("Unclosed for loop")
        }

        return .for(loopVar, iterableExpr, body, elseBody, test: testExpr)
    }

    // Parse a complete macro/endmacro structure
    private mutating func parseMacroStatement() throws -> Statement {
        let macroName = try consumeIdentifier()
        var parameters: [String] = []
        var defaults: OrderedDictionary<String, Expression> = [:]

        try consume(.openParen, message: "Expected '(' after macro name.")
        if !check(.closeParen) {
            repeat {
                let paramName = try consumeIdentifier()
                parameters.append(paramName)
                if match(.equals) {
                    defaults[paramName] = try parseExpression()
                }
            } while match(.comma)
        }
        try consume(.closeParen, message: "Expected ')' after macro parameters.")
        try consume(.closeStatement, message: "Expected '%}' after macro definition.")

        let body = try parseNodesUntil(["endmacro"])

        try consume(.openStatement, message: "Expected '{%' for endmacro.")
        try consumeIdentifier("endmacro")
        try consume(.closeStatement, message: "Expected '%}' after endmacro.")

        return .macro(macroName, parameters, defaults, body)
    }

    // MARK: -

    private var isAtEnd: Bool {
        current >= tokens.count || peek().kind == .eof
    }

    private func peek() -> Token {
        guard current < tokens.count else {
            return Token(kind: .eof, value: "", position: tokens.last?.position ?? 0)
        }
        return tokens[current]
    }

    @discardableResult
    private mutating func advance() -> Token {
        if !isAtEnd { current += 1 }
        return previous()
    }

    private func previous() -> Token {
        guard current > 0 else {
            return Token(kind: .eof, value: "", position: 0)
        }
        return tokens[current - 1]
    }

    private func check(_ kind: Token.Kind) -> Bool {
        isAtEnd ? false : peek().kind == kind
    }

    private mutating func match(_ kinds: Token.Kind...) -> Bool {
        for kind in kinds {
            if check(kind) {
                advance()
                return true
            }
        }
        return false
    }

    @discardableResult
    private mutating func consume(_ kind: Token.Kind, message: String) throws -> Token {
        if check(kind) { return advance() }
        throw JinjaError.parser("\(message). Got \(peek().kind) instead")
    }

    private func peekKeyword(_ keyword: String) -> Bool {
        guard !isAtEnd else { return false }
        let token = peek()
        return token.value == keyword
    }

    private mutating func matchKeyword(_ keyword: String) -> Bool {
        if peekKeyword(keyword) {
            advance()
            return true
        }
        return false
    }

    @discardableResult
    private mutating func consumeIdentifier(_ name: String? = nil) throws -> String {
        guard !isAtEnd else {
            throw JinjaError.parser("Expected identifier but found EOF.")
        }
        let token = peek()
        if token.kind == .identifier {
            if let name = name, token.value != name {
                throw JinjaError.parser("Expected identifier '\(name)' but found '\(token.value)'.")
            }
            advance()
            return token.value
        }
        throw JinjaError.parser("Expected identifier but found \(token.kind).")
    }

    // MARK: - Node Parsing

    private mutating func parseNode() throws -> Node {
        let token = peek()

        switch token.kind {
        case .text:
            advance()
            return .text(token.value)

        case .openExpression:
            try consume(.openExpression, message: "Expected '{{'.")
            let expression = try parseExpression()
            try consume(.closeExpression, message: "Expected '}}' after expression.")
            return .expression(expression)

        case .openStatement:
            try consume(.openStatement, message: "Expected '{%'.")
            let statement = try parseStatement()
            // The closing '%}' is consumed by the statement parsing function
            return .statement(statement)

        default:
            if isAtEnd { return .text("") }
            throw JinjaError.parser("Unexpected token type: \(token.kind)")
        }
    }

    private mutating func parseStatement() throws -> Statement {
        let keywordToken = peek()

        switch keywordToken.kind {
        case .set:
            advance()  // consume keyword
            let identifier = try consumeIdentifier()
            try consume(.equals, message: "Expected '=' after identifier.")
            let expression = try parseExpression()
            try consume(.closeStatement, message: "Expected '%}' after set statement.")
            return .set(identifier, expression)
        case .if:
            advance()  // consume keyword
            return try parseIfStatement()
        case .for:
            advance()  // consume keyword
            return try parseForStatement()
        case .macro:
            advance()  // consume keyword
            return try parseMacroStatement()
        default:
            throw JinjaError.parser("Unknown statement: \(keywordToken.value)")
        }
    }

    private mutating func parseExpression() throws -> Expression {
        return try parseTernary()
    }

    private mutating func parseTernary() throws -> Expression {
        let expr = try parseOr()

        if matchKeyword("if") {
            let test = try parseOr()
            var alternate: Expression?

            if matchKeyword("else") {
                alternate = try parseOr()
            }

            return .ternary(expr, test: test, alternate: alternate)
        }

        return expr
    }

    private mutating func parseOr() throws -> Expression {
        var expr = try parseAnd()

        while matchKeyword("or") {
            let right = try parseAnd()
            expr = .binary(.or, expr, right)
        }

        return expr
    }

    private mutating func parseAnd() throws -> Expression {
        var expr = try parseEquality()

        while matchKeyword("and") {
            let right = try parseEquality()
            expr = .binary(.and, expr, right)
        }

        return expr
    }

    private mutating func parseEquality() throws -> Expression {
        var expr = try parseComparison()

        while true {
            if match(.equal) {
                let right = try parseComparison()
                expr = .binary(.equal, expr, right)
            } else if match(.notEqual) {
                let right = try parseComparison()
                expr = .binary(.notEqual, expr, right)
            } else {
                break
            }
        }

        return expr
    }

    private mutating func parseComparison() throws -> Expression {
        var expr = try parseTerm()

        while true {
            if match(.less) {
                let right = try parseTerm()
                expr = .binary(.less, expr, right)
            } else if match(.lessEqual) {
                let right = try parseTerm()
                expr = .binary(.lessEqual, expr, right)
            } else if match(.greater) {
                let right = try parseTerm()
                expr = .binary(.greater, expr, right)
            } else if match(.greaterEqual) {
                let right = try parseTerm()
                expr = .binary(.greaterEqual, expr, right)
            } else if matchKeyword("in") {
                let right = try parseTerm()
                expr = .binary(.`in`, expr, right)
            } else if matchKeyword("not"), matchKeyword("in") {
                let right = try parseTerm()
                expr = .binary(.notIn, expr, right)
            } else {
                break
            }
        }

        return expr
    }

    private mutating func parseTerm() throws -> Expression {
        var expr = try parseFactor()

        while true {
            if match(.plus) {
                let right = try parseFactor()
                expr = .binary(.add, expr, right)
            } else if match(.minus) {
                let right = try parseFactor()
                expr = .binary(.subtract, expr, right)
            } else if match(.concat) {
                let right = try parseFactor()
                expr = .binary(.concat, expr, right)
            } else {
                break
            }
        }

        return expr
    }

    private mutating func parseFactor() throws -> Expression {
        var expr = try parseUnary()

        while true {
            if match(.multiply) {
                let right = try parseUnary()
                expr = .binary(.multiply, expr, right)
            } else if match(.divide) {
                let right = try parseUnary()
                expr = .binary(.divide, expr, right)
            } else if match(.modulo) {
                let right = try parseUnary()
                expr = .binary(.modulo, expr, right)
            } else {
                break
            }
        }

        return expr
    }

    private mutating func parseUnary() throws -> Expression {
        if matchKeyword("not") {
            let expr = try parseUnary()
            return .unary(.not, expr)
        }

        if match(.minus) {
            let expr = try parseUnary()
            return .unary(.minus, expr)
        }

        if match(.plus) {
            let expr = try parseUnary()
            return .unary(.plus, expr)
        }

        var expr = try parsePostfix()

        // Handle adjacent string literals as implicit concatenation
        while case .string = expr, case .string(let val) = try? parsePrimary(calledFromUnary: true)
        {
            let right = Expression.string(val)
            expr = .binary(.concat, expr, right)
        }

        return expr
    }

    private mutating func parsePostfix() throws -> Expression {
        var expr = try parsePrimary()

        while true {
            if match(.dot) {
                let name = try consumeIdentifier()
                expr = .member(expr, .identifier(name), computed: false)
            } else if match(.openBracket) {
                let index = try parseExpression()
                try consume(.closeBracket, message: "Expected ']' after index.")
                expr = .member(expr, index, computed: true)
            } else if match(.openParen) {
                let (args, kwargs) = try parseArguments()
                try consume(.closeParen, message: "Expected ')' after arguments.")
                expr = .call(expr, args, kwargs)
            } else if match(.pipe) {
                let filterName = try consumeIdentifier()
                var args: [Expression] = []
                var kwargs: [String: Expression] = [:]

                if match(.openParen) {
                    (args, kwargs) = try parseArguments()
                    try consume(.closeParen, message: "Expected ')' after filter arguments.")
                }

                expr = .filter(expr, filterName, args, kwargs)
            } else if matchKeyword("is") {
                let negated = matchKeyword("not")
                let testName = try consumeIdentifier()
                var args: [Expression] = []
                if match(.openParen) {
                    (args, _) = try parseArguments()
                    try consume(.closeParen, message: "Expected ')' after test arguments.")
                }
                if args.isEmpty {
                    expr = .test(expr, testName, negated: negated)
                } else {
                    expr = .testArgs(expr, testName, args, negated: negated)
                }
            } else {
                break
            }
        }

        return expr
    }

    private mutating func parsePrimary(calledFromUnary: Bool = false) throws -> Expression {
        let token = peek()
        switch token.kind {
        case .string:
            advance()
            return .string(token.value)
        case .number:
            advance()
            if token.value.contains(".") {
                return .number(Double(token.value) ?? 0.0)
            } else {
                return .integer(Int(token.value) ?? 0)
            }
        case .boolean:
            advance()
            return .boolean(token.value == "true")
        case .null:
            advance()
            return .null
        case .openBracket:
            advance()
            var elements: [Expression] = []
            if !check(.closeBracket) {
                repeat {
                    elements.append(try parseExpression())
                } while match(.comma)
            }
            try consume(.closeBracket, message: "Expected ']' after array literal.")
            return .array(elements)
        case .openBrace:
            advance()
            var pairs: OrderedDictionary<String, Expression> = [:]
            if !check(.closeBrace) {
                repeat {
                    let keyToken = try consume(
                        .string, message: "Expected string literal for object key.")
                    try consume(.colon, message: "Expected ':' after object key.")
                    let value = try parseExpression()
                    pairs[keyToken.value] = value
                } while match(.comma)
            }
            try consume(.closeBrace, message: "Expected '}' after object literal.")
            return .object(pairs)
        case .openParen:
            advance()
            let expr = try parseExpression()
            try consume(.closeParen, message: "Expected ')' after expression.")
            return expr
        case .identifier, .if, .else, .in, .is, .not, .and, .or:
            advance()
            return .identifier(token.value)
        default:
            if token.kind == .text {
                throw JinjaError.parser("Unexpected text found in expression: '\(token.value)'")
            }

            if calledFromUnary {
                // To avoid infinite recursion in parseUnary for adjacent string literal concatenation
                throw JinjaError.parser("Not a primary expression")
            }
            throw JinjaError.parser("Unexpected token for primary expression: \(token.kind)")
        }
    }

    private mutating func parseArguments() throws -> ([Expression], [String: Expression]) {
        var args: [Expression] = []
        var kwargs: [String: Expression] = [:]

        if !check(.closeParen) {
            repeat {
                let expr = try parseExpression()
                if match(.equals) {
                    if case .identifier(let key) = expr {
                        let value = try parseExpression()
                        kwargs[key] = value
                    } else {
                        throw JinjaError.parser("Identifier expected for keyword argument.")
                    }
                } else {
                    args.append(expr)
                }
            } while match(.comma)
        }

        return (args, kwargs)
    }
}

// MARK: - Small helpers
extension Array where Element == Node {
    fileprivate func guardNonEmptyOrThrow(_ message: String = "") throws -> [Node] {
        if isEmpty { throw JinjaError.parser(message.isEmpty ? "Empty block body" : message) }
        return self
    }
}

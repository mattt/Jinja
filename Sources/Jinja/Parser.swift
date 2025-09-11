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
    public static func parse(_ tokens: [Token]) throws -> [Node] {
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
            } else {
                nodes.append(node)
            }
        }

        // Apply constant folding optimization
        return parser.optimizeNodes(nodes)
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

        case let .macro(name, args, body):
            return .macro(name, args, optimizeNodes(body))

        case let .program(nodes):
            return .program(optimizeNodes(nodes))
        }
    }

    // Parse nodes until we hit one of the specified statement keywords
    private mutating func parseNodesUntil(_ keywords: Set<String>) throws -> [Node] {
        var nodes: [Node] = []

        while !isAtEnd {
            let token = peek()

            // Check if this is a statement token with one of our target keywords
            if case .statement = token.kind {
                let content = token.value.trimmingCharacters(in: .whitespaces)
                let firstWord = content.components(separatedBy: .whitespaces).first ?? ""
                if keywords.contains(firstWord) {
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
    private mutating func parseIfStatement() throws -> Node {
        var branches: [(Expression?, [Node])] = []

        // Parse the initial if statement
        let ifToken = advance()  // consume the if statement token
        let ifContent = ifToken.value.trimmingCharacters(in: .whitespaces)
        let ifConditionPart = String(ifContent.dropFirst(2)).trimmingCharacters(in: .whitespaces)  // remove "if"

        let ifCondition = try ExpressionParser.parse(ifConditionPart)

        // Parse the body until we hit elif, else, or endif
        let ifBody = try parseNodesUntil(["elif", "else", "endif"])
        branches.append((ifCondition, ifBody))

        // Handle elif and else branches
        while !isAtEnd {
            let token = peek()

            guard case .statement = token.kind else {
                break
            }

            let content = token.value.trimmingCharacters(in: .whitespaces)
            let firstWord = content.components(separatedBy: .whitespaces).first ?? ""

            if firstWord == "elif" {
                advance()  // consume the elif token
                let elifConditionPart = String(content.dropFirst(4)).trimmingCharacters(
                    in: .whitespaces)  // remove "elif"

                let elifCondition = try ExpressionParser.parse(elifConditionPart)

                let elifBody = try parseNodesUntil(["elif", "else", "endif"])
                branches.append((elifCondition, elifBody))

            } else if firstWord == "else" {
                advance()  // consume the else token
                let elseBody = try parseNodesUntil(["endif"])
                branches.append((nil, elseBody))  // nil condition means "else"

            } else if firstWord == "endif" {
                advance()  // consume the endif token
                break

            } else {
                throw JinjaError.parser("Expected elif, else, or endif, got: \(firstWord)")
            }
        }

        // Convert branches to the expected format for Statement.if
        if branches.count == 1 {
            // Simple if statement
            return .statement(.if(branches[0].0!, branches[0].1, []))
        } else {
            // Complex if/elif/else - we need to nest them
            var result = branches.last!
            for branch in branches.dropLast().reversed() {
                if let condition = branch.0 {
                    result = (condition, branch.1)
                    result = (
                        nil,
                        [
                            .statement(
                                .if(
                                    condition,
                                    branch.1,
                                    result.0 == nil
                                        ? result.1 : [.statement(.if(result.0!, result.1, []))]
                                )
                            )
                        ]
                    )
                }
            }

            let rootBranch = branches[0]
            let alternateBranches = Array(branches.dropFirst())

            // Build nested if statements for elif chains
            var alternate: [Node] = []
            if alternateBranches.count > 0 {
                alternate = [buildNestedIf(alternateBranches)]
            }

            return .statement(.if(rootBranch.0!, rootBranch.1, alternate))
        }
    }

    // Helper to build nested if statements for elif chains
    private func buildNestedIf(_ branches: [(Expression?, [Node])]) -> Node {
        if branches.count == 1 {
            let branch = branches[0]
            if let condition = branch.0 {
                return .statement(.if(condition, branch.1, []))
            } else {
                // This is an else branch - return the body directly
                return branches[0].1.count == 1
                    ? branches[0].1[0] : .statement(.if(.boolean(true), branches[0].1, []))
            }
        }

        let first = branches[0]
        let rest = Array(branches.dropFirst())

        if let condition = first.0 {
            return .statement(.if(condition, first.1, [buildNestedIf(rest)]))
        } else {
            // This should be the else branch, which should be at the end
            return .statement(.if(.boolean(true), first.1, []))
        }
    }

    // Parse a complete for/endfor structure
    private mutating func parseForStatement() throws -> Node {
        // Parse the initial for statement
        let forToken = advance()  // consume the for statement token
        let forContent = forToken.value.trimmingCharacters(in: .whitespaces)

        // Extract loop variable and iterable from "for var in iterable"
        let parts = forContent.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 4 && parts[0] == "for" && parts[2] == "in" else {
            throw JinjaError.parser("Invalid for loop syntax: \(forContent)")
        }

        let loopVarName = parts[1]
        let iterableContent = parts[3...].joined(separator: " ")

        // Parse the iterable expression
        let iterableExpr = try ExpressionParser.parse(iterableContent)

        // Parse the body until we hit endfor
        let forBody = try parseNodesUntil(["endfor"])

        // Consume the endfor token
        if !isAtEnd {
            let token = peek()
            if case .statement = token.kind {
                let content = token.value.trimmingCharacters(in: .whitespaces)
                if content == "endfor" {
                    advance()  // consume endfor
                }
            }
        }

        return .statement(.for(.single(loopVarName), iterableExpr, forBody, [], test: nil))
    }

    // MARK: -

    private var isAtEnd: Bool {
        current >= tokens.count || peek().kind == .eof
    }

    private func peek() -> Token {
        guard current < tokens.count else {
            return Token(kind: .eof, value: "", position: current)
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

    private mutating func consume(_ kind: Token.Kind, message: String) throws -> Token {
        if check(kind) { return advance() }
        throw JinjaError.parser("\(message). Got \(peek().kind) instead")
    }

    // MARK: - Node Parsing

    private mutating func parseNode() throws -> Node {
        let token = peek()

        switch token.kind {
        case .text:
            advance()
            return .text(token.value)

        case .expression:
            return try parseExpressionNode(token.value)

        case .statement:
            let content = token.value.trimmingCharacters(in: .whitespaces)
            let firstWord = content.components(separatedBy: .whitespaces).first ?? ""

            // Handle structured control flow statements
            if firstWord == "if" {
                return try parseIfStatement()
            } else if firstWord == "for" {
                return try parseForStatement()
            } else {
                return try parseStatementNode(token.value)
            }

        default:
            throw JinjaError.parser("Unexpected token type: \(token.kind)")
        }
    }

    private mutating func parseExpressionNode(_ content: String) throws -> Node {
        advance()  // consume the expression token

        // Parse the expression content
        let expression = try ExpressionParser.parse(content)

        return .expression(expression)
    }

    private mutating func parseStatementNode(_ content: String) throws -> Node {
        advance()  // consume the statement token

        // Parse the statement content
        let statement = try StatementParser.parse(content)

        return .statement(statement)
    }
}

// MARK: - Expression Parser

private struct ExpressionParser {
    private let content: String
    private let tokens: [String]
    private var current: Int = 0

    init(_ content: String) {
        self.content = content.trimmingCharacters(in: .whitespaces)
        self.tokens = self.content.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        self.current = 0
    }

    static func parse(_ content: String) throws -> Expression {
        var parser = ExpressionParser(content)
        return try parser.parseTernary()
    }

    mutating func parse() throws -> Expression {
        try parseTernary()
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
            if match("==") {
                let right = try parseComparison()
                expr = .binary(.equal, expr, right)
            } else if match("!=") {
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
            if match("<") {
                let right = try parseTerm()
                expr = .binary(.less, expr, right)
            } else if match("<=") {
                let right = try parseTerm()
                expr = .binary(.lessEqual, expr, right)
            } else if match(">") {
                let right = try parseTerm()
                expr = .binary(.greater, expr, right)
            } else if match(">=") {
                let right = try parseTerm()
                expr = .binary(.greaterEqual, expr, right)
            } else if matchKeyword("in") {
                let right = try parseTerm()
                expr = .binary(.`in`, expr, right)
            } else if matchKeyword("not") && peekKeyword("in") {
                advance()  // consume "in"
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
            if match("+") {
                let right = try parseFactor()
                expr = .binary(.add, expr, right)
            } else if match("-") {
                let right = try parseFactor()
                expr = .binary(.subtract, expr, right)
            } else if match("~") {
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
            if match("*") {
                let right = try parseUnary()
                expr = .binary(.multiply, expr, right)
            } else if match("/") {
                let right = try parseUnary()
                expr = .binary(.divide, expr, right)
            } else if match("%") {
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

        if match("-") {
            let expr = try parseUnary()
            return .unary(.minus, expr)
        }

        if match("+") {
            let expr = try parseUnary()
            return .unary(.plus, expr)
        }

        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> Expression {
        var expr = try parsePrimary()

        while true {
            if match(".") {
                let name = consumeIdentifier()
                expr = .member(expr, .identifier(name), computed: false)
            } else if match("[") {
                let index = try parseTernary()
                try consume("]")
                expr = .member(expr, index, computed: true)
            } else if match("(") {
                let (args, kwargs) = try parseArguments()
                try consume(")")
                expr = .call(expr, args, kwargs)
            } else if match("|") {
                let filterName = consumeIdentifier()
                var args: [Expression] = []
                var kwargs: [String: Expression] = [:]

                if match("(") {
                    (args, kwargs) = try parseArguments()
                    try consume(")")
                }

                expr = .filter(expr, filterName, args, kwargs)
            } else if matchKeyword("is") {
                let negated = matchKeyword("not")
                let testName = consumeIdentifier()
                expr = .test(expr, testName, negated: negated)
            } else {
                break
            }
        }

        return expr
    }

    private mutating func parsePrimary() throws -> Expression {
        // String literals
        if let stringValue = parseStringLiteral() {
            return .string(stringValue)
        }

        // Number literals
        if let numberValue = parseNumberLiteral() {
            if numberValue.contains(".") {
                return .number(Double(numberValue) ?? 0.0)
            } else {
                return .integer(Int(numberValue) ?? 0)
            }
        }

        // Boolean literals
        if match("true") {
            return .boolean(true)
        }

        if match("false") {
            return .boolean(false)
        }

        // Null literal
        if match("none") || match("null") {
            return .null
        }

        // Array literal
        if match("[") {
            var elements: [Expression] = []

            if !peek("]") {
                repeat {
                    elements.append(try parseTernary())
                } while match(",")
            }

            try consume("]")
            return .array(elements)
        }

        // Object literal
        if match("{") {
            var pairs: OrderedDictionary<String, Expression> = [:]

            if !peek("}") {
                repeat {
                    let key = consumeString()
                    try consume(":")
                    let value = try parseTernary()
                    pairs[key] = value
                } while match(",")
            }

            try consume("}")
            return .object(pairs)
        }

        // Grouped expression
        if match("(") {
            let expr = try parseTernary()
            try consume(")")
            return expr
        }

        // Identifier
        if isAtEnd || !(current < tokens.count) {
            throw JinjaError.parser("Unexpected end of expression")
        }

        let token = tokens[current]
        advance()
        return .identifier(token)
    }

    private mutating func parseArguments() throws -> ([Expression], [String: Expression]) {
        var args: [Expression] = []
        var kwargs: [String: Expression] = [:]

        if !peek(")") {
            repeat {
                // Check for keyword argument
                if current + 1 < tokens.count && tokens[current + 1] == "=" {
                    let key = consumeIdentifier()
                    try consume("=")
                    let value = try parseTernary()
                    kwargs[key] = value
                } else {
                    let arg = try parseTernary()
                    args.append(arg)
                }
            } while match(",")
        }

        return (args, kwargs)
    }

    // MARK: -

    private var isAtEnd: Bool {
        current >= tokens.count
    }

    private mutating func advance() {
        if !isAtEnd { current += 1 }
    }

    private func peek(_ value: String) -> Bool {
        guard current < tokens.count else { return false }
        return tokens[current] == value
    }

    private mutating func match(_ value: String) -> Bool {
        if peek(value) {
            advance()
            return true
        }
        return false
    }

    private mutating func matchKeyword(_ keyword: String) -> Bool {
        match(keyword)
    }

    private func peekKeyword(_ keyword: String) -> Bool {
        peek(keyword)
    }

    private mutating func consume(_ value: String) throws {
        if !match(value) {
            throw JinjaError.parser(
                "Expected '\(value)' but got '\(current < tokens.count ? tokens[current] : "EOF")'")
        }
    }

    private mutating func consumeIdentifier() -> String {
        guard current < tokens.count else { return "" }
        let token = tokens[current]
        advance()
        return token
    }

    private mutating func consumeString() -> String {
        guard current < tokens.count else { return "" }
        var token = tokens[current]
        advance()

        // Remove quotes if present
        if (token.hasPrefix("\"") && token.hasSuffix("\""))
            || (token.hasPrefix("'") && token.hasSuffix("'"))
        {
            token = String(token.dropFirst().dropLast())
        }

        return token
    }

    private mutating func parseStringLiteral() -> String? {
        guard current < tokens.count else { return nil }
        let token = tokens[current]

        if (token.hasPrefix("\"") && token.hasSuffix("\""))
            || (token.hasPrefix("'") && token.hasSuffix("'"))
        {
            advance()
            return String(token.dropFirst().dropLast())
        }

        return nil
    }

    private mutating func parseNumberLiteral() -> String? {
        guard current < tokens.count else { return nil }
        let token = tokens[current]

        if Double(token) != nil {
            advance()
            return token
        }

        return nil
    }
}

// MARK: - Statement Parser

private struct StatementParser {
    private let content: String
    private let tokens: [String]
    private var current: Int = 0

    init(_ content: String) {
        self.content = content.trimmingCharacters(in: .whitespaces)
        self.tokens = self.content.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        self.current = 0
    }

    static func parse(_ content: String) throws -> Statement {
        var parser = StatementParser(content)
        return try parser.parse()
    }

    mutating func parse() throws -> Statement {
        guard current < tokens.count else {
            throw JinjaError.parser("Empty statement")
        }

        let keyword = tokens[current]
        advance()

        switch keyword {
        case "set":
            return try parseSet()
        case "if":
            return try parseIf()
        case "elif":
            // elif statements should be handled by parseIfStatement, not here
            throw JinjaError.parser(
                "Unexpected elif statement - should be handled in if block parsing")
        case "else", "endif":
            // else and endif statements should be handled as part of if statement parsing
            throw JinjaError.parser(
                "Unexpected \(keyword) statement - should be handled in if block parsing")
        case "for":
            return try parseFor()
        case "endfor":
            // endfor statements should be handled by parseForStatement, not here
            throw JinjaError.parser(
                "Unexpected endfor statement - should be handled in for block parsing")
        case "macro":
            return try parseMacro()
        default:
            throw JinjaError.parser("Unknown statement: \(keyword)")
        }
    }

    private mutating func parseSet() throws -> Statement {
        let identifier = consumeIdentifier()
        try consume("=")

        // Parse the rest as expression
        let exprContent = tokens[current...].joined(separator: " ")
        let expression = try ExpressionParser.parse(exprContent)

        return .set(identifier, expression)
    }

    private mutating func parseIf() throws -> Statement {
        // Parse condition
        let conditionTokens = collectUntilKeyword(["endif", "else", "elif"])
        let conditionContent = conditionTokens.joined(separator: " ")
        let condition = try ExpressionParser.parse(conditionContent)

        // This creates a simple conditional statement for inline usage
        // For structured if/elif/else blocks with bodies, parseIfStatement() is used instead
        return .`if`(condition, [], [])
    }

    private mutating func parseFor() throws -> Statement {
        let loopVar = consumeIdentifier()
        try consume("in")

        let iterableTokens = collectUntilKeyword(["endfor", "if"])
        let iterableContent = iterableTokens.joined(separator: " ")
        let iterable = try ExpressionParser.parse(iterableContent)

        return .for(.single(loopVar), iterable, [], [], test: nil)
    }

    private mutating func parseMacro() throws -> Statement {
        let name = consumeIdentifier()

        // Parse parameters if present
        var params: [String] = []
        if match("(") {
            if !peek(")") {
                repeat {
                    params.append(consumeIdentifier())
                } while match(",")
            }
            try consume(")")
        }

        return .macro(name, params, [])
    }

    // MARK: -

    private var isAtEnd: Bool {
        current >= tokens.count
    }

    private mutating func advance() {
        if !isAtEnd { current += 1 }
    }

    private func peek(_ value: String) -> Bool {
        guard current < tokens.count else { return false }
        return tokens[current] == value
    }

    private mutating func match(_ value: String) -> Bool {
        if peek(value) {
            advance()
            return true
        }
        return false
    }

    private mutating func consume(_ value: String) throws {
        if !match(value) {
            throw JinjaError.parser(
                "Expected '\(value)' but got '\(current < tokens.count ? tokens[current] : "EOF")'")
        }
    }

    private mutating func consumeIdentifier() -> String {
        guard current < tokens.count else { return "" }
        let token = tokens[current]
        advance()
        return token
    }

    private mutating func collectUntilKeyword(_ keywords: [String]) -> [String] {
        var collected: [String] = []

        while current < tokens.count && !keywords.contains(tokens[current]) {
            collected.append(tokens[current])
            advance()
        }

        return collected
    }
}

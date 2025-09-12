import Foundation
import OrderedCollections

// MARK: - AST

/// A node in the abstract syntax tree representing template content.
public indirect enum Node: Sendable, Hashable {
    /// Plain text content to be output directly.
    case text(String)
    /// Expression to be evaluated and output.
    case expression(Expression)
    /// Control flow statement to be executed.
    case statement(Statement)
}

/// An expression that can be evaluated to produce a value.
public indirect enum Expression: Sendable, Hashable {
    /// String literal value.
    case string(String)
    /// Floating-point number literal.
    case number(Double)
    /// Integer literal value.
    case integer(Int)
    /// Boolean literal value.
    case boolean(Bool)
    /// Null literal value.
    case null
    /// Array literal with ordered elements.
    case array([Expression])
    /// Tuple literal with ordered elements.
    case tuple([Expression])
    /// Object literal with key-value pairs.
    case object(OrderedDictionary<String, Expression>)
    /// Variable or function identifier reference.
    case identifier(String)
    /// Binary operation with operator and operands.
    case binary(BinaryOp, Expression, Expression)
    /// Unary operation with operator and operand.
    case unary(UnaryOp, Expression)
    /// Function call with arguments and keyword arguments.
    case call(Expression, [Expression], [String: Expression])
    /// Member access (object.property or object[key]).
    case member(Expression, Expression, computed: Bool)
    /// Array or string slicing operation.
    case slice(Expression, start: Expression?, stop: Expression?, step: Expression?)
    /// Filter application to transform a value.
    case filter(Expression, String, [Expression], [String: Expression])
    /// Test operation to check a condition.
    case test(Expression, String, negated: Bool)
    /// Test operation with arguments (e.g., value is divisibleby(3)).
    case testArgs(Expression, String, [Expression], negated: Bool)
    /// Ternary conditional expression (value if test else alternate).
    case ternary(Expression, test: Expression, alternate: Expression?)
    /// Select expression for conditional evaluation.
    case select(Expression, test: Expression)
}

/// A control flow statement that affects template execution.
public enum Statement: Sendable, Hashable {
    /// Block of nodes to execute sequentially.
    case program([Node])
    /// Variable assignment statement.
    case set(target: Expression, value: Expression?, body: [Node])
    /// Conditional statement with test, body, and optional alternate.
    case `if`(Expression, [Node], [Node])
    /// Loop statement with variable, iterable, body, else block, and optional condition.
    case `for`(LoopVar, Expression, [Node], [Node], test: Expression?)
    /// Macro definition with name, parameters, default values, and body.
    case macro(String, [String], OrderedDictionary<String, Expression>, [Node])
    /// Exits a loop immediately.
    case `break`
    /// Skips the current iteration of a loop.
    case `continue`
    /// Calls a macro with a body.
    case call(callable: Expression, callerArgs: [Expression]?, body: [Node])
    /// Applies a filter to a block of content.
    case filter(filterExpr: Expression, body: [Node])
}

/// Loop variable specification for for-loops.
public enum LoopVar: Sendable, Hashable {
    /// Single loop variable.
    case single(String)
    /// Multiple loop variables for unpacking.
    case tuple([String])
}

/// Binary operators for expressions.
public enum BinaryOp: String, Sendable, Hashable, CaseIterable {
    // MARK: Arithmetic Operators

    /// Addition operator (`+`)
    case add = "+"

    /// Subtraction operator (`-`)
    case subtract = "-"

    /// Multiplication operator (`*`)
    case multiply = "*"

    /// Division operator (`/`)
    case divide = "/"

    /// Modulo operator (`%`)
    case modulo = "%"

    // MARK: String Operators

    /// String concatenation operator (`~`)
    case concat = "~"

    // MARK: Equality Comparison Operators

    /// Equality operator (`==`)
    case equal = "=="

    /// Inequality operator (`!=`)
    case notEqual = "!="

    // MARK: Relational Comparison Operators

    /// Less than operator (`<`)
    case less = "<"

    /// Less than or equal to operator (`<=`)
    case lessEqual = "<="

    /// Greater than operator (`>`)
    case greater = ">"

    /// Greater than or equal to operator (`>=`)
    case greaterEqual = ">="

    // MARK: Logical Operators

    /// Logical AND operator (`and`)
    case and = "and"

    /// Logical OR operator (`or`)
    case or = "or"

    // MARK: Membership Test Operators

    /// Membership test operator (`in`)
    case `in` = "in"

    /// Negated membership test operator (`not in`)
    case notIn = "not in"
}

/// Unary operators for expressions.
public enum UnaryOp: String, Sendable, Hashable, CaseIterable {
    /// Logical negation operator.
    case not = "not"
    /// Numeric negation operator.
    case minus = "-"
    /// Numeric identity operator.
    case plus = "+"
}

// MARK: - Parser

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
            } else if case .text(let text) = node, text.isEmpty {
                // do not add empty text nodes
            } else {
                nodes.append(node)
            }
        }

        return nodes
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
            return .statement(statement)

        default:
            if isAtEnd { return .text("") }
            throw JinjaError.parser("Unexpected token type: \(token.kind)")
        }
    }

    // Parse nodes until we hit one of the specified statement keywords
    private mutating func parseNodesUntil(_ kinds: Set<Token.Kind>) throws -> [Node] {
        var nodes: [Node] = []

        while !isAtEnd {
            if check(.openStatement) {
                let nextToken = tokens[current + 1]
                if kinds.contains(nextToken.kind) {
                    break
                }
            }

            let node = try parseNode()

            if case .text(let newText) = node,
                case .text(let existingText)? = nodes.last
            {
                nodes[nodes.count - 1] = .text(existingText + newText)
            } else {
                nodes.append(node)
            }
        }

        return nodes
    }

    // MARK: - Statement Parsing

    private mutating func parseStatement() throws -> Statement {
        let keywordToken = peek()

        switch keywordToken.kind {
        case .if:
            advance()
            return try parseIfStatement()
        case .for:
            advance()
            return try parseForStatement()
        case .set:
            advance()
            return try parseSetStatement()
        case .macro:
            advance()
            return try parseMacroStatement()
        case .break:
            advance()
            try consume(.closeStatement, message: "Expected '%}' after break.")
            return .break
        case .continue:
            advance()
            try consume(.closeStatement, message: "Expected '%}' after continue.")
            return .continue
        case .call:
            advance()
            return try parseCallStatement()
        case .filter:
            advance()
            return try parseFilterStatement()
        default:
            throw JinjaError.parser("Unknown statement: \(keywordToken.value)")
        }
    }

    private mutating func parseIfStatement() throws -> Statement {
        let condition = try parseExpression()
        try consume(.closeStatement, message: "Expected '%}' after if condition.")
        let body = try parseNodesUntil([.elif, .else, .endif])

        var alternate: [Node] = []

        if match(.openStatement) {
            if peek().kind == .elif {
                advance()
                alternate.append(.statement(try parseIfStatement()))
            } else if peek().kind == .else {
                advance()
                try consume(.closeStatement, message: "Expected '%}' after else.")
                alternate = try parseNodesUntil([.endif])
                try consume(.openStatement, message: "Expected '{%' for endif.")
                try consume(.endif, message: "Expected 'endif'.")
                try consume(.closeStatement, message: "Expected '%}' after endif.")
            } else {
                try consume(.endif, message: "Expected 'endif'.")
                try consume(.closeStatement, message: "Expected '%}' after endif.")
            }
        } else {
            throw JinjaError.parser("Unclosed if statement")
        }

        return .if(condition, body, alternate)
    }

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

        try consume(.in, message: "Expected 'in' in for loop.")

        let iterableExpr = try parseExpression()
        var testExpr: Expression?

        if match(.if) {
            testExpr = try parseExpression()
        }

        try consume(.closeStatement, message: "Expected '%}' after for loop.")

        let body = try parseNodesUntil([.else, .endfor])
        var elseBody: [Node] = []

        if match(.openStatement) {
            if match(.else) {
                try consume(.closeStatement, message: "Expected '%}' after else.")
                elseBody = try parseNodesUntil([.endfor])
                try consume(.openStatement, message: "Expected '{%' for endfor.")
                try consume(.endfor, message: "Expected 'endfor'.")
                try consume(.closeStatement, message: "Expected '%}' after endfor.")
            } else {
                try consume(.endfor, message: "Expected 'endfor'.")
                try consume(.closeStatement, message: "Expected '%}' after endfor.")
            }
        } else {
            throw JinjaError.parser("Unclosed for loop")
        }

        return .for(loopVar, iterableExpr, body, elseBody, test: testExpr)
    }

    private mutating func parseSetStatement() throws -> Statement {
        let target = try parseExpressionSequence()

        if match(.equals) {
            let value = try parseExpressionSequence()
            try consume(.closeStatement, message: "Expected '%}' after set statement.")
            return .set(target: target, value: value, body: [])
        } else {
            try consume(.closeStatement, message: "Expected '%}' after set statement.")
            let body = try parseNodesUntil([.endset])
            try consume(.openStatement, message: "Expected '{%' for endset.")
            try consume(.endset, message: "Expected 'endset'.")
            try consume(.closeStatement, message: "Expected '%}' after endset.")
            return .set(target: target, value: nil, body: body)
        }
    }

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

        let body = try parseNodesUntil([.endmacro])

        try consume(.openStatement, message: "Expected '{%' for endmacro.")
        try consume(.endmacro, message: "Expected 'endmacro'.")
        try consume(.closeStatement, message: "Expected '%}' after endmacro.")

        return .macro(macroName, parameters, defaults, body)
    }

    private mutating func parseCallStatement() throws -> Statement {
        var callerArgs: [Expression]?
        if match(.openParen) {
            let (args, _) = try parseArguments()
            callerArgs = args
            try consume(.closeParen, message: "Expected ')' after caller arguments.")
        }

        let callable = try parseExpression()

        try consume(.closeStatement, message: "Expected '%}' after call statement.")

        let body = try parseNodesUntil([.endcall])

        try consume(.openStatement, message: "Expected '{%' for endcall.")
        try consume(.endcall, message: "Expected 'endcall'.")
        try consume(.closeStatement, message: "Expected '%}' after endcall.")

        return .call(callable: callable, callerArgs: callerArgs, body: body)
    }

    private mutating func parseFilterStatement() throws -> Statement {
        let filterExpr = try parseExpression()

        try consume(.closeStatement, message: "Expected '%}' after filter statement.")

        let body = try parseNodesUntil([.endfilter])

        try consume(.openStatement, message: "Expected '{%' for endfilter.")
        try consume(.endfilter, message: "Expected 'endfilter'.")
        try consume(.closeStatement, message: "Expected '%}' after endfilter.")

        return .filter(filterExpr: filterExpr, body: body)
    }

    // MARK: - Expression Parsing

    private mutating func parseExpression() throws -> Expression {
        return try parseTernary()
    }

    private mutating func parseExpressionSequence() throws -> Expression {
        var expressions: [Expression] = [try parseExpression()]
        while match(.comma) {
            expressions.append(try parseExpression())
        }
        return expressions.count == 1 ? expressions[0] : .tuple(expressions)
    }

    private mutating func parseTernary() throws -> Expression {
        let expr = try parseFilter()

        if match(.if) {
            let test = try parseFilter()
            var alternate: Expression?

            if match(.else) {
                alternate = try parseExpression()
            }

            return .ternary(expr, test: test, alternate: alternate)
        }

        return expr
    }

    private mutating func parseFilter() throws -> Expression {
        var expr = try parseTest()
        while match(.pipe) {
            let filterName = try consumeIdentifier()
            var args: [Expression] = []
            var kwargs: [String: Expression] = [:]

            if match(.openParen) {
                (args, kwargs) = try parseArguments()
                try consume(.closeParen, message: "Expected ')' after filter arguments.")
            }

            expr = .filter(expr, filterName, args, kwargs)
        }
        return expr
    }

    private mutating func parseTest() throws -> Expression {
        var expr = try parseOr()
        if match(.is) {
            let negated = match(.not)
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
        }
        return expr
    }

    private mutating func parseOr() throws -> Expression {
        var expr = try parseAnd()
        while match(.or) {
            let right = try parseAnd()
            expr = .binary(.or, expr, right)
        }
        return expr
    }

    private mutating func parseAnd() throws -> Expression {
        var expr = try parseComparison()
        while match(.and) {
            let right = try parseComparison()
            expr = .binary(.and, expr, right)
        }
        return expr
    }

    private mutating func parseComparison() throws -> Expression {
        var expr = try parseTerm()
        while true {
            if match(.equal) {
                let right = try parseTerm()
                expr = .binary(.equal, expr, right)
            } else if match(.notEqual) {
                let right = try parseTerm()
                expr = .binary(.notEqual, expr, right)
            } else if match(.less) {
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
            } else if match(.in) {
                let right = try parseTerm()
                expr = .binary(.in, expr, right)
            } else if match(.not), match(.in) {
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
        if match(.not) {
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
        return try parseAccess()
    }

    private mutating func parseAccess() throws -> Expression {
        var expr = try parsePrimary()

        while true {
            if match(.dot) {
                let name = try consumeIdentifier()
                expr = .member(expr, .identifier(name), computed: false)
            } else if match(.openBracket) {
                // Slice or subscript
                let start = try? parseExpression()
                if match(.colon) {
                    let stop = try? parseExpression()
                    let step = match(.colon) ? try parseExpression() : nil
                    expr = .slice(expr, start: start, stop: stop, step: step)
                } else if let index = start {
                    expr = .member(expr, index, computed: true)
                } else {
                    throw JinjaError.parser("Invalid subscript")
                }
                try consume(.closeBracket, message: "Expected ']' after index.")
            } else if match(.openParen) {
                let (args, kwargs) = try parseArguments()
                try consume(.closeParen, message: "Expected ')' after arguments.")
                expr = .call(expr, args, kwargs)
            } else {
                break
            }
        }

        return expr
    }

    private mutating func parsePrimary() throws -> Expression {
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
        case .identifier:
            advance()
            return .identifier(token.value)
        default:
            throw JinjaError.parser("Unexpected token for primary expression: \(token.kind)")
        }
    }

    private mutating func parseArguments() throws -> ([Expression], [String: Expression]) {
        var args: [Expression] = []
        var kwargs: [String: Expression] = [:]

        if !check(.closeParen) {
            repeat {
                // Look ahead for keyword argument
                if let key = try? peekIdentifier(), tokens[current + 1].kind == .equals {
                    advance()  // consume identifier
                    advance()  // consume equals
                    let value = try parseExpression()
                    kwargs[key] = value
                } else {
                    args.append(try parseExpression())
                }
            } while match(.comma)
        }

        return (args, kwargs)
    }

    // MARK: - Helpers

    private var isAtEnd: Bool {
        current >= tokens.count || peek().kind == .eof
    }

    private func peek() -> Token {
        guard current < tokens.count else {
            return Token(kind: .eof, value: "", position: tokens.last?.position ?? 0)
        }
        return tokens[current]
    }

    private func peekIdentifier() throws -> String {
        let token = peek()
        guard token.kind == .identifier else {
            throw JinjaError.parser("Expected identifier")
        }
        return token.value
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

    @discardableResult
    private mutating func consumeIdentifier(_ name: String? = nil) throws -> String {
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
}

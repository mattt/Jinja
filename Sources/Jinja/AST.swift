import Foundation
@_exported import OrderedCollections

public indirect enum Node: Sendable {
    case text(String)
    case expression(Expression)
    case statement(Statement)
}

public indirect enum Expression: Sendable {
    // Literals
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case null
    case array([Expression])
    case tuple([Expression])
    case object(OrderedDictionary<String, Expression>)

    // Operations
    case identifier(String)
    case binary(BinaryOp, Expression, Expression)
    case unary(UnaryOp, Expression)
    case call(Expression, [Expression], [String: Expression])  // callee, args, kwargs
    case member(Expression, Expression, computed: Bool)
    case slice(Expression, start: Expression?, stop: Expression?, step: Expression?)
    case filter(Expression, String, [Expression], [String: Expression])  // operand, filter, args, kwargs
    case test(Expression, String, negated: Bool)
    case ternary(Expression, test: Expression, alternate: Expression?)
    case select(Expression, test: Expression)
}

public enum Statement: Sendable {
    case program([Node])
    case set(String, Expression)
    case `if`(Expression, [Node], [Node])  // test, body, alternate
    case `for`(LoopVar, Expression, [Node], [Node], test: Expression?)  // var, iterable, body, else, condition
    case macro(String, [String], [Node])  // name, args, body
}

public enum LoopVar: Sendable {
    case single(String)
    case tuple([String])
}

public enum BinaryOp: String, Sendable {
    case add = "+", subtract = "-", multiply = "*", divide = "/", modulo = "%"
    case concat = "~"
    case equal = "==", notEqual = "!="
    case less = "<", lessEqual = "<=", greater = ">", greaterEqual = ">="
    case and = "and", or = "or"
    case `in` = "in", notIn = "not in"
}

public enum UnaryOp: String, Sendable {
    case not = "not"
    case minus = "-"
    case plus = "+"
}

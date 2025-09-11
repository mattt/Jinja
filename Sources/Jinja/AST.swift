import Foundation
@_exported import OrderedCollections

/// A node in the abstract syntax tree representing template content.
public indirect enum Node: Sendable {
    /// Plain text content to be output directly.
    case text(String)
    /// Expression to be evaluated and output.
    case expression(Expression)
    /// Control flow statement to be executed.
    case statement(Statement)
}

/// An expression that can be evaluated to produce a value.
public indirect enum Expression: Sendable {
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
    /// Ternary conditional expression (value if test else alternate).
    case ternary(Expression, test: Expression, alternate: Expression?)
    /// Select expression for conditional evaluation.
    case select(Expression, test: Expression)
}

/// A control flow statement that affects template execution.
public enum Statement: Sendable {
    /// Block of nodes to execute sequentially.
    case program([Node])
    /// Variable assignment statement.
    case set(String, Expression)
    /// Conditional statement with test, body, and optional alternate.
    case `if`(Expression, [Node], [Node])
    /// Loop statement with variable, iterable, body, else block, and optional condition.
    case `for`(LoopVar, Expression, [Node], [Node], test: Expression?)
    /// Macro definition with name, parameters, and body.
    case macro(String, [String], [Node])
}

/// Loop variable specification for for-loops.
public enum LoopVar: Sendable {
    /// Single loop variable.
    case single(String)
    /// Multiple loop variables for unpacking.
    case tuple([String])
}

/// Binary operators for expressions.
public enum BinaryOp: String, Sendable {
    /// Arithmetic operators.
    case add = "+", subtract = "-", multiply = "*", divide = "/", modulo = "%"
    /// String concatenation operator.
    case concat = "~"
    /// Equality comparison operators.
    case equal = "==", notEqual = "!="
    /// Relational comparison operators.
    case less = "<", lessEqual = "<=", greater = ">", greaterEqual = ">="
    /// Logical operators.
    case and = "and", or = "or"
    /// Membership test operators.
    case `in` = "in", notIn = "not in"
}

/// Unary operators for expressions.
public enum UnaryOp: String, Sendable {
    /// Logical negation operator.
    case not = "not"
    /// Numeric negation operator.
    case minus = "-"
    /// Numeric identity operator.
    case plus = "+"
}

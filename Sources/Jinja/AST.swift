import Foundation
@_exported import OrderedCollections

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

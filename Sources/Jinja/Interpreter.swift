import Foundation

/// Executes parsed Jinja template nodes to produce rendered output.
public enum Interpreter {
    private struct Buffer: TextOutputStream {
        var parts: [String] = []

        init() {
            parts.reserveCapacity(64)  // Typical template has many small parts
        }

        mutating func write(_ string: String) {
            parts.append(string)
        }

        func build() -> String {
            parts.joined()
        }
    }

    // Built-in filters
    private static let filters: [String: @Sendable ([Value]) async throws -> Value] = [
        "upper": { values in
            guard case let .string(str) = values.first else {
                throw JinjaError.runtime("upper filter requires string")
            }
            return .string(str.uppercased())
        },

        "lower": { values in
            guard case let .string(str) = values.first else {
                throw JinjaError.runtime("lower filter requires string")
            }
            return .string(str.lowercased())
        },

        "length": { values in
            switch values.first {
            case let .string(str):
                return .integer(str.count)
            case let .array(arr):
                return .integer(arr.count)
            case let .object(obj):
                return .integer(obj.count)
            default:
                throw JinjaError.runtime("length filter requires string, array, or object")
            }
        },

        "join": { values in
            guard values.count >= 2,
                case let .array(array) = values[0],
                case let .string(separator) = values[1]
            else {
                throw JinjaError.runtime("join filter requires array and separator")
            }

            let strings = array.map { $0.description }
            return .string(strings.joined(separator: separator))
        },

        "default": { values in
            guard values.count >= 2 else {
                throw JinjaError.runtime("default filter requires at least 2 arguments")
            }

            let value = values[0]
            let defaultValue = values[1]

            switch value {
            case .null, .undefined:
                return defaultValue
            case let .string(str) where str.isEmpty:
                return defaultValue
            case let .array(arr) where arr.isEmpty:
                return defaultValue
            case let .object(obj) where obj.isEmpty:
                return defaultValue
            default:
                return value
            }
        },
    ]

    // Built-in tests
    private static let tests: [String: @Sendable ([Value]) async throws -> Bool] = [
        "defined": { values in
            guard let value = values.first else { return false }
            return value != .undefined
        },

        "undefined": { values in
            guard let value = values.first else { return true }
            return value == .undefined
        },

        "none": { values in
            guard let value = values.first else { return false }
            return value == .null
        },

        "string": { values in
            guard let value = values.first else { return false }
            return value.isString
        },

        "number": { values in
            guard let value = values.first else { return false }
            return value.isNumber
        },

        "boolean": { values in
            guard let value = values.first else { return false }
            return value.isBoolean
        },

        "iterable": { values in
            guard let value = values.first else { return false }
            return value.isIterable
        },
    ]

    /// Interprets nodes and renders them to a string using the given environment.
    public static func interpret(_ nodes: [Node], environment: Environment) throws -> String {
        // Use the fast path with synchronous environment
        let env = environment.snapshot()
        var buffer = Buffer()
        try interpret(nodes, env: env, into: &buffer)
        return buffer.build()
    }

    /// High-performance synchronous interpreter using Environment
    private static func interpret(_ nodes: [Node], env: Environment, into buffer: inout Buffer)
        throws
    {
        for node in nodes {
            try interpretNode(node, env: env, into: &buffer)
        }
    }

    /// High-performance synchronous node interpretation
    private static func interpretNode(_ node: Node, env: Environment, into buffer: inout Buffer)
        throws
    {
        switch node {
        case let .text(content):
            buffer.write(content)

        case let .expression(expr):
            let value = try evaluateExpression(expr, env: env)
            buffer.write(value.description)

        case let .statement(stmt):
            try executeStatementWithOutput(stmt, env: env, into: &buffer)
        }
    }

    /// Evaluates an expression in the given environment and returns its value.
    static func evaluateExpression(_ expr: Expression, env: Environment) throws -> Value {
        switch expr {
        case let .string(value):
            return .string(value)

        case let .number(value):
            return .number(value)

        case let .integer(value):
            return .integer(value)

        case let .boolean(value):
            return .boolean(value)

        case .null:
            return .null

        case let .array(elements):
            var values: [Value] = []
            values.reserveCapacity(elements.count)
            for element in elements {
                let value = try evaluateExpression(element, env: env)
                values.append(value)
            }
            return .array(values)

        case let .object(pairs):
            var dict: OrderedDictionary<String, Value> = [:]
            for (key, expr) in pairs {
                let value = try evaluateExpression(expr, env: env)
                dict[key] = value
            }
            return .object(dict)

        case let .identifier(name):
            return env.get(name)

        case let .binary(op, left, right):
            let leftValue = try evaluateExpression(left, env: env)
            let rightValue = try evaluateExpression(right, env: env)
            return try evaluateBinaryValues(op, leftValue, rightValue)

        case let .unary(op, operand):
            let value = try evaluateExpression(operand, env: env)
            return try evaluateUnaryValue(op, value)

        case let .member(object, property, computed):
            let objectValue = try evaluateExpression(object, env: env)

            if computed {
                let propertyValue = try evaluateExpression(property, env: env)
                return try evaluateComputedMember(objectValue, propertyValue)
            } else {
                guard case let .identifier(propertyName) = property else {
                    throw JinjaError.runtime("Property access requires identifier")
                }
                return try evaluatePropertyMember(objectValue, propertyName)
            }

        case let .filter(operand, filterName, args, _):
            let operandValue = try evaluateExpression(operand, env: env)
            var argValues = [operandValue]
            for arg in args {
                let value = try evaluateExpression(arg, env: env)
                argValues.append(value)
            }
            return try evaluateFilter(filterName, argValues)

        case let .ternary(value, test, alternate):
            let testValue = try evaluateExpression(test, env: env)
            if testValue.isTruthy {
                return try evaluateExpression(value, env: env)
            } else if let alternate = alternate {
                return try evaluateExpression(alternate, env: env)
            } else {
                return .null
            }

        default:
            throw JinjaError.runtime("Unimplemented expression type")
        }
    }

    /// Synchronous statement execution with output
    private static func executeStatementWithOutput(
        _ statement: Statement, env: Environment, into buffer: inout Buffer
    )
        throws
    {
        switch statement {
        case let .`if`(test, body, alternate):
            let testValue = try evaluateExpression(test, env: env)
            let nodesToExecute = testValue.isTruthy ? body : alternate

            for node in nodesToExecute {
                try interpretNode(node, env: env, into: &buffer)
            }

        case let .for(loopVar, iterable, body, elseBody, _):
            let iterableValue = try evaluateExpression(iterable, env: env)

            switch iterableValue {
            case let .array(items):
                if items.isEmpty {
                    // Execute else block
                    for node in elseBody {
                        try interpretNode(node, env: env, into: &buffer)
                    }
                } else {
                    let childEnv = Environment(parent: env)
                    for (index, item) in items.enumerated() {
                        // Set loop variables
                        switch loopVar {
                        case let .single(varName):
                            childEnv.set(varName, value: item)
                        case let .tuple(varNames):
                            if case let .array(tupleItems) = item {
                                for (i, varName) in varNames.enumerated() {
                                    let value = i < tupleItems.count ? tupleItems[i] : .undefined
                                    childEnv.set(varName, value: value)
                                }
                            }
                        }

                        // Set loop context variables
                        childEnv.set(
                            "loop",
                            value: .object([
                                "index": .integer(index + 1),
                                "index0": .integer(index),
                                "first": .boolean(index == 0),
                                "last": .boolean(index == items.count - 1),
                                "length": .integer(items.count),
                            ])
                        )

                        // Execute body
                        for node in body {
                            try interpretNode(node, env: childEnv, into: &buffer)
                        }
                    }
                }

            default:
                throw JinjaError.runtime("Cannot iterate over non-iterable value")
            }

        default:
            throw JinjaError.runtime("Unimplemented statement type")
        }
    }

    // MARK: - Synchronous Helper Methods for Environment

    private static func evaluateBinaryValues(_ op: BinaryOp, _ left: Value, _ right: Value) throws
        -> Value
    {
        switch op {
        case .add:
            return try addValues(left, right)
        case .subtract:
            return try subtractValues(left, right)
        case .multiply:
            return try multiplyValues(left, right)
        case .divide:
            return try divideValues(left, right)
        case .modulo:
            return try moduloValues(left, right)
        case .concat:
            return .string(left.description + right.description)
        case .equal:
            return .boolean(valuesEqual(left, right))
        case .notEqual:
            return .boolean(!valuesEqual(left, right))
        case .less:
            return .boolean(try compareValues(left, right) < 0)
        case .lessEqual:
            return .boolean(try compareValues(left, right) <= 0)
        case .greater:
            return .boolean(try compareValues(left, right) > 0)
        case .greaterEqual:
            return .boolean(try compareValues(left, right) >= 0)
        case .and:
            return .boolean(left.isTruthy && right.isTruthy)
        case .or:
            return .boolean(left.isTruthy || right.isTruthy)
        case .`in`:
            return .boolean(try valueInCollection(left, right))
        case .notIn:
            return .boolean(!(try valueInCollection(left, right)))
        }
    }

    private static func evaluateUnaryValue(_ op: UnaryOp, _ value: Value) throws -> Value {
        switch op {
        case .not:
            return .boolean(!value.isTruthy)
        case .minus:
            switch value {
            case let .number(n):
                return .number(-n)
            case let .integer(i):
                return .integer(-i)
            default:
                throw JinjaError.runtime("Cannot negate non-numeric value")
            }
        case .plus:
            switch value {
            case .number, .integer:
                return value
            default:
                throw JinjaError.runtime("Cannot apply unary plus to non-numeric value")
            }
        }
    }

    private static func evaluateComputedMember(_ object: Value, _ property: Value) throws -> Value {
        switch (object, property) {
        case let (.array(arr), .integer(index)):
            let safeIndex = index < 0 ? arr.count + index : index
            guard safeIndex >= 0 && safeIndex < arr.count else {
                return .undefined
            }
            return arr[safeIndex]

        case let (.object(obj), .string(key)):
            return obj[key] ?? .undefined

        case let (.string(str), .integer(index)):
            let safeIndex = index < 0 ? str.count + index : index
            guard safeIndex >= 0 && safeIndex < str.count else {
                return .undefined
            }
            let char = str[str.index(str.startIndex, offsetBy: safeIndex)]
            return .string(String(char))

        default:
            return .undefined
        }
    }

    private static func evaluatePropertyMember(_ object: Value, _ propertyName: String) throws
        -> Value
    {
        switch object {
        case let .object(obj):
            return obj[propertyName] ?? .undefined
        default:
            return .undefined
        }
    }

    private static func evaluateFilter(_ filterName: String, _ argValues: [Value]) throws -> Value {
        // Inline the most common filters for performance
        switch filterName {
        case "upper":
            guard case let .string(str) = argValues.first else {
                throw JinjaError.runtime("upper filter requires string")
            }
            return .string(str.uppercased())

        case "lower":
            guard case let .string(str) = argValues.first else {
                throw JinjaError.runtime("lower filter requires string")
            }
            return .string(str.lowercased())

        case "length":
            switch argValues.first {
            case let .string(str):
                return .integer(str.count)
            case let .array(arr):
                return .integer(arr.count)
            case let .object(obj):
                return .integer(obj.count)
            default:
                throw JinjaError.runtime("length filter requires string, array, or object")
            }

        case "join":
            guard argValues.count >= 2,
                case let .array(array) = argValues[0],
                case let .string(separator) = argValues[1]
            else {
                throw JinjaError.runtime("join filter requires array and separator")
            }

            let strings = array.map { $0.description }
            return .string(strings.joined(separator: separator))

        case "default":
            guard argValues.count >= 2 else {
                throw JinjaError.runtime("default filter requires at least 2 arguments")
            }

            let value = argValues[0]
            let defaultValue = argValues[1]

            switch value {
            case .null, .undefined:
                return defaultValue
            case let .string(str) where str.isEmpty:
                return defaultValue
            case let .array(arr) where arr.isEmpty:
                return defaultValue
            case let .object(obj) where obj.isEmpty:
                return defaultValue
            default:
                return value
            }

        default:
            throw JinjaError.runtime("Unknown filter: \(filterName)")
        }
    }

    // MARK: - Helper Methods

    private static func addValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            return .integer(a + b)
        case let (.number(a), .number(b)):
            return .number(a + b)
        case let (.integer(a), .number(b)):
            return .number(Double(a) + b)
        case let (.number(a), .integer(b)):
            return .number(a + Double(b))
        case let (.string(a), .string(b)):
            return .string(a + b)
        case let (.array(a), .array(b)):
            return .array(a + b)
        default:
            throw JinjaError.runtime("Cannot add values of different types")
        }
    }

    private static func subtractValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            return .integer(a - b)
        case let (.number(a), .number(b)):
            return .number(a - b)
        case let (.integer(a), .number(b)):
            return .number(Double(a) - b)
        case let (.number(a), .integer(b)):
            return .number(a - Double(b))
        default:
            throw JinjaError.runtime("Cannot subtract non-numeric values")
        }
    }

    private static func multiplyValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            return .integer(a * b)
        case let (.number(a), .number(b)):
            return .number(a * b)
        case let (.integer(a), .number(b)):
            return .number(Double(a) * b)
        case let (.number(a), .integer(b)):
            return .number(a * Double(b))
        case let (.string(s), .integer(n)):
            return .string(String(repeating: s, count: n))
        case let (.integer(n), .string(s)):
            return .string(String(repeating: s, count: n))
        default:
            throw JinjaError.runtime("Cannot multiply values of these types")
        }
    }

    private static func divideValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .number(Double(a) / Double(b))
        case let (.number(a), .number(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .number(a / b)
        case let (.integer(a), .number(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .number(Double(a) / b)
        case let (.number(a), .integer(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .number(a / Double(b))
        default:
            throw JinjaError.runtime("Cannot divide non-numeric values")
        }
    }

    private static func moduloValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            guard b != 0 else { throw JinjaError.runtime("Modulo by zero") }
            return .integer(a % b)
        default:
            throw JinjaError.runtime("Modulo operation requires integers")
        }
    }

    private static func compareValues(_ left: Value, _ right: Value) throws -> Int {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            return a < b ? -1 : a > b ? 1 : 0
        case let (.number(a), .number(b)):
            return a < b ? -1 : a > b ? 1 : 0
        case let (.string(a), .string(b)):
            return a < b ? -1 : a > b ? 1 : 0
        default:
            throw JinjaError.runtime("Cannot compare values of different types")
        }
    }

    private static func valuesEqual(_ left: Value, _ right: Value) -> Bool {
        switch (left, right) {
        case let (.string(a), .string(b)):
            return a == b
        case let (.integer(a), .integer(b)):
            return a == b
        case let (.number(a), .number(b)):
            return a == b
        case let (.boolean(a), .boolean(b)):
            return a == b
        case (.null, .null):
            return true
        case (.undefined, .undefined):
            return true
        default:
            return false
        }
    }

    private static func valueInCollection(_ value: Value, _ collection: Value) throws -> Bool {
        switch collection {
        case let .array(items):
            return items.contains { valuesEqual(value, $0) }
        case let .string(str):
            guard case let .string(substr) = value else { return false }
            return str.contains(substr)
        case let .object(dict):
            guard case let .string(key) = value else { return false }
            return dict.keys.contains(key)
        default:
            throw JinjaError.runtime("'in' operator requires iterable on right side")
        }
    }
}

// MARK: - Value Extensions

extension Value {

}

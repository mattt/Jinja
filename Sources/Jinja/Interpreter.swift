import Foundation
@_exported import OrderedCollections

// MARK: - Context

/// A context is a dictionary of variables and their values.
public typealias Context = [String: Value]

private let builtinValues: Context = [
    "true": true,
    "false": false,
    "True": true,
    "False": false,
    "none": .null,
    "range": .function { values in
        guard !values.isEmpty else { return .array([]) }

        switch values.count {
        case 1:
            if case let .integer(end) = values[0] {
                return .array((0..<end).map { .integer($0) })
            }
        case 2:
            if case let .integer(start) = values[0],
                case let .integer(end) = values[1]
            {
                return .array((start..<end).map { .integer($0) })
            }
        case 3:
            if case let .integer(start) = values[0],
                case let .integer(end) = values[1],
                case let .integer(step) = values[2]
            {
                return .array(stride(from: start, to: end, by: step).map { .integer($0) })
            }
        default:
            break
        }

        throw JinjaError.runtime("Invalid arguments to range function")
    },
]

// MARK: - Environment

/// Execution environment that stores variables and provides context for template rendering.
public final class Environment: @unchecked Sendable {
    private(set) var variables: [String: Value] = [:]
    private let parent: Environment?
    // Store macro definitions by name for invocation
    struct MacroDef {
        let name: String
        let parameters: [String]
        let defaults: OrderedDictionary<String, Expression>
        let body: [Node]
    }
    var macros: [String: MacroDef] = [:]

    /// Creates a new environment with optional parent and initial variables.
    /// - Parameters:
    ///   - parent: The parent environment
    ///   - initial: The initial variables
    public init(parent: Environment? = nil, initial: [String: Value] = [:]) {
        self.parent = parent
        self.variables = initial

        // Initialize built-in variables if this is a root environment
        if parent == nil {
            variables.merge(builtinValues) { _, new in new }
        }
    }

    /// A subscript to get and set variables in the environment.
    public subscript(name: String) -> Value {
        get {
            if let value = variables[name] {
                return value
            }

            // Check parent environment
            if let parent = parent {
                return parent[name]
            }

            return .undefined
        }
        set {
            variables[name] = newValue
        }
    }
}

// MARK: - Interpreter

/// Executes parsed Jinja template nodes to produce rendered output.
public enum Interpreter {
    /// Buffer for accumulating rendered output.
    private struct Buffer: TextOutputStream {
        var parts: [String] = []

        init() {
            parts.reserveCapacity(128)
        }

        mutating func write(_ string: String) {
            parts.append(string)
        }

        func build() -> String {
            parts.joined()
        }
    }

    /// Built-in filters
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

    /// Built-in tests
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
        let env = Environment(initial: environment.variables)
        var buffer = Buffer()
        try interpret(nodes, env: env, into: &buffer)
        return buffer.build()
    }

    private static func interpret(_ nodes: [Node], env: Environment, into buffer: inout Buffer)
        throws
    {
        for node in nodes {
            try interpretNode(node, env: env, into: &buffer)
        }
    }

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

    private static func evaluateExpression(_ expr: Expression, env: Environment) throws -> Value {
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
            return env[name]

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

        case let .filter(operand, filterName, args, kwargs):
            let operandValue = try evaluateExpression(operand, env: env)
            var argValues = [operandValue]
            for arg in args {
                let value = try evaluateExpression(arg, env: env)
                argValues.append(value)
            }
            var kwargValues: [String: Value] = [:]
            for (key, expr) in kwargs {
                kwargValues[key] = try evaluateExpression(expr, env: env)
            }
            return try evaluateFilter(filterName, argValues, kwargs: kwargValues, env: env)

        case let .ternary(value, test, alternate):
            let testValue = try evaluateExpression(test, env: env)
            if testValue.isTruthy {
                return try evaluateExpression(value, env: env)
            } else if let alternate = alternate {
                return try evaluateExpression(alternate, env: env)
            } else {
                return .null
            }

        case let .test(operand, testName, negated):
            let operandValue = try evaluateExpression(operand, env: env)
            let result = try evaluateTest(testName, [operandValue], env: env)
            return .boolean(negated ? !result : result)

        case let .testArgs(operand, testName, args, negated):
            let operandValue = try evaluateExpression(operand, env: env)
            var argValues: [Value] = [operandValue]
            for arg in args {
                argValues.append(try evaluateExpression(arg, env: env))
            }
            let result = try evaluateTest(testName, argValues, env: env)
            return .boolean(negated ? !result : result)

        case let .call(function, args, kwargs):
            let functionValue = try evaluateExpression(function, env: env)
            guard case let .function(fn) = functionValue else {
                throw JinjaError.runtime("Cannot call non-function value")
            }

            var argValues: [Value] = []
            for arg in args {
                argValues.append(try evaluateExpression(arg, env: env))
            }

            // Merge kwargs by appending their values after positional arguments
            for (_, expr) in kwargs {
                argValues.append(try evaluateExpression(expr, env: env))
            }

            return try fn(argValues)

        case let .slice(array, start, stop, step):
            let arrayValue = try evaluateExpression(array, env: env)
            guard case let .array(items) = arrayValue else {
                throw JinjaError.runtime("Slice requires array")
            }

            let startIdx: Value? = try start.map { try evaluateExpression($0, env: env) }
            let stopIdx: Value? = try stop.map { try evaluateExpression($0, env: env) }
            let stepVal: Value? = try step.map { try evaluateExpression($0, env: env) }

            // Simple slice implementation
            var sliceStart = 0
            var sliceEnd = items.count
            var sliceStep = 1

            if let startValue = startIdx, case let .integer(s) = startValue {
                sliceStart = s
            }
            if let stopValue = stopIdx, case let .integer(e) = stopValue {
                sliceEnd = e
            }
            if let stepValue = stepVal, case let .integer(st) = stepValue {
                sliceStep = st
            }

            let result = stride(from: sliceStart, to: sliceEnd, by: sliceStep).compactMap { idx in
                idx >= 0 && idx < items.count ? items[idx] : nil
            }

            return .array(result)

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

        case let .for(loopVar, iterable, body, elseBody, test):
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
                            childEnv[varName] = item
                        case let .tuple(varNames):
                            if case let .array(tupleItems) = item {
                                for (i, varName) in varNames.enumerated() {
                                    let value = i < tupleItems.count ? tupleItems[i] : .undefined
                                    childEnv[varName] = value
                                }
                            }
                        }

                        // Set loop context variables
                        let loopContext: OrderedDictionary<String, Value> = [
                            "index": .integer(index + 1),
                            "index0": .integer(index),
                            "first": .boolean(index == 0),
                            "last": .boolean(index == items.count - 1),
                            "length": .integer(items.count),
                            "revindex": .integer(items.count - index),
                            "revindex0": .integer(items.count - index - 1),
                        ]

                        // Add cycle function
                        let cycleFunction: @Sendable ([Value]) throws -> Value = { cycleArgs in
                            guard !cycleArgs.isEmpty else { return .string("") }
                            let cycleIndex = index % cycleArgs.count
                            return cycleArgs[cycleIndex]
                        }

                        var loopObj = loopContext
                        loopObj["cycle"] = .function(cycleFunction)
                        childEnv["loop"] = .object(loopObj)

                        // Optional inline test filter for the loop
                        if let test = test {
                            let testValue = try evaluateExpression(test, env: childEnv)
                            if !testValue.isTruthy { continue }
                        }

                        // Execute body
                        for node in body {
                            try interpretNode(node, env: childEnv, into: &buffer)
                        }
                    }
                }

            case let .object(dict):
                // Iterate over object as array of [key, value]
                let items = dict.map { key, value in Value.array([.string(key), value]) }
                if items.isEmpty {
                    for node in elseBody { try interpretNode(node, env: env, into: &buffer) }
                } else {
                    let childEnv = Environment(parent: env)
                    for (index, item) in items.enumerated() {
                        switch loopVar {
                        case let .single(varName):
                            childEnv[varName] = item
                        case let .tuple(varNames):
                            if case let .array(tupleItems) = item {
                                for (i, varName) in varNames.enumerated() {
                                    let value = i < tupleItems.count ? tupleItems[i] : .undefined
                                    childEnv[varName] = value
                                }
                            }
                        }
                        let loopContext: OrderedDictionary<String, Value> = [
                            "index": .integer(index + 1),
                            "index0": .integer(index),
                            "first": .boolean(index == 0),
                            "last": .boolean(index == items.count - 1),
                            "length": .integer(items.count),
                            "revindex": .integer(items.count - index),
                            "revindex0": .integer(items.count - index - 1),
                        ]
                        var loopObj = loopContext
                        loopObj["cycle"] = .function { args in
                            guard !args.isEmpty else { return .string("") }
                            let cycleIndex = index % args.count
                            return args[cycleIndex]
                        }
                        childEnv["loop"] = .object(loopObj)
                        if let test = test {
                            let testValue = try evaluateExpression(test, env: childEnv)
                            if !testValue.isTruthy { continue }
                        }
                        for node in body { try interpretNode(node, env: childEnv, into: &buffer) }
                    }
                }
            case let .string(str):
                let chars = str.map { Value.string(String($0)) }
                if chars.isEmpty {
                    for node in elseBody { try interpretNode(node, env: env, into: &buffer) }
                } else {
                    let childEnv = Environment(parent: env)
                    for (index, item) in chars.enumerated() {
                        switch loopVar {
                        case let .single(varName):
                            childEnv[varName] = item
                        case let .tuple(varNames):
                            for (i, varName) in varNames.enumerated() {
                                childEnv[varName] = i == 0 ? item : .undefined
                            }
                        }
                        let loopContext: OrderedDictionary<String, Value> = [
                            "index": .integer(index + 1),
                            "index0": .integer(index),
                            "first": .boolean(index == 0),
                            "last": .boolean(index == chars.count - 1),
                            "length": .integer(chars.count),
                            "revindex": .integer(chars.count - index),
                            "revindex0": .integer(chars.count - index - 1),
                        ]
                        var loopObj = loopContext
                        loopObj["cycle"] = .function { args in
                            guard !args.isEmpty else { return .string("") }
                            let cycleIndex = index % args.count
                            return args[cycleIndex]
                        }
                        childEnv["loop"] = .object(loopObj)
                        if let test = test {
                            let testValue = try evaluateExpression(test, env: childEnv)
                            if !testValue.isTruthy { continue }
                        }
                        for node in body { try interpretNode(node, env: childEnv, into: &buffer) }
                    }
                }
            default:
                throw JinjaError.runtime("Cannot iterate over non-iterable value")
            }

        case let .set(target, value, body):
            if let valueExpr = value {
                let evaluatedValue = try evaluateExpression(valueExpr, env: env)
                try assign(target: target, value: evaluatedValue, env: env)
            } else {
                var bodyBuffer = Buffer()
                try interpret(body, env: env, into: &bodyBuffer)
                let renderedBody = bodyBuffer.build()
                let valueToAssign = Value.string(renderedBody)
                try assign(target: target, value: valueToAssign, env: env)
            }

        case let .macro(name, parameters, defaults, body):
            // Record macro definition in environment
            env.macros[name] = Environment.MacroDef(
                name: name, parameters: parameters, defaults: defaults, body: body)
            // Expose as callable function too
            env[name] = .function { passedArgs in
                let macroEnv = Environment(parent: env)
                // Start with defaults
                for (key, expr) in defaults {
                    // Evaluate defaults in current env
                    let val = try evaluateExpression(expr, env: env)
                    macroEnv[key] = val
                }
                // Bind positional args
                for (index, paramName) in parameters.enumerated() {
                    let value = index < passedArgs.count ? passedArgs[index] : macroEnv[paramName]
                    macroEnv[paramName] = value
                }
                var macroBuffer = Buffer()
                try interpret(body, env: macroEnv, into: &macroBuffer)
                return .string(macroBuffer.build())
            }

        case let .program(nodes):
            try interpret(nodes, env: env, into: &buffer)

        case let .call(callable, callerArgs, body):
            guard let callableValue = try? evaluateExpression(callable, env: env),
                case .function(let function) = callableValue
            else {
                throw JinjaError.runtime("Cannot call non-function value")
            }

            var bodyBuffer = Buffer()
            try interpret(body, env: env, into: &bodyBuffer)
            let renderedBody = bodyBuffer.build()

            var finalArgs = callerArgs?.compactMap { try? evaluateExpression($0, env: env) } ?? []
            finalArgs.append(.string(renderedBody))

            let result = try function(finalArgs)
            buffer.write(result.description)

        case let .filter(filterExpr, body):
            var bodyBuffer = Buffer()
            try interpret(body, env: env, into: &bodyBuffer)
            let renderedBody = bodyBuffer.build()

            if case let .filter(_, name, args, _) = filterExpr {
                var filterArgs = [Value.string(renderedBody)]
                filterArgs.append(contentsOf: try args.map { try evaluateExpression($0, env: env) })
                // TODO: Handle kwargs in filters if necessary
                let filteredValue = try evaluateFilter(name, filterArgs, kwargs: [:], env: env)
                buffer.write(filteredValue.description)
            } else if case let .identifier(name) = filterExpr {
                let filteredValue = try evaluateFilter(
                    name, [.string(renderedBody)], kwargs: [:], env: env)
                buffer.write(filteredValue.description)
            } else {
                throw JinjaError.runtime("Invalid filter expression in filter statement")
            }

        case .break, .continue:
            // These are handled by executeStatementWithControlFlow, this path shouldn't be hit.
            throw JinjaError.runtime("Unexpected statement type for executeStatementWithOutput")
        }
    }

    private static func executeStatement(_ statement: Statement, env: Environment) throws {
        switch statement {
        case let .set(target, value, body):
            if let valueExpr = value {
                let evaluatedValue = try evaluateExpression(valueExpr, env: env)
                try assign(target: target, value: evaluatedValue, env: env)
            } else {
                var bodyBuffer = Buffer()
                try interpret(body, env: env, into: &bodyBuffer)
                let renderedBody = bodyBuffer.build()
                let valueToAssign = Value.string(renderedBody)
                try assign(target: target, value: valueToAssign, env: env)
            }

        case let .macro(name, parameters, defaults, body):
            // Record macro definition in environment
            env.macros[name] = Environment.MacroDef(
                name: name, parameters: parameters, defaults: defaults, body: body)
            // Expose as callable function too
            env[name] = .function { passedArgs in
                let macroEnv = Environment(parent: env)
                // Start with defaults
                for (key, expr) in defaults {
                    // Evaluate defaults in current env
                    let val = try evaluateExpression(expr, env: env)
                    macroEnv[key] = val
                }
                // Bind positional args
                for (index, paramName) in parameters.enumerated() {
                    let value = index < passedArgs.count ? passedArgs[index] : macroEnv[paramName]
                    macroEnv[paramName] = value
                }
                var macroBuffer = Buffer()
                try interpret(body, env: macroEnv, into: &macroBuffer)
                return .string(macroBuffer.build())
            }

        // These statements do not produce output directly or are handled elsewhere.
        case .if, .for, .program, .break, .continue, .call, .filter:
            break
        }
    }

    private static func assign(target: Expression, value: Value, env: Environment) throws {
        switch target {
        case .identifier(let name):
            env[name] = value
        case .tuple(let expressions):
            guard let values = value.array else {
                throw JinjaError.runtime("Cannot unpack non-array value for tuple assignment.")
            }
            guard expressions.count == values.count else {
                throw JinjaError.runtime(
                    "Tuple assignment mismatch: \(expressions.count) variables and \(values.count) values."
                )
            }
            for (expr, val) in zip(expressions, values) {
                try assign(target: expr, value: val, env: env)
            }
        default:
            throw JinjaError.runtime("Invalid target for assignment: \(target)")
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
            return left.isTruthy ? right : left
        case .or:
            return left.isTruthy ? left : right
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
        case let .string(str):
            if propertyName == "upper" {
                return .function { _ in .string(str.uppercased()) }
            }
            if propertyName == "lower" {
                return .function { _ in .string(str.lowercased()) }
            }
            return .undefined
        case let .object(obj):
            // Support Python-like dict.items() for iteration
            if propertyName == "items" {
                let fn: @Sendable ([Value]) throws -> Value = { _ in
                    let pairs = obj.map { key, value in Value.array([.string(key), value]) }
                    return .array(pairs)
                }
                return .function(fn)
            }
            return obj[propertyName] ?? .undefined
        default:
            return .undefined
        }
    }

    private static func evaluateTest(_ testName: String, _ argValues: [Value], env: Environment)
        throws -> Bool
    {
        switch testName {
        case "defined":
            guard let value = argValues.first else { return false }
            return value != .undefined

        case "undefined":
            guard let value = argValues.first else { return true }
            return value == .undefined

        case "none":
            guard let value = argValues.first else { return false }
            return value == .null

        case "string":
            guard let value = argValues.first else { return false }
            return value.isString

        case "number":
            guard let value = argValues.first else { return false }
            return value.isNumber

        case "boolean":
            guard let value = argValues.first else { return false }
            return value.isBoolean

        case "iterable":
            guard let value = argValues.first else { return false }
            return value.isIterable

        case "even":
            guard let value = argValues.first else { return false }
            switch value {
            case let .integer(num):
                return num % 2 == 0
            case let .number(num):
                return Int(num) % 2 == 0
            default:
                return false
            }

        case "odd":
            guard let value = argValues.first else { return false }
            switch value {
            case let .integer(num):
                return num % 2 != 0
            case let .number(num):
                return Int(num) % 2 != 0
            default:
                return false
            }

        case "divisibleby":
            guard argValues.count >= 2 else { return false }
            switch (argValues[0], argValues[1]) {
            case let (.integer(a), .integer(b)):
                return b != 0 && a % b == 0
            case let (.number(a), .number(b)):
                return b != 0.0 && Int(a) % Int(b) == 0
            default:
                return false
            }

        case "equalto":
            guard argValues.count >= 2 else { return false }
            return valuesEqual(argValues[0], argValues[1])

        default:
            // Look up dynamic tests from the environment
            let testValue = env[testName]
            guard case let .function(fn) = testValue else {
                throw JinjaError.runtime("Unknown test: \(testName)")
            }
            let result = try fn(argValues)
            if case let .boolean(b) = result { return b }
            return result.isTruthy
        }
    }

    private static func evaluateFilter(
        _ filterName: String, _ argValues: [Value], kwargs: [String: Value], env: Environment
    )
        throws -> Value
    {
        // Inline the most common filters for performance
        switch filterName {
        case "upper":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            return .string(str.uppercased())

        case "lower":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            return .string(str.lowercased())

        case "length", "count":
            switch argValues.first {
            case let .string(str):
                return .integer(str.count)
            case let .array(arr):
                return .integer(arr.count)
            case let .object(obj):
                return .integer(obj.count)
            default:
                throw JinjaError.runtime("length/count filter requires string, array, or object")
            }

        case "join":
            guard argValues.count >= 2,
                case let .array(array) = argValues[0],
                case let .string(separator) = argValues[1]
            else {
                return .string("")
            }

            let strings = array.map { $0.description }
            return .string(strings.joined(separator: separator))

        case "trim":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            return .string(str.trimmingCharacters(in: .whitespacesAndNewlines))

        case "escape", "e":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            let escaped =
                str
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
            return .string(escaped)

        case "tojson":
            guard let value = argValues.first else { return .string("null") }
            return .string(toJsonString(value))

        case "abs":
            guard let value = argValues.first else {
                return .integer(0)
            }
            switch value {
            case let .integer(i):
                return .integer(abs(i))
            case let .number(n):
                return .number(abs(n))
            default:
                // TODO: check what python jinja does
                return .integer(0)
            }

        case "capitalize":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            return .string(str.prefix(1).uppercased() + str.dropFirst().lowercased())

        case "center":
            guard case let .string(str) = argValues.first,
                argValues.count > 1,
                case let .integer(width) = argValues[1]
            else {
                // TODO: default width?
                return argValues.first ?? .string("")
            }

            let padCount = width - str.count
            if padCount <= 0 {
                return .string(str)
            }
            let leftPad = String(repeating: " ", count: padCount / 2)
            let rightPad = String(repeating: " ", count: padCount - (padCount / 2))
            return .string(leftPad + str + rightPad)

        case "first":
            guard let value = argValues.first else { return .undefined }
            switch value {
            case let .array(arr):
                return arr.first ?? .undefined
            case let .string(str):
                return .string(String(str.prefix(1)))
            default:
                return .undefined
            }

        case "last":
            guard let value = argValues.first else { return .undefined }
            switch value {
            case let .array(arr):
                return arr.last ?? .undefined
            case let .string(str):
                return .string(String(str.suffix(1)))
            default:
                return .undefined
            }

        case "float":
            guard let value = argValues.first else { return .number(0.0) }
            switch value {
            case let .integer(i):
                return .number(Double(i))
            case let .number(n):
                return .number(n)
            case let .string(s):
                return .number(Double(s) ?? 0.0)
            default:
                return .number(0.0)
            }

        case "int":
            guard let value = argValues.first else { return .integer(0) }
            switch value {
            case let .integer(i):
                return .integer(i)
            case let .number(n):
                return .integer(Int(n))
            case let .string(s):
                return .integer(Int(s) ?? 0)
            default:
                return .integer(0)
            }

        case "list":
            guard let value = argValues.first else { return .array([]) }
            switch value {
            case let .array(arr):
                return .array(arr)
            case let .string(str):
                return .array(str.map { .string(String($0)) })
            case let .object(dict):
                return .array(dict.values.map { $0 })
            default:
                return .array([])
            }

        case "max":
            guard let value = argValues.first, let items = value.array else { return .undefined }
            return items.max(by: { a, b in
                do {
                    return try compareValues(a, b) < 0
                } catch {
                    return false
                }
            }) ?? .undefined

        case "min":
            guard let value = argValues.first, let items = value.array else { return .undefined }
            return items.min(by: { a, b in
                do {
                    return try compareValues(a, b) < 0
                } catch {
                    return false
                }
            }) ?? .undefined

        case "round":
            guard let value = argValues.first else { return .number(0.0) }
            let precision = (argValues.count > 1 ? argValues[1].integer : 0) ?? 0
            let method = argValues.count > 2 ? (argValues[2].string ?? "common") : "common"

            guard let number = value.number else {
                return value  // Or throw error
            }

            if method == "common" {
                let divisor = pow(10.0, Double(precision))
                return .number((number * divisor).rounded() / divisor)
            } else if method == "ceil" {
                let divisor = pow(10.0, Double(precision))
                return .number(ceil(number * divisor) / divisor)
            } else if method == "floor" {
                let divisor = pow(10.0, Double(precision))
                return .number(floor(number * divisor) / divisor)
            }
            return .number(number)

        case "string":
            guard let value = argValues.first else { return .string("") }
            return .string(value.description)

        case "title":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            return .string(str.capitalized)

        case "wordcount":
            guard case let .string(str) = argValues.first else {
                return .integer(0)
            }
            let words = str.split { $0.isWhitespace || $0.isNewline }
            return .integer(words.count)

        case "replace":
            guard argValues.count >= 3,
                case let .string(str) = argValues[0],
                case let .string(old) = argValues[1],
                case let .string(new) = argValues[2]
            else {
                return argValues.first ?? .string("")
            }
            let count = argValues.count > 3 ? argValues[3].integer : nil
            var result = ""
            var remaining = str
            var replacements = 0
            while let range = remaining.range(of: old) {
                if let count = count, replacements >= count {
                    break
                }
                result += remaining[..<range.lowerBound]
                result += new
                remaining = String(remaining[range.upperBound...])
                replacements += 1
            }
            result += remaining
            return .string(result)

        case "urlencode":
            guard let value = argValues.first else {
                return .string("")
            }

            let str: String
            if case let .string(s) = value {
                str = s
            } else if case .object(let dict) = value {
                str = dict.map { key, value in
                    let encodedKey =
                        key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let encodedValue =
                        value.description.addingPercentEncoding(
                            withAllowedCharacters: .urlQueryAllowed) ?? ""
                    return "\(encodedKey)=\(encodedValue)"
                }.joined(separator: "&")
            } else {
                return .string("")
            }

            return .string(str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")

        case "batch":
            guard let value = argValues.first, let items = value.array,
                argValues.count > 1, let batchSize = argValues[1].integer, batchSize > 0
            else {
                return .array([])
            }

            let fillWith = argValues.count > 2 ? argValues[2] : .null

            var result = [Value]()
            var batch = [Value]()
            for item in items {
                batch.append(item)
                if batch.count == batchSize {
                    result.append(.array(batch))
                    batch = []
                }
            }
            if !batch.isEmpty {
                while batch.count < batchSize {
                    batch.append(fillWith)
                }
                result.append(.array(batch))
            }
            return .array(result)

        case "reverse":
            guard let value = argValues.first else { return .undefined }
            switch value {
            case let .array(arr):
                return .array(arr.reversed())
            case let .string(str):
                return .string(String(str.reversed()))
            default:
                return value
            }

        case "sort":
            guard let value = argValues.first, var items = value.array else {
                return .array([])
            }
            let reverse = argValues.count > 1 ? argValues[1].isTruthy : false
            items.sort { a, b in
                do {
                    let result = try compareValues(a, b)
                    return reverse ? result > 0 : result < 0
                } catch {
                    return false
                }
            }
            return .array(items)

        case "sum":
            guard let value = argValues.first, let items = value.array else {
                return .integer(0)
            }
            let start = argValues.count > 1 ? argValues[1] : .integer(0)
            let sum = items.reduce(start) { acc, next in
                try! addValues(acc, next)  // Should handle errors
            }
            return sum

        case "truncate":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            let length = argValues.count > 1 ? (argValues[1].integer ?? 255) : 255
            let killwords = argValues.count > 2 ? (argValues[2].isTruthy) : false
            let end = argValues.count > 3 ? (argValues[3].string ?? "...") : "..."

            if str.count <= length {
                return .string(str)
            }

            if killwords {
                return .string(str.prefix(length) + end)
            } else {
                let truncated = str.prefix(length)
                if let lastSpace = truncated.lastIndex(where: { $0.isWhitespace }) {
                    return .string(truncated[..<lastSpace] + end)
                } else {
                    return .string(truncated + end)
                }
            }

        case "unique":
            guard let value = argValues.first, let items = value.array else {
                return .array([])
            }
            var seen = Set<Value>()
            var result = [Value]()
            for item in items {
                if !seen.contains(item) {
                    seen.insert(item)
                    result.append(item)
                }
            }
            return .array(result)

        case "indent":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            let width = argValues.count > 1 ? (argValues[1].integer ?? 4) : 4
            let indentFirst = argValues.count > 2 ? (argValues[2].isTruthy) : true
            let indentChar = String(repeating: " ", count: width)
            let lines = str.split(separator: "\n", omittingEmptySubsequences: false).map(
                String.init)
            var result = ""
            for (i, line) in lines.enumerated() {
                if i == 0 && !indentFirst {
                    result += line
                } else if !line.isEmpty {
                    result += indentChar + line
                }
                if i < lines.count - 1 {
                    result += "\n"
                }
            }
            return .string(result)

        case "slice":
            guard let value = argValues.first, let items = value.array,
                argValues.count > 1, let numSlices = argValues[1].integer, numSlices > 0
            else {
                return .array([])
            }

            let fillWith = argValues.count > 2 ? argValues[2] : .null
            var result = Array(repeating: [Value](), count: numSlices)
            let itemsPerSlice = (items.count + numSlices - 1) / numSlices

            for i in 0..<itemsPerSlice {
                for j in 0..<numSlices {
                    let index = i * numSlices + j
                    if index < items.count {
                        result[j].append(items[index])
                    } else {
                        result[j].append(fillWith)
                    }
                }
            }

            return .array(result.map { .array($0) })

        case "map":
            guard let value = argValues.first, let items = value.array else {
                return .array([])
            }

            if let filterName = argValues.count > 1 ? argValues[1].string : nil {
                return .array(
                    try items.map {
                        try evaluateFilter(filterName, [$0], kwargs: [:], env: env)
                    })
            } else if let attribute = kwargs["attribute"]?.string {
                return .array(
                    try items.map {
                        try evaluatePropertyMember($0, attribute)
                    })
            }

            return .array([])

        case "select":
            guard let value = argValues.first, let items = value.array,
                argValues.count > 1, let testName = argValues[1].string
            else {
                return .array([])
            }
            let testArgs = Array(argValues.dropFirst(2))
            return .array(
                try items.filter {
                    try evaluateTest(testName, [$0] + testArgs, env: env)
                })

        case "reject":
            guard let value = argValues.first, let items = value.array,
                argValues.count > 1, let testName = argValues[1].string
            else {
                return .array([])
            }
            let testArgs = Array(argValues.dropFirst(2))
            return .array(
                try items.filter {
                    try !evaluateTest(testName, [$0] + testArgs, env: env)
                })

        case "selectattr":
            guard let value = argValues.first, let items = value.array,
                argValues.count > 2, let attribute = argValues[1].string,
                let testName = argValues[2].string
            else {
                return .array([])
            }
            let testArgs = Array(argValues.dropFirst(3))
            return .array(
                try items.filter {
                    let attrValue = try evaluatePropertyMember($0, attribute)
                    return try evaluateTest(testName, [attrValue] + testArgs, env: env)
                })

        case "rejectattr":
            guard let value = argValues.first, let items = value.array,
                argValues.count > 2, let attribute = argValues[1].string,
                let testName = argValues[2].string
            else {
                return .array([])
            }
            let testArgs = Array(argValues.dropFirst(3))
            return .array(
                try items.filter {
                    let attrValue = try evaluatePropertyMember($0, attribute)
                    return try !evaluateTest(testName, [attrValue] + testArgs, env: env)
                })

        case "groupby":
            guard let value = argValues.first, let items = value.array,
                argValues.count > 1, let attribute = argValues[1].string
            else {
                return .array([])
            }
            var groups = OrderedDictionary<Value, [Value]>()
            for item in items {
                let key = try evaluatePropertyMember(item, attribute)
                groups[key, default: []].append(item)
            }
            let result = groups.map { key, value in
                Value.object([
                    "grouper": key,
                    "list": .array(value),
                ])
            }
            return .array(result)

        case "attr":
            guard let obj = argValues.first, argValues.count > 1,
                let attribute = argValues[1].string
            else {
                return .undefined
            }
            return try evaluatePropertyMember(obj, attribute)

        case "forceescape":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            let escaped =
                str
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
            return .string(escaped)

        case "safe":
            return argValues.first ?? .string("")

        case "striptags":
            guard case let .string(str) = argValues.first else {
                return .string("")
            }
            // Regular expression to find HTML tags and replace them.
            // This is a simplified version. A more robust solution would be more complex.
            let regex = try! NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive)
            let range = NSRange(location: 0, length: str.utf16.count)
            let noTags = regex.stringByReplacingMatches(
                in: str, options: [], range: range, withTemplate: "")
            // Replace adjacent whitespace with a single space
            let components = noTags.components(separatedBy: .whitespacesAndNewlines)
            return .string(components.filter { !$0.isEmpty }.joined(separator: " "))

        case "format":
            guard argValues.count > 1, let formatString = argValues[0].string else {
                return argValues.first ?? .string("")
            }
            let args = Array(argValues.dropFirst())
            // This is a very basic implementation of string formatting.
            // It doesn't handle named placeholders or complex format specifiers.
            var result = ""
            var formatIdx = formatString.startIndex
            var argIdx = 0
            while formatIdx < formatString.endIndex {
                let char = formatString[formatIdx]
                if char == "%", argIdx < args.count {
                    formatIdx = formatString.index(after: formatIdx)
                    if formatIdx < formatString.endIndex {
                        let specifier = formatString[formatIdx]
                        if specifier == "s" {
                            result += args[argIdx].description
                            argIdx += 1
                        } else {
                            result.append("%")
                            result.append(specifier)
                        }
                    } else {
                        result.append("%")
                    }
                } else {
                    result.append(char)
                }
                formatIdx = formatString.index(after: formatIdx)
            }
            return .string(result)

        case "filesizeformat":
            guard let value = argValues.first, let num = value.number else {
                return .string("")
            }
            let binary = kwargs["binary"]?.isTruthy ?? false
            let bytes = num
            let unit: Double = binary ? 1024 : 1000
            if bytes < unit {
                return .string("\(Int(bytes)) Bytes")
            }
            let exp = Int(log(bytes) / log(unit))
            let pre = (binary ? "KMGTPEZY" : "kMGTPEZY")
            let preIndex = pre.index(pre.startIndex, offsetBy: exp - 1)
            let preChar = pre[preIndex]
            let suffix = binary ? "iB" : "B"
            return .string(
                String(format: "%.1f %s\(suffix)", bytes / pow(unit, Double(exp)), String(preChar)))

        case "random":
            guard let value = argValues.first else {
                return .undefined
            }
            switch value {
            case let .array(arr):
                return arr.randomElement() ?? .undefined
            case let .string(str):
                return str.randomElement().map { .string(String($0)) } ?? .undefined
            case let .object(dict):
                if dict.isEmpty { return .undefined }
                let randomIndex = dict.keys.indices.randomElement()!
                let randomKey = dict.keys[randomIndex]
                return .string(randomKey)
            default:
                return .undefined
            }

        case "wordwrap":
            guard let value = argValues.first, let str = value.string else {
                return .string("")
            }
            let width = argValues.count > 1 ? (argValues[1].integer ?? 79) : 79
            _ = argValues.count > 2 ? (argValues[2].isTruthy) : true

            var lines = [String]()
            let paragraphs = str.components(separatedBy: .newlines)
            for paragraph in paragraphs {
                var line = ""
                let words = paragraph.components(separatedBy: .whitespaces)
                for word in words {
                    if line.isEmpty {
                        line = word
                    } else if line.count + word.count + 1 <= width {
                        line += " \(word)"
                    } else {
                        lines.append(line)
                        line = word
                    }
                }
                if !line.isEmpty {
                    lines.append(line)
                }
            }
            return .string(lines.joined(separator: "\n"))

        case "xmlattr":
            guard let value = argValues.first, case let .object(dict) = value else {
                return .string("")
            }
            let autocapitalize = argValues.count > 1 ? argValues[1].isTruthy : false
            var result = ""
            for (key, value) in dict {
                if key.starts(with: "_") { continue }
                let finalKey = autocapitalize ? key.capitalized : key
                result += " \(finalKey)=\"\(value.description)\""
            }
            return .string(result)

        case "dictsort":
            guard case let .object(dict) = argValues.first else {
                return .array([])
            }
            let sortedPairs = dict.sorted { $0.key < $1.key }
            let resultArray = sortedPairs.map { key, value in
                Value.array([.string(key), value])
            }
            return .array(resultArray)

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

        // Test filters (return boolean values for type checking)
        case "defined":
            guard let value = argValues.first else { return .boolean(false) }
            return .boolean(value != .undefined)

        case "undefined":
            guard let value = argValues.first else { return .boolean(true) }
            return .boolean(value == .undefined)

        case "none":
            guard let value = argValues.first else { return .boolean(false) }
            return .boolean(value == .null)

        case "string":
            guard let value = argValues.first else { return .boolean(false) }
            return .boolean(value.isString)

        case "number":
            guard let value = argValues.first else { return .boolean(false) }
            return .boolean(value.isNumber)

        case "boolean":
            guard let value = argValues.first else { return .boolean(false) }
            return .boolean(value.isBoolean)

        case "iterable":
            guard let value = argValues.first else { return .boolean(false) }
            return .boolean(value.isIterable)

        default:
            // Fallback to environment-provided filters
            let filterValue = env[filterName]
            guard case let .function(fn) = filterValue else {
                throw JinjaError.runtime("Unknown filter: \(filterName)")
            }
            return try fn(argValues)
        }
    }

    private static func toJsonString(_ value: Value) -> String {
        switch value {
        case .string(let str):
            let escaped =
                str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        case .integer(let num):
            return String(num)
        case .number(let num):
            return String(num)
        case .boolean(let bool):
            return bool ? "true" : "false"
        case .null, .undefined:
            return "null"
        case .array(let items):
            let jsonItems = items.map { toJsonString($0) }
            return "[\(jsonItems.joined(separator: ", "))]"
        case .object(let dict):
            let jsonPairs = dict.map { key, value -> String in
                let keyJson = "\"\(key)\""
                let valueJson = toJsonString(value)
                return "\(keyJson): \(valueJson)"
            }
            return "{\(jsonPairs.joined(separator: ", "))}"
        default:
            return "null"
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
            throw JinjaError.runtime("Cannot add values of different types (\(left) and \(right))")
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
            throw JinjaError.runtime("Cannot subtract non-numeric values (\(left) and \(right))")
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
            throw JinjaError.runtime("Cannot multiply values of these types (\(left) and \(right))")
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
            throw JinjaError.runtime("Cannot divide non-numeric values (\(left) and \(right))")
        }
    }

    private static func moduloValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            guard b != 0 else { throw JinjaError.runtime("Modulo by zero") }
            return .integer(a % b)
        default:
            throw JinjaError.runtime("Modulo operation requires integers (\(left) and \(right))")
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
            throw JinjaError.runtime(
                "Cannot compare values of different types (\(left) and \(right))")
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
            guard !substr.isEmpty else { return true }  // '' in 'abc' -> true
            return str.contains(substr)
        case let .object(dict):
            guard case let .string(key) = value else { return false }
            return dict.keys.contains(key)
        case .undefined, .null:
            return false
        default:
            throw JinjaError.runtime(
                "'in' operator requires iterable on right side (\(collection))")
        }
    }
}

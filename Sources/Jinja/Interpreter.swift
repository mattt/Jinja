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

    public static func evaluatePropertyMember(_ object: Value, _ propertyName: String) throws
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

    public static func evaluateTest(_ testName: String, _ argValues: [Value], env: Environment)
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

    public static func evaluateFilter(
        _ filterName: String, _ argValues: [Value], kwargs: [String: Value], env: Environment
    )
        throws -> Value
    {
        // Try environment-provided filters first
        let filterValue = env[filterName]
        if case let .function(fn) = filterValue {
            return try fn(argValues)
        }

        // Fallback to built-in filters
        if let filterFunction = Filters.default[filterName] {
            return try filterFunction(argValues, kwargs, env)
        }

        throw JinjaError.runtime("Unknown filter: \(filterName)")
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

    public static func addValues(_ left: Value, _ right: Value) throws -> Value {
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

    public static func compareValues(_ left: Value, _ right: Value) throws -> Int {
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

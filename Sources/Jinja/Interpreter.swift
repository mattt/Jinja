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
    struct Macro {
        let name: String
        let parameters: [String]
        let defaults: OrderedDictionary<String, Expression>
        let body: [Node]
    }
    var macros: [String: Macro] = [:]

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

            let startIdx: Value? = try start.map { try evaluateExpression($0, env: env) }
            let stopIdx: Value? = try stop.map { try evaluateExpression($0, env: env) }
            let stepVal: Value? = try step.map { try evaluateExpression($0, env: env) }

            switch arrayValue {
            case let .array(items):
                // Simple slice implementation for arrays
                var sliceStart = 0
                var sliceEnd = items.count
                var sliceStep = 1

                if let startValue = startIdx, case let .integer(s) = startValue {
                    sliceStart = s >= 0 ? s : items.count + s
                }
                if let stopValue = stopIdx, case let .integer(e) = stopValue {
                    sliceEnd = e >= 0 ? e : items.count + e
                }
                if let stepValue = stepVal, case let .integer(st) = stepValue {
                    sliceStep = st
                }

                let result = stride(from: sliceStart, to: sliceEnd, by: sliceStep).compactMap {
                    idx in
                    idx >= 0 && idx < items.count ? items[idx] : nil
                }
                return .array(result)

            case let .string(str):
                // String slice implementation
                let chars = Array(str)
                var sliceStart = 0
                var sliceEnd = chars.count
                var sliceStep = 1

                if let startValue = startIdx, case let .integer(s) = startValue {
                    sliceStart = s >= 0 ? s : chars.count + s
                }
                if let stopValue = stopIdx, case let .integer(e) = stopValue {
                    sliceEnd = e >= 0 ? e : chars.count + e
                }
                if let stepValue = stepVal, case let .integer(st) = stepValue {
                    sliceStep = st
                }

                let result = stride(from: sliceStart, to: sliceEnd, by: sliceStep).compactMap {
                    idx in
                    idx >= 0 && idx < chars.count ? chars[idx] : nil
                }
                return .string(String(result))

            default:
                throw JinjaError.runtime("Slice requires array or string")
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
            env.macros[name] = Environment.Macro(
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
            env.macros[name] = Environment.Macro(
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

    // MARK: -

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
            switch propertyName {
            case "upper":
                return .function { _ in .string(str.uppercased()) }
            case "lower":
                return .function { _ in .string(str.lowercased()) }
            case "title":
                return .function { _ in .string(str.capitalized) }
            case "strip":
                return .function { _ in .string(str.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            case "lstrip":
                return .function { _ in
                    let trimmed = str.drop(while: { $0.isWhitespace })
                    return .string(String(trimmed))
                }
            case "rstrip":
                return .function { _ in
                    let reversed = str.reversed().drop(while: { $0.isWhitespace })
                    return .string(String(reversed.reversed()))
                }
            case "split":
                return .function { args in
                    if args.isEmpty {
                        // Split on whitespace
                        let components = str.split(separator: " ").map(String.init)
                        return .array(components.map(Value.string))
                    } else if case let .string(separator) = args[0] {
                        if args.count > 1, case let .integer(limit) = args[1] {
                            let components = str.components(separatedBy: separator)
                            let limitedComponents = Array(components.prefix(limit + 1))
                            return .array(limitedComponents.map(Value.string))
                        } else {
                            let components = str.components(separatedBy: separator)
                            return .array(components.map(Value.string))
                        }
                    }
                    return .array([.string(str)])
                }
            case "replace":
                return .function { args in
                    guard args.count >= 2,
                        case let .string(old) = args[0],
                        case let .string(new) = args[1]
                    else {
                        return .string(str)
                    }
                    if args.count > 2, case let .integer(count) = args[2] {
                        // Replace only the first 'count' occurrences
                        var result = str
                        for _ in 0..<count {
                            if let range = result.range(of: old) {
                                result.replaceSubrange(range, with: new)
                            } else {
                                break
                            }
                        }
                        return .string(result)
                    } else {
                        return .string(str.replacingOccurrences(of: old, with: new))
                    }
                }
            default:
                return .undefined
            }
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
        // Try built-in tests first
        if let testFunction = Tests.default[testName] {
            return try testFunction(argValues, [:], env)
        }

        // Look up dynamic tests from the environment
        let testValue = env[testName]
        guard case let .function(fn) = testValue else {
            throw JinjaError.runtime("Unknown test: \(testName)")
        }
        let result = try fn(argValues)
        if case let .boolean(b) = result { return b }
        return result.isTruthy
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

    fileprivate static func valuesEqual(_ left: Value, _ right: Value) -> Bool {
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

// MARK: - Tests

/// Built-in tests for Jinja template rendering.
public enum Tests {
    // MARK: - Basic Tests

    /// Tests if a value is defined (not undefined).
    @Sendable public static func defined(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        return value != .undefined
    }

    /// Tests if a value is undefined.
    @Sendable public static func undefined(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return true }
        return value == .undefined
    }

    /// Tests if a value is none/null.
    @Sendable public static func none(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        return value == .null
    }

    /// Tests if a value is a string.
    @Sendable public static func string(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        return value.isString
    }

    /// Tests if a value is a number.
    @Sendable public static func number(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        return value.isNumber
    }

    /// Tests if a value is a boolean.
    @Sendable public static func boolean(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        return value.isBoolean
    }

    /// Tests if a value is iterable.
    @Sendable public static func iterable(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        return value.isIterable
    }

    // MARK: - Numeric Tests

    /// Tests if a number is even.
    @Sendable public static func even(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        switch value {
        case let .integer(num):
            return num % 2 == 0
        case let .number(num):
            return Int(num) % 2 == 0
        default:
            return false
        }
    }

    /// Tests if a number is odd.
    @Sendable public static func odd(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        switch value {
        case let .integer(num):
            return num % 2 != 0
        case let .number(num):
            return Int(num) % 2 != 0
        default:
            return false
        }
    }

    /// Tests if a number is divisible by another number.
    @Sendable public static func divisibleby(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard values.count >= 2 else { return false }
        switch (values[0], values[1]) {
        case let (.integer(a), .integer(b)):
            return b != 0 && a % b == 0
        case let (.number(a), .number(b)):
            return b != 0.0 && Int(a) % Int(b) == 0
        default:
            return false
        }
    }

    // MARK: - Comparison Tests

    /// Tests if two values are equal.
    @Sendable public static func equalto(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard values.count >= 2 else { return false }
        return Interpreter.valuesEqual(values[0], values[1])
    }

    /// Tests if a value is a mapping (dictionary/object).
    @Sendable public static func mapping(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        if case .object(_) = value {
            return true
        }
        return false
    }

    /// Tests if a value is callable (function).
    @Sendable public static func callable(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        if case .function(_) = value {
            return true
        }
        return false
    }

    /// Tests if a value is an integer.
    @Sendable public static func integer(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        if case .integer(_) = value {
            return true
        }
        return false
    }

    /// Tests if a string is all lowercase.
    @Sendable public static func isLower(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        if case let .string(str) = value {
            return str == str.lowercased() && str != str.uppercased()
        }
        return false
    }

    /// Tests if a string is all uppercase.
    @Sendable public static func isUpper(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = values.first else { return false }
        if case let .string(str) = value {
            return str == str.uppercased() && str != str.lowercased()
        }
        return false
    }

    /// Dictionary of all available tests.
    public static let `default`:
        [String: @Sendable ([Value], [String: Value], Environment) throws -> Bool] = [
            "defined": defined,
            "undefined": undefined,
            "none": none,
            "string": string,
            "number": number,
            "boolean": boolean,
            "iterable": iterable,
            "even": even,
            "odd": odd,
            "divisibleby": divisibleby,
            "equalto": equalto,
            "mapping": mapping,
            "callable": callable,
            "integer": integer,
            "lower": isLower,
            "upper": isUpper,
        ]
}

// MARK: - Filters

/// Built-in filters for Jinja template rendering.
public enum Filters {
    // MARK: - Basic String Filters

    /// Converts a string to uppercase.
    @Sendable public static func upper(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            throw JinjaError.runtime("upper filter requires string")
        }
        return .string(str.uppercased())
    }

    /// Converts a string to lowercase.
    @Sendable public static func lower(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            throw JinjaError.runtime("lower filter requires string")
        }
        return .string(str.lowercased())
    }

    /// Returns the length of a string, array, or object.
    @Sendable public static func length(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
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
    }

    /// Joins an array of values with a separator.
    @Sendable public static func join(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard values.count >= 2,
            case let .array(array) = values[0],
            case let .string(separator) = values[1]
        else {
            throw JinjaError.runtime("join filter requires array and separator")
        }

        let strings = array.map { $0.description }
        return .string(strings.joined(separator: separator))
    }

    /// Returns a default value if the input is null, undefined, or empty.
    @Sendable public static func `default`(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
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
    }

    // MARK: - Array Filters

    /// Returns the first item from an array.
    @Sendable public static func first(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
            return .undefined
        }

        switch value {
        case let .array(arr):
            return arr.first ?? .undefined
        case let .string(str):
            return str.first.map { .string(String($0)) } ?? .undefined
        default:
            throw JinjaError.runtime("first filter requires array or string")
        }
    }

    /// Returns the last item from an array.
    @Sendable public static func last(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
            return .undefined
        }

        switch value {
        case let .array(arr):
            return arr.last ?? .undefined
        case let .string(str):
            return str.last.map { .string(String($0)) } ?? .undefined
        default:
            throw JinjaError.runtime("last filter requires array or string")
        }
    }

    /// Returns a random item from an array.
    @Sendable public static func random(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
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
    }

    /// Reverses an array or string.
    @Sendable public static func reverse(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
            return .undefined
        }

        switch value {
        case let .array(arr):
            return .array(arr.reversed())
        case let .string(str):
            return .string(String(str.reversed()))
        default:
            throw JinjaError.runtime("reverse filter requires array or string")
        }
    }

    /// Sorts an array.
    @Sendable public static func sort(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, case let .array(items) = value else {
            return .array([])
        }

        let reverse = kwargs["reverse"]?.isTruthy ?? false
        let caseSensitive = kwargs["case_sensitive"]?.isTruthy ?? true

        let sortedItems: [Value]
        if let attribute = kwargs["attribute"]?.string {
            sortedItems = try items.sorted { a, b in
                let aValue = try Interpreter.evaluatePropertyMember(a, attribute)
                let bValue = try Interpreter.evaluatePropertyMember(b, attribute)
                let comparison = try Interpreter.compareValues(aValue, bValue)
                return reverse ? comparison > 0 : comparison < 0
            }
        } else {
            sortedItems = try items.sorted { a, b in
                let comparison: Int
                if !caseSensitive, case let .string(aStr) = a, case let .string(bStr) = b {
                    comparison =
                        aStr.lowercased() < bStr.lowercased()
                        ? -1 : aStr.lowercased() > bStr.lowercased() ? 1 : 0
                } else {
                    comparison = try Interpreter.compareValues(a, b)
                }
                return reverse ? comparison > 0 : comparison < 0
            }
        }

        return .array(sortedItems)
    }

    /// Groups items by a given attribute.
    @Sendable public static func groupby(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let attribute = values[1].string
        else {
            return .array([])
        }
        var groups = OrderedDictionary<Value, [Value]>()
        for item in items {
            let key = try Interpreter.evaluatePropertyMember(item, attribute)
            groups[key, default: []].append(item)
        }
        let result = groups.map { key, value in
            Value.object([
                "grouper": key,
                "list": .array(value),
            ])
        }
        return .array(result)
    }

    /// Slices an array into multiple slices.
    @Sendable public static func slice(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let numSlices = values[1].integer, numSlices > 0
        else {
            return .array([])
        }

        let fillWith = values.count > 2 ? values[2] : .null
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
    }

    /// Maps items through a filter or extracts attribute values.
    @Sendable public static func map(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else {
            return .array([])
        }

        if let filterName = values.count > 1 ? values[1].string : nil {
            return .array(
                try items.map {
                    try Interpreter.evaluateFilter(filterName, [$0], kwargs: [:], env: env)
                })
        } else if let attribute = kwargs["attribute"]?.string {
            return .array(
                try items.map {
                    try Interpreter.evaluatePropertyMember($0, attribute)
                })
        }

        return .array([])
    }

    /// Selects items that pass a test.
    @Sendable public static func select(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let testName = values[1].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(2))
        return .array(
            try items.filter {
                try Interpreter.evaluateTest(testName, [$0] + testArgs, env: env)
            })
    }

    /// Rejects items that pass a test.
    @Sendable public static func reject(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let testName = values[1].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(2))
        return .array(
            try items.filter {
                try !Interpreter.evaluateTest(testName, [$0] + testArgs, env: env)
            })
    }

    /// Selects items with an attribute that passes a test.
    @Sendable public static func selectattr(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 2, let attribute = values[1].string,
            let testName = values[2].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(3))
        return .array(
            try items.filter {
                let attrValue = try Interpreter.evaluatePropertyMember($0, attribute)
                return try Interpreter.evaluateTest(testName, [attrValue] + testArgs, env: env)
            })
    }

    /// Rejects items with an attribute that passes a test.
    @Sendable public static func rejectattr(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 2, let attribute = values[1].string,
            let testName = values[2].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(3))
        return .array(
            try items.filter {
                let attrValue = try Interpreter.evaluatePropertyMember($0, attribute)
                return try !Interpreter.evaluateTest(testName, [attrValue] + testArgs, env: env)
            })
    }

    // MARK: - Object Filters

    /// Gets an attribute from an object.
    @Sendable public static func attr(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let obj = values.first, values.count > 1,
            let attribute = values[1].string
        else {
            return .undefined
        }
        return try Interpreter.evaluatePropertyMember(obj, attribute)
    }

    /// Sorts a dictionary by keys and returns key-value pairs.
    @Sendable public static func dictsort(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .object(dict) = values.first else {
            return .array([])
        }
        let sortedPairs = dict.sorted { $0.key < $1.key }
        let resultArray = sortedPairs.map { key, value in
            Value.array([.string(key), value])
        }
        return .array(resultArray)
    }

    // MARK: - String Processing Filters

    /// Escapes HTML characters.
    @Sendable public static func forceescape(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
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
    }

    /// Marks a string as safe (no-op for basic implementation).
    @Sendable public static func safe(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        return values.first ?? .string("")
    }

    /// Strips HTML tags from a string.
    @Sendable public static func striptags(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        let regex = try! NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive)
        let range = NSRange(location: 0, length: str.utf16.count)
        let noTags = regex.stringByReplacingMatches(
            in: str, options: [], range: range, withTemplate: "")
        let components = noTags.components(separatedBy: .whitespacesAndNewlines)
        return .string(components.filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// Basic string formatting.
    @Sendable public static func format(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard values.count > 1, let formatString = values[0].string else {
            return values.first ?? .string("")
        }
        let args = Array(values.dropFirst())
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
    }

    /// Wraps text to a specified width.
    @Sendable public static func wordwrap(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let str = value.string else {
            return .string("")
        }
        let width = values.count > 1 ? (values[1].integer ?? 79) : 79
        _ = values.count > 2 ? (values[2].isTruthy) : true

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
    }

    /// Formats file size in human readable format.
    @Sendable public static func filesizeformat(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let num = value.number else {
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
    }

    /// Formats object attributes as XML attributes.
    @Sendable public static func xmlattr(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, case let .object(dict) = value else {
            return .string("")
        }
        let autocapitalize = values.count > 1 ? values[1].isTruthy : false
        var result = ""
        for (key, value) in dict {
            if key.starts(with: "_") { continue }
            let finalKey = autocapitalize ? key.capitalized : key
            result += " \(finalKey)=\"\(value.description)\""
        }
        return .string(result)
    }

    // MARK: - Test Filters (return boolean values)

    /// Tests if a value is defined (not undefined).
    @Sendable public static func defined(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value != .undefined)
    }

    /// Tests if a value is undefined.
    @Sendable public static func undefined(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(true) }
        return .boolean(value == .undefined)
    }

    /// Tests if a value is none/null.
    @Sendable public static func none(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value == .null)
    }

    /// Tests if a value is a string.
    @Sendable public static func string(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isString)
    }

    /// Tests if a value is a number.
    @Sendable public static func number(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isNumber)
    }

    /// Tests if a value is a boolean.
    @Sendable public static func boolean(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isBoolean)
    }

    /// Tests if a value is iterable.
    @Sendable public static func iterable(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isIterable)
    }

    // MARK: - Additional Filters

    /// Trims whitespace from a string.
    @Sendable public static func trim(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        return .string(str.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Escapes HTML characters (alias for forceescape).
    @Sendable public static func escape(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        return try forceescape(values, kwargs: kwargs, env: env)
    }

    /// Converts value to JSON string.
    @Sendable public static func tojson(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .string("null") }

        let encoder = JSONEncoder()
        if kwargs["indent"]?.isTruthy ?? false {
            encoder.outputFormatting = .prettyPrinted
        }

        if let jsonData = (try? encoder.encode(value)),
            let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return .string(jsonString)
        } else {
            return .string("null")
        }
    }

    /// Returns absolute value of a number.
    @Sendable public static func abs(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
            return .integer(0)
        }
        switch value {
        case let .integer(i):
            return .integer(Swift.abs(i))
        case let .number(n):
            return .number(Swift.abs(n))
        default:
            throw JinjaError.runtime("abs filter requires number or integer")
        }
    }

    /// Capitalizes the first letter and lowercases the rest.
    @Sendable public static func capitalize(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        return .string(str.prefix(1).uppercased() + str.dropFirst().lowercased())
    }

    /// Centers a string within a specified width.
    @Sendable public static func center(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first,
            values.count > 1,
            case let .integer(width) = values[1]
        else {
            return values.first ?? .string("")
        }

        let padCount = width - str.count
        if padCount <= 0 {
            return .string(str)
        }
        let leftPad = String(repeating: " ", count: padCount / 2)
        let rightPad = String(repeating: " ", count: padCount - (padCount / 2))
        return .string(leftPad + str + rightPad)
    }

    /// Converts a value to float.
    @Sendable public static func float(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .number(0.0) }
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
    }

    /// Converts a value to integer.
    @Sendable public static func int(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .integer(0) }
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
    }

    /// Converts a value to list.
    @Sendable public static func list(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .array([]) }
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
    }

    /// Returns the maximum value from an array.
    @Sendable public static func max(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else { return .undefined }
        return items.max(by: { a, b in
            do {
                return try Interpreter.compareValues(a, b) < 0
            } catch {
                return false
            }
        }) ?? .undefined
    }

    /// Returns the minimum value from an array.
    @Sendable public static func min(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else { return .undefined }
        return items.min(by: { a, b in
            do {
                return try Interpreter.compareValues(a, b) < 0
            } catch {
                return false
            }
        }) ?? .undefined
    }

    /// Rounds a number to specified precision.
    @Sendable public static func round(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .number(0.0) }
        let precision = (values.count > 1 ? values[1].integer : 0) ?? 0
        let method = values.count > 2 ? (values[2].string ?? "common") : "common"

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
    }

    /// Capitalizes each word in a string.
    @Sendable public static func title(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        return .string(str.capitalized)
    }

    /// Counts words in a string.
    @Sendable public static func wordcount(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .integer(0)
        }
        let words = str.split { $0.isWhitespace || $0.isNewline }
        return .integer(words.count)
    }

    /// Replaces occurrences of a substring.
    @Sendable public static func replace(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard values.count >= 3,
            case let .string(str) = values[0],
            case let .string(old) = values[1],
            case let .string(new) = values[2]
        else {
            return values.first ?? .string("")
        }
        let count = values.count > 3 ? values[3].integer : nil
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
    }

    /// URL encodes a string or object.
    @Sendable public static func urlencode(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
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
    }

    /// Batches items into groups.
    @Sendable public static func batch(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let batchSize = values[1].integer, batchSize > 0
        else {
            return .array([])
        }

        let fillWith = values.count > 2 ? values[2] : .null

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
    }

    /// Sums values in an array.
    @Sendable public static func sum(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else {
            return .integer(0)
        }
        let start = values.count > 1 ? values[1] : .integer(0)
        let sum = items.reduce(start) { acc, next in
            try! Interpreter.addValues(acc, next)  // Should handle errors
        }
        return sum
    }

    /// Truncates a string to a specified length.
    @Sendable public static func truncate(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        let length = values.count > 1 ? (values[1].integer ?? 255) : 255
        let killwords = values.count > 2 ? (values[2].isTruthy) : false
        let end = values.count > 3 ? (values[3].string ?? "...") : "..."

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
    }

    /// Returns unique items from an array.
    @Sendable public static func unique(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else {
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
    }

    /// Indents text.
    @Sendable public static func indent(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        let width = values.count > 1 ? (values[1].integer ?? 4) : 4
        let indentFirst = values.count > 2 ? (values[2].isTruthy) : true
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
    }

    /// Returns items (key-value pairs) of a dictionary/object.
    @Sendable public static func items(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
            return .array([])
        }

        if case let .object(obj) = value {
            let pairs = obj.map { key, value in
                Value.array([.string(key), value])
            }
            return .array(pairs)
        }

        return .array([])
    }

    /// Dictionary of all available filters.
    public static let `default`:
        [String: @Sendable ([Value], [String: Value], Environment) throws -> Value] = [
            "upper": upper,
            "lower": lower,
            "length": length,
            "count": length,  // alias for length
            "join": join,
            "default": `default`,
            "first": first,
            "last": last,
            "random": random,
            "reverse": reverse,
            "sort": sort,
            "groupby": groupby,
            "slice": slice,
            "map": map,
            "select": select,
            "reject": reject,
            "selectattr": selectattr,
            "rejectattr": rejectattr,
            "attr": attr,
            "dictsort": dictsort,
            "forceescape": forceescape,
            "safe": safe,
            "striptags": striptags,
            "format": format,
            "wordwrap": wordwrap,
            "filesizeformat": filesizeformat,
            "xmlattr": xmlattr,
            "defined": defined,
            "undefined": undefined,
            "none": none,
            "string": string,
            "number": number,
            "boolean": boolean,
            "iterable": iterable,
            "trim": trim,
            "escape": escape,
            "e": escape,  // alias for escape
            "tojson": tojson,
            "abs": abs,
            "capitalize": capitalize,
            "center": center,
            "float": float,
            "int": int,
            "list": list,
            "max": max,
            "min": min,
            "round": round,
            "title": title,
            "wordcount": wordcount,
            "replace": replace,
            "urlencode": urlencode,
            "batch": batch,
            "sum": sum,
            "truncate": truncate,
            "unique": unique,
            "indent": indent,
            "items": items,
        ]
}

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
    "range": .function { values, _, _ in
        guard !values.isEmpty else { return .array([]) }

        switch values.count {
        case 1:
            if case let .int(end) = values[0] {
                return .array((0..<end).map { .int($0) })
            }
        case 2:
            if case let .int(start) = values[0],
                case let .int(end) = values[1]
            {
                return .array((start..<end).map { .int($0) })
            }
        case 3:
            if case let .int(start) = values[0],
                case let .int(end) = values[1],
                case let .int(step) = values[2]
            {
                return .array(stride(from: start, to: end, by: step).map { .int($0) })
            }
        default:
            break
        }

        throw JinjaError.runtime("Invalid arguments to range function")
    },
    "namespace": .function { _, kwargs, _ in
        var ns: OrderedDictionary<String, Value> = [:]
        for (key, value) in kwargs {
            ns[key] = value
        }
        return .object(ns)
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

/// Internal control flow exceptions for loop statements.
enum ControlFlow: Error, Sendable {
    /// Control flow exception for break statement.
    case `break`
    /// Control flow exception for continue statement.
    case `continue`
}

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
            return .double(value)

        case let .integer(value):
            return .int(value)

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

        case let .tuple(elements):
            var values: [Value] = []
            values.reserveCapacity(elements.count)
            for element in elements {
                let value = try evaluateExpression(element, env: env)
                values.append(value)
            }
            return .array(values)  // Tuples are represented as arrays in the runtime

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

            // Handle short-circuiting operators
            switch op {
            case .and:
                return leftValue.isTruthy ? try evaluateExpression(right, env: env) : leftValue
            case .or:
                return leftValue.isTruthy ? leftValue : try evaluateExpression(right, env: env)
            default:
                let rightValue = try evaluateExpression(right, env: env)
                return try evaluateBinaryValues(op, leftValue, rightValue)
            }

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

        case let .call(callableExpr, argsExpr, kwargsExpr):
            let callableValue = try evaluateExpression(callableExpr, env: env)
            guard case let .function(function) = callableValue else {
                throw JinjaError.runtime("Cannot call non-function value")
            }

            // Handle unpacking in arguments
            var argValues: [Value] = []
            for argExpr in argsExpr {
                if case let .unary(.multiply, expr) = argExpr {
                    // Unpack the array/tuple
                    let value = try evaluateExpression(expr, env: env)
                    if case let .array(items) = value {
                        argValues.append(contentsOf: items)
                    } else {
                        throw JinjaError.runtime("Cannot unpack non-array value")
                    }
                } else {
                    argValues.append(try evaluateExpression(argExpr, env: env))
                }
            }

            let kwargs = try kwargsExpr.mapValues { try evaluateExpression($0, env: env) }
            return try function(argValues, kwargs, env)

        case let .slice(array, start, stop, step):
            let arrayValue = try evaluateExpression(array, env: env)

            let startIdx: Value? = try start.map { try evaluateExpression($0, env: env) }
            let stopIdx: Value? = try stop.map { try evaluateExpression($0, env: env) }
            let stepVal: Value? = try step.map { try evaluateExpression($0, env: env) }

            switch arrayValue {
            case let .array(items):
                // Array slice implementation similar to string slicing
                var sliceStart = 0
                var sliceEnd = items.count
                var sliceStep = 1

                if let stepValue = stepVal, case let .int(st) = stepValue {
                    sliceStep = st
                }

                if let startValue = startIdx, case let .int(s) = startValue {
                    sliceStart = s >= 0 ? s : items.count + s
                } else if sliceStep < 0 {
                    sliceStart = items.count - 1
                }

                if let stopValue = stopIdx, case let .int(e) = stopValue {
                    sliceEnd = e >= 0 ? e : items.count + e
                } else if sliceStep < 0 {
                    sliceEnd = -1  // Go to beginning for reverse slice
                }

                var result: [Value] = []
                if sliceStep > 0 {
                    var idx = sliceStart
                    while idx < sliceEnd && idx >= 0 && idx < items.count {
                        result.append(items[idx])
                        idx += sliceStep
                    }
                } else if sliceStep < 0 {
                    var idx = sliceStart
                    while idx > sliceEnd && idx >= 0 && idx < items.count {
                        result.append(items[idx])
                        idx += sliceStep
                    }
                }
                return .array(result)

            case let .string(str):
                // String slice implementation
                let chars = Array(str)
                var sliceStart = 0
                var sliceEnd = chars.count
                var sliceStep = 1

                if let stepValue = stepVal, case let .int(st) = stepValue {
                    sliceStep = st
                }

                if let startValue = startIdx, case let .int(s) = startValue {
                    sliceStart = s >= 0 ? s : chars.count + s
                } else if sliceStep < 0 {
                    sliceStart = chars.count - 1
                }

                if let stopValue = stopIdx, case let .int(e) = stopValue {
                    sliceEnd = e >= 0 ? e : chars.count + e
                } else if sliceStep < 0 {
                    sliceEnd = -1  // Go to beginning for reverse slice
                }

                var result: [Character] = []
                if sliceStep > 0 {
                    var idx = sliceStart
                    while idx < sliceEnd && idx >= 0 && idx < chars.count {
                        result.append(chars[idx])
                        idx += sliceStep
                    }
                } else if sliceStep < 0 {
                    var idx = sliceStart
                    while idx > sliceEnd && idx >= 0 && idx < chars.count {
                        result.append(chars[idx])
                        idx += sliceStep
                    }
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
                            "index": .int(index + 1),
                            "index0": .int(index),
                            "first": .boolean(index == 0),
                            "last": .boolean(index == items.count - 1),
                            "length": .int(items.count),
                            "revindex": .int(items.count - index),
                            "revindex0": .int(items.count - index - 1),
                        ]

                        // Add cycle function
                        let cycleFunction:
                            @Sendable ([Value], [String: Value], Environment) throws -> Value = {
                                cycleArgs, _, _ in
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
                        var shouldBreak = false
                        for node in body {
                            do {
                                try interpretNode(node, env: childEnv, into: &buffer)
                            } catch ControlFlow.break {
                                shouldBreak = true
                                break
                            } catch ControlFlow.continue {
                                break  // Break from inner loop (current iteration)
                            }
                        }
                        if shouldBreak { break }
                    }
                }

            case let .object(dict):
                if dict.isEmpty {
                    for node in elseBody { try interpretNode(node, env: env, into: &buffer) }
                } else {
                    let childEnv = Environment(parent: env)
                    for (index, (key, value)) in dict.enumerated() {
                        switch loopVar {
                        case let .single(varName):
                            // Single variable gets the key
                            childEnv[varName] = .string(key)
                        case let .tuple(varNames):
                            // Tuple unpacking: first gets key, second gets value
                            if varNames.count >= 1 {
                                childEnv[varNames[0]] = .string(key)
                            }
                            if varNames.count >= 2 {
                                childEnv[varNames[1]] = value
                            }
                            // Set remaining variables to undefined
                            for i in 2..<varNames.count {
                                childEnv[varNames[i]] = .undefined
                            }
                        }
                        let loopContext: OrderedDictionary<String, Value> = [
                            "index": .int(index + 1),
                            "index0": .int(index),
                            "first": .boolean(index == 0),
                            "last": .boolean(index == dict.count - 1),
                            "length": .int(dict.count),
                            "revindex": .int(dict.count - index),
                            "revindex0": .int(dict.count - index - 1),
                        ]
                        var loopObj = loopContext
                        loopObj["cycle"] = .function { args, _, _ in
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
                            "index": .int(index + 1),
                            "index0": .int(index),
                            "first": .boolean(index == 0),
                            "last": .boolean(index == chars.count - 1),
                            "length": .int(chars.count),
                            "revindex": .int(chars.count - index),
                            "revindex0": .int(chars.count - index - 1),
                        ]
                        var loopObj = loopContext
                        loopObj["cycle"] = .function { args, _, _ in
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
            env[name] = .function { passedArgs, passedKwargs, callTimeEnv in
                let macroEnv = Environment(parent: env)

                let caller = callTimeEnv["caller"]
                if caller != .undefined {
                    macroEnv["caller"] = caller
                }

                // Start with defaults
                for (key, expr) in defaults {
                    // Evaluate defaults in current env
                    let val = try evaluateExpression(expr, env: env)
                    macroEnv[key] = val
                }
                // Bind positional args
                for (index, paramName) in parameters.enumerated() {
                    let value =
                        index < passedArgs.count ? passedArgs[index] : macroEnv[paramName]
                    macroEnv[paramName] = value
                }
                // Bind keyword args
                for (key, value) in passedKwargs {
                    macroEnv[key] = value
                }
                var macroBuffer = Buffer()
                try interpret(body, env: macroEnv, into: &macroBuffer)
                return .string(macroBuffer.build())
            }

        case let .program(nodes):
            try interpret(nodes, env: env, into: &buffer)

        case let .call(callExpr, callerParameters, body):
            let (callable, args, kwargs) = Self.extractCallParts(from: callExpr)

            guard let callableValue = try? evaluateExpression(callable, env: env),
                case .function(let function) = callableValue
            else {
                throw JinjaError.runtime("Cannot call non-function value")
            }

            let callTimeEnv = Environment(parent: env)
            callTimeEnv["caller"] = .function { callerArgs, _, _ in
                let bodyEnv = Environment(parent: env)
                for (paramName, value) in zip(callerParameters ?? [], callerArgs) {
                    guard case let .identifier(paramName) = paramName else {
                        throw JinjaError.runtime("Caller parameter must be an identifier")
                    }
                    bodyEnv[paramName] = value
                }
                var bodyBuffer = Buffer()
                try interpret(body, env: bodyEnv, into: &bodyBuffer)
                return .string(bodyBuffer.build())
            }

            let finalArgs = try args.map { try evaluateExpression($0, env: env) }
            let finalKwargs = try kwargs.mapValues { try evaluateExpression($0, env: env) }

            let result = try function(finalArgs, finalKwargs, callTimeEnv)
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

        case .break:
            throw ControlFlow.break
        case .continue:
            throw ControlFlow.continue
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
            env[name] = .function { passedArgs, passedKwargs, callTimeEnv in
                let macroEnv = Environment(parent: env)

                let caller = callTimeEnv["caller"]
                if caller != .undefined {
                    macroEnv["caller"] = caller
                }

                // Start with defaults
                for (key, expr) in defaults {
                    // Evaluate defaults in current env
                    let val = try evaluateExpression(expr, env: env)
                    macroEnv[key] = val
                }
                // Bind positional args
                for (index, paramName) in parameters.enumerated() {
                    let value =
                        index < passedArgs.count ? passedArgs[index] : macroEnv[paramName]
                    macroEnv[paramName] = value
                }
                // Bind keyword args
                for (key, value) in passedKwargs {
                    macroEnv[key] = value
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
            guard case let .array(values) = value else {
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
        case .member(let objectExpr, let propertyExpr, let computed):
            // Handle property assignment like ns.foo = 'bar'
            let objectValue = try evaluateExpression(objectExpr, env: env)

            if computed {
                let propertyValue = try evaluateExpression(propertyExpr, env: env)
                guard case let .string(key) = propertyValue else {
                    throw JinjaError.runtime("Computed property key must be a string")
                }
                if case var .object(dict) = objectValue {
                    dict[key] = value
                    // Update the object in the environment
                    if case let .identifier(name) = objectExpr {
                        env[name] = .object(dict)
                    }
                }
            } else {
                guard case let .identifier(propertyName) = propertyExpr else {
                    throw JinjaError.runtime("Property assignment requires identifier")
                }
                if case var .object(dict) = objectValue {
                    dict[propertyName] = value
                    // Update the object in the environment
                    if case let .identifier(name) = objectExpr {
                        env[name] = .object(dict)
                    }
                }
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
        case .multiply:
            // This should not be evaluated directly - it's only used for unpacking in calls
            throw JinjaError.runtime("Unpacking operator can only be used in function calls")
        case .minus:
            switch value {
            case let .double(n):
                return .double(-n)
            case let .int(i):
                return .int(-i)
            default:
                throw JinjaError.runtime("Cannot negate non-numeric value")
            }
        case .plus:
            switch value {
            case .double, .int:
                return value
            default:
                throw JinjaError.runtime("Cannot apply unary plus to non-numeric value")
            }
        }
    }

    private static func evaluateComputedMember(_ object: Value, _ property: Value) throws -> Value {
        switch (object, property) {
        case let (.array(arr), .int(index)):
            let safeIndex = index < 0 ? arr.count + index : index
            guard safeIndex >= 0 && safeIndex < arr.count else {
                return .undefined
            }
            return arr[safeIndex]

        case let (.object(obj), .string(key)):
            return obj[key] ?? .undefined

        case let (.string(str), .int(index)):
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
                return .function { _, _, _ in .string(str.uppercased()) }
            case "lower":
                return .function { _, _, _ in .string(str.lowercased()) }
            case "title":
                return .function { _, _, _ in .string(str.capitalized) }
            case "strip":
                return .function { _, _, _ in
                    .string(str.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            case "lstrip":
                return .function { _, _, _ in
                    let trimmed = str.drop(while: { $0.isWhitespace })
                    return .string(String(trimmed))
                }
            case "rstrip":
                return .function { _, _, _ in
                    let reversed = str.reversed().drop(while: { $0.isWhitespace })
                    return .string(String(reversed.reversed()))
                }
            case "split":
                return .function { args, _, _ in
                    if args.isEmpty {
                        // Split on whitespace
                        let components = str.split(separator: " ").map(String.init)
                        return .array(components.map(Value.string))
                    } else if case let .string(separator) = args[0] {
                        if args.count > 1, case let .int(limit) = args[1] {
                            // Split with limit: split at most 'limit' times
                            var components: [String] = []
                            var remaining = str
                            var splits = 0

                            while splits < limit, let range = remaining.range(of: separator) {
                                components.append(String(remaining[..<range.lowerBound]))
                                remaining = String(remaining[range.upperBound...])
                                splits += 1
                            }
                            // Add the remainder
                            components.append(remaining)
                            return .array(components.map(Value.string))
                        } else {
                            let components = str.components(separatedBy: separator)
                            return .array(components.map(Value.string))
                        }
                    }
                    return .array([.string(str)])
                }
            case "replace":
                return .function { args, kwargs, _ in
                    guard args.count >= 2,
                        case let .string(old) = args[0],
                        case let .string(new) = args[1]
                    else {
                        return .string(str)
                    }

                    // Check for count parameter in args or kwargs
                    var maxReplacements: Int? = nil
                    if args.count > 2, case let .int(count) = args[2] {
                        maxReplacements = count
                    } else if let countValue = kwargs["count"],
                        case let .int(count) = countValue
                    {
                        maxReplacements = count
                    }

                    // Special case: replacing empty string inserts at character boundaries
                    if old.isEmpty {
                        var result = ""
                        var replacements = 0
                        for char in str {
                            if let count = maxReplacements, replacements >= count {
                                result += String(char)
                            } else {
                                result += new + String(char)
                                replacements += 1
                            }
                        }
                        // Add final replacement if we haven't hit the count limit
                        if maxReplacements == nil || replacements < maxReplacements! {
                            result += new
                        }
                        return .string(result)
                    }

                    if let count = maxReplacements {
                        // Replace only the first 'count' occurrences
                        var result = str
                        var replacements = 0
                        while replacements < count, let range = result.range(of: old) {
                            result.replaceSubrange(range, with: new)
                            replacements += 1
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
                let fn: @Sendable ([Value], [String: Value], Environment) throws -> Value = {
                    _, _, _ in
                    let pairs = obj.map { key, value in Value.array([.string(key), value]) }
                    return .array(pairs)
                }
                return .function(fn)
            }
            // Support Python-like dict.get(key, default) method
            if propertyName == "get" {
                let fn: @Sendable ([Value], [String: Value], Environment) throws -> Value = {
                    args, _, _ in
                    guard !args.isEmpty else {
                        throw JinjaError.runtime("get() requires at least 1 argument")
                    }

                    let key: String
                    switch args[0] {
                    case let .string(s):
                        key = s
                    default:
                        key = args[0].description
                    }

                    let defaultValue = args.count > 1 ? args[1] : .null
                    return obj[key] ?? defaultValue
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
        // Try environment-provided tests first
        let testValue = env[testName]
        if case let .function(fn) = testValue {
            let result = try fn(argValues, [:], env)
            if case let .boolean(b) = result { return b }
            return result.isTruthy
        }

        // Fallback to built-in tests
        if let testFunction = Tests.builtIn[testName] {
            return try testFunction(argValues, [:], env)
        }

        throw JinjaError.runtime("Unknown test: \(testName)")
    }

    public static func evaluateFilter(
        _ filterName: String, _ argValues: [Value], kwargs: [String: Value], env: Environment
    )
        throws -> Value
    {
        // Try environment-provided filters first
        let filterValue = env[filterName]
        if case let .function(fn) = filterValue {
            return try fn(argValues, kwargs, env)
        }

        // Fallback to built-in filters
        if let filterFunction = Filters.builtIn[filterName] {
            return try filterFunction(argValues, kwargs, env)
        }

        throw JinjaError.runtime("Unknown filter: \(filterName)")
    }

    // MARK: - Helper Methods

    public static func addValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.int(a), .int(b)):
            return .int(a + b)
        case let (.double(a), .double(b)):
            return .double(a + b)
        case let (.int(a), .double(b)):
            return .double(Double(a) + b)
        case let (.double(a), .int(b)):
            return .double(a + Double(b))
        case let (.string(a), .string(b)):
            return .string(a + b)
        case let (.string(a), b):
            return .string(a + b.description)
        case let (a, .string(b)):
            return .string(a.description + b)
        case let (.array(a), .array(b)):
            return .array(a + b)
        default:
            throw JinjaError.runtime("Cannot add values of different types (\(left) and \(right))")
        }
    }

    private static func subtractValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.int(a), .int(b)):
            return .int(a - b)
        case let (.double(a), .double(b)):
            return .double(a - b)
        case let (.int(a), .double(b)):
            return .double(Double(a) - b)
        case let (.double(a), .int(b)):
            return .double(a - Double(b))
        default:
            throw JinjaError.runtime("Cannot subtract non-numeric values (\(left) and \(right))")
        }
    }

    private static func multiplyValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.int(a), .int(b)):
            return .int(a * b)
        case let (.double(a), .double(b)):
            return .double(a * b)
        case let (.int(a), .double(b)):
            return .double(Double(a) * b)
        case let (.double(a), .int(b)):
            return .double(a * Double(b))
        case let (.string(s), .int(n)):
            return .string(String(repeating: s, count: n))
        case let (.int(n), .string(s)):
            return .string(String(repeating: s, count: n))
        default:
            throw JinjaError.runtime("Cannot multiply values of these types (\(left) and \(right))")
        }
    }

    private static func divideValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.int(a), .int(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .double(Double(a) / Double(b))
        case let (.double(a), .double(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .double(a / b)
        case let (.int(a), .double(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .double(Double(a) / b)
        case let (.double(a), .int(b)):
            guard b != 0 else { throw JinjaError.runtime("Division by zero") }
            return .double(a / Double(b))
        default:
            throw JinjaError.runtime("Cannot divide non-numeric values (\(left) and \(right))")
        }
    }

    private static func moduloValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.int(a), .int(b)):
            guard b != 0 else { throw JinjaError.runtime("Modulo by zero") }
            return .int(a % b)
        default:
            throw JinjaError.runtime("Modulo operation requires integers (\(left) and \(right))")
        }
    }

    public static func compareValues(_ left: Value, _ right: Value) throws -> Int {
        switch (left, right) {
        case let (.int(a), .int(b)):
            return a < b ? -1 : a > b ? 1 : 0
        case let (.double(a), .double(b)):
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
        case let (.int(a), .int(b)):
            return a == b
        case let (.double(a), .double(b)):
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

    private static func extractCallParts(from expression: Expression) -> (
        callable: Expression, args: [Expression], kwargs: [String: Expression]
    ) {
        switch expression {
        case let .call(callable, args, kwargs):
            return (callable, args, kwargs)
        default:
            return (expression, [], [:])
        }
    }
}

// MARK: - Tests

/// Built-in tests for Jinja template rendering.
public enum Tests {
    // MARK: - Basic Tests

    /// Tests if a value is defined (not undefined).
    @Sendable public static func defined(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value != .undefined
    }

    /// Tests if a value is undefined.
    @Sendable public static func undefined(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return true }
        return value == .undefined
    }

    /// Tests if a value is none/null.
    @Sendable public static func none(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value == .null
    }

    /// Tests if a value is a string.
    @Sendable public static func string(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value.isString
    }

    /// Tests if a value is a number.
    @Sendable public static func number(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value.isInt || value.isDouble
    }

    /// Tests if a value is a boolean.
    @Sendable public static func boolean(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value.isBoolean
    }

    /// Tests if a value is iterable.
    @Sendable public static func iterable(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value.isIterable
    }

    // MARK: - Numeric Tests

    /// Tests if a number is even.
    @Sendable public static func even(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        switch value {
        case let .int(num):
            return num % 2 == 0
        case let .double(num):
            return Int(num) % 2 == 0
        default:
            return false
        }
    }

    /// Tests if a number is odd.
    @Sendable public static func odd(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        switch value {
        case let .int(num):
            return num % 2 != 0
        case let .double(num):
            return Int(num) % 2 != 0
        default:
            return false
        }
    }

    /// Tests if a number is divisible by another number.
    @Sendable public static func divisibleby(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        switch (args[0], args[1]) {
        case let (.int(a), .int(b)):
            return b != 0 && a % b == 0
        case let (.double(a), .double(b)):
            return b != 0.0 && Int(a) % Int(b) == 0
        default:
            return false
        }
    }

    // MARK: - Comparison Tests

    /// Tests if two values are equal.
    @Sendable public static func equalto(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        return Interpreter.valuesEqual(args[0], args[1])
    }

    /// Tests if a value is a mapping (dictionary/object).
    @Sendable public static func mapping(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        if case .object(_) = value {
            return true
        }
        return false
    }

    /// Tests if a value is callable (function).
    @Sendable public static func callable(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        if case .function(_) = value {
            return true
        }
        return false
    }

    /// Tests if a value is an integer.
    @Sendable public static func integer(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        if case .int(_) = value {
            return true
        }
        return false
    }

    /// Tests if a string is all lowercase.
    @Sendable public static func lower(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        if case let .string(str) = value {
            return str == str.lowercased() && str != str.uppercased()
        }
        return false
    }

    /// Tests if a string is all uppercase.
    @Sendable public static func upper(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        if case let .string(str) = value {
            return str == str.uppercased() && str != str.lowercased()
        }
        return false
    }

    /// Tests if a value is true.
    @Sendable public static func `true`(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value == .boolean(true)
    }

    /// Tests if a value is false.
    @Sendable public static func `false`(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        return value == .boolean(false)
    }

    /// Tests if a value is a float.
    @Sendable public static func float(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        if case .double(_) = value {
            return true
        }
        return false
    }

    /// Tests if a value is a sequence (array or string).
    @Sendable public static func sequence(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first else { return false }
        switch value {
        case .array(_), .string(_):
            return true
        default:
            return false
        }
    }

    /// Tests if a value is escaped (always returns false for basic implementation).
    @Sendable public static func escaped(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        // In basic implementation, values are not escaped by default
        return false
    }

    /// Tests if a filter exists by name.
    @Sendable public static func filter(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first, case let .string(filterName) = value else { return false }
        return Filters.builtIn[filterName] != nil
    }

    /// Tests if a test exists by name.
    @Sendable public static func test(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard let value = args.first, case let .string(testName) = value else { return false }
        return Tests.builtIn[testName] != nil
    }

    /// Tests if two values point to the same memory address (identity test).
    @Sendable public static func sameas(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        // For basic implementation, this is the same as equality
        // In a more advanced implementation, this would check object identity
        return Interpreter.valuesEqual(args[0], args[1])
    }

    /// Tests if a value is in a sequence.
    @Sendable public static func `in`(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        let value = args[0]
        let container = args[1]

        switch container {
        case let .array(arr):
            return arr.contains { Interpreter.valuesEqual($0, value) }
        case let .string(str):
            if case let .string(searchStr) = value {
                return str.contains(searchStr)
            }
            return false
        case let .object(dict):
            if case let .string(key) = value {
                return dict[key] != nil
            }
            return false
        default:
            return false
        }
    }

    // MARK: - Comparison Tests

    /// Tests if a == b.
    @Sendable public static func eq(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        return try equalto(args, kwargs: kwargs, env: env)
    }

    /// Tests if a != b.
    @Sendable public static func ne(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        return !Interpreter.valuesEqual(args[0], args[1])
    }

    /// Tests if a > b.
    @Sendable public static func gt(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        do {
            return try Interpreter.compareValues(args[0], args[1]) > 0
        } catch {
            return false
        }
    }

    /// Tests if a >= b.
    @Sendable public static func ge(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        do {
            return try Interpreter.compareValues(args[0], args[1]) >= 0
        } catch {
            return false
        }
    }

    /// Tests if a < b.
    @Sendable public static func lt(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        do {
            return try Interpreter.compareValues(args[0], args[1]) < 0
        } catch {
            return false
        }
    }

    /// Tests if a <= b.
    @Sendable public static func le(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Bool {
        guard args.count >= 2 else { return false }
        do {
            return try Interpreter.compareValues(args[0], args[1]) <= 0
        } catch {
            return false
        }
    }

    /// Dictionary of all available tests.
    public static let builtIn:
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
            "mapping": mapping,
            "callable": callable,
            "integer": integer,
            "true": `true`,
            "false": `false`,
            "lower": lower,
            "upper": upper,
            "float": float,
            "sequence": sequence,
            "escaped": escaped,
            "filter": filter,
            "test": test,
            "sameas": sameas,
            "in": `in`,
            "eq": eq,
            "==": eq,
            "equalto": eq,
            "ne": ne,
            "!=": ne,
            "gt": gt,
            ">": gt,
            "greaterthan": gt,
            "ge": ge,
            ">=": ge,
            "lt": lt,
            "<": lt,
            "lessthan": lt,
            "le": le,
            "<=": le,
        ]
}

// MARK: - Filters

/// Built-in filters for Jinja template rendering.
public enum Filters {
    // MARK: - Basic String Filters

    /// Converts a string to uppercase.
    @Sendable public static func upper(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            throw JinjaError.runtime("upper filter requires string")
        }
        return .string(str.uppercased())
    }

    /// Converts a string to lowercase.
    @Sendable public static func lower(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            throw JinjaError.runtime("lower filter requires string")
        }
        return .string(str.lowercased())
    }

    /// Returns the length of a string, array, or object.
    @Sendable public static func length(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        switch args.first {
        case let .string(str):
            return .int(str.count)
        case let .array(arr):
            return .int(arr.count)
        case let .object(obj):
            return .int(obj.count)
        default:
            throw JinjaError.runtime("length filter requires string, array, or object")
        }
    }

    /// Joins an array of values with a separator.
    @Sendable public static func join(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard args.count >= 2,
            case let .array(array) = args[0],
            case let .string(separator) = args[1]
        else {
            throw JinjaError.runtime("join filter requires array and separator")
        }

        let strings = array.map { $0.description }
        return .string(strings.joined(separator: separator))
    }

    /// Returns a default value if the input is undefined,
    /// or if the input is falsey and the second / `boolean` argument is `true`.
    @Sendable public static func `default`(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard args.count >= 2 else {
            throw JinjaError.runtime("default filter requires at least 2 arguments")
        }

        let input = args[0]
        let defaultValue = args[1]

        let boolean: Bool?
        if args.count > 3 {
            boolean = args[3].isTruthy
        } else if case let .boolean(boolValue) = kwargs["boolean"] {
            boolean = boolValue
        } else {
            boolean = nil
        }

        // If input is undefined, return default value
        if input == .undefined {
            return defaultValue
        }

        // If boolean is true and input is falsey, return default value
        if boolean == true && !input.isTruthy {
            return defaultValue
        }

        // Otherwise return the input value
        return input
    }

    // MARK: - Array Filters

    /// Returns the first item from an array.
    @Sendable public static func first(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value else {
            return .array([])
        }

        let reverse = kwargs["reverse"]?.isTruthy ?? false
        let caseSensitive = kwargs["case_sensitive"]?.isTruthy ?? true

        let sortedItems: [Value]
        if case let .string(attribute)? = kwargs["attribute"] {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value,
            args.count > 1, case let .string(attribute) = args[1]
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value,
            args.count > 1, case let .int(numSlices) = args[1], numSlices > 0
        else {
            return .array([])
        }

        let fillWith = args.count > 2 ? args[2] : .null
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value else {
            return .array([])
        }

        if args.count > 1, case let .string(filterName) = args[1] {
            return .array(
                try items.map {
                    try Interpreter.evaluateFilter(filterName, [$0], kwargs: [:], env: env)
                })
        } else if case let .string(attribute)? = kwargs["attribute"] {
            return .array(
                try items.map {
                    try Interpreter.evaluatePropertyMember($0, attribute)
                })
        }

        return .array([])
    }

    /// Selects items that pass a test.
    @Sendable public static func select(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value,
            args.count > 1, case let .string(testName) = args[1]
        else {
            return .array([])
        }
        let testArgs = Array(args.dropFirst(2))
        return .array(
            try items.filter {
                try Interpreter.evaluateTest(testName, [$0] + testArgs, env: env)
            })
    }

    /// Rejects items that pass a test.
    @Sendable public static func reject(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value,
            args.count > 1, case let .string(testName) = args[1]
        else {
            return .array([])
        }
        let testArgs = Array(args.dropFirst(2))
        return .array(
            try items.filter {
                try !Interpreter.evaluateTest(testName, [$0] + testArgs, env: env)
            })
    }

    /// Selects items with an attribute that passes a test.
    /// If no test is specified,
    /// the attribute’s value will be evaluated as a boolean.
    @Sendable public static func selectattr(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .array(items)? = args.first,
              args.count >= 2, case let .string(attribute) = args[1]
        else {
            return .array([])
        }
                
        let testArgs = Array(args.dropFirst(2))
        return .array(
            try items.filter {
                let attrValue = try Interpreter.evaluatePropertyMember($0, attribute)
                guard !testArgs.isEmpty else {
                    return attrValue.isTruthy
                }
                return try Interpreter.evaluateTest(attribute, [attrValue] + testArgs, env: env)
            })
    }

    /// Rejects items with an attribute that passes a test.
    @Sendable public static func rejectattr(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value,
            args.count > 2, case let .string(attribute) = args[1],
            case let .string(testName) = args[2]
        else {
            return .array([])
        }
        let testArgs = Array(args.dropFirst(3))
        return .array(
            try items.filter {
                let attrValue = try Interpreter.evaluatePropertyMember($0, attribute)
                return try !Interpreter.evaluateTest(testName, [attrValue] + testArgs, env: env)
            })
    }

    // MARK: - Object Filters

    /// Gets an attribute from an object.
    @Sendable public static func attr(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let obj = args.first, args.count > 1,
            case let .string(attribute) = args[1]
        else {
            return .undefined
        }
        return try Interpreter.evaluatePropertyMember(obj, attribute)
    }

    /// Sorts a dictionary by keys and returns key-value pairs.
    @Sendable public static func dictsort(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .object(dict) = args.first else {
            return .array([])
        }

        let caseSensitive =
            kwargs["case_sensitive"]?.isTruthy ?? (args.count > 1 ? args[1].isTruthy : false)
        let by: String
        if case let .string(s)? = kwargs["by"] {
            by = s
        } else if args.count > 2, case let .string(s) = args[2] {
            by = s
        } else {
            by = "key"
        }
        let reverse = kwargs["reverse"]?.isTruthy ?? (args.count > 3 ? args[3].isTruthy : false)

        let sortedPairs: [(key: String, value: Value)]
        if by == "value" {
            sortedPairs = dict.sorted { a, b in
                let comparison =
                    caseSensitive
                    ? a.value.description.compare(b.value.description)
                    : a.value.description.localizedCaseInsensitiveCompare(b.value.description)
                return reverse ? comparison == .orderedDescending : comparison == .orderedAscending
            }
        } else {
            sortedPairs = dict.sorted { a, b in
                let comparison =
                    caseSensitive
                    ? a.key.compare(b.key)
                    : a.key.localizedCaseInsensitiveCompare(b.key)
                return reverse ? comparison == .orderedDescending : comparison == .orderedAscending
            }
        }

        let resultArray = sortedPairs.map { key, value in
            Value.array([.string(key), value])
        }
        return .array(resultArray)
    }

    // MARK: - String Processing Filters

    /// Escapes HTML characters.
    @Sendable public static func forceescape(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        return args.first ?? .string("")
    }

    /// Strips HTML tags from a string.
    @Sendable public static func striptags(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard args.count > 1, case let .string(formatString) = args[0] else {
            return args.first ?? .string("")
        }
        let args = Array(args.dropFirst())
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .string(str) = value else {
            return .string("")
        }
        let width: Int
        if args.count > 1, case let .int(w) = args[1] {
            width = w
        } else {
            width = 79
        }
        _ = args.count > 2 ? (args[2].isTruthy) : true

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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .double(num) = value else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .object(dict) = value else {
            return .string("")
        }
        let autospace =
            kwargs["autospace"]?.isTruthy ?? (args.count > 1 ? args[1].isTruthy : true)
        var result = ""
        for (key, value) in dict {
            if value == .null || value == .undefined { continue }
            // Validate key doesn't contain invalid characters
            if key.contains(" ") || key.contains("/") || key.contains(">") || key.contains("=") {
                throw JinjaError.runtime("Invalid character in XML attribute key: '\(key)'")
            }
            let escapedValue = value.description
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            result += "\(key)=\"\(escapedValue)\""
        }
        if autospace && !result.isEmpty {
            result = " " + result
        }
        return .string(result)
    }

    /// Converts a value to a string.
    @Sendable public static func string(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else { return .string("") }
        return .string(value.description)
    }

    // MARK: - Additional Filters

    /// Trims whitespace from a string.
    @Sendable public static func trim(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            return .string("")
        }
        return .string(str.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Escapes HTML characters (alias for forceescape).
    @Sendable public static func escape(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        return try forceescape(args, kwargs: kwargs, env: env)
    }

    /// Converts value to JSON string.
    @Sendable public static func tojson(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else { return .string("null") }

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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else {
            return .int(0)
        }
        switch value {
        case let .int(i):
            return .int(Swift.abs(i))
        case let .double(n):
            return .double(Swift.abs(n))
        default:
            throw JinjaError.runtime("abs filter requires number or integer")
        }
    }

    /// Capitalizes the first letter and lowercases the rest.
    @Sendable public static func capitalize(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            return .string("")
        }
        return .string(str.prefix(1).uppercased() + str.dropFirst().lowercased())
    }

    /// Centers a string within a specified width.
    @Sendable public static func center(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first,
            args.count > 1,
            case let .int(width) = args[1]
        else {
            return args.first ?? .string("")
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else { return .double(0.0) }
        switch value {
        case let .int(i):
            return .double(Double(i))
        case let .double(n):
            return .double(n)
        case let .string(s):
            return .double(Double(s) ?? 0.0)
        default:
            return .double(0.0)
        }
    }

    /// Converts a value to integer.
    @Sendable public static func int(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else { return .int(0) }
        switch value {
        case let .int(i):
            return .int(i)
        case let .double(n):
            return .int(Int(n))
        case let .string(s):
            return .int(Int(s) ?? 0)
        default:
            return .int(0)
        }
    }

    /// Converts a value to list.
    @Sendable public static func list(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else { return .array([]) }
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value else { return .undefined }
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value else { return .undefined }
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else { return .double(0.0) }
        let precision: Int
        if args.count > 1, case let .int(p) = args[1] {
            precision = p
        } else {
            precision = 0
        }
        let method: String
        if args.count > 2, case let .string(m) = args[2] {
            method = m
        } else {
            method = "common"
        }

        guard case let .double(number) = value else {
            return value  // Or throw error
        }

        if method == "common" {
            let divisor = pow(10.0, Double(precision))
            return .double((number * divisor).rounded() / divisor)
        } else if method == "ceil" {
            let divisor = pow(10.0, Double(precision))
            return .double(ceil(number * divisor) / divisor)
        } else if method == "floor" {
            let divisor = pow(10.0, Double(precision))
            return .double(floor(number * divisor) / divisor)
        }
        return .double(number)
    }

    /// Capitalizes each word in a string.
    @Sendable public static func title(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            return .string("")
        }
        return .string(str.capitalized)
    }

    /// Counts words in a string.
    @Sendable public static func wordcount(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            return .int(0)
        }
        let words = str.split { $0.isWhitespace || $0.isNewline }
        return .int(words.count)
    }

    /// Return string with all occurrences of a substring replaced with a new one.
    /// The first argument is the substring that should be replaced,
    /// the second is the replacement string.
    /// If the optional third argument count is given,
    /// only the first count occurrences are replaced.
    @Sendable public static func replace(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard args.count >= 3,
            case let .string(str) = args[0],
            case let .string(old) = args[1],
            case let .string(new) = args[2]
        else {
            return args.first ?? .string("")
        }

        // Handle count parameter - can be positional (3rd arg) or named (count=)
        let count: Int?
        if args.count > 3, case let .int(c) = args[3] {
            count = c
        } else if let countValue = kwargs["count"], case let .int(c) = countValue {
            count = c
        } else {
            count = nil
        }

        // Special case: replacing empty string inserts at character boundaries
        if old.isEmpty {
            var result = ""
            var replacements = 0

            // Insert at the beginning
            if count == nil || replacements < count! {
                result += new
                replacements += 1
            }

            // Insert between each character
            for char in str {
                result += String(char)
                if count == nil || replacements < count! {
                    result += new
                    replacements += 1
                }
            }

            return .string(result)
        }

        // Regular case: replace occurrences of the substring
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value,
            args.count > 1, case let .int(batchSize) = args[1], batchSize > 0
        else {
            return .array([])
        }

        let fillWith = args.count > 2 ? args[2] : .null

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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value else {
            return .int(0)
        }

        let attribute: String?
        if case let .string(a)? = kwargs["attribute"] {
            attribute = a
        } else if args.count > 1, case let .string(a) = args[1] {
            attribute = a
        } else {
            attribute = nil
        }
        let start = kwargs["start"] ?? (args.count > 2 ? args[2] : .int(0))

        let valuesToSum: [Value]
        if let attr = attribute {
            valuesToSum = try items.map { item in
                try Interpreter.evaluatePropertyMember(item, attr)
            }
        } else {
            valuesToSum = items
        }

        let sum = try valuesToSum.reduce(start) { acc, next in
            try Interpreter.addValues(acc, next)
        }
        return sum
    }

    /// Truncates a string to a specified length.
    @Sendable public static func truncate(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            return .string("")
        }
        let length: Int
        if args.count > 1, case let .int(l) = args[1] {
            length = l
        } else {
            length = 255
        }
        let killwords = args.count > 2 ? (args[2].isTruthy) : false
        let end: String
        if args.count > 3, case let .string(e) = args[3] {
            end = e
        } else {
            end = "..."
        }

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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first, case let .array(items) = value else {
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
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = args.first else {
            return .string("")
        }

        let width: String
        if let widthValue = kwargs["width"] {
            if case let .int(intWidth) = widthValue {
                width = String(repeating: " ", count: intWidth)
            } else if case let .string(s) = widthValue {
                width = s
            } else {
                width = "    "
            }
        } else if args.count > 1 {
            if case let .int(intWidth) = args[1] {
                width = String(repeating: " ", count: intWidth)
            } else if case let .string(s) = args[1] {
                width = s
            } else {
                width = "    "
            }
        } else {
            width = "    "
        }

        let first = kwargs["first"]?.isTruthy ?? (args.count > 2 ? args[2].isTruthy : false)
        let blank = kwargs["blank"]?.isTruthy ?? (args.count > 3 ? args[3].isTruthy : false)

        let lines = str.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result = ""

        for (i, line) in lines.enumerated() {
            if i == 0 && !first {
                result += line
            } else if line.isEmpty && !blank {
                result += line
            } else {
                result += width + line
            }
            if i < lines.count - 1 {
                result += "\n"
            }
        }
        return .string(result)
    }

    /// Returns items (key-value pairs) of a dictionary/object.
    @Sendable public static func items(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else {
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

    /// Pretty prints a variable (useful for debugging).
    @Sendable public static func pprint(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = args.first else { return .string("") }

        func prettyPrint(_ val: Value, indent: Int = 0) -> String {
            let indentString = String(repeating: "  ", count: indent)
            switch val {
            case let .array(arr):
                if arr.isEmpty { return "[]" }
                let items = arr.map { prettyPrint($0, indent: indent + 1) }
                return "[\n" + items.map { "\(indentString)  \($0)" }.joined(separator: ",\n")
                    + "\n\(indentString)]"
            case let .object(dict):
                if dict.isEmpty { return "{}" }
                let items = dict.map { key, value in
                    "\(indentString)  \"\(key)\": \(prettyPrint(value, indent: indent + 1))"
                }
                return "{\n" + items.joined(separator: ",\n") + "\n\(indentString)}"
            case let .string(str):
                return "\"\(str)\""
            default:
                return val.description
            }
        }

        return .string(prettyPrint(value))
    }

    /// Converts URLs in text into clickable links.
    @Sendable public static func urlize(
        _ args: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(text) = args.first else {
            return .string("")
        }

        let trimUrlLimit: Int?
        if case let .int(limit)? = kwargs["trim_url_limit"] {
            trimUrlLimit = limit
        } else {
            trimUrlLimit = nil
        }
        let nofollow = kwargs["nofollow"]?.isTruthy ?? false
        let target: String?
        if case let .string(t)? = kwargs["target"] {
            target = t
        } else {
            target = nil
        }
        let rel: String?
        if case let .string(r)? = kwargs["rel"] {
            rel = r
        } else {
            rel = nil
        }

        func buildAttributes() -> String {
            var attributes = ""
            if nofollow { attributes += " rel=\"nofollow\"" }
            if let target = target { attributes += " target=\"\(target)\"" }
            if let rel = rel { attributes += " rel=\"\(rel)\"" }
            return attributes
        }

        // Basic implementation - just detect simple http/https URLs
        let httpRegex = try! NSRegularExpression(
            pattern: "https?://[^\\s<>\"'\\[\\]{}|\\\\^`]+", options: [])
        let range = NSRange(location: 0, length: text.utf16.count)

        var result = text
        let matches = httpRegex.matches(in: text, options: [], range: range).reversed()

        for match in matches {
            let url = (text as NSString).substring(with: match.range)
            let displayUrl =
                trimUrlLimit != nil && url.count > trimUrlLimit!
                ? String(url.prefix(trimUrlLimit!)) + "..." : url
            let replacement = "<a href=\"\(url)\"\(buildAttributes())>\(displayUrl)</a>"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return .string(result)
    }

    /// Dictionary of all available filters.
    public static let builtIn:
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
            "string": string,
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
            "pprint": pprint,
            "urlize": urlize,
        ]
}

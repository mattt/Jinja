import Foundation
@_exported import OrderedCollections

// MARK: - Context

/// A context is a dictionary of variables and their values.
public typealias Context = [String: Value]

// MARK: - Environment

/// Execution environment that stores variables and provides context for template rendering.
///
/// The environment maintains the variable scope during template execution and provides
/// configuration options that affect rendering behavior.
public final class Environment: @unchecked Sendable {
    private let parent: Environment?
    private(set) var variables: [String: Value] = [:]

    // Options

    /// Whether leading spaces and tabs are stripped from the start of a line to a block.
    /// The default value is `false`.
    public var lstripBlocks: Bool = false

    /// Whether the first newline after a block is removed.
    /// This applies to block tags, not variable tags.
    /// The default value is `false`.
    public var trimBlocks: Bool = false

    // MARK: -

    /// Creates a new environment with optional parent and initial variables.
    ///
    /// - Parameters:
    ///   - parent: The parent environment to inherit variables from
    ///   - initial: The initial variables to set in this environment
    public init(parent: Environment? = nil, initial: [String: Value] = [:]) {
        self.parent = parent
        self.variables = initial
    }

    /// Gets or sets a variable in the environment.
    ///
    /// When getting a variable, this looks in the current environment first,
    /// then in parent environments. Returns `.undefined` if the variable is not found.
    ///
    /// - Parameter name: The variable name
    /// - Returns: The value associated with the variable name, or `.undefined`
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

/// Executes parsed Jinja template nodes to produce rendered output.
public enum Interpreter {
    /// Interprets nodes and renders them to a string using the given environment.
    ///
    /// - Parameters:
    ///   - nodes: The AST nodes to interpret and render
    ///   - environment: The execution environment containing variables
    /// - Returns: The rendered template output as a string
    /// - Throws: `JinjaError` if an error occurs during interpretation
    public static func interpret(_ nodes: [Node], environment: Environment) throws -> String {
        // Use the fast path with synchronous environment
        let env = Environment(initial: environment.variables)
        var buffer: any TextOutputStream = Buffer()
        try interpret(nodes, env: env, into: &buffer)
        return (buffer as! Buffer).build()
    }

    // MARK: -

    static func interpret(
        _ nodes: [Node], env: Environment, into buffer: inout (any TextOutputStream)
    )
        throws
    {
        for node in nodes {
            try interpretNode(node, env: env, into: &buffer)
        }
    }

    static func interpretNode(
        _ node: Node, env: Environment, into buffer: inout (any TextOutputStream)
    )
        throws
    {
        switch node {
        case let .text(content):
            buffer.write(content)

        case .comment:
            // Comments are ignored during execution
            break

        case let .expression(expr):
            let value = try evaluateExpression(expr, env: env)
            buffer.write(value.description)

        case let .statement(stmt):
            try executeStatementWithOutput(stmt, env: env, into: &buffer)
        }
    }

    static func evaluateExpression(_ expr: Expression, env: Environment) throws -> Value {
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

            switch callableValue {
            case .function(let function):
                return try function(argValues, kwargs, env)
            case .macro(let macro):
                return try callMacro(
                    macro: macro, arguments: argValues, keywordArguments: kwargs, env: env)
            default:
                throw JinjaError.runtime("Cannot call non-function value")
            }

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
    static func executeStatementWithOutput(
        _ statement: Statement, env: Environment, into buffer: inout (any TextOutputStream)
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
                var bodyBuffer: any TextOutputStream = Buffer()
                try interpret(body, env: env, into: &bodyBuffer)
                let renderedBody = (bodyBuffer as! Buffer).build()
                let valueToAssign = Value.string(renderedBody)
                try assign(target: target, value: valueToAssign, env: env)
            }

        case let .macro(name, parameters, defaults, body):
            try registerMacro(
                name: name, parameters: parameters, defaults: defaults, body: body, env: env)

        case let .program(nodes):
            try interpret(nodes, env: env, into: &buffer)

        case let .call(callExpr, callerParameters, body):
            let callable: Expression
            let args: [Expression]
            let kwargs: [String: Expression]
            switch callExpr {
            case let .call(c, a, k):
                callable = c
                args = a
                kwargs = k
            default:
                callable = callExpr
                args = []
                kwargs = [:]
            }

            let callableValue = try evaluateExpression(callable, env: env)

            let callTimeEnv = Environment(parent: env)
            callTimeEnv["caller"] = .function { callerArgs, _, _ in
                let bodyEnv = Environment(parent: env)
                for (paramName, value) in zip(callerParameters ?? [], callerArgs) {
                    guard case let .identifier(paramName) = paramName else {
                        throw JinjaError.runtime("Caller parameter must be an identifier")
                    }
                    bodyEnv[paramName] = value
                }
                var bodyBuffer: any TextOutputStream = Buffer()
                try interpret(body, env: bodyEnv, into: &bodyBuffer)
                return .string((bodyBuffer as! Buffer).build())
            }

            let finalArgs = try args.map { try evaluateExpression($0, env: env) }
            let finalKwargs = try kwargs.mapValues { try evaluateExpression($0, env: env) }

            switch callableValue {
            case .function(let function):
                let result = try function(finalArgs, finalKwargs, callTimeEnv)
                buffer.write(result.description)
            case .macro(let macro):
                let result = try callMacro(
                    macro: macro, arguments: finalArgs, keywordArguments: finalKwargs,
                    env: callTimeEnv)
                buffer.write(result.description)
            default:
                throw JinjaError.runtime("Cannot call non-function value")
            }

        case let .filter(filterExpr, body):
            var bodyBuffer: any TextOutputStream = Buffer()
            try interpret(body, env: env, into: &bodyBuffer)
            let renderedBody = (bodyBuffer as! Buffer).build()

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

    static func executeStatement(_ statement: Statement, env: Environment) throws {
        switch statement {
        case let .set(target, value, body):
            if let valueExpr = value {
                let evaluatedValue = try evaluateExpression(valueExpr, env: env)
                try assign(target: target, value: evaluatedValue, env: env)
            } else {
                var bodyBuffer: any TextOutputStream = Buffer()
                try interpret(body, env: env, into: &bodyBuffer)
                let renderedBody = (bodyBuffer as! Buffer).build()
                let valueToAssign = Value.string(renderedBody)
                try assign(target: target, value: valueToAssign, env: env)
            }

        case let .macro(name, parameters, defaults, body):
            try registerMacro(
                name: name, parameters: parameters, defaults: defaults, body: body, env: env)

        // These statements do not produce output directly or are handled elsewhere.
        case .if, .for, .program, .break, .continue, .call, .filter:
            break
        }
    }

    static func assign(target: Expression, value: Value, env: Environment) throws {
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

    static func registerMacro(
        name: String, parameters: [String], defaults: OrderedDictionary<String, Expression>,
        body: [Node],
        env: Environment
    ) throws {
        env[name] = .macro(
            Macro(name: name, parameters: parameters, defaults: defaults, body: body))
    }

    static func callMacro(
        macro: Macro, arguments: [Value], keywordArguments: [String: Value], env: Environment
    ) throws -> Value {
        let macroEnv = Environment(parent: env)

        let caller = env["caller"]
        if caller != .undefined {
            macroEnv["caller"] = caller
        }

        // Start with defaults
        for (key, expr) in macro.defaults {
            // Evaluate defaults in current env
            let val = try evaluateExpression(expr, env: env)
            macroEnv[key] = val
        }

        // Bind positional args
        for (index, paramName) in macro.parameters.enumerated() {
            let value =
                index < arguments.count ? arguments[index] : macroEnv[paramName]
            macroEnv[paramName] = value
        }

        // Bind keyword args
        for (key, value) in keywordArguments {
            macroEnv[key] = value
        }

        var macroBuffer: any TextOutputStream = Buffer()
        try interpret(macro.body, env: macroEnv, into: &macroBuffer)
        return .string((macroBuffer as! Buffer).build())
    }

    static func evaluateBinaryValues(
        _ op: Expression.BinaryOp, _ left: Value, _ right: Value
    ) throws
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

    static func evaluateUnaryValue(_ op: Expression.UnaryOp, _ value: Value) throws -> Value {
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

    static func evaluateComputedMember(_ object: Value, _ property: Value) throws -> Value {
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

    static func evaluatePropertyMember(_ object: Value, _ propertyName: String) throws
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

    static func evaluateTest(_ testName: String, _ argValues: [Value], env: Environment)
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

    static func evaluateFilter(
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

    // MARK: - Value Operations

    static func addValues(_ left: Value, _ right: Value) throws -> Value {
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

    static func subtractValues(_ left: Value, _ right: Value) throws -> Value {
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

    static func multiplyValues(_ left: Value, _ right: Value) throws -> Value {
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

    static func divideValues(_ left: Value, _ right: Value) throws -> Value {
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

    static func moduloValues(_ left: Value, _ right: Value) throws -> Value {
        switch (left, right) {
        case let (.int(a), .int(b)):
            guard b != 0 else { throw JinjaError.runtime("Modulo by zero") }
            return .int(a % b)
        default:
            throw JinjaError.runtime("Modulo operation requires integers (\(left) and \(right))")
        }
    }

    static func valuesEqual(_ left: Value, _ right: Value) -> Bool {
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

    static func compareValues(_ left: Value, _ right: Value) throws -> Int {
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

    static func valueInCollection(_ value: Value, _ collection: Value) throws -> Bool {
        switch collection {
        case .undefined:
            return false
        case .null:
            return false
        case let .array(items):
            return items.contains { valuesEqual(value, $0) }
        case let .string(str):
            guard case let .string(substr) = value else { return false }
            guard !substr.isEmpty else { return true }  // '' in 'abc' -> true
            return str.contains(substr)
        case let .object(dict):
            guard case let .string(key) = value else { return false }
            return dict.keys.contains(key)

        default:
            throw JinjaError.runtime(
                "'in' operator requires iterable on right side (\(collection))")
        }
    }
}

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

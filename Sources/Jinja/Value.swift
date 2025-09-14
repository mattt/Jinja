@_exported import OrderedCollections

/// Represents values in Jinja template expressions and variables.
public enum Value: Sendable {
    /// Null value representing absence of data.
    case null
    /// Undefined value for uninitialized variables.
    case undefined
    /// Boolean value (`true` or `false`).
    case boolean(Bool)
    /// Integer numeric value.
    case int(Int)
    /// Floating-point numeric value.
    case double(Double)
    /// String value containing text data.
    case string(String)
    /// Array containing ordered collection of values.
    case array([Value])
    /// Object containing key-value pairs with preserved insertion order.
    case object(OrderedDictionary<String, Value>)
    /// Function value that can be called with arguments.
    case function(@Sendable ([Value], [String: Value], Environment) throws -> Value)
    /// Macro value that can be invoked with arguments.
    case macro(Macro)
    /// Global value that can be accessed from the environment.
    case global(Global)

    /// Creates a Value from any Swift value.
    public init(any value: Any?) throws {
        switch value {
        case nil:
            self = .null
        case let str as String:
            self = .string(str)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let float as Float:
            self = .double(Double(float))
        case let bool as Bool:
            self = .boolean(bool)
        case let array as [Any?]:
            let values = try array.map { try Value(any: $0) }
            self = .array(values)
        case let dict as [String: Any?]:
            var orderedDict = OrderedDictionary<String, Value>()
            for (key, value) in dict {
                orderedDict[key] = try Value(any: value)
            }
            self = .object(orderedDict)
        case let global as Global:
            self = .global(global)
        case let macro as Macro:
            self = .macro(macro)
        default:
            throw JinjaError.runtime(
                "Cannot convert value of type \(type(of: value)) to Jinja Value")
        }
    }

    /// Returns whether the value is `null`.
    public var isNull: Bool {
        return self == .null
    }

    /// Returns whether the value is `undefined`.
    public var isUndefined: Bool {
        return self == .undefined
    }

    /// Returns `true` if this value is a boolean.
    public var isBoolean: Bool {
        if case .boolean = self { return true }
        return false
    }

    /// Returns `true` if this value is an integer.
    public var isInt: Bool {
        if case .int = self { return true }
        return false
    }

    /// Returns `true` if this value is a floating-point number.
    public var isDouble: Bool {
        if case .double = self { return true }
        return false
    }

    /// Returns `true` if this value is a string.
    public var isString: Bool {
        if case .string = self { return true }
        return false
    }

    /// Returns `true` if this value is an array.
    public var isArray: Bool {
        if case .array = self { return true }
        return false
    }

    /// Returns `true` if this value is an object.
    public var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    /// Returns `true` if this value is a function.
    public var isFunction: Bool {
        if case .function = self { return true }
        return false
    }

    /// Returns `true` if this value is a macro.
    public var isMacro: Bool {
        if case .macro = self { return true }
        return false
    }

    /// Returns `true` if this value is a global.
    public var isGlobal: Bool {
        if case .global = self { return true }
        return false
    }

    /// Returns `true` if this value can be iterated over (array, object, or string).
    public var isIterable: Bool {
        switch self {
        case .array, .object, .string: return true
        default: return false
        }
    }

    /// Returns `true` if this value is truthy in boolean context.
    public var isTruthy: Bool {
        switch self {
        case .null, .undefined: false
        case .boolean(let b): b
        case .double(let n): n != 0.0
        case .int(let i): i != 0
        case .string(let s): !s.isEmpty
        case .array(let a): !a.isEmpty
        case .object(let o): !o.isEmpty
        case .function: true
        case .macro: true
        case .global: true
        }
    }
}

// MARK: - CustomStringConvertible

extension Value: CustomStringConvertible {
    /// String representation of the value for template output.
    public var description: String {
        switch self {
        case .string(let s): s
        case .double(let n): String(n)
        case .int(let i): String(i)
        case .boolean(let b): String(b)
        case .null: ""
        case .undefined: ""
        case .array(let a): "[\(a.map { $0.description }.joined(separator: ", "))]"
        case .object(let o):
            "{\(o.map { "\($0.key): \($0.value.description)" }.joined(separator: ", "))}"
        case .function: "[Function]"
        case .macro(let m): "[Macro \(m.name)]"
        case .global(let g): "[Global(\(g))]"
        }
    }
}

// MARK: - Equatable

extension Value: Equatable {
    /// Compares two values for equality.
    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case let (.string(lhs), .string(rhs)): return lhs == rhs
        case let (.double(lhs), .double(rhs)): return lhs == rhs
        case let (.int(lhs), .int(rhs)): return lhs == rhs
        case let (.boolean(lhs), .boolean(rhs)): return lhs == rhs
        case (.null, .null): return true
        case (.undefined, .undefined): return true
        case let (.array(lhs), .array(rhs)): return lhs == rhs
        case let (.object(lhs), .object(rhs)): return lhs == rhs
        case (.function, .function): return false
        case let (.macro(lhs), .macro(rhs)): return lhs == rhs
        case (.global, .global): return false
        default: return false
        }
    }
}

// MARK: - Hashable

extension Value: Hashable {
    /// Hashes the value into the given hasher.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .string(value): hasher.combine(value)
        case let .double(value): hasher.combine(value)
        case let .int(value): hasher.combine(value)
        case let .boolean(value): hasher.combine(value)
        case .null: hasher.combine(0)
        case .undefined: hasher.combine(0)
        case let .array(value): hasher.combine(value)
        case let .object(value): hasher.combine(value)
        case .function: hasher.combine(0)
        case .macro(let m): hasher.combine(m)
        case .global: hasher.combine(0)
        }
    }
}

// MARK: - Encodable

extension Value: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .undefined:
            try container.encodeNil()
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            var dictionary: [String: Value] = [:]
            for (key, value) in value {
                dictionary[key] = value
            }
            try container.encode(dictionary)
        case .function:
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot encode function values"
                ))
        case .macro(let m):
            try container.encode(m)
        case .global(let g):
            try container.encode(g)
        }
    }
}

// MARK: - Decodable

extension Value: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let integer = try? container.decode(Int.self) {
            self = .int(integer)
        } else if let number = try? container.decode(Double.self) {
            self = .double(number)
        } else if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let value = try? container.decode([Value].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: Value].self) {
            var orderedDictionary: OrderedDictionary<String, Value> = [:]
            for (key) in value.keys.sorted() {
                orderedDictionary[key] = value[key]
            }
            self = .object(orderedDictionary)
        } else if let macro = try? container.decode(Macro.self) {
            self = .macro(macro)
        } else if let global = try? container.decode(Global.self) {
            self = .global(global)
        } else {
            throw DecodingError.typeMismatch(
                Value.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot decode Value from any supported container type"
                ))

        }
    }
}

// MARK: - ExpressibleByNilLiteral

extension Value: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

// MARK: - ExpressibleByBooleanLiteral

extension Value: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension Value: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

// MARK: - ExpressibleByFloatLiteral

extension Value: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

// MARK: - ExpressibleByStringLiteral

extension Value: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - ExpressibleByArrayLiteral

extension Value: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Value...) {
        self = .array(elements)
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension Value: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Value)...) {
        var dict = OrderedDictionary<String, Value>()
        for (key, value) in elements {
            dict[key] = value
        }
        self = .object(dict)
    }
}

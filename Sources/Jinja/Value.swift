@_exported import OrderedCollections

/// Represents values in Jinja template expressions and variables.
public enum Value: Sendable {
    /// String value containing text data.
    case string(String)
    /// Floating-point numeric value.
    case number(Double)
    /// Integer numeric value.
    case integer(Int)
    /// Boolean value (`true` or `false`).
    case boolean(Bool)
    /// Null value representing absence of data.
    case null
    /// Undefined value for uninitialized variables.
    case undefined
    /// Array containing ordered collection of values.
    case array([Value])
    /// Object containing key-value pairs with preserved insertion order.
    case object(OrderedDictionary<String, Value>)
    /// Function value that can be called with arguments.
    case function(@Sendable ([Value], [String: Value], Environment) throws -> Value)

    /// Creates a Value from any Swift value.
    public init(any value: Any?) throws {
        switch value {
        case nil:
            self = .null
        case let str as String:
            self = .string(str)
        case let int as Int:
            self = .integer(int)
        case let double as Double:
            self = .number(double)
        case let float as Float:
            self = .number(Double(float))
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
        default:
            throw JinjaError.runtime(
                "Cannot convert value of type \(type(of: value)) to Jinja Value")
        }
    }

    /// Returns `true` if this value is a boolean.
    public var isBoolean: Bool {
        if case .boolean = self { return true }
        return false
    }

    /// Returns `true` if this value is a number (integer or floating-point).
    public var isNumber: Bool {
        switch self {
        case .number, .integer: return true
        default: return false
        }
    }

    /// Returns `true` if this value can be iterated over (array, object, or string).
    public var isIterable: Bool {
        switch self {
        case .array, .object, .string: return true
        default: return false
        }
    }

    /// Returns `true` if this value is a string.
    public var isString: Bool {
        if case .string = self { return true }
        return false
    }

    /// Returns `true` if this value is truthy in boolean context.
    public var isTruthy: Bool {
        switch self {
        case .null, .undefined: false
        case .boolean(let b): b
        case .string(let s): !s.isEmpty
        case .number(let n): n != 0.0
        case .integer(let i): i != 0
        case .array(let a): !a.isEmpty
        case .object(let o): !o.isEmpty
        case .function: true
        }
    }

    /// Returns the array of values if this value is an array, otherwise `nil`.
    public var array: [Value]? {
        guard case let .array(values) = self else { return nil }
        return values
    }

    /// Returns the string value if this value is a string, otherwise `nil`.
    public var string: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    /// Returns the integer value if this value is an integer, otherwise `nil`.
    public var integer: Int? {
        guard case let .integer(value) = self else { return nil }
        return value
    }

    /// Returns the floating-point value if this value is a number, otherwise `nil`.
    public var number: Double? {
        switch self {
        case let .number(value):
            return value
        case let .integer(value):
            return Double(value)
        default:
            return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension Value: CustomStringConvertible {
    /// String representation of the value for template output.
    public var description: String {
        switch self {
        case .string(let s): s
        case .number(let n): String(n)
        case .integer(let i): String(i)
        case .boolean(let b): String(b)
        case .null: ""
        case .undefined: ""
        case .array(let a): "[\(a.map { $0.description }.joined(separator: ", "))]"
        case .object(let o):
            "{\(o.map { "\($0.key): \($0.value.description)" }.joined(separator: ", "))}"
        case .function: "[Function]"
        }
    }
}

// MARK: - Equatable

extension Value: Equatable {
    /// Compares two values for equality.
    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case let (.string(lhs), .string(rhs)): return lhs == rhs
        case let (.number(lhs), .number(rhs)): return lhs == rhs
        case let (.integer(lhs), .integer(rhs)): return lhs == rhs
        case let (.boolean(lhs), .boolean(rhs)): return lhs == rhs
        case (.null, .null): return true
        case (.undefined, .undefined): return true
        case let (.array(lhs), .array(rhs)): return lhs == rhs
        case let (.object(lhs), .object(rhs)): return lhs == rhs
        case (.function, .function): return false
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
        case let .number(value): hasher.combine(value)
        case let .integer(value): hasher.combine(value)
        case let .boolean(value): hasher.combine(value)
        case .null: hasher.combine(0)
        case .undefined: hasher.combine(0)
        case let .array(value): hasher.combine(value)
        case let .object(value): hasher.combine(value)
        case .function: hasher.combine(0)
        }
    }
}

// MARK: - Encodable

extension Value: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .boolean(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .undefined:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let .array(value):
            var container = encoder.unkeyedContainer()
            for element in value {
                try container.encode(element)
            }
        case let .object(value):
            var container = encoder.container(keyedBy: CodingKeys.self)
            for (key, val) in value {
                try container.encode(val, forKey: CodingKeys(stringValue: key))
            }
        case .function:
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot encode function values"
                ))
        }
    }

    private struct CodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

// MARK: - Decodable

extension Value: Decodable {
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .null
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let integer = try? container.decode(Int.self) {
                self = .integer(integer)
            } else if let boolean = try? container.decode(Bool.self) {
                self = .boolean(boolean)
            } else {
                throw DecodingError.typeMismatch(
                    Value.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Cannot decode Value from single value container"
                    ))
            }
        } else if var container = try? decoder.unkeyedContainer() {
            var values: [Value] = []
            while !container.isAtEnd {
                let value = try container.decode(Value.self)
                values.append(value)
            }
            self = .array(values)
        } else if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            var dict = OrderedDictionary<String, Value>()
            for key in container.allKeys {
                let value = try container.decode(Value.self, forKey: key)
                dict[key.stringValue] = value
            }
            self = .object(dict)
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

// MARK: - ExpressibleByStringLiteral

extension Value: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension Value: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

// MARK: - ExpressibleByFloatLiteral

extension Value: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

// MARK: - ExpressibleByBooleanLiteral

extension Value: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
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

// MARK: - ExpressibleByNilLiteral

extension Value: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

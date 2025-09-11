@_exported import OrderedCollections

public enum Value: Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case null
    case undefined
    case array([Value])
    case object(OrderedDictionary<String, Value>)
    case function(@Sendable ([Value]) async throws -> Value)

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
            throw JinjaError.runtime("Cannot convert value of type \(type(of: value)) to Jinja Value")
        }
    }

    public var isBoolean: Bool {
        if case .boolean = self { return true }
        return false
    }

    public var isNumber: Bool {
        switch self {
        case .number, .integer: return true
        default: return false
        }
    }

    public var isIterable: Bool {
        switch self {
        case .array, .object, .string: return true
        default: return false
        }
    }

    public var isString: Bool {
        if case .string = self { return true }
        return false
    }

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
}

// MARK: - CustomStringConvertible

extension Value: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let s): s
        case .number(let n): String(n)
        case .integer(let i): String(i)
        case .boolean(let b): String(b)
        case .null: ""
        case .undefined: ""
        case .array(let a): "[\(a.map { $0.description }.joined(separator: ", "))]"
        case .object(let o): "{\(o.map { "\($0.key): \($0.value.description)" }.joined(separator: ", "))}"
        case .function: "[Function]"
        }
    }
}

// MARK: - Equatable

extension Value: Equatable {
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
        case (.function, .function): return true
        default: return false
        }
    }
}

// MARK: - Hashable

extension Value: Hashable {
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

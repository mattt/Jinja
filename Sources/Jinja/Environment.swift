@_exported import OrderedCollections

private let builtinValues: [String: Value] = [
    "true": .boolean(true),
    "false": .boolean(false),
    "none": .null,
    "range": .function { values in
        guard !values.isEmpty else { return .array([]) }

        switch values.count {
        case 1:
            if case let .integer(end) = values[0] {
                return .array((0 ..< end).map { .integer($0) })
            }
        case 2:
            if case let .integer(start) = values[0],
                case let .integer(end) = values[1]
            {
                return .array((start ..< end).map { .integer($0) })
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

/// Execution environment that stores variables and provides context for template rendering.
public final class Environment: @unchecked Sendable {
    private var variables: [String: Value] = [:]
    private let parent: Environment?

    /// Creates a new environment with optional parent and initial variables.
    public init(parent: Environment? = nil, initial: [String: Value] = [:]) {
        self.parent = parent
        self.variables = initial

        // Initialize built-in variables if this is a root environment
        if parent == nil {
            variables.merge(builtinValues) { _, new in new }
        }
    }

    /// Sets a variable to the given value.
    public func set(_ name: String, value: Value) {
        variables[name] = value
    }

    /// Gets the value of a variable, returning undefined if not found.
    public func get(_ name: String) -> Value {
        if let value = variables[name] {
            return value
        }

        // Check parent environment
        if let parent = parent {
            return parent.get(name)
        }

        return .undefined
    }

    /// Sets multiple variables from a dictionary of Any values.
    public func setAll(_ values: [String: Any]) throws {
        for (key, value) in values {
            let jinjaValue = try convertToValue(value)
            variables[key] = jinjaValue
        }
    }

    /// Sets multiple variables from a dictionary of Value objects.
    public func setAllValues(_ values: [String: Value]) {
        variables.merge(values) { _, new in new }
    }

    /// Creates a child environment for scope isolation.
    public func childEnv() -> Environment {
        Environment(parent: self)
    }

    /// Creates a snapshot environment for template rendering.
    public func snapshot() -> Environment {
        // For performance, just copy current variables directly
        // Most template rendering doesn't use nested environments
        return Environment(initial: variables)
    }

    private func convertToValue(_ value: Any) throws -> Value {
        switch value {
        case let str as String:
            return .string(str)
        case let int as Int:
            return .integer(int)
        case let double as Double:
            return .number(double)
        case let bool as Bool:
            return .boolean(bool)
        case let array as [Any]:
            let values = try array.map { try convertToValue($0) }
            return .array(values)
        case let dict as [String: Any]:
            var orderedDict: OrderedDictionary<String, Value> = [:]
            for (k, v) in dict {
                orderedDict[k] = try convertToValue(v)
            }
            return .object(orderedDict)
        case Optional<Any>.none:
            return .null
        default:
            throw JinjaError.runtime("Cannot convert value of type \(type(of: value))")
        }
    }
}

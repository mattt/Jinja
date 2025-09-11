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

/// Execution environment that stores variables and provides context for template rendering.
public final class Environment: @unchecked Sendable {
    private(set) var variables: [String: Value] = [:]
    private let parent: Environment?

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

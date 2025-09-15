import Foundation

/// An exception that can be raised in Jinja templates with `raise_exception`.
public struct Exception: Error {
    /// The message of the exception, if any.
    var message: String?
}

/// An object that cycles through values.
final class Cycler: @unchecked Sendable {
    private let items: [Value]
    private let lock = NSLock()
    private var currentIndex: Int = 0

    init(items: [Value]) {
        self.items = items
    }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty ? .null : items[currentIndex]
    }

    func next() -> Value {
        lock.lock()
        defer { lock.unlock() }

        guard !items.isEmpty else { return .null }

        let result = items[currentIndex]
        currentIndex = (currentIndex + 1) % items.count
        return result
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentIndex = 0
    }
}

/// An object that joins sections.
final class Joiner: @unchecked Sendable {
    private let separator: String
    private let lock = NSLock()
    private var first: Bool = true

    init(separator: String = ", ") {
        self.separator = separator
    }

    func join() -> String {
        lock.lock()
        defer { lock.unlock() }

        if first {
            first = false
            return ""
        } else {
            return separator
        }
    }
}

/// Built-in global functions available in the Jinja environment.
public enum Globals: Sendable {
    public static let builtIn: [String: Value] = [
        "raise_exception": .function(raiseException),
        "range": .function(range),
        "lipsum": .function(lipsum),
        "dict": .function(dict),
        "cycler": .function(cycler),
        "joiner": .function(joiner),
        "namespace": .function(namespace),
    ]

    /// Raises an exception with an optional custom message.
    ///
    /// This is useful for debugging templates or enforcing constraints.
    ///
    /// - Parameters:
    ///   - args: Function arguments. First argument should be the error message (optional).
    ///   - kwargs: Keyword arguments (unused).
    ///   - env: The current environment.
    /// - Throws: JinjaError.runtime with the provided message or a default message.
    /// - Returns: Never returns a value as it always throws.
    @discardableResult
    public static func raiseException(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        let arguments = try resolveCallArguments(
            args: args,
            kwargs: kwargs,
            parameters: ["message"],
            defaults: ["message": .null]
        )

        if case let .string(message)? = arguments["message"] {
            throw Exception(message: message)
        } else {
            throw Exception()
        }
    }

    /// Return a list containing an arithmetic progression of integers.
    ///
    /// range(i, j) returns [i, i+1, i+2, ..., j-1]; start defaults to 0.
    /// When step is given, it specifies the increment (or decrement).
    ///
    /// - Parameters:
    ///   - args: Function arguments: [start], stop, [step]
    ///   - kwargs: Keyword arguments (unused)
    ///   - env: The current environment
    /// - Returns: Array of integers in the specified range
    public static func range(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        let start: Int
        let stop: Int
        let step: Int

        switch args.count {
        case 1:
            guard case let .int(stopValue) = args[0] else {
                throw JinjaError.runtime("range() stop argument must be an integer")
            }
            start = 0
            stop = stopValue
            step = 1
        case 2:
            guard case let .int(startValue) = args[0],
                case let .int(stopValue) = args[1]
            else {
                throw JinjaError.runtime("range() arguments must be integers")
            }
            start = startValue
            stop = stopValue
            step = 1
        case 3:
            guard case let .int(startValue) = args[0],
                case let .int(stopValue) = args[1],
                case let .int(stepValue) = args[2]
            else {
                throw JinjaError.runtime("range() arguments must be integers")
            }
            start = startValue
            stop = stopValue
            step = stepValue
        default:
            throw JinjaError.runtime("range() takes 1 to 3 arguments")
        }

        guard step != 0 else {
            throw JinjaError.runtime("range() step argument must not be zero")
        }

        var result: [Value] = []
        if step > 0 {
            var current = start
            while current < stop {
                result.append(.int(current))
                current += step
            }
        } else {
            var current = start
            while current > stop {
                result.append(.int(current))
                current += step
            }
        }

        return .array(result)
    }

    /// Generates lorem ipsum text for templates.
    ///
    /// - Parameters:
    ///   - args: Function arguments (unused)
    ///   - kwargs: Keyword arguments: n, html, min, max
    ///   - env: The current environment
    /// - Returns: Generated lorem ipsum text
    public static func lipsum(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        let arguments = try resolveCallArguments(
            args: args,
            kwargs: kwargs,
            parameters: ["n", "html", "min", "max"],
            defaults: [
                "n": .int(5),
                "html": .boolean(true),
                "min": .int(20),
                "max": .int(100),
            ]
        )

        guard case let .int(n) = arguments["n"]!,
            case let .boolean(html) = arguments["html"]!,
            case let .int(min) = arguments["min"]!,
            case let .int(max) = arguments["max"]!
        else {
            throw JinjaError.runtime("Invalid arguments for lipsum()")
        }

        let words = [
            "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
            "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
            "magna", "aliqua", "enim", "ad", "minim", "veniam", "quis", "nostrud",
            "exercitation", "ullamco", "laboris", "nisi", "aliquip", "ex", "ea", "commodo",
            "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate",
            "velit", "esse", "cillum", "fugiat", "nulla", "pariatur", "excepteur", "sint",
            "occaecat", "cupidatat", "non", "proident", "sunt", "culpa", "qui", "officia",
            "deserunt", "mollit", "anim", "id", "est", "laborum",
        ]

        var paragraphs: [String] = []

        for _ in 0..<n {
            let wordCount = Int.random(in: min...max)
            var paragraph: [String] = []

            for _ in 0..<wordCount {
                paragraph.append(words.randomElement()!)
            }

            var text = paragraph.joined(separator: " ")
            text = text.prefix(1).uppercased() + text.dropFirst()
            text += "."

            if html {
                text = "<p>\(text)</p>"
            }

            paragraphs.append(text)
        }

        let result =
            html ? paragraphs.joined(separator: "\n") : paragraphs.joined(separator: "\n\n")
        return .string(result)
    }

    /// Creates a dictionary from keyword arguments.
    ///
    /// A convenient alternative to dict literals.
    ///
    /// - Parameters:
    ///   - args: Function arguments (unused)
    ///   - kwargs: Keyword arguments to convert to dictionary
    ///   - env: The current environment
    /// - Returns: Object containing the provided key-value pairs
    public static func dict(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        var orderedDict = OrderedDictionary<String, Value>()
        for (key, value) in kwargs {
            orderedDict[key] = value
        }
        return .object(orderedDict)
    }

    /// Creates a cycler object that cycles through values.
    ///
    /// - Parameters:
    ///   - args: Items to cycle through
    ///   - kwargs: Keyword arguments (unused)
    ///   - env: The current environment
    /// - Returns: Object with cycling functionality
    public static func cycler(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        guard !args.isEmpty else {
            throw JinjaError.runtime("cycler() requires at least one argument")
        }

        let cyclerInstance = Cycler(items: args)

        var cyclerDict = OrderedDictionary<String, Value>()
        cyclerDict["current"] = cyclerInstance.current
        cyclerDict["next"] = .function { (_, _, _) throws -> Value in
            return cyclerInstance.next()
        }
        cyclerDict["reset"] = .function { (_, _, _) throws -> Value in
            cyclerInstance.reset()
            return .null
        }

        return .object(cyclerDict)
    }

    /// Creates a joiner object for joining sections.
    ///
    /// - Parameters:
    ///   - args: Function arguments (unused)
    ///   - kwargs: Keyword arguments: sep
    ///   - env: The current environment
    /// - Returns: Function that returns separator after first call
    public static func joiner(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        let arguments = try resolveCallArguments(
            args: args,
            kwargs: kwargs,
            parameters: ["sep"],
            defaults: ["sep": .string(", ")]
        )

        guard case let .string(separator) = arguments["sep"]! else {
            throw JinjaError.runtime("joiner separator must be a string")
        }

        let joinerInstance = Joiner(separator: separator)
        return .function { (_, _, _) throws -> Value in
            return .string(joinerInstance.join())
        }
    }

    /// Creates a namespace object for attribute assignment.
    ///
    /// - Parameters:
    ///   - args: Function arguments (unused)
    ///   - kwargs: Initial values for the namespace
    ///   - env: The current environment
    /// - Returns: Object that can be used for attribute storage
    public static func namespace(
        _ args: [Value], _ kwargs: [String: Value], _ env: Environment
    ) throws -> Value {
        var namespaceDict = OrderedDictionary<String, Value>()
        for (key, value) in kwargs {
            namespaceDict[key] = value
        }
        return .object(namespaceDict)
    }
}

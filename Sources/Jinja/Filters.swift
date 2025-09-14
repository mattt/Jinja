import Foundation

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

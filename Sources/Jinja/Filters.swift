import Foundation
import OrderedCollections

/// Built-in filters for Jinja template rendering.
public enum Filters {
    // MARK: - Basic String Filters

    /// Converts a string to uppercase.
    @Sendable public static func upper(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            throw JinjaError.runtime("upper filter requires string")
        }
        return .string(str.uppercased())
    }

    /// Converts a string to lowercase.
    @Sendable public static func lower(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            throw JinjaError.runtime("lower filter requires string")
        }
        return .string(str.lowercased())
    }

    /// Returns the length of a string, array, or object.
    @Sendable public static func length(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        switch values.first {
        case let .string(str):
            return .integer(str.count)
        case let .array(arr):
            return .integer(arr.count)
        case let .object(obj):
            return .integer(obj.count)
        default:
            throw JinjaError.runtime("length filter requires string, array, or object")
        }
    }

    /// Joins an array of values with a separator.
    @Sendable public static func join(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard values.count >= 2,
            case let .array(array) = values[0],
            case let .string(separator) = values[1]
        else {
            throw JinjaError.runtime("join filter requires array and separator")
        }

        let strings = array.map { $0.description }
        return .string(strings.joined(separator: separator))
    }

    /// Returns a default value if the input is null, undefined, or empty.
    @Sendable public static func `default`(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard values.count >= 2 else {
            throw JinjaError.runtime("default filter requires at least 2 arguments")
        }

        let value = values[0]
        let defaultValue = values[1]

        switch value {
        case .null, .undefined:
            return defaultValue
        case let .string(str) where str.isEmpty:
            return defaultValue
        case let .array(arr) where arr.isEmpty:
            return defaultValue
        case let .object(obj) where obj.isEmpty:
            return defaultValue
        default:
            return value
        }
    }

    // MARK: - Array Filters

    /// Returns the first item from an array.
    @Sendable public static func first(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, case let .array(items) = value else {
            return .array([])
        }

        let reverse = kwargs["reverse"]?.isTruthy ?? false
        let caseSensitive = kwargs["case_sensitive"]?.isTruthy ?? true

        let sortedItems: [Value]
        if let attribute = kwargs["attribute"]?.string {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let attribute = values[1].string
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let numSlices = values[1].integer, numSlices > 0
        else {
            return .array([])
        }

        let fillWith = values.count > 2 ? values[2] : .null
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else {
            return .array([])
        }

        if let filterName = values.count > 1 ? values[1].string : nil {
            return .array(
                try items.map {
                    try Interpreter.evaluateFilter(filterName, [$0], kwargs: [:], env: env)
                })
        } else if let attribute = kwargs["attribute"]?.string {
            return .array(
                try items.map {
                    try Interpreter.evaluatePropertyMember($0, attribute)
                })
        }

        return .array([])
    }

    /// Selects items that pass a test.
    @Sendable public static func select(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let testName = values[1].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(2))
        return .array(
            try items.filter {
                try Interpreter.evaluateTest(testName, [$0] + testArgs, env: env)
            })
    }

    /// Rejects items that pass a test.
    @Sendable public static func reject(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let testName = values[1].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(2))
        return .array(
            try items.filter {
                try !Interpreter.evaluateTest(testName, [$0] + testArgs, env: env)
            })
    }

    /// Selects items with an attribute that passes a test.
    @Sendable public static func selectattr(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 2, let attribute = values[1].string,
            let testName = values[2].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(3))
        return .array(
            try items.filter {
                let attrValue = try Interpreter.evaluatePropertyMember($0, attribute)
                return try Interpreter.evaluateTest(testName, [attrValue] + testArgs, env: env)
            })
    }

    /// Rejects items with an attribute that passes a test.
    @Sendable public static func rejectattr(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 2, let attribute = values[1].string,
            let testName = values[2].string
        else {
            return .array([])
        }
        let testArgs = Array(values.dropFirst(3))
        return .array(
            try items.filter {
                let attrValue = try Interpreter.evaluatePropertyMember($0, attribute)
                return try !Interpreter.evaluateTest(testName, [attrValue] + testArgs, env: env)
            })
    }

    // MARK: - Object Filters

    /// Gets an attribute from an object.
    @Sendable public static func attr(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let obj = values.first, values.count > 1,
            let attribute = values[1].string
        else {
            return .undefined
        }
        return try Interpreter.evaluatePropertyMember(obj, attribute)
    }

    /// Sorts a dictionary by keys and returns key-value pairs.
    @Sendable public static func dictsort(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .object(dict) = values.first else {
            return .array([])
        }
        let sortedPairs = dict.sorted { $0.key < $1.key }
        let resultArray = sortedPairs.map { key, value in
            Value.array([.string(key), value])
        }
        return .array(resultArray)
    }

    // MARK: - String Processing Filters

    /// Escapes HTML characters.
    @Sendable public static func forceescape(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        return values.first ?? .string("")
    }

    /// Strips HTML tags from a string.
    @Sendable public static func striptags(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard values.count > 1, let formatString = values[0].string else {
            return values.first ?? .string("")
        }
        let args = Array(values.dropFirst())
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let str = value.string else {
            return .string("")
        }
        let width = values.count > 1 ? (values[1].integer ?? 79) : 79
        _ = values.count > 2 ? (values[2].isTruthy) : true

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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let num = value.number else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, case let .object(dict) = value else {
            return .string("")
        }
        let autocapitalize = values.count > 1 ? values[1].isTruthy : false
        var result = ""
        for (key, value) in dict {
            if key.starts(with: "_") { continue }
            let finalKey = autocapitalize ? key.capitalized : key
            result += " \(finalKey)=\"\(value.description)\""
        }
        return .string(result)
    }

    // MARK: - Test Filters (return boolean values)

    /// Tests if a value is defined (not undefined).
    @Sendable public static func defined(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value != .undefined)
    }

    /// Tests if a value is undefined.
    @Sendable public static func undefined(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(true) }
        return .boolean(value == .undefined)
    }

    /// Tests if a value is none/null.
    @Sendable public static func none(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value == .null)
    }

    /// Tests if a value is a string.
    @Sendable public static func string(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isString)
    }

    /// Tests if a value is a number.
    @Sendable public static func number(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isNumber)
    }

    /// Tests if a value is a boolean.
    @Sendable public static func boolean(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isBoolean)
    }

    /// Tests if a value is iterable.
    @Sendable public static func iterable(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .boolean(false) }
        return .boolean(value.isIterable)
    }

    // MARK: - Additional Filters

    /// Trims whitespace from a string.
    @Sendable public static func trim(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        return .string(str.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Escapes HTML characters (alias for forceescape).
    @Sendable public static func escape(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        return try forceescape(values, kwargs: kwargs, env: env)
    }

    /// Converts value to JSON string.
    @Sendable public static func tojson(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .string("null") }
        return .string(toJsonString(value))
    }

    /// Returns absolute value of a number.
    @Sendable public static func abs(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
            return .integer(0)
        }
        switch value {
        case let .integer(i):
            return .integer(Swift.abs(i))
        case let .number(n):
            return .number(Swift.abs(n))
        default:
            throw JinjaError.runtime("abs filter requires number or integer")
        }
    }

    /// Capitalizes the first letter and lowercases the rest.
    @Sendable public static func capitalize(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        return .string(str.prefix(1).uppercased() + str.dropFirst().lowercased())
    }

    /// Centers a string within a specified width.
    @Sendable public static func center(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first,
            values.count > 1,
            case let .integer(width) = values[1]
        else {
            return values.first ?? .string("")
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .number(0.0) }
        switch value {
        case let .integer(i):
            return .number(Double(i))
        case let .number(n):
            return .number(n)
        case let .string(s):
            return .number(Double(s) ?? 0.0)
        default:
            return .number(0.0)
        }
    }

    /// Converts a value to integer.
    @Sendable public static func int(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .integer(0) }
        switch value {
        case let .integer(i):
            return .integer(i)
        case let .number(n):
            return .integer(Int(n))
        case let .string(s):
            return .integer(Int(s) ?? 0)
        default:
            return .integer(0)
        }
    }

    /// Converts a value to list.
    @Sendable public static func list(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .array([]) }
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else { return .undefined }
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else { return .undefined }
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else { return .number(0.0) }
        let precision = (values.count > 1 ? values[1].integer : 0) ?? 0
        let method = values.count > 2 ? (values[2].string ?? "common") : "common"

        guard let number = value.number else {
            return value  // Or throw error
        }

        if method == "common" {
            let divisor = pow(10.0, Double(precision))
            return .number((number * divisor).rounded() / divisor)
        } else if method == "ceil" {
            let divisor = pow(10.0, Double(precision))
            return .number(ceil(number * divisor) / divisor)
        } else if method == "floor" {
            let divisor = pow(10.0, Double(precision))
            return .number(floor(number * divisor) / divisor)
        }
        return .number(number)
    }

    /// Capitalizes each word in a string.
    @Sendable public static func title(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        return .string(str.capitalized)
    }

    /// Counts words in a string.
    @Sendable public static func wordcount(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .integer(0)
        }
        let words = str.split { $0.isWhitespace || $0.isNewline }
        return .integer(words.count)
    }

    /// Replaces occurrences of a substring.
    @Sendable public static func replace(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard values.count >= 3,
            case let .string(str) = values[0],
            case let .string(old) = values[1],
            case let .string(new) = values[2]
        else {
            return values.first ?? .string("")
        }
        let count = values.count > 3 ? values[3].integer : nil
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array,
            values.count > 1, let batchSize = values[1].integer, batchSize > 0
        else {
            return .array([])
        }

        let fillWith = values.count > 2 ? values[2] : .null

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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else {
            return .integer(0)
        }
        let start = values.count > 1 ? values[1] : .integer(0)
        let sum = items.reduce(start) { acc, next in
            try! Interpreter.addValues(acc, next)  // Should handle errors
        }
        return sum
    }

    /// Truncates a string to a specified length.
    @Sendable public static func truncate(
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        let length = values.count > 1 ? (values[1].integer ?? 255) : 255
        let killwords = values.count > 2 ? (values[2].isTruthy) : false
        let end = values.count > 3 ? (values[3].string ?? "...") : "..."

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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard let value = values.first, let items = value.array else {
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
        _ values: [Value], kwargs: [String: Value] = [:], env: Environment
    ) throws -> Value {
        guard case let .string(str) = values.first else {
            return .string("")
        }
        let width = values.count > 1 ? (values[1].integer ?? 4) : 4
        let indentFirst = values.count > 2 ? (values[2].isTruthy) : true
        let indentChar = String(repeating: " ", count: width)
        let lines = str.split(separator: "\n", omittingEmptySubsequences: false).map(
            String.init)
        var result = ""
        for (i, line) in lines.enumerated() {
            if i == 0 && !indentFirst {
                result += line
            } else if !line.isEmpty {
                result += indentChar + line
            }
            if i < lines.count - 1 {
                result += "\n"
            }
        }
        return .string(result)
    }

    // MARK: - Helper Methods

    /// Converts a value to JSON string format.
    private static func toJsonString(_ value: Value) -> String {
        switch value {
        case .string(let str):
            let escaped =
                str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        case .integer(let num):
            return String(num)
        case .number(let num):
            return String(num)
        case .boolean(let bool):
            return bool ? "true" : "false"
        case .null, .undefined:
            return "null"
        case .array(let items):
            let jsonItems = items.map { toJsonString($0) }
            return "[\(jsonItems.joined(separator: ", "))]"
        case .object(let dict):
            let jsonPairs = dict.map { key, value -> String in
                let keyJson = "\"\(key)\""
                let valueJson = toJsonString(value)
                return "\(keyJson): \(valueJson)"
            }
            return "{\(jsonPairs.joined(separator: ", "))}"
        default:
            return "null"
        }
    }

    /// Dictionary of all available filters.
    public static let `default`:
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
            "defined": defined,
            "undefined": undefined,
            "none": none,
            "string": string,
            "number": number,
            "boolean": boolean,
            "iterable": iterable,
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
        ]
}

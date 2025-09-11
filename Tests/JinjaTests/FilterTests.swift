import Testing
@testable import Jinja

@Suite("Filter Functionality Tests")
struct FilterTests {
    
    // MARK: - Test Data
    
    private static func createEnvironmentWithFilters() -> Environment {
        let env = Environment()
        
        // Built-in minja filters that should be supported
        env["count"] = .function { values in
            guard let first = values.first else { return .integer(0) }
            switch first {
            case .array(let arr): return .integer(arr.count)
            case .object(let dict): return .integer(dict.count)
            case .string(let str): return .integer(str.count)
            default: return .integer(0)
            }
        }
        
        env["join"] = .function { values in
            guard values.count >= 2,
                  case .array(let items) = values[0],
                  case .string(let separator) = values[1] else {
                return .string("")
            }
            let strings = items.map { $0.description }
            return .string(strings.joined(separator: separator))
        }
        
        env["upper"] = .function { values in
            guard let first = values.first,
                  case .string(let str) = first else {
                return .string("")
            }
            return .string(str.uppercased())
        }
        
        env["lower"] = .function { values in
            guard let first = values.first,
                  case .string(let str) = first else {
                return .string("")
            }
            return .string(str.lowercased())
        }
        
        env["trim"] = .function { values in
            guard let first = values.first,
                  case .string(let str) = first else {
                return .string("")
            }
            return .string(str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        env["escape"] = .function { values in
            guard let first = values.first,
                  case .string(let str) = first else {
                return .string("")
            }
            // Basic HTML escaping
            let escaped = str
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
            return .string(escaped)
        }
        
        env["e"] = env["escape"] // alias for escape
        
        env["tojson"] = .function { values in
            guard let first = values.first else { return .string("null") }
            
            switch first {
            case .string(let str):
                // Basic JSON string escaping
                let escaped = str
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\t", with: "\\t")
                return .string("\"\(escaped)\"")
            case .integer(let num):
                return .string(String(num))
            case .number(let num):
                return .string(String(num))
            case .boolean(let bool):
                return .string(bool ? "true" : "false")
            case .null, .undefined:
                return .string("null")
            case .array(let items):
                let jsonItems = items.map { item -> String in
                    let result = try? env["tojson"]!.function!([item])
                    return result?.description ?? "null"
                }
                return .string("[\(jsonItems.joined(separator: ", "))]")
            case .object(let dict):
                let jsonPairs = dict.map { key, value -> String in
                    let keyJson = "\"\(key)\""
                    let result = try? env["tojson"]!.function!([value])
                    let valueJson = result?.description ?? "null"
                    return "\(keyJson): \(valueJson)"
                }
                return .string("{\(jsonPairs.joined(separator: ", "))}")
            default:
                return .string("null")
            }
        }
        
        env["dictsort"] = .function { values in
            guard let first = values.first,
                  case .object(let dict) = first else {
                return .array([])
            }
            
            let sortedPairs = dict.sorted { $0.key < $1.key }
            let resultArray = sortedPairs.map { key, value in
                Value.array([.string(key), value])
            }
            return .array(resultArray)
        }
        
        return env
    }
    
    // MARK: - Basic Filter Tests
    
    @Test("Filter application syntax")
    func testFilterApplicationSyntax() throws {
        let template = try Template("{{ 'hello' | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([:], environment: env)
        #expect(result == "HELLO")
    }
    
    @Test("Filter with arguments")
    func testFilterWithArguments() throws {
        let template = try Template("{{ ['a', 'b', 'c'] | join(', ') }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([:], environment: env)
        #expect(result == "a, b, c")
    }
    
    @Test("Chained filters")
    func testChainedFilters() throws {
        let template = try Template("{{ '  Hello World  ' | trim | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([:], environment: env)
        #expect(result == "HELLO WORLD")
    }
    
    @Test("Filter on variable")
    func testFilterOnVariable() throws {
        let template = try Template("{{ name | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render(["name": "alice"], environment: env)
        #expect(result == "ALICE")
    }
    
    @Test("Filter on complex expression")
    func testFilterOnComplexExpression() throws {
        let template = try Template("{{ (first ~ ' ' ~ last) | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "first": "john",
            "last": "doe"
        ], environment: env)
        #expect(result == "JOHN DOE")
    }
    
    // MARK: - Built-in minja Filters
    
    @Test("Count filter")
    func testCountFilter() throws {
        let env = Self.createEnvironmentWithFilters()
        
        // Count array elements
        let arrayTemplate = try Template("{{ items | count }}")
        let arrayResult = try arrayTemplate.render([
            "items": ["a", "b", "c"]
        ], environment: env)
        #expect(arrayResult == "3")
        
        // Count object keys
        let objTemplate = try Template("{{ data | count }}")
        let objResult = try objTemplate.render([
            "data": ["key1": "value1", "key2": "value2"]
        ], environment: env)
        #expect(objResult == "2")
        
        // Count string characters
        let strTemplate = try Template("{{ text | count }}")
        let strResult = try strTemplate.render([
            "text": "hello"
        ], environment: env)
        #expect(strResult == "5")
    }
    
    @Test("Join filter")
    func testJoinFilter() throws {
        let template = try Template("{{ items | join(' - ') }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "items": ["apple", "banana", "cherry"]
        ], environment: env)
        #expect(result == "apple - banana - cherry")
    }
    
    @Test("Join filter with different separators")
    func testJoinFilterDifferentSeparators() throws {
        let env = Self.createEnvironmentWithFilters()
        
        let commaTemplate = try Template("{{ items | join(', ') }}")
        let commaResult = try commaTemplate.render([
            "items": ["a", "b", "c"]
        ], environment: env)
        #expect(commaResult == "a, b, c")
        
        let pipeTemplate = try Template("{{ items | join(' | ') }}")
        let pipeResult = try pipeTemplate.render([
            "items": ["x", "y", "z"]
        ], environment: env)
        #expect(pipeResult == "x | y | z")
        
        let emptyTemplate = try Template("{{ items | join('') }}")
        let emptyResult = try emptyTemplate.render([
            "items": ["1", "2", "3"]
        ], environment: env)
        #expect(emptyResult == "123")
    }
    
    @Test("String transformation filters")
    func testStringTransformationFilters() throws {
        let env = Self.createEnvironmentWithFilters()
        
        // Upper case
        let upperTemplate = try Template("{{ text | upper }}")
        let upperResult = try upperTemplate.render(["text": "hello world"], environment: env)
        #expect(upperResult == "HELLO WORLD")
        
        // Lower case
        let lowerTemplate = try Template("{{ text | lower }}")
        let lowerResult = try lowerTemplate.render(["text": "HELLO WORLD"], environment: env)
        #expect(lowerResult == "hello world")
        
        // Trim whitespace
        let trimTemplate = try Template("{{ text | trim }}")
        let trimResult = try trimTemplate.render(["text": "  hello world  "], environment: env)
        #expect(trimResult == "hello world")
    }
    
    @Test("Escape filter")
    func testEscapeFilter() throws {
        let env = Self.createEnvironmentWithFilters()
        
        // Test HTML escaping
        let template = try Template("{{ html | escape }}")
        let result = try template.render([
            "html": "<script>alert('xss')</script>"
        ], environment: env)
        #expect(result == "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
        
        // Test 'e' alias
        let aliasTemplate = try Template("{{ html | e }}")
        let aliasResult = try aliasTemplate.render([
            "html": "<div>Hello & \"World\"</div>"
        ], environment: env)
        #expect(aliasResult == "&lt;div&gt;Hello &amp; &quot;World&quot;&lt;/div&gt;")
    }
    
    @Test("ToJSON filter")
    func testToJSONFilter() throws {
        let env = Self.createEnvironmentWithFilters()
        
        // String to JSON
        let strTemplate = try Template("{{ text | tojson }}")
        let strResult = try strTemplate.render(["text": "hello\nworld"], environment: env)
        #expect(strResult == "\"hello\\nworld\"")
        
        // Number to JSON
        let numTemplate = try Template("{{ num | tojson }}")
        let numResult = try numTemplate.render(["num": 42], environment: env)
        #expect(numResult == "42")
        
        // Boolean to JSON
        let boolTemplate = try Template("{{ flag | tojson }}")
        let boolResult = try boolTemplate.render(["flag": true], environment: env)
        #expect(boolResult == "true")
        
        // Array to JSON
        let arrayTemplate = try Template("{{ items | tojson }}")
        let arrayResult = try arrayTemplate.render([
            "items": ["a", "b", 1, true]
        ], environment: env)
        #expect(arrayResult == "[\"a\", \"b\", 1, true]")
        
        // Object to JSON
        let objTemplate = try Template("{{ data | tojson }}")
        let objResult = try objTemplate.render([
            "data": ["name": "John", "age": 30]
        ], environment: env)
        #expect(objResult.contains("\"name\": \"John\""))
        #expect(objResult.contains("\"age\": 30"))
    }
    
    @Test("Dictsort filter")
    func testDictsortFilter() throws {
        let template = try Template("{% for key, value in data | dictsort %}{{ key }}:{{ value }} {% endfor %}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "data": ["zebra": 1, "alpha": 2, "beta": 3]
        ], environment: env)
        
        // Should be sorted alphabetically by key
        #expect(result == "alpha:2 beta:3 zebra:1 ")
    }
    
    // MARK: - Filter Error Handling
    
    @Test("Undefined filter")
    func testUndefinedFilter() throws {
        let template = try Template("{{ value | nonexistent_filter }}")
        let env = Environment()
        
        #expect(throws: JinjaError.self) {
            _ = try template.render(["value": "test"], environment: env)
        }
    }
    
    @Test("Filter with wrong argument count")
    func testFilterWithWrongArgumentCount() throws {
        let template = try Template("{{ items | join }}")  // join requires separator argument
        let env = Self.createEnvironmentWithFilters()
        
        // This should handle gracefully or throw appropriate error
        let result = try template.render([
            "items": ["a", "b", "c"]
        ], environment: env)
        #expect(result == "") // join without separator returns empty string
    }
    
    @Test("Filter on invalid type")
    func testFilterOnInvalidType() throws {
        let template = try Template("{{ number | upper }}")  // upper only works on strings
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render(["number": 42], environment: env)
        #expect(result == "") // Should return empty string for invalid type
    }
    
    // MARK: - Advanced Filter Usage
    
    @Test("Filters in complex expressions")
    func testFiltersInComplexExpressions() throws {
        let template = try Template("{{ (items | count) > 0 }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result1 = try template.render([
            "items": ["a", "b", "c"]
        ], environment: env)
        #expect(result1 == "true")
        
        let result2 = try template.render([
            "items": []
        ], environment: env)
        #expect(result2 == "false")
    }
    
    @Test("Filters in control structures")
    func testFiltersInControlStructures() throws {
        let template = try Template("""
        {% if name | trim %}
        Hello {{ name | upper }}!
        {% endif %}
        """)
        let env = Self.createEnvironmentWithFilters()
        
        let result1 = try template.render(["name": "  alice  "], environment: env)
        #expect(result1.contains("Hello ALICE!"))
        
        let result2 = try template.render(["name": "   "], environment: env)
        #expect(!result2.contains("Hello"))
    }
    
    @Test("Nested filter calls")
    func testNestedFilterCalls() throws {
        let template = try Template("{{ items | join(' | ') | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "items": ["apple", "banana", "cherry"]
        ], environment: env)
        #expect(result == "APPLE | BANANA | CHERRY")
    }
    
    @Test("Filter with member access")
    func testFilterWithMemberAccess() throws {
        let template = try Template("{{ user.name | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "user": ["name": "john doe"]
        ], environment: env)
        #expect(result == "JOHN DOE")
    }
    
    @Test("Filter with array access")
    func testFilterWithArrayAccess() throws {
        let template = try Template("{{ users[0].name | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "users": [["name": "alice"], ["name": "bob"]]
        ], environment: env)
        #expect(result == "ALICE")
    }
    
    // MARK: - Chat Template Filter Patterns
    
    @Test("Chat template message joining")
    func testChatTemplateMessageJoining() throws {
        let template = try Template("""
        {{ messages | join('\\n') }}
        """)
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "messages": [
                "System: You are a helpful assistant",
                "User: Hello",
                "Assistant: Hi there!"
            ]
        ], environment: env)
        #expect(result.contains("System: You are a helpful assistant\\nUser: Hello"))
    }
    
    @Test("Chat template conditional formatting")
    func testChatTemplateConditionalFormatting() throws {
        let template = try Template("""
        {% for message in messages %}
        {{ message.role | upper }}: {{ message.content | trim }}
        {% endfor %}
        """)
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "messages": [
                ["role": "user", "content": "  What's the weather?  "],
                ["role": "assistant", "content": "It's sunny today."]
            ]
        ], environment: env)
        
        #expect(result.contains("USER: What's the weather?"))
        #expect(result.contains("ASSISTANT: It's sunny today."))
    }
    
    // MARK: - Filter Block Syntax
    
    @Test("Filter block syntax")
    func testFilterBlockSyntax() throws {
        // minja supports {% filter filtername %}...{% endfilter %} syntax
        let template = try Template("""
        {% filter upper %}
        hello world
        {% endfilter %}
        """)
        let env = Self.createEnvironmentWithFilters()
        
        // This may not be implemented yet, but should be part of comprehensive tests
        #expect(throws: JinjaError.self) {
            _ = try template.render([:], environment: env)
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty string filter")
    func testEmptyStringFilter() throws {
        let template = try Template("{{ '' | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([:], environment: env)
        #expect(result == "")
    }
    
    @Test("Null value filter")
    func testNullValueFilter() throws {
        let template = try Template("{{ none | upper }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([:], environment: env)
        #expect(result == "") // Should handle gracefully
    }
    
    @Test("Filter with complex argument")
    func testFilterWithComplexArgument() throws {
        let template = try Template("{{ items | join(sep ~ suffix) }}")
        let env = Self.createEnvironmentWithFilters()
        
        let result = try template.render([
            "items": ["a", "b", "c"],
            "sep": ", ",
            "suffix": "!"
        ], environment: env)
        #expect(result == "a, !b, !c")
    }
}

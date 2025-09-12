// import Testing
// @testable import Jinja

// @Suite("Test Operator (is/is not) Tests")
// struct TestOperatorTests {

//     // MARK: - Test Environment Setup

//     private static func createEnvironmentWithTests() -> Environment {
//         let env = Environment()

//         // Built-in tests that minja should support
//         env["defined"] = .function { values in
//             guard let first = values.first else { return .boolean(false) }
//             return .boolean(first != .undefined)
//         }

//         env["undefined"] = .function { values in
//             guard let first = values.first else { return .boolean(true) }
//             return .boolean(first == .undefined)
//         }

//         env["none"] = .function { values in
//             guard let first = values.first else { return .boolean(true) }
//             return .boolean(first == .null)
//         }

//         env["boolean"] = .function { values in
//             guard let first = values.first else { return .boolean(false) }
//             return .boolean(first.isBoolean)
//         }

//         env["string"] = .function { values in
//             guard let first = values.first else { return .boolean(false) }
//             return .boolean(first.isString)
//         }

//         env["number"] = .function { values in
//             guard let first = values.first else { return .boolean(false) }
//             return .boolean(first.isNumber)
//         }

//         env["iterable"] = .function { values in
//             guard let first = values.first else { return .boolean(false) }
//             return .boolean(first.isIterable)
//         }

//         env["even"] = .function { values in
//             guard let first = values.first else { return .boolean(false) }
//             switch first {
//             case .integer(let num): return .boolean(num % 2 == 0)
//             case .number(let num): return .boolean(Int(num) % 2 == 0)
//             default: return .boolean(false)
//             }
//         }

//         env["odd"] = .function { values in
//             guard let first = values.first else { return .boolean(false) }
//             switch first {
//             case .integer(let num): return .boolean(num % 2 != 0)
//             case .number(let num): return .boolean(Int(num) % 2 != 0)
//             default: return .boolean(false)
//             }
//         }

//         env["divisibleby"] = .function { values in
//             guard values.count >= 2,
//                   let dividend = values[0] as? Value,
//                   let divisor = values[1] as? Value else { return .boolean(false) }

//             switch (dividend, divisor) {
//             case (.integer(let a), .integer(let b)):
//                 return .boolean(b != 0 && a % b == 0)
//             case (.number(let a), .number(let b)):
//                 return .boolean(b != 0.0 && Int(a) % Int(b) == 0)
//             default:
//                 return .boolean(false)
//             }
//         }

//         env["equalto"] = .function { values in
//             guard values.count >= 2 else { return .boolean(false) }
//             return .boolean(values[0] == values[1])
//         }

//         return env
//     }

//     // MARK: - Basic Test Syntax

//     @Test("Basic is test syntax")
//     func testBasicIsTestSyntax() throws {
//         let template = try Template("{{ value is defined }}")
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render(["value": "hello"], environment: env)
//         #expect(result1 == "true")

//         let result2 = try template.render([:], environment: env) // value is undefined
//         #expect(result2 == "false")
//     }

//     @Test("Basic is not test syntax")
//     func testBasicIsNotTestSyntax() throws {
//         let template = try Template("{{ value is not none }}")
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render(["value": "hello"], environment: env)
//         #expect(result1 == "true")

//         let result2 = try template.render(["value": nil], environment: env)
//         #expect(result2 == "false")
//     }

//     // MARK: - Built-in Tests

//     @Test("Defined test")
//     func testDefinedTest() throws {
//         let env = Self.createEnvironmentWithTests()

//         let template = try Template("{{ var is defined }}")

//         let result1 = try template.render(["var": "exists"], environment: env)
//         #expect(result1 == "true")

//         let result2 = try template.render([:], environment: env)
//         #expect(result2 == "false")
//     }

//     @Test("Undefined test")
//     func testUndefinedTest() throws {
//         let env = Self.createEnvironmentWithTests()

//         let template = try Template("{{ var is undefined }}")

//         let result1 = try template.render([:], environment: env)
//         #expect(result1 == "true")

//         let result2 = try template.render(["var": "exists"], environment: env)
//         #expect(result2 == "false")
//     }

//     @Test("None test")
//     func testNoneTest() throws {
//         let env = Self.createEnvironmentWithTests()

//         let template = try Template("{{ var is none }}")

//         let result1 = try template.render(["var": nil], environment: env)
//         #expect(result1 == "true")

//         let result2 = try template.render(["var": "not null"], environment: env)
//         #expect(result2 == "false")
//     }

//     @Test("Type tests")
//     func testTypeTests() throws {
//         let env = Self.createEnvironmentWithTests()

//         // String test
//         let strTemplate = try Template("{{ value is string }}")
//         let strResult1 = try strTemplate.render(["value": "hello"], environment: env)
//         let strResult2 = try strTemplate.render(["value": 42], environment: env)
//         #expect(strResult1 == "true")
//         #expect(strResult2 == "false")

//         // Number test
//         let numTemplate = try Template("{{ value is number }}")
//         let numResult1 = try numTemplate.render(["value": 42], environment: env)
//         let numResult2 = try numTemplate.render(["value": 3.14], environment: env)
//         let numResult3 = try numTemplate.render(["value": "text"], environment: env)
//         #expect(numResult1 == "true")
//         #expect(numResult2 == "true")
//         #expect(numResult3 == "false")

//         // Boolean test
//         let boolTemplate = try Template("{{ value is boolean }}")
//         let boolResult1 = try boolTemplate.render(["value": true], environment: env)
//         let boolResult2 = try boolTemplate.render(["value": false], environment: env)
//         let boolResult3 = try boolTemplate.render(["value": "true"], environment: env)
//         #expect(boolResult1 == "true")
//         #expect(boolResult2 == "true")
//         #expect(boolResult3 == "false")
//     }

//     @Test("Iterable test")
//     func testIterableTest() throws {
//         let env = Self.createEnvironmentWithTests()

//         let template = try Template("{{ value is iterable }}")

//         let result1 = try template.render(["value": ["a", "b", "c"]], environment: env)
//         let result2 = try template.render(["value": ["key": "value"]], environment: env)
//         let result3 = try template.render(["value": "string"], environment: env)
//         let result4 = try template.render(["value": 42], environment: env)

//         #expect(result1 == "true")  // array is iterable
//         #expect(result2 == "true")  // object is iterable
//         #expect(result3 == "true")  // string is iterable
//         #expect(result4 == "false") // number is not iterable
//     }

//     @Test("Even and odd tests")
//     func testEvenOddTests() throws {
//         let env = Self.createEnvironmentWithTests()

//         // Even test
//         let evenTemplate = try Template("{{ num is even }}")
//         let evenResult1 = try evenTemplate.render(["num": 4], environment: env)
//         let evenResult2 = try evenTemplate.render(["num": 5], environment: env)
//         let evenResult3 = try evenTemplate.render(["num": 0], environment: env)
//         #expect(evenResult1 == "true")
//         #expect(evenResult2 == "false")
//         #expect(evenResult3 == "true")

//         // Odd test
//         let oddTemplate = try Template("{{ num is odd }}")
//         let oddResult1 = try oddTemplate.render(["num": 3], environment: env)
//         let oddResult2 = try oddTemplate.render(["num": 6], environment: env)
//         let oddResult3 = try oddTemplate.render(["num": 1], environment: env)
//         #expect(oddResult1 == "true")
//         #expect(oddResult2 == "false")
//         #expect(oddResult3 == "true")
//     }

//     @Test("Divisibleby test")
//     func testDivisiblebyTest() throws {
//         let env = Self.createEnvironmentWithTests()

//         let template = try Template("{{ num is divisibleby(3) }}")

//         let result1 = try template.render(["num": 9], environment: env)
//         let result2 = try template.render(["num": 10], environment: env)
//         let result3 = try template.render(["num": 0], environment: env)

//         #expect(result1 == "true")
//         #expect(result2 == "false")
//         #expect(result3 == "true")
//     }

//     @Test("Equalto test")
//     func testEqualtoTest() throws {
//         let env = Self.createEnvironmentWithTests()

//         let template = try Template("{{ value is equalto(42) }}")

//         let result1 = try template.render(["value": 42], environment: env)
//         let result2 = try template.render(["value": 43], environment: env)
//         let result3 = try template.render(["value": "42"], environment: env)

//         #expect(result1 == "true")
//         #expect(result2 == "false")
//         #expect(result3 == "false") // Different types
//     }

//     // MARK: - Negated Tests

//     @Test("Negated tests")
//     func testNegatedTests() throws {
//         let env = Self.createEnvironmentWithTests()

//         // is not defined
//         let notDefinedTemplate = try Template("{{ var is not defined }}")
//         let notDefinedResult1 = try notDefinedTemplate.render([:], environment: env)
//         let notDefinedResult2 = try notDefinedTemplate.render(["var": "exists"], environment: env)
//         #expect(notDefinedResult1 == "true")
//         #expect(notDefinedResult2 == "false")

//         // is not none
//         let notNoneTemplate = try Template("{{ var is not none }}")
//         let notNoneResult1 = try notNoneTemplate.render(["var": "hello"], environment: env)
//         let notNoneResult2 = try notNoneTemplate.render(["var": nil], environment: env)
//         #expect(notNoneResult1 == "true")
//         #expect(notNoneResult2 == "false")

//         // is not even
//         let notEvenTemplate = try Template("{{ num is not even }}")
//         let notEvenResult1 = try notEvenTemplate.render(["num": 3], environment: env)
//         let notEvenResult2 = try notEvenTemplate.render(["num": 4], environment: env)
//         #expect(notEvenResult1 == "true")
//         #expect(notEvenResult2 == "false")
//     }

//     // MARK: - Tests in Control Structures

//     @Test("Tests in if statements")
//     func testTestsInIfStatements() throws {
//         let template = try Template("""
//         {% if user is defined %}
//         Hello {{ user }}!
//         {% else %}
//         Hello Guest!
//         {% endif %}
//         """)
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render(["user": "Alice"], environment: env)
//         #expect(result1.contains("Hello Alice!"))

//         let result2 = try template.render([:], environment: env)
//         #expect(result2.contains("Hello Guest!"))
//     }

//     @Test("Tests in for loop conditions")
//     func testTestsInForLoopConditions() throws {
//         let template = try Template("""
//         {% for item in items if item is not none %}
//         {{ item }}
//         {% endfor %}
//         """)
//         let env = Self.createEnvironmentWithTests()

//         let result = try template.render([
//             "items": ["apple", nil, "banana", nil, "cherry"]
//         ], environment: env)

//         #expect(result.contains("apple"))
//         #expect(result.contains("banana"))
//         #expect(result.contains("cherry"))
//         #expect(!result.contains("null"))
//     }

//     @Test("Complex test expressions")
//     func testComplexTestExpressions() throws {
//         let template = try Template("{{ (x is defined) and (x is not none) and (x is number) }}")
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render(["x": 42], environment: env)
//         let result2 = try template.render(["x": "not a number"], environment: env)
//         let result3 = try template.render(["x": nil], environment: env)
//         let result4 = try template.render([:], environment: env)

//         #expect(result1 == "true")
//         #expect(result2 == "false")
//         #expect(result3 == "false")
//         #expect(result4 == "false")
//     }

//     // MARK: - Tests with Member Access

//     @Test("Tests with member access")
//     func testTestsWithMemberAccess() throws {
//         let template = try Template("{{ user.name is defined }}")
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render([
//             "user": ["name": "Alice", "age": 30]
//         ], environment: env)
//         #expect(result1 == "true")

//         let result2 = try template.render([
//             "user": ["age": 30] // no name property
//         ], environment: env)
//         #expect(result2 == "false")
//     }

//     @Test("Tests with array access")
//     func testTestsWithArrayAccess() throws {
//         let template = try Template("{{ items[1] is defined }}")
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render([
//             "items": ["first", "second", "third"]
//         ], environment: env)
//         #expect(result1 == "true")

//         let result2 = try template.render([
//             "items": ["only"] // index 1 doesn't exist
//         ], environment: env)
//         #expect(result2 == "false")
//     }

//     // MARK: - Chat Template Test Patterns

//     @Test("Chat template role validation")
//     func testChatTemplateRoleValidation() throws {
//         let template = try Template("""
//         {% for message in messages %}
//         {% if message.role is defined and message.content is defined %}
//         {{ message.role }}: {{ message.content }}
//         {% endif %}
//         {% endfor %}
//         """)
//         let env = Self.createEnvironmentWithTests()

//         let result = try template.render([
//             "messages": [
//                 ["role": "user", "content": "Hello"],
//                 ["role": "assistant"], // missing content
//                 ["content": "World"], // missing role
//                 ["role": "user", "content": "Goodbye"]
//             ]
//         ], environment: env)

//         #expect(result.contains("user: Hello"))
//         #expect(result.contains("user: Goodbye"))
//         #expect(!result.contains("assistant:")) // should be filtered out
//         #expect(!result.contains("World")) // should be filtered out
//     }

//     @Test("Chat template conditional formatting with tests")
//     func testChatTemplateConditionalFormattingWithTests() throws {
//         let template = try Template("""
//         {% for message in messages %}
//         {% if message.role is equalto('system') %}
//         <|system|>{{ message.content }}<|end|>
//         {% elif message.role is equalto('user') %}
//         <|user|>{{ message.content }}<|end|>
//         {% elif message.role is equalto('assistant') %}
//         <|assistant|>{{ message.content }}<|end|>
//         {% endif %}
//         {% endfor %}
//         """)
//         let env = Self.createEnvironmentWithTests()

//         let result = try template.render([
//             "messages": [
//                 ["role": "system", "content": "You are helpful"],
//                 ["role": "user", "content": "Hi there"],
//                 ["role": "assistant", "content": "Hello!"]
//             ]
//         ], environment: env)

//         #expect(result.contains("<|system|>You are helpful<|end|>"))
//         #expect(result.contains("<|user|>Hi there<|end|>"))
//         #expect(result.contains("<|assistant|>Hello!<|end|>"))
//     }

//     @Test("Tool validation with tests")
//     func testToolValidationWithTests() throws {
//         let template = try Template("""
//         {% if tools is defined and tools is iterable %}
//         Available tools: {{ tools | count }}
//         {% for tool in tools if tool.name is defined %}
//         - {{ tool.name }}
//         {% endfor %}
//         {% endif %}
//         """)
//         let env = Self.createEnvironmentWithTests()

//         let result = try template.render([
//             "tools": [
//                 ["name": "calculator", "type": "function"],
//                 ["type": "function"], // missing name
//                 ["name": "weather", "type": "function"]
//             ]
//         ], environment: env)

//         #expect(result.contains("Available tools: 3"))
//         #expect(result.contains("- calculator"))
//         #expect(result.contains("- weather"))
//         #expect(!result.contains("- function")) // anonymous tool should be filtered out
//     }

//     // MARK: - Error Cases

//     @Test("Undefined test function")
//     func testUndefinedTestFunction() throws {
//         let template = try Template("{{ value is nonexistent_test }}")
//         let env = Environment()

//         #expect(throws: JinjaError.self) {
//             _ = try template.render(["value": "test"], environment: env)
//         }
//     }

//     @Test("Test with wrong argument count")
//     func testTestWithWrongArgumentCount() throws {
//         let template = try Template("{{ value is divisibleby }}")  // missing argument
//         let env = Self.createEnvironmentWithTests()

//         #expect(throws: JinjaError.self) {
//             _ = try template.render(["value": 10], environment: env)
//         }
//     }

//     // MARK: - Edge Cases

//     @Test("Chained tests")
//     func testChainedTests() throws {
//         let template = try Template("{{ value is defined and value is not none and value is string }}")
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render(["value": "hello"], environment: env)
//         let result2 = try template.render(["value": 42], environment: env)
//         let result3 = try template.render(["value": nil], environment: env)

//         #expect(result1 == "true")
//         #expect(result2 == "false")
//         #expect(result3 == "false")
//     }

//     @Test("Tests in ternary expressions")
//     func testTestsInTernaryExpressions() throws {
//         let template = try Template("{{ 'defined' if value is defined else 'undefined' }}")
//         let env = Self.createEnvironmentWithTests()

//         let result1 = try template.render(["value": "exists"], environment: env)
//         let result2 = try template.render([:], environment: env)

//         #expect(result1 == "defined")
//         #expect(result2 == "undefined")
//     }

//     @Test("Tests with function calls")
//     func testTestsWithFunctionCalls() throws {
//         let template = try Template("{{ range(5)[2] is even }}")
//         let env = Self.createEnvironmentWithTests()

//         let result = try template.render([:], environment: env)
//         #expect(result == "true") // range(5)[2] is 2, which is even
//     }
// }

//
//  BasicTests.swift
//  Jinja
//

import Testing

@testable import Jinja

@Suite("Basic Jinja Template Tests", .enabled(if: true))
struct BasicTests {

    // MARK: - Template Creation and Rendering Tests

    @Test("Simple template creation and rendering")
    func testSimpleTemplate() async throws {
        let template = try Template("Hello {{ name }}!")
        let result = try template.render(["name": "World"])
        #expect(result == "Hello World!")
    }

    @Test("Variable substitution with Value types")
    func testVariableSubstitution() async throws {
        let template = try Template("{{ greeting }} {{ name }}!")
        let context: [String: Value] = [
            "greeting": "Hello",
            "name": "Swift",
        ]
        let result = try template.render(context)
        #expect(result == "Hello Swift!")
    }

    @Test("Compiled template creation and reuse")
    func testCompiledTemplate() async throws {
        let compiled = try Template("Hello {{ name }}!")

        let result1 = try compiled.render(["name": "Alice"])
        let result2 = try compiled.render(["name": "Bob"])

        #expect(result1 == "Hello Alice!")
        #expect(result2 == "Hello Bob!")
    }

    // MARK: - Tokenization Tests

    @Test("Basic tokenization")
    func testBasicTokenization() async throws {
        let tokens = try Lexer.tokenize("{{ name }}")

        #expect(tokens.count >= 1)

        // Find the expression token
        let expressionToken = tokens.first { token in
            token.kind == Token.Kind.expression
        }
        #expect(expressionToken != nil)
        #expect(expressionToken?.value == "name")
    }

    @Test("Text tokenization")
    func testTextTokenization() async throws {
        let tokens = try Lexer.tokenize("Hello, world!")

        #expect(tokens.count >= 1)
        let textToken = tokens.first { token in
            token.kind == Token.Kind.text
        }
        #expect(textToken != nil)
        #expect(textToken?.value == "Hello, world!")
    }

    @Test("Mixed content tokenization")
    func testMixedTokenization() async throws {
        let tokens = try Lexer.tokenize("Hello {{ name }}!")

        #expect(tokens.count >= 2)

        let textTokens = tokens.filter { $0.kind == Token.Kind.text }
        let expressionTokens = tokens.filter { $0.kind == Token.Kind.expression }

        #expect(textTokens.count >= 1)
        #expect(expressionTokens.count >= 1)
    }

    // MARK: - Parsing Tests

    @Test("Parse simple text")
    func testParseSimpleText() async throws {
        let tokens = try Lexer.tokenize("Hello, world!")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)

        if case let .text(content) = nodes[0] {
            #expect(content == "Hello, world!")
        } else {
            Issue.record("Expected text node")
        }
    }

    @Test("Parse variable expression")
    func testParseVariable() async throws {
        let tokens = try Lexer.tokenize("{{ name }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)

        if case let .expression(expr) = nodes[0] {
            if case let .identifier(name) = expr {
                #expect(name == "name")
            } else {
                Issue.record("Expected identifier expression")
            }
        } else {
            Issue.record("Expected expression node")
        }
    }

    @Test("Parse string literal")
    func testParseStringLiteral() async throws {
        let tokens = try Lexer.tokenize("{{ 'hello' }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)

        if case let .expression(expr) = nodes[0] {
            if case let .string(value) = expr {
                #expect(value == "hello")
            } else {
                Issue.record("Expected string literal expression")
            }
        } else {
            Issue.record("Expected expression node")
        }
    }

    // MARK: - Control Structure Tests

    @Test("For loop statement test")
    func testForLoopStatement() async throws {
        let template = try Template("{% for item in items %}{{ item }}{% endfor %}")
        let context: [String: Value] = [
            "items": ["a", "b", "c"]
        ]

        let result = try template.render(context)
        #expect(result == "abc")
    }

    @Test("For loop with mixed content test")
    func testForLoopMixedContent() async throws {
        let template = try Template("Items: {% for item in items %}{{ item }}, {% endfor %}done")
        let context: [String: Value] = [
            "items": ["apple", "banana"]
        ]

        let result = try template.render(context)
        #expect(result.contains("apple"))
        #expect(result.contains("banana"))
    }

    @Test("Empty for loop test")
    func testEmptyForLoop() async throws {
        let template = try Template("{% for item in items %}{{ item }}{% endfor %}")
        let context: [String: Value] = [
            "items": []
        ]

        let result = try template.render(context)
        #expect(result == "")
    }

    @Test("Elif statement test")
    func testElifStatement() async throws {
        let template = try Template(
            "{% if x == 1 %}one{% elif x == 2 %}two{% else %}other{% endif %}")

        let result1 = try template.render(["x": 1])
        let result2 = try template.render(["x": 2])
        let result3 = try template.render(["x": 3])

        #expect(result1.contains("one"))
        #expect(result2.contains("two"))
        #expect(result3.contains("other"))
    }

    // MARK: - Error Handling Tests

    @Test("Invalid template syntax throws error")
    func testInvalidSyntax() async throws {
        #expect(throws: JinjaError.self) {
            _ = try Template("{% invalid syntax %}")
        }
    }

    @Test("Tokenization error on invalid input")
    func testTokenizationError() async throws {
        #expect(throws: JinjaError.self) {
            _ = try Lexer.tokenize("{{ unclosed")
        }
    }


}

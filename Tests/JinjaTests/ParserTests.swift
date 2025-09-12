import Testing

@testable import Jinja

@Suite("Parser AST Generation Tests")
struct ParserTests {

    // MARK: - Expression Parsing

    @Test("Literal expression parsing")
    func testLiteralExpressions() throws {
        // String literals
        let stringTokens = try Lexer.tokenize("{{ 'hello world' }}")
        let stringNodes = try Parser.parse(stringTokens)
        #expect(stringNodes.count == 1)
        if case .expression(.string(let value)) = stringNodes[0] {
            #expect(value == "hello world")
        } else {
            Issue.record("Expected string expression")
        }

        // Integer literals
        let intTokens = try Lexer.tokenize("{{ 42 }}")
        let intNodes = try Parser.parse(intTokens)
        #expect(intNodes.count == 1)
        if case .expression(.integer(let value)) = intNodes[0] {
            #expect(value == 42)
        } else {
            Issue.record("Expected integer expression")
        }

        // Float literals
        let floatTokens = try Lexer.tokenize("{{ 3.14 }}")
        let floatNodes = try Parser.parse(floatTokens)
        #expect(floatNodes.count == 1)
        if case .expression(.number(let value)) = floatNodes[0] {
            #expect(value == 3.14)
        } else {
            Issue.record("Expected number expression")
        }

        // Boolean literals
        let boolTokens = try Lexer.tokenize("{{ true }}")
        let boolNodes = try Parser.parse(boolTokens)
        #expect(boolNodes.count == 1)
        if case .expression(.boolean(let value)) = boolNodes[0] {
            #expect(value == true)
        } else {
            Issue.record("Expected boolean expression")
        }

        // None literal
        let noneTokens = try Lexer.tokenize("{{ none }}")
        let noneNodes = try Parser.parse(noneTokens)
        #expect(noneNodes.count == 1)
        if case .expression(.null) = noneNodes[0] {
            // Success
        } else {
            Issue.record("Expected null expression")
        }
    }

    @Test("Array literal parsing")
    func testArrayLiteralParsing() throws {
        let tokens = try Lexer.tokenize("{{ [1, 'hello', true] }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .expression(.array(let elements)) = nodes[0] {
            #expect(elements.count == 3)

            if case .integer(let intVal) = elements[0] {
                #expect(intVal == 1)
            } else {
                Issue.record("Expected integer in array")
            }

            if case .string(let strVal) = elements[1] {
                #expect(strVal == "hello")
            } else {
                Issue.record("Expected string in array")
            }

            if case .boolean(let boolVal) = elements[2] {
                #expect(boolVal == true)
            } else {
                Issue.record("Expected boolean in array")
            }
        } else {
            Issue.record("Expected array expression")
        }
    }

    @Test("Object literal parsing")
    func testObjectLiteralParsing() throws {
        let tokens = try Lexer.tokenize("{{ {'name': 'John', 'age': 30} }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .expression(.object(let dict)) = nodes[0] {
            #expect(dict.count == 2)

            if case .string(let nameVal) = dict["name"] {
                #expect(nameVal == "John")
            } else {
                Issue.record("Expected string value for name")
            }

            if case .integer(let ageVal) = dict["age"] {
                #expect(ageVal == 30)
            } else {
                Issue.record("Expected integer value for age")
            }
        } else {
            Issue.record("Expected object expression")
        }
    }

    @Test("Binary operation parsing")
    func testBinaryOperationParsing() throws {
        // Arithmetic operations
        let addTokens = try Lexer.tokenize("{{ a + b }}")
        let addNodes = try Parser.parse(addTokens)
        #expect(addNodes.count == 1)
        if case .expression(.binary(.add, .identifier(let left), .identifier(let right))) =
            addNodes[0]
        {
            #expect(left == "a")
            #expect(right == "b")
        } else {
            Issue.record("Expected binary add expression")
        }

        // Comparison operations
        let eqTokens = try Lexer.tokenize("{{ x == y }}")
        let eqNodes = try Parser.parse(eqTokens)
        #expect(eqNodes.count == 1)
        if case .expression(.binary(.equal, .identifier(let left), .identifier(let right))) =
            eqNodes[0]
        {
            #expect(left == "x")
            #expect(right == "y")
        } else {
            Issue.record("Expected binary equal expression")
        }

        // String concatenation
        let concatTokens = try Lexer.tokenize("{{ 'hello' ~ ' world' }}")
        let concatNodes = try Parser.parse(concatTokens)
        #expect(concatNodes.count == 1)
        if case .expression(.binary(.concat, .string(let left), .string(let right))) = concatNodes[
            0]
        {
            #expect(left == "hello")
            #expect(right == " world")
        } else {
            Issue.record("Expected binary concat expression")
        }
    }

    @Test("Unary operation parsing")
    func testUnaryOperationParsing() throws {
        // Logical not
        let notTokens = try Lexer.tokenize("{{ not condition }}")
        let notNodes = try Parser.parse(notTokens)
        #expect(notNodes.count == 1)
        if case .expression(.unary(.not, .identifier(let operand))) = notNodes[0] {
            #expect(operand == "condition")
        } else {
            Issue.record("Expected unary not expression")
        }

        // Numeric negation
        let minusTokens = try Lexer.tokenize("{{ -value }}")
        let minusNodes = try Parser.parse(minusTokens)
        #expect(minusNodes.count == 1)
        if case .expression(.unary(.minus, .identifier(let operand))) = minusNodes[0] {
            #expect(operand == "value")
        } else {
            Issue.record("Expected unary minus expression")
        }
    }

    @Test("Member access parsing")
    func testMemberAccessParsing() throws {
        // Dot notation
        let dotTokens = try Lexer.tokenize("{{ object.property }}")
        let dotNodes = try Parser.parse(dotTokens)
        #expect(dotNodes.count == 1)
        if case .expression(.member(.identifier(let obj), .identifier(let prop), computed: false)) =
            dotNodes[0]
        {
            #expect(obj == "object")
            #expect(prop == "property")
        } else {
            Issue.record("Expected member access expression")
        }

        // Bracket notation
        let bracketTokens = try Lexer.tokenize("{{ object['key'] }}")
        let bracketNodes = try Parser.parse(bracketTokens)
        #expect(bracketNodes.count == 1)
        if case .expression(.member(.identifier(let obj), .string(let key), computed: true)) =
            bracketNodes[0]
        {
            #expect(obj == "object")
            #expect(key == "key")
        } else {
            Issue.record("Expected computed member access expression")
        }
    }

    @Test("Function call parsing")
    func testFunctionCallParsing() throws {
        // Simple function call
        let simpleTokens = try Lexer.tokenize("{{ func() }}")
        let simpleNodes = try Parser.parse(simpleTokens)
        #expect(simpleNodes.count == 1)
        if case .expression(.call(.identifier(let name), let args, let kwargs)) = simpleNodes[0] {
            #expect(name == "func")
            #expect(args.isEmpty)
            #expect(kwargs.isEmpty)
        } else {
            Issue.record("Expected function call expression")
        }

        // Function call with arguments
        let argsTokens = try Lexer.tokenize("{{ func(arg1, arg2) }}")
        let argsNodes = try Parser.parse(argsTokens)
        #expect(argsNodes.count == 1)
        if case .expression(.call(.identifier(let name), let args, let kwargs)) = argsNodes[0] {
            #expect(name == "func")
            #expect(args.count == 2)
            #expect(kwargs.isEmpty)
        } else {
            Issue.record("Expected function call with args expression")
        }

        // Function call with keyword arguments
        let kwargsTokens = try Lexer.tokenize("{{ func(pos_arg, key=value) }}")
        let kwargsNodes = try Parser.parse(kwargsTokens)
        #expect(kwargsNodes.count == 1)
        if case .expression(.call(.identifier(let name), let args, let kwargs)) = kwargsNodes[0] {
            #expect(name == "func")
            #expect(args.count == 1)
            #expect(kwargs.count == 1)
            #expect(kwargs["key"] != nil)
        } else {
            Issue.record("Expected function call with kwargs expression")
        }
    }

    @Test("Filter parsing")
    func testFilterParsing() throws {
        // Simple filter
        let simpleTokens = try Lexer.tokenize("{{ value | upper }}")
        let simpleNodes = try Parser.parse(simpleTokens)
        #expect(simpleNodes.count == 1)
        if case .expression(.filter(.identifier(let value), let filterName, let args, let kwargs)) =
            simpleNodes[0]
        {
            #expect(value == "value")
            #expect(filterName == "upper")
            #expect(args.isEmpty)
            #expect(kwargs.isEmpty)
        } else {
            Issue.record("Expected filter expression")
        }

        // Filter with arguments
        let argsTokens = try Lexer.tokenize("{{ items | join(', ') }}")
        let argsNodes = try Parser.parse(argsTokens)
        #expect(argsNodes.count == 1)
        if case .expression(.filter(.identifier(let value), let filterName, let args, let kwargs)) =
            argsNodes[0]
        {
            #expect(value == "items")
            #expect(filterName == "join")
            #expect(args.count == 1)
            #expect(kwargs.isEmpty)
        } else {
            Issue.record("Expected filter with args expression")
        }

        // Chained filters
        let chainedTokens = try Lexer.tokenize("{{ value | upper | trim }}")
        let chainedNodes = try Parser.parse(chainedTokens)
        #expect(chainedNodes.count == 1)
        if case .expression(
            .filter(.filter(.identifier(let value), let firstFilter, _, _), let secondFilter, _, _)) =
            chainedNodes[0]
        {
            #expect(value == "value")
            #expect(firstFilter == "upper")
            #expect(secondFilter == "trim")
        } else {
            Issue.record("Expected chained filter expression")
        }
    }

    @Test("Test operation parsing")
    func testTestOperationParsing() throws {
        // Simple test
        let simpleTokens = try Lexer.tokenize("{{ value is defined }}")
        let simpleNodes = try Parser.parse(simpleTokens)
        #expect(simpleNodes.count == 1)
        if case .expression(.test(.identifier(let value), let testName, negated: let negated)) =
            simpleNodes[0]
        {
            #expect(value == "value")
            #expect(testName == "defined")
            #expect(negated == false)
        } else {
            Issue.record("Expected test expression")
        }

        // Negated test
        let negatedTokens = try Lexer.tokenize("{{ value is not none }}")
        let negatedNodes = try Parser.parse(negatedTokens)
        #expect(negatedNodes.count == 1)
        if case .expression(.test(.identifier(let value), let testName, negated: let negated)) =
            negatedNodes[0]
        {
            #expect(value == "value")
            #expect(testName == "none")
            #expect(negated == true)
        } else {
            Issue.record("Expected negated test expression")
        }
    }

    @Test("Ternary expression parsing")
    func testTernaryExpressionParsing() throws {
        let tokens = try Lexer.tokenize("{{ 'yes' if condition else 'no' }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .expression(
            .ternary(
                .string(let value), test: .identifier(let condition), alternate: .string(let alt))) =
            nodes[0]
        {
            #expect(value == "yes")
            #expect(condition == "condition")
            #expect(alt == "no")
        } else {
            Issue.record("Expected ternary expression")
        }
    }

    // MARK: - Statement Parsing

    @Test("Set statement parsing")
    func testSetStatementParsing() throws {
        let tokens = try Lexer.tokenize("{% set x = 42 %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .statement(.set(let identifier, .integer(let value))) = nodes[0] {
            #expect(identifier == "x")
            #expect(value == 42)
        } else {
            Issue.record("Expected set statement")
        }
    }

    @Test("If statement parsing")
    func testIfStatementParsing() throws {
        let tokens = try Lexer.tokenize("{% if condition %}Hello{% endif %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .statement(.if(.identifier(let condition), let body, let alternate)) = nodes[0] {
            #expect(condition == "condition")
            #expect(body.count == 1)
            #expect(alternate.isEmpty)

            if case .text(let text) = body[0] {
                #expect(text == "Hello")
            } else {
                Issue.record("Expected text in if body")
            }
        } else {
            Issue.record("Expected if statement")
        }
    }

    @Test("If-else statement parsing")
    func testIfElseStatementParsing() throws {
        let tokens = try Lexer.tokenize("{% if condition %}Hello{% else %}World{% endif %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .statement(.if(.identifier(let condition), let body, let alternate)) = nodes[0] {
            #expect(condition == "condition")
            #expect(body.count == 1)
            #expect(alternate.count == 1)

            if case .text(let ifText) = body[0] {
                #expect(ifText == "Hello")
            } else {
                Issue.record("Expected text in if body")
            }

            if case .text(let elseText) = alternate[0] {
                #expect(elseText == "World")
            } else {
                Issue.record("Expected text in else body")
            }
        } else {
            Issue.record("Expected if-else statement")
        }
    }

    @Test("If-elif-else statement parsing")
    func testIfElifElseStatementParsing() throws {
        let tokens = try Lexer.tokenize(
            "{% if x == 1 %}One{% elif x == 2 %}Two{% else %}Other{% endif %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .statement(.if(let condition, let body, let alternate)) = nodes[0] {
            // Root condition should be x == 1
            if case .binary(.equal, .identifier(let left), .integer(let right)) = condition {
                #expect(left == "x")
                #expect(right == 1)
            } else {
                Issue.record("Expected binary equal condition")
            }

            // Body should contain "One"
            #expect(body.count == 1)
            if case .text(let text) = body[0] {
                #expect(text == "One")
            } else {
                Issue.record("Expected text in if body")
            }

            // Alternate should contain nested if for elif
            #expect(alternate.count == 1)
        } else {
            Issue.record("Expected if-elif-else statement")
        }
    }

    @Test("For loop parsing")
    func testForLoopParsing() throws {
        let tokens = try Lexer.tokenize("{% for item in items %}{{ item }}{% endfor %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .statement(
            .for(
                .single(let loopVar), .identifier(let iterable), let body, let elseBody,
                test: let test)) = nodes[0]
        {
            #expect(loopVar == "item")
            #expect(iterable == "items")
            #expect(body.count == 1)
            #expect(elseBody.isEmpty)
            #expect(test == nil)

            if case .expression(.identifier(let itemRef)) = body[0] {
                #expect(itemRef == "item")
            } else {
                Issue.record("Expected expression in for body")
            }
        } else {
            Issue.record("Expected for statement")
        }
    }

    @Test("For loop with else parsing")
    func testForLoopWithElseParsing() throws {
        let tokens = try Lexer.tokenize(
            "{% for item in items %}{{ item }}{% else %}Empty{% endfor %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .statement(
            .for(
                .single(let loopVar), .identifier(let iterable), let body, let elseBody,
                test: let test)) = nodes[0]
        {
            #expect(loopVar == "item")
            #expect(iterable == "items")
            #expect(body.count == 1)
            #expect(elseBody.count == 1)
            #expect(test == nil)

            if case .text(let elseText) = elseBody[0] {
                #expect(elseText == "Empty")
            } else {
                Issue.record("Expected text in for else body")
            }
        } else {
            Issue.record("Expected for statement with else")
        }
    }

    @Test("Macro definition parsing")
    func testMacroDefinitionParsing() throws {
        let tokens = try Lexer.tokenize(
            "{% macro greet(name, greeting) %}{{ greeting }} {{ name }}{% endmacro %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .statement(.macro(let name, let params, _, let body)) = nodes[0] {
            #expect(name == "greet")
            #expect(params == ["name", "greeting"])
            #expect(body.count >= 1)  // Should have the macro body content
        } else {
            Issue.record("Expected macro statement")
        }
    }

    // MARK: - Complex Expression Parsing

    @Test("Operator precedence parsing")
    func testOperatorPrecedenceParsing() throws {
        // Test that 2 + 3 * 4 is parsed as 2 + (3 * 4)
        let tokens = try Lexer.tokenize("{{ 2 + 3 * 4 }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .expression(
            .binary(
                .add, .integer(let left),
                .binary(.multiply, .integer(let mulLeft), .integer(let mulRight)))) = nodes[0]
        {
            #expect(left == 2)
            #expect(mulLeft == 3)
            #expect(mulRight == 4)
        } else {
            Issue.record("Expected correct operator precedence parsing")
        }
    }

    @Test("Parentheses grouping parsing")
    func testParenthesesGroupingParsing() throws {
        // Test that (2 + 3) * 4 is parsed as (2 + 3) * 4
        let tokens = try Lexer.tokenize("{{ (2 + 3) * 4 }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .expression(
            .binary(
                .multiply, .binary(.add, .integer(let addLeft), .integer(let addRight)),
                .integer(let right))) = nodes[0]
        {
            #expect(addLeft == 2)
            #expect(addRight == 3)
            #expect(right == 4)
        } else {
            Issue.record("Expected correct parentheses grouping parsing")
        }
    }

    @Test("Complex member access parsing")
    func testComplexMemberAccessParsing() throws {
        let tokens = try Lexer.tokenize("{{ user.profile.name }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case .expression(
            .member(
                .member(.identifier(let obj1), .identifier(let prop1), computed: false),
                .identifier(let prop2), computed: false)) = nodes[0]
        {
            #expect(obj1 == "user")
            #expect(prop1 == "profile")
            #expect(prop2 == "name")
        } else {
            Issue.record("Expected chained member access expression")
        }
    }

    @Test("Mixed member access parsing")
    func testMixedMemberAccessParsing() throws {
        let tokens = try Lexer.tokenize("{{ data.items[0].name }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        // Should parse as ((data.items)[0]).name
        if case .expression(
            .member(
                .member(
                    .member(.identifier(let obj), .identifier(let prop1), computed: false),
                    .integer(let index), computed: true), .identifier(let prop2), computed: false)) =
            nodes[0]
        {
            #expect(obj == "data")
            #expect(prop1 == "items")
            #expect(index == 0)
            #expect(prop2 == "name")
        } else {
            Issue.record("Expected mixed member access expression")
        }
    }

    // MARK: - Node Coalescing and Optimization

    @Test("Text node coalescing")
    func testTextNodeCoalescing() throws {
        let tokens = try Lexer.tokenize("Hello World")
        let nodes = try Parser.parse(tokens)

        // Adjacent text should be coalesced into a single node
        #expect(nodes.count == 1)
        if case .text(let content) = nodes[0] {
            #expect(content == "Hello World")
        } else {
            Issue.record("Expected coalesced text node")
        }
    }

    @Test("Expression constant folding")
    func testExpressionConstantFolding() throws {
        // Integer arithmetic
        let intTokens = try Lexer.tokenize("{{ 2 + 3 }}")
        let intNodes = try Parser.parse(intTokens)
        #expect(intNodes.count == 1)
        if case .expression(.integer(let result)) = intNodes[0] {
            #expect(result == 5)
        } else {
            Issue.record("Expected constant folded integer")
        }

        // Float arithmetic
        let floatTokens = try Lexer.tokenize("{{ 2.5 + 3.5 }}")
        let floatNodes = try Parser.parse(floatTokens)
        #expect(floatNodes.count == 1)
        if case .expression(.number(let result)) = floatNodes[0] {
            #expect(result == 6.0)
        } else {
            Issue.record("Expected constant folded number")
        }

        // String concatenation
        let stringTokens = try Lexer.tokenize("{{ 'hello' ~ ' world' }}")
        let stringNodes = try Parser.parse(stringTokens)
        #expect(stringNodes.count == 1)
        if case .expression(.string(let result)) = stringNodes[0] {
            #expect(result == "hello world")
        } else {
            Issue.record("Expected constant folded string")
        }

        // Boolean operations
        let boolTokens = try Lexer.tokenize("{{ not false }}")
        let boolNodes = try Parser.parse(boolTokens)
        #expect(boolNodes.count == 1)
        if case .expression(.boolean(let result)) = boolNodes[0] {
            #expect(result == true)
        } else {
            Issue.record("Expected constant folded boolean")
        }
    }

    @Test("Statement optimization")
    func testStatementOptimization() throws {
        // Constant true condition should optimize to just the body
        let trueTokens = try Lexer.tokenize("{% if true %}Hello{% endif %}")
        let trueNodes = try Parser.parse(trueTokens)
        #expect(trueNodes.count == 1)
        if case .statement(.program(let body)) = trueNodes[0] {
            #expect(body.count == 1)
            if case .text(let content) = body[0] {
                #expect(content == "Hello")
            } else {
                Issue.record("Expected text in optimized body")
            }
        } else {
            Issue.record("Expected optimized program statement")
        }

        // Constant false condition should optimize to just the alternate
        let falseTokens = try Lexer.tokenize("{% if false %}Hello{% else %}World{% endif %}")
        let falseNodes = try Parser.parse(falseTokens)
        #expect(falseNodes.count == 1)
        if case .statement(.program(let body)) = falseNodes[0] {
            #expect(body.count == 1)
            if case .text(let content) = body[0] {
                #expect(content == "World")
            } else {
                Issue.record("Expected text in optimized alternate")
            }
        } else {
            Issue.record("Expected optimized program statement")
        }
    }

    // MARK: - Error Cases

    @Test("Invalid expression syntax")
    func testInvalidExpressionSyntax() throws {
        #expect(throws: JinjaError.self) {
            _ = try Parser.parse([
                Token(kind: .expression, value: "invalid syntax !!!", position: 0)
            ])
        }
    }

    @Test("Invalid statement syntax")
    func testInvalidStatementSyntax() throws {
        #expect(throws: JinjaError.self) {
            _ = try Parser.parse([Token(kind: .statement, value: "invalid statement", position: 0)])
        }
    }

    @Test("Mismatched control structures")
    func testMismatchedControlStructures() throws {
        #expect(throws: JinjaError.self) {
            let tokens = try Lexer.tokenize("{% if condition %}{% endfor %}")
            _ = try Parser.parse(tokens)
        }
    }

    @Test("Unclosed control structures")
    func testUnclosedControlStructures() throws {
        #expect(throws: JinjaError.self) {
            let tokens = try Lexer.tokenize("{% if condition %}Hello")
            _ = try Parser.parse(tokens)
        }
    }

    // MARK: - Edge Cases

    @Test("Empty expressions")
    func testEmptyExpressions() throws {
        #expect(throws: JinjaError.self) {
            let tokens = try Lexer.tokenize("{{ }}")
            _ = try Parser.parse(tokens)
        }
    }

    @Test("Empty statements")
    func testEmptyStatements() throws {
        #expect(throws: JinjaError.self) {
            let tokens = try Lexer.tokenize("{% %}")
            _ = try Parser.parse(tokens)
        }
    }

    @Test("Nested expressions in text")
    func testNestedExpressionsInText() throws {
        let tokens = try Lexer.tokenize("Hello {{ name }}, you have {{ count }} messages")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 4)  // text, expr, text, expr

        if case .text(let text1) = nodes[0] {
            #expect(text1 == "Hello ")
        } else {
            Issue.record("Expected first text node")
        }

        if case .expression(.identifier(let name)) = nodes[1] {
            #expect(name == "name")
        } else {
            Issue.record("Expected name expression")
        }

        if case .text(let text2) = nodes[2] {
            #expect(text2 == ", you have ")
        } else {
            Issue.record("Expected second text node")
        }

        if case .expression(.identifier(let count)) = nodes[3] {
            #expect(count == "count")
        } else {
            Issue.record("Expected count expression")
        }
    }

    @Test("Complex nested structures")
    func testComplexNestedStructures() throws {
        let template = """
            {% for user in users %}
                {% if user.active %}
                    <div>{{ user.name }} - {{ user.email }}</div>
                {% else %}
                    <div class="inactive">{{ user.name }}</div>
                {% endif %}
            {% endfor %}
            """

        let tokens = try Lexer.tokenize(template)
        let nodes = try Parser.parse(tokens)

        // Should successfully parse without throwing
        #expect(nodes.count > 0)

        // Root node should be a for statement
        if case .statement(
            .for(.single(let loopVar), .identifier(let iterable), let body, _, test: _)) = nodes[0]
        {
            #expect(loopVar == "user")
            #expect(iterable == "users")
            #expect(body.count > 0)
        } else {
            Issue.record("Expected for statement at root")
        }
    }
}

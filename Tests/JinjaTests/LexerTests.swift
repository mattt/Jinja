import Testing
@testable import Jinja

@Suite("Lexer Tokenization Tests")
struct LexerTests {
    
    // MARK: - Basic Template Delimiters
    
    @Test("Expression tokenization")
    func testExpressionTokenization() throws {
        let tokens = try Lexer.tokenize("{{ variable }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "variable")
    }
    
    @Test("Statement tokenization")
    func testStatementTokenization() throws {
        let tokens = try Lexer.tokenize("{% if condition %}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 1)
        #expect(statementTokens[0].value == "if condition")
    }
    
    @Test("Comment handling (preprocessor)")
    func testCommentHandling() throws {
        let tokens = try Lexer.tokenize("Hello {# comment #} World")
        
        // Comments should be removed in preprocessing
        let textTokens = tokens.filter { $0.kind == .text }
        #expect(textTokens.count == 1)
        #expect(textTokens[0].value == "Hello  World")
    }
    
    // MARK: - Whitespace Control (Space Elision)
    
    @Test("Expression whitespace control")
    func testExpressionWhitespaceControl() throws {
        let tokens = try Lexer.tokenize("{{- variable -}}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "variable")
    }
    
    @Test("Statement whitespace control")
    func testStatementWhitespaceControl() throws {
        let tokens = try Lexer.tokenize("{%- if condition -%}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 1)
        #expect(statementTokens[0].value == "if condition")
    }
    
    @Test("Mixed whitespace control")
    func testMixedWhitespaceControl() throws {
        let tokens = try Lexer.tokenize("   {%-   for item in items   -%}   content   {%-   endfor   -%}   ")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 2)
        #expect(statementTokens[0].value == "for item in items")
        #expect(statementTokens[1].value == "endfor")
    }
    
    // MARK: - String Literals
    
    @Test("String literal tokenization - double quotes")
    func testStringLiteralDoubleQuotes() throws {
        let tokens = try Lexer.tokenize("{{ \"hello world\" }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "\"hello world\"")
    }
    
    @Test("String literal tokenization - single quotes")
    func testStringLiteralSingleQuotes() throws {
        let tokens = try Lexer.tokenize("{{ 'hello world' }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "'hello world'")
    }
    
    @Test("String literal with escapes")
    func testStringLiteralEscapes() throws {
        let tokens = try Lexer.tokenize("{{ \"line 1\\nline 2\\ttabbed\" }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "\"line 1\\nline 2\\ttabbed\"")
    }
    
    // MARK: - Numbers
    
    @Test("Integer literal tokenization")
    func testIntegerLiteral() throws {
        let tokens = try Lexer.tokenize("{{ 42 }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "42")
    }
    
    @Test("Float literal tokenization")
    func testFloatLiteral() throws {
        let tokens = try Lexer.tokenize("{{ 3.14159 }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "3.14159")
    }
    
    @Test("Negative number tokenization")
    func testNegativeNumber() throws {
        let tokens = try Lexer.tokenize("{{ -42 }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "-42")
    }
    
    // MARK: - Boolean and None Literals
    
    @Test("Boolean literal tokenization")
    func testBooleanLiterals() throws {
        let truTokens = try Lexer.tokenize("{{ true }}")
        let falseTokens = try Lexer.tokenize("{{ false }}")
        
        let trueExpr = truTokens.filter { $0.kind == .expression }
        let falseExpr = falseTokens.filter { $0.kind == .expression }
        
        #expect(trueExpr.count == 1)
        #expect(trueExpr[0].value == "true")
        
        #expect(falseExpr.count == 1)
        #expect(falseExpr[0].value == "false")
    }
    
    @Test("None literal tokenization")
    func testNoneLiteral() throws {
        let tokens = try Lexer.tokenize("{{ none }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "none")
    }
    
    // MARK: - Operators
    
    @Test("Arithmetic operators")
    func testArithmeticOperators() throws {
        let expressions = [
            "{{ a + b }}",
            "{{ a - b }}",
            "{{ a * b }}",
            "{{ a / b }}",
            "{{ a % b }}"
        ]
        
        for expr in expressions {
            let tokens = try Lexer.tokenize(expr)
            let exprTokens = tokens.filter { $0.kind == .expression }
            #expect(exprTokens.count == 1)
        }
    }
    
    @Test("Comparison operators")
    func testComparisonOperators() throws {
        let expressions = [
            "{{ a == b }}",
            "{{ a != b }}",
            "{{ a < b }}",
            "{{ a <= b }}",
            "{{ a > b }}",
            "{{ a >= b }}"
        ]
        
        for expr in expressions {
            let tokens = try Lexer.tokenize(expr)
            let exprTokens = tokens.filter { $0.kind == .expression }
            #expect(exprTokens.count == 1)
        }
    }
    
    @Test("Logical operators")
    func testLogicalOperators() throws {
        let expressions = [
            "{{ a and b }}",
            "{{ a or b }}",
            "{{ not a }}"
        ]
        
        for expr in expressions {
            let tokens = try Lexer.tokenize(expr)
            let exprTokens = tokens.filter { $0.kind == .expression }
            #expect(exprTokens.count == 1)
        }
    }
    
    @Test("String concatenation operator")
    func testConcatOperator() throws {
        let tokens = try Lexer.tokenize("{{ a ~ b }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "a ~ b")
    }
    
    @Test("Membership operators")
    func testMembershipOperators() throws {
        let inTokens = try Lexer.tokenize("{{ item in list }}")
        let notInTokens = try Lexer.tokenize("{{ item not in list }}")
        
        let inExpr = inTokens.filter { $0.kind == .expression }
        let notInExpr = notInTokens.filter { $0.kind == .expression }
        
        #expect(inExpr.count == 1)
        #expect(inExpr[0].value == "item in list")
        
        #expect(notInExpr.count == 1)
        #expect(notInExpr[0].value == "item not in list")
    }
    
    // MARK: - Filters
    
    @Test("Filter syntax tokenization")
    func testFilterSyntax() throws {
        let tokens = try Lexer.tokenize("{{ value | upper }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "value | upper")
    }
    
    @Test("Filter with arguments")
    func testFilterWithArguments() throws {
        let tokens = try Lexer.tokenize("{{ items | join(', ') }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "items | join(', ')")
    }
    
    @Test("Chained filters")
    func testChainedFilters() throws {
        let tokens = try Lexer.tokenize("{{ value | upper | trim }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "value | upper | trim")
    }
    
    // MARK: - Tests (is operator)
    
    @Test("Test operator tokenization")
    func testTestOperator() throws {
        let tokens = try Lexer.tokenize("{{ value is defined }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "value is defined")
    }
    
    @Test("Negated test operator")
    func testNegatedTestOperator() throws {
        let tokens = try Lexer.tokenize("{{ value is not none }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "value is not none")
    }
    
    // MARK: - Array and Object Literals
    
    @Test("Array literal tokenization")
    func testArrayLiteral() throws {
        let tokens = try Lexer.tokenize("{{ [1, 2, 3] }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "[1, 2, 3]")
    }
    
    @Test("Object literal tokenization")
    func testObjectLiteral() throws {
        let tokens = try Lexer.tokenize("{{ {'key': 'value', 'num': 42} }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "{'key': 'value', 'num': 42}")
    }
    
    // MARK: - Member Access
    
    @Test("Dot notation member access")
    func testDotNotation() throws {
        let tokens = try Lexer.tokenize("{{ object.property }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "object.property")
    }
    
    @Test("Bracket notation member access")
    func testBracketNotation() throws {
        let tokens = try Lexer.tokenize("{{ object['key'] }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "object['key']")
    }
    
    // MARK: - Function Calls
    
    @Test("Function call tokenization")
    func testFunctionCall() throws {
        let tokens = try Lexer.tokenize("{{ func(arg1, arg2) }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "func(arg1, arg2)")
    }
    
    @Test("Function call with keyword arguments")
    func testFunctionCallWithKwargs() throws {
        let tokens = try Lexer.tokenize("{{ func(pos_arg, key=value) }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 1)
        #expect(expressionTokens[0].value == "func(pos_arg, key=value)")
    }
    
    // MARK: - Control Structures
    
    @Test("If statement tokenization")
    func testIfStatement() throws {
        let tokens = try Lexer.tokenize("{% if condition %}content{% endif %}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 2)
        #expect(statementTokens[0].value == "if condition")
        #expect(statementTokens[1].value == "endif")
    }
    
    @Test("If-elif-else statement tokenization")
    func testIfElifElseStatement() throws {
        let tokens = try Lexer.tokenize("{% if condition1 %}A{% elif condition2 %}B{% else %}C{% endif %}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 4)
        #expect(statementTokens[0].value == "if condition1")
        #expect(statementTokens[1].value == "elif condition2")
        #expect(statementTokens[2].value == "else")
        #expect(statementTokens[3].value == "endif")
    }
    
    @Test("For loop tokenization")
    func testForLoop() throws {
        let tokens = try Lexer.tokenize("{% for item in items %}{{ item }}{% endfor %}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 2)
        #expect(statementTokens[0].value == "for item in items")
        #expect(statementTokens[1].value == "endfor")
    }
    
    @Test("For loop with else")
    func testForLoopWithElse() throws {
        let tokens = try Lexer.tokenize("{% for item in items %}{{ item }}{% else %}empty{% endfor %}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 3)
        #expect(statementTokens[0].value == "for item in items")
        #expect(statementTokens[1].value == "else")
        #expect(statementTokens[2].value == "endfor")
    }
    
    @Test("Set statement tokenization")
    func testSetStatement() throws {
        let tokens = try Lexer.tokenize("{% set variable = value %}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 1)
        #expect(statementTokens[0].value == "set variable = value")
    }
    
    @Test("Macro definition tokenization")
    func testMacroDefinition() throws {
        let tokens = try Lexer.tokenize("{% macro name(arg1, arg2) %}body{% endmacro %}")
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        #expect(statementTokens.count == 2)
        #expect(statementTokens[0].value == "macro name(arg1, arg2)")
        #expect(statementTokens[1].value == "endmacro")
    }
    
    // MARK: - Complex Templates
    
    @Test("Nested structures tokenization")
    func testNestedStructures() throws {
        let template = """
        {% for message in messages %}
            {% if message.role == 'user' %}
                User: {{ message.content }}
            {% elif message.role == 'assistant' %}
                Assistant: {{ message.content }}
            {% endif %}
        {% endfor %}
        """
        
        let tokens = try Lexer.tokenize(template)
        
        let statementTokens = tokens.filter { $0.kind == .statement }
        let expressionTokens = tokens.filter { $0.kind == .expression }
        let textTokens = tokens.filter { $0.kind == .text }
        
        #expect(statementTokens.count > 0)
        #expect(expressionTokens.count > 0)
        #expect(textTokens.count > 0)
    }
    
    // MARK: - Error Cases
    
    @Test("Unclosed expression error")
    func testUnclosedExpressionError() throws {
        #expect(throws: JinjaError.self) {
            _ = try Lexer.tokenize("{{ unclosed")
        }
    }
    
    @Test("Unclosed statement error")
    func testUnclosedStatementError() throws {
        #expect(throws: JinjaError.self) {
            _ = try Lexer.tokenize("{% unclosed")
        }
    }
    
    @Test("Unclosed string literal error")
    func testUnclosedStringError() throws {
        #expect(throws: JinjaError.self) {
            _ = try Lexer.tokenize("{{ \"unclosed string")
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty template")
    func testEmptyTemplate() throws {
        let tokens = try Lexer.tokenize("")
        #expect(tokens.count > 0) // Should at least have EOF token
    }
    
    @Test("Whitespace only template")
    func testWhitespaceOnlyTemplate() throws {
        let tokens = try Lexer.tokenize("   \n\t  \n   ")
        
        let textTokens = tokens.filter { $0.kind == .text }
        #expect(textTokens.count == 1)
    }
    
    @Test("Adjacent expressions")
    func testAdjacentExpressions() throws {
        let tokens = try Lexer.tokenize("{{ a }}{{ b }}")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        #expect(expressionTokens.count == 2)
        #expect(expressionTokens[0].value == "a")
        #expect(expressionTokens[1].value == "b")
    }
    
    @Test("Mixed delimiters")
    func testMixedDelimiters() throws {
        let tokens = try Lexer.tokenize("{{ expr }}{% stmt %}text")
        
        let expressionTokens = tokens.filter { $0.kind == .expression }
        let statementTokens = tokens.filter { $0.kind == .statement }
        let textTokens = tokens.filter { $0.kind == .text }
        
        #expect(expressionTokens.count == 1)
        #expect(statementTokens.count == 1)
        #expect(textTokens.count == 1)
    }
}

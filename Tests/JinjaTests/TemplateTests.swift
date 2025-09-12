import Testing

@testable import Jinja

@Suite("Template Tests")
struct TemplateTests {

    @Test("No template")
    func noTemplate() throws {
        let string = #"Hello, world!"#
        let context: Context = [:]

        // Check result of lexer
        let tokens = try Lexer.tokenize(string)
        #expect(
            tokens == [
                Token(kind: .text, value: "Hello, world!", position: 0),
                Token(kind: .eof, value: "", position: 13),
            ]
        )

        // Check result of parser
        let nodes = try Parser.parse(tokens)
        #expect(
            nodes == [
                .text("Hello, world!")
            ]
        )

        // Check result of template initialized with string
        let rendered = try Template(string).render(context)
        #expect(rendered == "Hello, world!")

        // Check result of template initialized with nodes
        #expect(rendered == (try Template(nodes: nodes).render(context)))
    }

    @Test("Text nodes")
    func textNodes() throws {
        let string = #"0{{ 'A' }}1{{ 'B' }}{{ 'C' }}2{{ 'D' }}3"#
        let context: Context = [:]

        // Check result of lexer
        let tokens = try Lexer.tokenize(string)
        #expect(
            tokens == [
                Token(kind: .text, value: "0", position: 0),
                Token(kind: .expression, value: "'A'", position: 1),
                Token(kind: .text, value: "1", position: 10),
                Token(kind: .expression, value: "'B'", position: 11),
                Token(kind: .expression, value: "'C'", position: 20),
                Token(kind: .text, value: "2", position: 29),
                Token(kind: .expression, value: "'D'", position: 30),
                Token(kind: .text, value: "3", position: 39),
                Token(kind: .eof, value: "", position: 40),
            ]
        )

        // Check result of parser
        let nodes = try Parser.parse(tokens)
        #expect(
            nodes == [
                .text("0"),
                .expression(.string("A")),
                .text("1"),
                .expression(.string("B")),
                .expression(.string("C")),
                .text("2"),
                .expression(.string("D")),
                .text("3"),
            ]
        )

        // Check result of template initialized with string
        let rendered = try Template(string).render(context)
        #expect(rendered == "0A1BC2D3")

        // Check result of template initialized with nodes
        #expect(rendered == (try Template(nodes: nodes).render(context)))
    }

    @Test("Boolean literals")
    func booleanLiterals() throws {
        let string = #"|{{ true }}|{{ false }}|{{ True }}|{{ False }}|"#
        let context: Context = [:]

        // Check result of lexer
        let tokens = try Lexer.tokenize(string)
        #expect(
            tokens == [
                Token(kind: .text, value: "|", position: 0),
                Token(kind: .expression, value: "true", position: 1),
                Token(kind: .text, value: "|", position: 11),
                Token(kind: .expression, value: "false", position: 12),
                Token(kind: .text, value: "|", position: 23),
                Token(kind: .expression, value: "True", position: 24),
                Token(kind: .text, value: "|", position: 34),
                Token(kind: .expression, value: "False", position: 35),
                Token(kind: .text, value: "|", position: 46),
                Token(kind: .eof, value: "", position: 47),
            ]
        )

        // Check result of parser
        let nodes = try Parser.parse(tokens)
        #expect(
            nodes == [
                .text("|"),
                .expression(.boolean(true)),
                .text("|"),
                .expression(.boolean(false)),
                .text("|"),
                .expression(.identifier("True")),
                .text("|"),
                .expression(.identifier("False")),
                .text("|"),
            ]
        )

        // Check result of template initialized with string
        let rendered = try Template(string).render(context)
        #expect(rendered == "|true|false|true|false|")

        // Check result of template initialized with nodes
        #expect(rendered == (try Template(nodes: nodes).render(context)))
    }

    @Test("Logical AND operator")
    func logicalAnd() throws {
        let string =
            #"{{ true and true }}{{ true and false }}{{ false and true }}{{ false and false }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "truefalsefalsefalse")
    }

    @Test("Logical OR operator")
    func logicalOr() throws {
        let string =
            #"{{ true or true }}{{ true or false }}{{ false or true }}{{ false or false }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "truetruetruefalse")
    }

    @Test("Logical NOT operator")
    func logicalNot() throws {
        let string = #"{{ not true }}{{ not false }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "falsetrue")
    }

    @Test("Logical NOT NOT operator")
    func logicalNotNot() throws {
        let string = #"{{ not not true }}{{ not not false }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "truefalse")
    }

    @Test("Logical AND OR combination")
    func logicalAndOr() throws {
        let string =
            #"{{ true and true or false }}{{ true and false or true }}{{ false and true or true }}{{ false and false or true }}{{ false and false or false }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "truetruetruetruefalse")
    }

    @Test("Logical AND NOT combination")
    func logicalAndNot() throws {
        let string =
            #"{{ true and not true }}{{ true and not false }}{{ false and not true }}{{ false and not false }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "falsetruefalsefalse")
    }

    @Test("Logical OR NOT combination")
    func logicalOrNot() throws {
        let string =
            #"{{ true or not true }}{{ true or not false }}{{ false or not true }}{{ false or not false }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "truetruefalsetrue")
    }

    @Test("Logical combined with comparison")
    func logicalCombined() throws {
        let string = #"{{ 1 == 2 and 2 == 2 }}{{ 1 == 2 or 2 == 2}}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "falsetrue")
    }

    @Test("If statement only")
    func ifOnly() throws {
        let string = #"{% if 1 == 1 %}{{ 'A' }}{% endif %}{{ 'B' }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "AB")
    }

    @Test("If else statement")
    func ifElseOnly() throws {
        let string = #"{% if 1 == 2 %}{{ 'A' }}{% else %}{{ 'B' }}{% endif %}{{ 'C' }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "BC")
    }

    @Test("If elif else statement")
    func ifElifElse() throws {
        let string =
            #"{% if 1 == 2 %}{{ 'A' }}{{ 'B' }}{{ 'C' }}{% elif 1 == 2 %}{{ 'D' }}{% elif 1 == 3 %}{{ 'E' }}{{ 'F' }}{% else %}{{ 'G' }}{{ 'H' }}{{ 'I' }}{% endif %}{{ 'J' }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "GHIJ")
    }

    @Test("Nested statements")
    func nestedStatements() throws {
        let string =
            #"{% set a = 0 %}{% set b = 0 %}{% set c = 0 %}{% set d = 0 %}{% if 1 == 1 %}{% set a = 2 %}{% set b = 3 %}{% elif 1 == 2 %}{% set c = 4 %}{% else %}{% set d = 5 %}{% endif %}{{ a }}{{ b }}{{ c }}{{ d }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "2300")
    }

    @Test("For loop")
    func forLoop() throws {
        let string = #"{% for message in messages %}{{ message['content'] }}{% endfor %}"#
        let context: Context = [
            "messages": [
                ["role": "user", "content": "A"],
                ["role": "assistant", "content": "B"],
                ["role": "user", "content": "C"],
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "ABC")
    }

    @Test("For loop unpacking")
    func forLoopUnpacking() throws {
        let string = #"|{% for x, y in [ [1, 2], [3, 4] ] %}|{{ x + ' ' + y }}|{% endfor %}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "||1 2||3 4||")
    }

    @Test("For loop with else")
    func forLoopDefault() throws {
        let string = #"{% for x in [] %}{{ 'A' }}{% else %}{{'B'}}{% endfor %}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "B")
    }

    @Test("For loop with select")
    func forLoopSelect() throws {
        let string = #"{% for x in [1, 2, 3, 4] if x > 2 %}{{ x }}{% endfor %}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "34")
    }

    @Test("For loop with selectattr")
    func forLoopSelect2() throws {
        let string =
            #"{% for x in arr | selectattr('value', 'equalto', 'a') %}{{ x['value'] }}{% endfor %}"#
        let context: Context = [
            "arr": [
                ["value": "a"],
                ["value": "b"],
                ["value": "c"],
                ["value": "a"],
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "aa")
    }

    @Test("For loop with break")
    func forLoopBreak() throws {
        let string =
            #"{% for x in [1, 2, 3, 4] %}{% if x == 3 %}{% break %}{% endif %}{{ x }}{% endfor %}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "12")
    }

    @Test("For loop with continue")
    func forLoopContinue() throws {
        let string =
            #"{% for x in [1, 2, 3, 4] %}{% if x == 3 %}{% continue %}{% endif %}{{ x }}{% endfor %}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "124")
    }

    @Test("For loop with objects")
    func forLoopObjects() throws {
        let string = #"{% for x in obj %}{{ x + ':' + obj[x] + ';' }}{% endfor %}"#
        let context: Context = [
            "obj": [
                "a": 1,
                "b": 2,
                "c": 3,
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "a:1;b:2;c:3;")
    }

    @Test("Variable assignment")
    func variables() throws {
        let string = #"{% set x = 'Hello' %}{% set y = 'World' %}{{ x + ' ' + y }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "Hello World")
    }

    @Test("Variable assignment with method call")
    func variables2() throws {
        let string = #"{% set x = 'Hello'.split('el')[-1] %}{{ x }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "lo")
    }

    @Test("Variable block assignment")
    func variablesBlock() throws {
        let string = #"{% set x %}Hello!\nMultiline/block set!\n{% endset %}{{ x }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "Hello!\nMultiline/block set!\n")
    }

    @Test("Variable unpacking")
    func variablesUnpacking() throws {
        let string =
            #"|{% set x, y = 1, 2 %}{{ x }}{{ y }}|{% set (x, y) = [1, 2] %}{{ x }}{{ y }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|12|12|")
    }

    @Test("Numbers and arithmetic")
    func numbers() throws {
        let string = #"|{{ 5 }}|{{ -5 }}|{{ add(3, -1) }}|{{ (3 - 1) + (a - 5) - (a + 5)}}|"#
        let context: Context = [
            "a": 0,
            "add": Value.function { (args: [Value]) -> Value in
                guard args.count == 2,
                    case let .integer(x) = args[0],
                    case let .integer(y) = args[1]
                else {
                    throw JinjaError.runtime("Invalid arguments for add function")
                }
                return .integer(x + y)
            },
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|5|-5|2|-8|")
    }

    @Test("Binary expressions")
    func binopExpr() throws {
        let string =
            #"{{ 1 % 2 }}{{ 1 < 2 }}{{ 1 > 2 }}{{ 1 >= 2 }}{{ 2 <= 2 }}{{ 2 == 2 }}{{ 2 != 3 }}{{ 2 + 3 }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "1truefalsefalsetruetruetrue5")
    }

    @Test("Binary expressions with concatenation")
    func binopExpr1() throws {
        let string = #"{{ 1 ~ "+" ~ 2 ~ "=" ~ 3 ~ " is " ~ true }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "1+2=3 is true")
    }

    @Test("String literals")
    func strings() throws {
        let string = #"{{ 'Bye' }}{{ bos_token + '[INST] ' }}"#
        let context: Context = [
            "bos_token": "<s>"
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "Bye<s>[INST] ")
    }

    @Test("String literals with quotes")
    func strings1() throws {
        let string =
            #"|{{ "test" }}|{{ "a" + 'b' + "c" }}|{{ '"' + "'" }}|{{ '\\'' }}|{{ "\\"" }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|test|abc|\"'|'|\"|")
    }

    @Test("String length")
    func strings2() throws {
        let string = #"|{{ "" | length }}|{{ "a" | length }}|{{ '' | length }}|{{ 'a' | length }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|0|1|0|1|")
    }

    @Test("String literals with template syntax")
    func strings3() throws {
        let string = #"|{{ '{{ "hi" }}' }}|{{ '{% if true %}{% endif %}' }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|{{ \"hi\" }}|{% if true %}{% endif %}|")
    }

    @Test("String concatenation")
    func strings4() throws {
        let string = #"{{ 'a' + 'b' 'c' }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "abc")
    }

    @Test("Function calls")
    func functions() throws {
        let string = #"{{ func() }}{{ func(apple) }}{{ func(x, 'test', 2, false) }}"#
        let context: Context = [
            "x": 10,
            "apple": "apple",
            "func": Value.function { (args: [Value]) -> Value in
                return .integer(args.count)
            },
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "014")
    }

    @Test("Object properties")
    func properties() throws {
        let string = #"{{ obj.x + obj.y }}{{ obj['x'] + obj.y }}"#
        let context: Context = [
            "obj": [
                "x": 10,
                "y": 20,
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "3030")
    }

    @Test("Object methods")
    func objMethods() throws {
        let string = #"{{ obj.x(x, y) }}{{ ' ' + obj.x() + ' ' }}{{ obj.z[x](x, y) }}"#
        let context: Context = [
            "x": "A",
            "y": "B",
            "obj": [
                "x": Value.function { (args: [Value]) -> Value in
                    let strings = args.compactMap { value in
                        if case .string(let str) = value { return str }
                        return nil
                    }
                    return .string(strings.joined())
                },
                "z": [
                    "A": Value.function { (args: [Value]) -> Value in
                        let strings = args.compactMap { value in
                            if case .string(let str) = value { return str }
                            return nil
                        }
                        return .string(strings.joined(separator: "_"))
                    }
                ],
            ],
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "AB  A_B")
    }

    @Test("String methods")
    func stringMethods() throws {
        let string =
            #"{{ '  A  '.strip() }}{% set x = '  B  ' %}{{ x.strip() }}{% set y = ' aBcD ' %}{{ y.upper() }}{{ y.lower() }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "AB ABCD  abcd ")
    }

    @Test("String methods title")
    func stringMethods2() throws {
        let string = #"{{ 'test test'.title() }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "Test Test")
    }

    @Test("String rstrip")
    func rstrip() throws {
        let string = #"{{ "   test it  ".rstrip() }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "   test it")
    }

    @Test("String lstrip")
    func lstrip() throws {
        let string = #"{{ "   test it  ".lstrip() }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "test it  ")
    }

    @Test("String split")
    func split() throws {
        let string = #"|{{ "   test it  ".split() | join("|") }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|test|it|")
    }

    @Test("String split with separator")
    func split2() throws {
        let string = #"|{{ "   test it  ".split(" ") | join("|") }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "||||test|it|||")
    }

    @Test("String split with limit")
    func split3() throws {
        let string = #"|{{ "   test it  ".split(" ", 4) | join("|") }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "||||test|it  |")
    }

    @Test("String replace")
    func replace() throws {
        let string =
            #"|{{ "test test".replace("test", "TEST") }}|{{ "test test".replace("test", "TEST", 1) }}|{{ "test test".replace("", "_", 2) }}|{{ "abcabc".replace("a", "x", count=1) }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|TEST TEST|TEST test|_t_est test|xbcabc|")
    }

    @Test("String slicing")
    func stringSlicing() throws {
        let string =
            #"|{{ x[0] }}|{{ x[:] }}|{{ x[:3] }}|{{ x[1:4] }}|{{ x[1:-1] }}|{{ x[1::2] }}|{{ x[5::-1] }}|"#
        let context: Context = [
            "x": "0123456789"
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|0|0123456789|012|123|12345678|13579|543210|")
    }

    @Test("Array slicing")
    func arraySlicing() throws {
        let string =
            #"|{{ strings[0] }}|{% for s in strings[:] %}{{ s }}{% endfor %}|{% for s in strings[:3] %}{{ s }}{% endfor %}|{% for s in strings[1:4] %}{{ s }}{% endfor %}|{% for s in strings[1:-1] %}{{ s }}{% endfor %}|{% for s in strings[1::2] %}{{ s }}{% endfor %}|{% for s in strings[5::-1] %}{{ s }}{% endfor %}|"#
        let context: Context = [
            "strings": ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|0|0123456789|012|123|12345678|13579|543210|")
    }

    @Test("Membership operators")
    func membership() throws {
        let string =
            #"|{{ 0 in arr }}|{{ 1 in arr }}|{{ true in arr }}|{{ false in arr }}|{{ 'a' in arr }}|{{ 'b' in arr }}|"#
        let context: Context = [
            "arr": [0, true, "a"]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|true|false|true|false|true|false|")
    }

    @Test("Membership negation with not")
    func membershipNegation1() throws {
        let string =
            #"|{{ not 0 in arr }}|{{ not 1 in arr }}|{{ not true in arr }}|{{ not false in arr }}|{{ not 'a' in arr }}|{{ not 'b' in arr }}|"#
        let context: Context = [
            "arr": [0, true, "a"]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|false|true|false|true|false|true|")
    }

    @Test("Membership negation with not in")
    func membershipNegation2() throws {
        let string =
            #"|{{ 0 not in arr }}|{{ 1 not in arr }}|{{ true not in arr }}|{{ false not in arr }}|{{ 'a' not in arr }}|{{ 'b' not in arr }}|"#
        let context: Context = [
            "arr": [0, true, "a"]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|false|true|false|true|false|true|")
    }

    @Test("Membership with undefined")
    func membershipUndefined() throws {
        let string =
            #"|{{ x is defined }}|{{ y is defined }}|{{ x in y }}|{{ y in x }}|{{ 1 in y }}|{{ 1 in x }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|false|false|false|false|false|false|")
    }

    @Test("Escaped characters")
    func escapedChars() throws {
        let string =
            #"{{ '\\n' }}{{ '\\t' }}{{ '\\'' }}{{ '\\"' }}{{ '\\\\' }}{{ '|\\n|\\t|\\'|\\"|\\\\|' }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "\n\t'\"\\|\n|\t|'|\"|\\|")
    }

    @Test("Substring inclusion")
    func substringInclusion() throws {
        let string =
            #"|{{ '' in 'abc' }}|{{ 'a' in 'abc' }}|{{ 'd' in 'abc' }}|{{ 'ab' in 'abc' }}|{{ 'ac' in 'abc' }}|{{ 'abc' in 'abc' }}|{{ 'abcd' in 'abc' }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|true|true|false|true|false|true|false|")
    }

    @Test("Filter operator")
    func filterOperator() throws {
        let string =
            #"{{ arr | length }}{{ 1 + arr | length }}{{ 2 + arr | sort | length }}{{ (arr | sort)[0] }}"#
        let context: Context = [
            "arr": [3, 2, 1]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "3451")
    }

    @Test("Filter operator string transformations")
    func filterOperator2() throws {
        let string =
            #"|{{ 'abc' | length }}|{{ 'aBcD' | upper }}|{{ 'aBcD' | lower }}|{{ 'test test' | capitalize}}|{{ 'test test' | title }}|{{ ' a b ' | trim }}|{{ '  A  B  ' | trim | lower | length }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|3|ABCD|abcd|Test test|Test Test|a b|4|")
    }

    @Test("Filter operator abs")
    func filterOperator3() throws {
        let string = #"|{{ -1 | abs }}|{{ 1 | abs }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|1|1|")
    }

    @Test("Filter operator selectattr")
    func filterOperator4() throws {
        let string = #"{{ items | selectattr('key') | length }}"#
        let context: Context = [
            "items": [
                ["key": "a"],
                ["key": 0],
                ["key": 1],
                [:],
                ["key": false],
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "2")
    }

    @Test("Filter operator selectattr with equalto")
    func filterOperator5() throws {
        let string = #"{{ messages | selectattr('role', 'equalto', 'system') | length }}"#
        let context: Context = [
            "messages": [
                ["role": "system"],
                ["role": "user"],
                ["role": "assistant"],
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "1")
    }

    @Test("Filter operator tojson")
    func filterOperator7() throws {
        let string =
            #"|{{ obj | tojson }}|{{ "test" | tojson }}|{{ 1 | tojson }}|{{ true | tojson }}|{{ null | tojson }}|{{ [1,2,3] | tojson }}|"#
        let context: Context = [
            "obj": [
                "string": "world",
                "number": 5,
                "boolean": true,
                "null": nil,
                "array": [1, 2, 3],
                "object": ["key": "value"],
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered.contains("\"string\": \"world\""))
        #expect(rendered.contains("\"test\""))
        #expect(rendered.contains("1"))
        #expect(rendered.contains("true"))
        #expect(rendered.contains("null"))
        #expect(rendered.contains("[1, 2, 3]"))
    }

    @Test("Filter statements")
    func filterStatements() throws {
        let string = #"{% filter upper %}text{% endfilter %}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "TEXT")
    }

    @Test("Boolean operations with numbers")
    func booleanNumerical() throws {
        let string =
            #"|{{ 1 and 2 }}|{{ 1 and 0 }}|{{ 0 and 1 }}|{{ 0 and 0 }}|{{ 1 or 2 }}|{{ 1 or 0 }}|{{ 0 or 1 }}|{{ 0 or 0 }}|{{ not 1 }}|{{ not 0 }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|2|0|0|0|1|1|1|0|false|true|")
    }

    @Test("Boolean operations with strings")
    func booleanStrings() throws {
        let string =
            #"|{{ 'a' and 'b' }}|{{ 'a' and '' }}|{{ '' and 'a' }}|{{ '' and '' }}|{{ 'a' or 'b' }}|{{ 'a' or '' }}|{{ '' or 'a' }}|{{ '' or '' }}|{{ not 'a' }}|{{ not '' }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|b||||a|a|a||false|true|")
    }

    @Test("Boolean operations mixed")
    func booleanMixed() throws {
        let string =
            #"|{{ true and 1 }}|{{ true and 0 }}|{{ false and 1 }}|{{ false and 0 }}|{{ true or 1 }}|{{ true or 0 }}|{{ false or 1 }}|{{ false or 0 }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|1|0|false|false|true|true|1|0|")
    }

    @Test("Boolean operations mixed with strings")
    func booleanMixed2() throws {
        let string =
            #"|{{ true and '' }}|{{ true and 'a' }}|{{ false or '' }}|{{ false or 'a' }}|{{ '' and true }}|{{ 'a' and true }}|{{ '' or false }}|{{ 'a' or false }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "||a||a||true|false|a|")
    }

    @Test("Boolean operations in if statements")
    func booleanMixedIf() throws {
        let string =
            #"{% if '' %}{{ 'A' }}{% endif %}{% if 'a' %}{{ 'B' }}{% endif %}{% if true and '' %}{{ 'C' }}{% endif %}{% if true and 'a' %}{{ 'D' }}{% endif %}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "BD")
    }

    @Test("Ternary operator")
    func ternaryOperator() throws {
        let string =
            #"|{{ 'a' if true else 'b' }}|{{ 'a' if false else 'b' }}|{{ 'a' if 1 + 1 == 2 else 'b' }}|{{ 'a' if 1 + 1 == 3 or 1 * 2 == 3 else 'b' }}|"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|a|b|a|b|")
    }

    @Test("Ternary operator with length")
    func ternaryOperator1() throws {
        let string = #"{{ (x if true else []) | length }}"#
        let context: Context = [
            "x": [[:], [:], [:]]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "3")
    }

    @Test("Ternary set")
    func ternarySet() throws {
        let string = #"{% set x = 1 if True else 2 %}{{ x }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "1")
    }

    @Test("Ternary consecutive")
    func ternaryConsecutive() throws {
        let string = #"{% set x = 1 if False else 2 if False else 3 %}{{ x }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "3")
    }

    @Test("Ternary shortcut")
    func ternaryShortcut() throws {
        let string = #"{{ 'foo' if false }}{{ 'bar' if true }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "bar")
    }

    @Test("Array literals")
    func arrayLiterals() throws {
        let string = #"{{ [1, true, 'hello', [1, 2, 3, 4], var] | length }}"#
        let context: Context = [
            "var": true
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "5")
    }

    @Test("Tuple literals")
    func tupleLiterals() throws {
        let string = #"{{ (1, (1, 2)) | length }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "2")
    }

    @Test("Object literals")
    func objectLiterals() throws {
        let string =
            #"{{ { 'key': 'value', key: 'value2', "key3": [1, {'foo': 'bar'} ] }['key'] }}"#
        let context: Context = [
            "key": "key2"
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "value")
    }

    @Test("Object literals nested")
    func objectLiterals1() throws {
        let string = #"{{{'key': {'key': 'value'}}['key']['key']}}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "value")
    }

    @Test("Array operators")
    func arrayOperators() throws {
        let string = #"{{ ([1, 2, 3] + [4, 5, 6]) | length }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "6")
    }

    @Test("Object operators")
    func objectOperators() throws {
        let string =
            #"|{{ 'known' in obj }}|{{ 'known' not in obj }}|{{ 'unknown' in obj }}|{{ 'unknown' not in obj }}|"#
        let context: Context = [
            "obj": [
                "known": true
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|true|false|false|true|")
    }

    @Test("Object get method")
    func objectOperators1() throws {
        let string =
            #"|{{ obj.get('known') }}|{{ obj.get('unknown') is none }}|{{ obj.get('unknown') is defined }}|"#
        let context: Context = [
            "obj": [
                "known": true
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "|true|true|true|")
    }

    @Test("Object items method")
    func objectOperators2() throws {
        let string = #"|{% for x, y in obj.items() %}|{{ x + ' ' + y }}|{% endfor %}|"#
        let context: Context = [
            "obj": [
                "a": 1,
                "b": 2,
                "c": 3,
            ]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "||a 1||b 2||c 3||")
    }

    @Test("Scope with namespace")
    func scope() throws {
        let string =
            #"{% set ns = namespace(found=false) %}{% for num in nums %}{% if num == 1 %}{{ 'found=' }}{% set ns.found = true %}{% endif %}{% endfor %}{{ ns.found }}"#
        let context: Context = [
            "nums": [1, 2, 3]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "found=true")
    }

    @Test("Scope without namespace")
    func scope1() throws {
        let string =
            #"{% set found = false %}{% for num in nums %}{% if num == 1 %}{{ 'found=' }}{% set found = true %}{% endif %}{% endfor %}{{ found }}"#
        let context: Context = [
            "nums": [1, 2, 3]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "found=false")
    }

    @Test("Undefined variables")
    func undefinedVariables() throws {
        let string = #"{{ undefined_variable }}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "")
    }

    @Test("Undefined access")
    func undefinedAccess() throws {
        let string = #"{{ object.undefined_attribute }}"#
        let context: Context = [
            "object": [:]
        ]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "")
    }

    @Test("Null variable")
    func nullVariable() throws {
        let string =
            #"{% if not null_val is defined %}{% set null_val = none %}{% endif %}{% if null_val is not none %}{{ 'fail' }}{% else %}{{ 'pass' }}{% endif %}"#
        let context: Context = [:]

        // Check result of template
        let rendered = try Template(string).render(context)
        #expect(rendered == "pass")
    }
}

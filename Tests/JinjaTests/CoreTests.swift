import Testing
import Foundation
@testable import Jinja

struct CoreTests {

    // MARK: - Value Tests

    @Test("Value isTruthy behavior")
    func testValueTruthy() {
        #expect(Value.null.isTruthy == false)
        #expect(Value.undefined.isTruthy == false)
        #expect(Value.boolean(true).isTruthy == true)
        #expect(Value.boolean(false).isTruthy == false)
        #expect(Value.string("").isTruthy == false)
        #expect(Value.string("hello").isTruthy == true)
        #expect(Value.number(0.0).isTruthy == false)
        #expect(Value.number(1.0).isTruthy == true)
        #expect(Value.integer(0).isTruthy == false)
        #expect(Value.integer(1).isTruthy == true)
        #expect(Value.array([]).isTruthy == false)
        #expect(Value.array([Value.integer(1)]).isTruthy == true)
        #expect(Value.object([:]).isTruthy == false)
        #expect(Value.object(["key": Value.string("value")]).isTruthy == true)
    }

    @Test("Value toString conversion")
    func testValuedescription() {
        #expect(Value.string("test").description == "test")
        #expect(Value.integer(42).description == "42")
        #expect(Value.number(3.14).description == "3.14")
        #expect(Value.boolean(true).description == "true")
        #expect(Value.boolean(false).description == "false")
        #expect(Value.null.description == "")
        #expect(Value.undefined.description == "")
        #expect(Value.array([Value.integer(1), Value.integer(2)]).description == "[1, 2]")
        #expect(Value.object(["a": Value.integer(1)]).description == "{a: 1}")
    }

    @Test("Value from Any conversion")
    func testValueFromAny() throws {
        #expect(try Value(any: nil) == Value.null)
        #expect(try Value(any: "hello") == Value.string("hello"))
        #expect(try Value(any: 42) == Value.integer(42))
        #expect(try Value(any: 3.14) == Value.number(3.14))
        #expect(try Value(any: Float(2.5)) == Value.number(2.5))
        #expect(try Value(any: true) == Value.boolean(true))

        let arrayValue = try Value(any: [1, "test", nil])
        if case let .array(values) = arrayValue {
            #expect(values.count == 3)
            #expect(values[0] == Value.integer(1))
            #expect(values[1] == Value.string("test"))
            #expect(values[2] == Value.null)
        } else {
            Issue.record("Expected array value")
        }

        let dictValue = try Value(any: ["key": "value", "num": 42])
        if case let .object(dict) = dictValue {
            #expect(dict["key"] == Value.string("value"))
            #expect(dict["num"] == Value.integer(42))
        } else {
            Issue.record("Expected object value")
        }

        #expect(throws: JinjaError.self) {
            _ = try Value(any: NSObject())
        }
    }

    @Test("Value literal conformances")
    func testValueLiterals() {
        let stringValue: Value = "test"
        #expect(stringValue == Value.string("test"))

        let intValue: Value = 42
        #expect(intValue == Value.integer(42))

        let doubleValue: Value = 3.14
        #expect(doubleValue == Value.number(3.14))

        let boolValue: Value = true
        #expect(boolValue == Value.boolean(true))

        let arrayValue: Value = [1, 2, 3]
        if case let .array(values) = arrayValue {
            #expect(values.count == 3)
            #expect(values[0] == Value.integer(1))
            #expect(values[1] == Value.integer(2))
            #expect(values[2] == Value.integer(3))
        } else {
            Issue.record("Expected array value")
        }

        let dictValue: Value = ["a": 1, "b": 2]
        if case let .object(dict) = dictValue {
            #expect(dict["a"] == Value.integer(1))
            #expect(dict["b"] == Value.integer(2))
        } else {
            Issue.record("Expected object value")
        }

        let nilValue: Value = nil
        #expect(nilValue == Value.null)
    }

    // MARK: - OrderedDictionary Tests

    @Test("OrderedDictionary basic operations")
    func testOrderedDictionary() {
        var dict = OrderedDictionary<String, Int>()

        #expect(dict.isEmpty == true)
        #expect(dict.count == 0)

        dict["first"] = 1
        dict["second"] = 2
        dict["third"] = 3

        #expect(dict.count == 3)
        #expect(dict["first"] == 1)
        #expect(dict["second"] == 2)
        #expect(dict["third"] == 3)

        #expect(dict.keys == ["first", "second", "third"])
        #expect(Array(dict.values) == [1, 2, 3])

        let removed = dict.removeValue(forKey: "second")
        #expect(removed == 2)
        #expect(dict.count == 2)
        #expect(dict.keys == ["first", "third"])
    }

    @Test("OrderedDictionary literal initialization")
    func testOrderedDictionaryLiteral() {
        let dict: OrderedDictionary<String, Int> = ["a": 1, "b": 2, "c": 3]

        #expect(dict.count == 3)
        #expect(dict.keys == ["a", "b", "c"])
        #expect(Array(dict.values) == [1, 2, 3])
    }

    @Test("OrderedDictionary sequence conformance")
    func testOrderedDictionarySequence() {
        let dict: OrderedDictionary<String, Int> = ["x": 10, "y": 20, "z": 30]

        var keys: [String] = []
        var values: [Int] = []

        for (key, value) in dict {
            keys.append(key)
            values.append(value)
        }

        #expect(keys == ["x", "y", "z"])
        #expect(values == [10, 20, 30])

        let mapped = dict.map { "\($0.key)=\($0.value)" }
        #expect(mapped == ["x=10", "y=20", "z=30"])
    }

    // MARK: - AST Node Tests

    @Test("Expression node creation")
    func testExpressionNodes() {
        let stringExpr = Expression.string("hello")
        let intExpr = Expression.integer(42)
        let boolExpr = Expression.boolean(true)
        let nullExpr = Expression.null

        // Test that expressions can be created without throwing

        let _ = Expression.array([stringExpr, intExpr])
        let _ = Expression.tuple([boolExpr, nullExpr])

        let _ = Expression.object(["key": stringExpr, "num": intExpr])

        let _ = Expression.identifier("variable")
        let _ = Expression.binary(.add, intExpr, Expression.integer(8))
        let _ = Expression.unary(.not, boolExpr)

        // All expressions created successfully
        #expect(Bool(true))
    }

    @Test("Statement node creation")
    func testStatementNodes() {
        let _ = Statement.set("x", Expression.integer(42))

        let _ = Statement.if(
            Expression.boolean(true),
            [Node.text("if body")],
            [Node.text("else body")]
        )

        let _ = Statement.for(
            .single("item"),
            Expression.identifier("items"),
            [Node.text("loop body")],
            [Node.text("else body")],
            test: Expression.boolean(true)
        )

        let _ = Statement.macro(
            "test_macro",
            ["arg1", "arg2"],
            [Node.text("macro body")]
        )

        let _ = Statement.program([
            Node.text("Hello"),
            Node.expression(Expression.string("world")),
        ])

        // All statements created successfully
        #expect(Bool(true))
    }

    @Test("Complex expression trees")
    func testComplexExpressions() {
        // Test nested binary operations: (a + b) * (c - d)
        let _ = Expression.binary(
            .multiply,
            Expression.binary(.add, Expression.identifier("a"), Expression.identifier("b")),
            Expression.binary(.subtract, Expression.identifier("c"), Expression.identifier("d"))
        )

        // Test function call with args and kwargs
        let _ = Expression.call(
            Expression.identifier("func"),
            [Expression.string("arg1"), Expression.integer(2)],
            ["key": Expression.boolean(true)]
        )

        // Test member access
        let _ = Expression.member(
            Expression.identifier("obj"),
            Expression.string("property"),
            computed: false
        )

        // Test slice expression
        let _ = Expression.slice(
            Expression.identifier("array"),
            start: Expression.integer(1),
            stop: Expression.integer(10),
            step: Expression.integer(2)
        )

        // Test filter expression
        let _ = Expression.filter(
            Expression.identifier("value"),
            "upper",
            [],
            [:]
        )

        // Test conditional expression
        let _ = Expression.ternary(
            Expression.boolean(true),
            test: Expression.identifier("condition"),
            alternate: Expression.string("fallback")
        )

        // All expressions should be created successfully
        #expect(Bool(true))
    }

    // MARK: - Binary and Unary Operations

    @Test("Binary operations enum")
    func testBinaryOps() {
        #expect(BinaryOp.add.rawValue == "+")
        #expect(BinaryOp.subtract.rawValue == "-")
        #expect(BinaryOp.multiply.rawValue == "*")
        #expect(BinaryOp.divide.rawValue == "/")
        #expect(BinaryOp.modulo.rawValue == "%")
        #expect(BinaryOp.concat.rawValue == "~")
        #expect(BinaryOp.equal.rawValue == "==")
        #expect(BinaryOp.notEqual.rawValue == "!=")
        #expect(BinaryOp.less.rawValue == "<")
        #expect(BinaryOp.lessEqual.rawValue == "<=")
        #expect(BinaryOp.greater.rawValue == ">")
        #expect(BinaryOp.greaterEqual.rawValue == ">=")
        #expect(BinaryOp.and.rawValue == "and")
        #expect(BinaryOp.or.rawValue == "or")
        #expect(BinaryOp.in.rawValue == "in")
        #expect(BinaryOp.notIn.rawValue == "not in")
    }

    @Test("Unary operations enum")
    func testUnaryOps() {
        #expect(UnaryOp.not.rawValue == "not")
        #expect(UnaryOp.minus.rawValue == "-")
        #expect(UnaryOp.plus.rawValue == "+")
    }

    @Test("Loop variable patterns")
    func testLoopVars() {
        let single = LoopVar.single("item")
        let tuple = LoopVar.tuple(["key", "value"])

        if case let .single(name) = single {
            #expect(name == "item")
        } else {
            Issue.record("Expected single loop var")
        }

        if case let .tuple(names) = tuple {
            #expect(names == ["key", "value"])
        } else {
            Issue.record("Expected tuple loop var")
        }
    }

    // MARK: - Optimization Tests

    @Test("Statement optimization - constant if conditions")
    func testStatementOptimization() async throws {
        // Test constant true condition optimization
        let tokens = try Lexer.tokenize("{% if true %}Hello{% endif %}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case let .statement(stmt) = nodes[0] {
            if case let .program(body) = stmt {
                #expect(body.count == 1)
                if case let .text(content) = body[0] {
                    #expect(content == "Hello")
                } else {
                    Issue.record("Expected text node in optimized body")
                }
            } else {
                Issue.record("Expected program statement after optimization")
            }
        } else {
            Issue.record("Expected statement node")
        }

        // Test constant false condition optimization
        let tokens2 = try Lexer.tokenize("{% if false %}Hello{% else %}World{% endif %}")
        let nodes2 = try Parser.parse(tokens2)

        #expect(nodes2.count == 1)
        if case let .statement(stmt) = nodes2[0] {
            if case let .program(body) = stmt {
                #expect(body.count == 1)
                if case let .text(content) = body[0] {
                    #expect(content == "World")
                } else {
                    Issue.record("Expected text node in optimized else body")
                }
            } else {
                Issue.record("Expected program statement after optimization")
            }
        } else {
            Issue.record("Expected statement node")
        }
    }

    @Test("Expression optimization - constant folding")
    func testExpressionOptimization() async throws {
        let tokens = try Lexer.tokenize("{{ 2 + 3 }}")
        let nodes = try Parser.parse(tokens)

        #expect(nodes.count == 1)
        if case let .expression(expr) = nodes[0] {
            if case let .integer(value) = expr {
                #expect(value == 5)
            } else {
                Issue.record("Expected integer expression after constant folding")
            }
        } else {
            Issue.record("Expected expression node")
        }
    }
}

// Value is already Equatable in the main module, no need to extend here

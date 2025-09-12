import Foundation
import Testing

@testable import Jinja

struct ValueTests {
    @Test("Initialization from Any")
    func initFromAny() throws {
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

    @Test("Literal conformances")
    func literals() {
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

    @Test("CustomStringConvertible conformance")
    func description() {
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

    @Test("isTruthy behavior")
    func isTruthy() {
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
}

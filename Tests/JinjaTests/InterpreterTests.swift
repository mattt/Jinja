import Foundation
import Testing

@testable import Jinja

@Suite("Interpreter")
struct InterpreterTests {
    @Suite("Filters")
    struct FiltersTests {
        let env = Environment()

        @Test("upper filter")
        func upperFilter() throws {
            let result = try Filters.upper([.string("hello world")], kwargs: [:], env: env)
            #expect(result == .string("HELLO WORLD"))
        }

        @Test("lower filter")
        func lowerFilter() throws {
            let result = try Filters.lower([.string("HELLO WORLD")], kwargs: [:], env: env)
            #expect(result == .string("hello world"))
        }

        @Test("length filter for strings")
        func lengthFilterString() throws {
            let result = try Filters.length([.string("hello")], kwargs: [:], env: env)
            #expect(result == .int(5))
        }

        @Test("length filter for arrays")
        func lengthFilterArray() throws {
            let values = [Value.int(1), .int(2), .int(3)]
            let result = try Filters.length([.array(values)], kwargs: [:], env: env)
            #expect(result == .int(3))
        }

        @Test("join filter")
        func joinFilter() throws {
            let values = [Value.string("a"), .string("b"), .string("c")]
            let result = try Filters.join([.array(values), .string(", ")], kwargs: [:], env: env)
            #expect(result == .string("a, b, c"))
        }

        @Test("default filter with undefined")
        func defaultFilterWithUndefined() throws {
            let result = try Filters.default(
                [.undefined, .string("fallback")], kwargs: [:], env: env)
            #expect(result == .string("fallback"))
        }

        @Test("default filter with defined value")
        func defaultFilterWithDefinedValue() throws {
            let result = try Filters.default(
                [.string("actual"), .string("fallback")], kwargs: [:], env: env)
            #expect(result == .string("actual"))
        }

        @Test("first filter with array")
        func firstFilterWithArray() throws {
            let values = [Value.string("a"), .string("b"), .string("c")]
            let result = try Filters.first([.array(values)], kwargs: [:], env: env)
            #expect(result == .string("a"))
        }

        @Test("last filter with array")
        func lastFilterWithArray() throws {
            let values = [Value.string("a"), .string("b"), .string("c")]
            let result = try Filters.last([.array(values)], kwargs: [:], env: env)
            #expect(result == .string("c"))
        }

        @Test("reverse filter with array")
        func reverseFilterWithArray() throws {
            let values = [Value.int(1), .int(2), .int(3)]
            let result = try Filters.reverse([.array(values)], kwargs: [:], env: env)
            let expected = Value.array([.int(3), .int(2), .int(1)])
            #expect(result == expected)
        }

        @Test("abs filter with negative integer")
        func absFilterWithNegativeInteger() throws {
            let result = try Filters.abs([.int(-5)], kwargs: [:], env: env)
            #expect(result == .int(5))
        }

        @Test("abs filter with negative number")
        func absFilterWithNegativeNumber() throws {
            let result = try Filters.abs([.double(-3.14)], kwargs: [:], env: env)
            #expect(result == .double(3.14))
        }

        @Test("capitalize filter")
        func capitalizeFilter() throws {
            let result = try Filters.capitalize([.string("hello world")], kwargs: [:], env: env)
            #expect(result == .string("Hello world"))
        }

        @Test("trim filter")
        func trimFilter() throws {
            let result = try Filters.trim([.string("  hello world  ")], kwargs: [:], env: env)
            #expect(result == .string("hello world"))
        }

        @Test("float filter")
        func floatFilter() throws {
            let result = try Filters.float([.int(42)], kwargs: [:], env: env)
            #expect(result == .double(42.0))
        }

        @Test("int filter")
        func intFilter() throws {
            let result = try Filters.int([.double(3.14)], kwargs: [:], env: env)
            #expect(result == .int(3))
        }

        @Test("unique filter")
        func uniqueFilter() throws {
            let values = [Value.int(1), .int(2), .int(1), .int(3), .int(2)]
            let result = try Filters.unique([.array(values)], kwargs: [:], env: env)
            let expected = Value.array([.int(1), .int(2), .int(3)])
            #expect(result == expected)
        }

        @Test("dictsort filter")
        func dictsortFilter() throws {
            let dict = Value.object(["c": .int(3), "a": .int(1), "b": .int(2)])
            let result = try Filters.dictsort([dict], kwargs: [:], env: env)
            let expected = Value.array([
                .array([.string("a"), .int(1)]),
                .array([.string("b"), .int(2)]),
                .array([.string("c"), .int(3)]),
            ])
            #expect(result == expected)
        }

        @Test("dictsort filter with reverse")
        func dictsortFilterWithReverse() throws {
            let dict = Value.object(["b": .int(2), "a": .int(1)])
            let result = try Filters.dictsort(
                [dict, .boolean(false), .string("key"), .boolean(true)], kwargs: [:], env: env)
            let expected = Value.array([
                .array([.string("b"), .int(2)]),
                .array([.string("a"), .int(1)]),
            ])
            #expect(result == expected)
        }

        @Test("pprint filter")
        func pprintFilter() throws {
            let dict = Value.object(["name": .string("test"), "value": .int(42)])
            let result = try Filters.pprint([dict], kwargs: [:], env: env)
            // Just check it's a string (exact format may vary)
            if case .string(let str) = result {
                #expect(str.contains("name"))
                #expect(str.contains("test"))
                #expect(str.contains("value"))
                #expect(str.contains("42"))
            } else {
                Issue.record("Expected string result")
            }
        }

        @Test("urlize filter")
        func urlizeFilter() throws {
            let text = "Visit https://example.com for more info"
            let result = try Filters.urlize([.string(text)], kwargs: [:], env: env)
            if case .string(let str) = result {
                #expect(str.contains("<a href=\"https://example.com\">"))
                #expect(str.contains("</a>"))
            } else {
                Issue.record("Expected string result")
            }
        }

        @Test("sum filter with attribute")
        func sumFilterWithAttribute() throws {
            let items = Value.array([
                .object(["price": .double(10.5)]),
                .object(["price": .double(20.0)]),
                .object(["price": .double(15.5)]),
            ])
            let result = try Filters.sum([items, .string("price")], kwargs: [:], env: env)
            #expect(result == .double(46.0))
        }

        @Test("indent filter")
        func indentFilter() throws {
            let text = "line1\nline2\nline3"
            let result = try Filters.indent([.string(text), .int(2)], kwargs: [:], env: env)
            if case .string(let str) = result {
                // First line is NOT indented by default
                #expect(str.hasPrefix("line1"))
                #expect(str.contains("  line2"))
                #expect(str.contains("  line3"))
            } else {
                Issue.record("Expected string result")
            }
        }

        @Test("indent filter with first")
        func indentFilterWithFirst() throws {
            let text = "line1\nline2\nline3"
            let result = try Filters.indent(
                [.string(text), .int(2), .boolean(true)], kwargs: [:], env: env)
            if case .string(let str) = result {
                // All lines should be indented when first=true
                #expect(str.contains("  line1"))
                #expect(str.contains("  line2"))
                #expect(str.contains("  line3"))
            } else {
                Issue.record("Expected string result")
            }
        }
    }

    @Suite("Tests")
    struct TestsTests {
        let env = Environment()

        // MARK: - Basic Tests

        @Test("defined test with defined value")
        func definedWithDefinedValue() throws {
            let result = try Tests.defined([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("defined test with undefined value")
        func definedWithUndefinedValue() throws {
            let result = try Tests.defined([.undefined], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("defined test with empty values")
        func definedWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.defined([], kwargs: [:], env: env)
            }
        }

        @Test("undefined test with undefined value")
        func undefinedWithUndefinedValue() throws {
            let result = try Tests.undefined([.undefined], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("undefined test with defined value")
        func undefinedWithDefinedValue() throws {
            let result = try Tests.undefined([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("undefined test with empty values")
        func undefinedWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.undefined([], kwargs: [:], env: env)
            }
        }

        @Test("none test with null value")
        func noneWithNullValue() throws {
            let result = try Tests.none([.null], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("none test with non-null value")
        func noneWithNonNullValue() throws {
            let result = try Tests.none([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("none test with empty values")
        func noneWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.none([], kwargs: [:], env: env)
            }
        }

        @Test("string test with string value")
        func stringWithStringValue() throws {
            let result = try Tests.string([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("string test with non-string value")
        func stringWithNonStringValue() throws {
            let result = try Tests.string([.int(42)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("string test with empty values")
        func stringWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.string([], kwargs: [:], env: env)
            }
        }

        @Test("number test with integer value")
        func numberWithIntegerValue() throws {
            let result = try Tests.number([.int(42)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("number test with float value")
        func numberWithFloatValue() throws {
            let result = try Tests.number([.double(3.14)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("number test with non-number value")
        func numberWithNonNumberValue() throws {
            let result = try Tests.number([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("number test with empty values")
        func numberWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.number([], kwargs: [:], env: env)
            }
        }

        @Test("boolean test with true value")
        func booleanWithTrueValue() throws {
            let result = try Tests.boolean([.boolean(true)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("boolean test with false value")
        func booleanWithFalseValue() throws {
            let result = try Tests.boolean([.boolean(false)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("boolean test with non-boolean value")
        func booleanWithNonBooleanValue() throws {
            let result = try Tests.boolean([.string("true")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("boolean test with empty values")
        func booleanWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.boolean([], kwargs: [:], env: env)
            }
        }

        @Test("iterable test with array value")
        func iterableWithArrayValue() throws {
            let result = try Tests.iterable(
                [.array([.string("a"), .string("b")])], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("iterable test with object value")
        func iterableWithObjectValue() throws {
            let result = try Tests.iterable(
                [.object(["key": .string("value")])], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("iterable test with string value")
        func iterableWithStringValue() throws {
            let result = try Tests.iterable([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("iterable test with non-iterable value")
        func iterableWithNonIterableValue() throws {
            let result = try Tests.iterable([.int(42)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("iterable test with empty values")
        func iterableWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.iterable([], kwargs: [:], env: env)
            }
        }

        // MARK: - Numeric Tests

        @Test("even test with even integer")
        func evenWithEvenInteger() throws {
            let result = try Tests.even([.int(4)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("even test with odd integer")
        func evenWithOddInteger() throws {
            let result = try Tests.even([.int(5)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("even test with even float")
        func evenWithEvenFloat() throws {
            let result = try Tests.even([.double(4.0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("even test with odd float")
        func evenWithOddFloat() throws {
            let result = try Tests.even([.double(5.0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("even test with non-number value")
        func evenWithNonNumberValue() throws {
            let result = try Tests.even([.string("4")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("even test with zero")
        func evenWithZero() throws {
            let result = try Tests.even([.int(0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("even test with empty values")
        func evenWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.even([], kwargs: [:], env: env)
            }
        }

        @Test("odd test with odd integer")
        func oddWithOddInteger() throws {
            let result = try Tests.odd([.int(3)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("odd test with even integer")
        func oddWithEvenInteger() throws {
            let result = try Tests.odd([.int(4)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("odd test with odd float")
        func oddWithOddFloat() throws {
            let result = try Tests.odd([.double(3.0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("odd test with even float")
        func oddWithEvenFloat() throws {
            let result = try Tests.odd([.double(4.0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("odd test with non-number value")
        func oddWithNonNumberValue() throws {
            let result = try Tests.odd([.string("3")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("odd test with empty values")
        func oddWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.odd([], kwargs: [:], env: env)
            }
        }

        @Test("divisibleby test with divisible integers")
        func divisiblebyWithDivisibleIntegers() throws {
            let result = try Tests.divisibleby([.int(10), .int(2)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("divisibleby test with non-divisible integers")
        func divisiblebyWithNonDivisibleIntegers() throws {
            let result = try Tests.divisibleby([.int(10), .int(3)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with divisible floats")
        func divisiblebyWithDivisibleFloats() throws {
            let result = try Tests.divisibleby(
                [.double(10.0), .double(2.0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("divisibleby test with non-divisible floats")
        func divisiblebyWithNonDivisibleFloats() throws {
            let result = try Tests.divisibleby(
                [.double(10.0), .double(3.0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with zero divisor")
        func divisiblebyWithZeroDivisor() throws {
            let result = try Tests.divisibleby([.int(10), .int(0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with non-number values")
        func divisiblebyWithNonNumberValues() throws {
            let result = try Tests.divisibleby(
                [.string("10"), .string("2")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with insufficient arguments")
        func divisiblebyWithInsufficientArguments() throws {
            #expect(throws: JinjaError.self) {
                try Tests.divisibleby([.int(10)], kwargs: [:], env: env)
            }
        }

        @Test("divisibleby test with empty values")
        func divisiblebyWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.divisibleby([], kwargs: [:], env: env)
            }
        }

        // MARK: - Comparison Tests

        @Test("equalto test with equal integers")
        func equaltoWithEqualIntegers() throws {
            let result = try Tests.eq([.int(42), .int(42)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different integers")
        func equaltoWithDifferentIntegers() throws {
            let result = try Tests.eq([.int(42), .int(43)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with equal strings")
        func equaltoWithEqualStrings() throws {
            let result = try Tests.eq(
                [.string("hello"), .string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different strings")
        func equaltoWithDifferentStrings() throws {
            let result = try Tests.eq(
                [.string("hello"), .string("world")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with equal booleans")
        func equaltoWithEqualBooleans() throws {
            let result = try Tests.eq([.boolean(true), .boolean(true)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different booleans")
        func equaltoWithDifferentBooleans() throws {
            let result = try Tests.eq(
                [.boolean(true), .boolean(false)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with equal null values")
        func equaltoWithEqualNullValues() throws {
            let result = try Tests.eq([.null, .null], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with equal undefined values")
        func equaltoWithEqualUndefinedValues() throws {
            let result = try Tests.eq([.undefined, .undefined], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different types")
        func equaltoWithDifferentTypes() throws {
            let result = try Tests.eq([.int(42), .string("42")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with insufficient arguments")
        func equaltoWithInsufficientArguments() throws {
            #expect(throws: JinjaError.self) {
                try Tests.eq([.int(42)], kwargs: [:], env: env)
            }
        }

        @Test("equalto test with empty values")
        func equaltoWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.eq([], kwargs: [:], env: env)
            }
        }

        // MARK: - Edge Cases

        @Test("Tests with null values")
        func testsWithNullValues() throws {
            let definedResult = try Tests.defined([.null], kwargs: [:], env: env)
            #expect(definedResult == true)  // null is defined, just null

            let undefinedResult = try Tests.undefined([.null], kwargs: [:], env: env)
            #expect(undefinedResult == false)  // null is not undefined

            let noneResult = try Tests.none([.null], kwargs: [:], env: env)
            #expect(noneResult == true)  // null is none
        }

        @Test("Tests with empty arrays and objects")
        func testsWithEmptyArraysAndObjects() throws {
            let emptyArray = Value.array([])
            let emptyObject = Value.object([:])

            // Empty array should be defined but falsy
            let definedResult = try Tests.defined([emptyArray], kwargs: [:], env: env)
            #expect(definedResult == true)

            // Empty array should be iterable
            let iterableResult = try Tests.iterable([emptyArray], kwargs: [:], env: env)
            #expect(iterableResult == true)

            // Empty object should be defined but falsy
            let definedObjectResult = try Tests.defined([emptyObject], kwargs: [:], env: env)
            #expect(definedObjectResult == true)

            // Empty object should be iterable
            let iterableObjectResult = try Tests.iterable([emptyObject], kwargs: [:], env: env)
            #expect(iterableObjectResult == true)
        }

        @Test("Tests with negative numbers")
        func testsWithNegativeNumbers() throws {
            // Negative even number
            let evenResult = try Tests.even([.int(-4)], kwargs: [:], env: env)
            #expect(evenResult == true)

            // Negative odd number
            let oddResult = try Tests.odd([.int(-3)], kwargs: [:], env: env)
            #expect(oddResult == true)

            // Divisibility with negative numbers
            let divisibleResult = try Tests.divisibleby(
                [.int(-10), .int(2)], kwargs: [:], env: env)
            #expect(divisibleResult == true)
        }

        @Test("Tests with floating point precision")
        func testsWithFloatingPointPrecision() throws {
            // Test even with floating point that should be even
            let evenResult = try Tests.even([.double(4.0)], kwargs: [:], env: env)
            #expect(evenResult == true)

            // Test even with floating point that should be odd
            let oddResult = try Tests.odd([.double(3.0)], kwargs: [:], env: env)
            #expect(oddResult == true)

            // Test divisibility with floating point
            let divisibleResult = try Tests.divisibleby(
                [.double(10.0), .double(2.0)], kwargs: [:], env: env)
            #expect(divisibleResult == true)
        }

        // MARK: - New Tests

        @Test("float test with number value")
        func floatWithNumberValue() throws {
            let result = try Tests.float([.double(3.14)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("float test with integer value")
        func floatWithIntegerValue() throws {
            let result = try Tests.float([.int(42)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("sequence test with array")
        func sequenceWithArray() throws {
            let result = try Tests.sequence(
                [.array([.string("a"), .string("b")])], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("sequence test with string")
        func sequenceWithString() throws {
            let result = try Tests.sequence([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("sequence test with object")
        func sequenceWithObject() throws {
            let result = try Tests.sequence(
                [.object(["key": .string("value")])], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("escaped test")
        func escaped() throws {
            // Basic implementation always returns false
            let result = try Tests.escaped([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("filter test with existing filter")
        func filterWithExistingFilter() throws {
            let result = try Tests.filter([.string("upper")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("filter test with non-existing filter")
        func filterWithNonExistingFilter() throws {
            let result = try Tests.filter([.string("nonexistent")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("test test with existing test")
        func testWithExistingTest() throws {
            let result = try Tests.test([.string("defined")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("test test with non-existing test")
        func testWithNonExistingTest() throws {
            let result = try Tests.test([.string("nonexistent")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("sameas test with equal values")
        func sameasWithEqualValues() throws {
            let result = try Tests.sameas([.int(42), .int(42)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("sameas test with different values")
        func sameasWithDifferentValues() throws {
            let result = try Tests.sameas([.int(42), .int(43)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("in test with value in array")
        func inWithValueInArray() throws {
            let array = Value.array([.string("a"), .string("b"), .string("c")])
            let result = try Tests.`in`([.string("b"), array], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("in test with value not in array")
        func inWithValueNotInArray() throws {
            let array = Value.array([.string("a"), .string("b"), .string("c")])
            let result = try Tests.`in`([.string("d"), array], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("in test with substring in string")
        func inWithSubstringInString() throws {
            let result = try Tests.`in`([.string("ell"), .string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("in test with key in object")
        func inWithKeyInObject() throws {
            let obj = Value.object(["name": .string("test"), "age": .int(25)])
            let result = try Tests.`in`([.string("name"), obj], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("comparison tests")
        func comparisonTests() throws {
            // gt test
            let gtResult = try Tests.gt([.int(5), .int(3)], kwargs: [:], env: env)
            #expect(gtResult == true)

            // lt test
            let ltResult = try Tests.lt([.int(3), .int(5)], kwargs: [:], env: env)
            #expect(ltResult == true)

            // ge test
            let geResult = try Tests.ge([.int(5), .int(5)], kwargs: [:], env: env)
            #expect(geResult == true)

            // le test
            let leResult = try Tests.le([.int(3), .int(5)], kwargs: [:], env: env)
            #expect(leResult == true)

            // ne test
            let neResult = try Tests.ne([.int(3), .int(5)], kwargs: [:], env: env)
            #expect(neResult == true)

            // eq test
            let eqResult = try Tests.eq([.int(5), .int(5)], kwargs: [:], env: env)
            #expect(eqResult == true)
        }
    }

    @Suite("Operators")
    struct OperatorTests {
        @Test("Floor division with integers")
        func floorDivisionIntegers() throws {
            let result = try Interpreter.evaluateBinaryValues(.floorDivide, .int(20), .int(7))
            #expect(result == .int(2))
        }

        @Test("Floor division with mixed types")
        func floorDivisionMixed() throws {
            let result = try Interpreter.evaluateBinaryValues(.floorDivide, .double(20.5), .int(7))
            #expect(result == .int(2))
        }

        @Test("Floor division by zero throws error")
        func floorDivisionByZero() throws {
            #expect(throws: JinjaError.self) {
                try Interpreter.evaluateBinaryValues(.floorDivide, .int(10), .int(0))
            }
        }

        @Test("Exponentiation with integers")
        func exponentiationIntegers() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .int(3))
            #expect(result == .int(8))
        }

        @Test("Exponentiation with mixed types")
        func exponentiationMixed() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .double(3.0))
            #expect(result == .double(8.0))
        }

        @Test("Exponentiation with negative exponent")
        func exponentiationNegative() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .int(-2))
            #expect(result == .double(0.25))
        }

    }

    @Suite("Globals")
    struct GlobalsTests {
        let env = Environment()

        @Test("raise_exception without arguments")
        func raiseException() throws {
            #expect(throws: TemplateException.self) {
                try Globals.raiseException([], [:], env)
            }
        }

        @Test("raise_exception with custom message")
        func raiseExceptionWithMessage() throws {
            do {
                try Globals.raiseException(["Template error: invalid input"], [:], env)
            } catch let error as TemplateException {
                #expect(error.message == "Template error: invalid input")
            }
        }

        @Test("strftime_now with basic format")
        func strftimeNowBasic() throws {
            let result = try Globals.strftimeNow([.string("%Y-%m-%d")], [:], env)
            guard case let .string(dateString) = result else {
                #expect(Bool(false), "Expected string result")
                return
            }

            // Verify the result matches the expected format (YYYY-MM-DD)
            let regex = try NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
            let range = NSRange(location: 0, length: dateString.utf16.count)
            let matches = regex.firstMatch(in: dateString, range: range)
            #expect(matches != nil, "Date string should match YYYY-MM-DD format")
        }

        @Test("strftime_now with time format")
        func strftimeNowTime() throws {
            let result = try Globals.strftimeNow([.string("%H:%M:%S")], [:], env)
            guard case let .string(timeString) = result else {
                #expect(Bool(false), "Expected string result")
                return
            }

            // Verify the result matches the expected format (HH:MM:SS)
            let regex = try NSRegularExpression(pattern: "^\\d{2}:\\d{2}:\\d{2}$")
            let range = NSRange(location: 0, length: timeString.utf16.count)
            let matches = regex.firstMatch(in: timeString, range: range)
            #expect(matches != nil, "Time string should match HH:MM:SS format")
        }

        @Test("strftime_now with weekday format")
        func strftimeNowWeekday() throws {
            let result = try Globals.strftimeNow([.string("%A")], [:], env)
            guard case let .string(weekdayString) = result else {
                #expect(Bool(false), "Expected string result")
                return
            }

            // Verify the result is a valid weekday name
            let weekdays = [
                "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
            ]
            #expect(weekdays.contains(weekdayString), "Result should be a valid weekday name")
        }

        @Test("strftime_now with complex format")
        func strftimeNowComplex() throws {
            let result = try Globals.strftimeNow([.string("%A, %B %d, %Y at %I:%M %p")], [:], env)
            guard case let .string(dateString) = result else {
                #expect(Bool(false), "Expected string result")
                return
            }

            // Should contain expected components
            #expect(dateString.contains(", "), "Should contain day/month separator")
            #expect(dateString.contains(" at "), "Should contain date/time separator")
            #expect(dateString.contains("AM") || dateString.contains("PM"), "Should contain AM/PM")

            // Check basic structure - should look like "Monday, September 15, 2025 at 01:30 PM"
            let regex = try NSRegularExpression(
                pattern: "\\w+, \\w+ \\d{1,2}, \\d{4} at \\d{1,2}:\\d{2} (AM|PM)")
            let range = NSRange(location: 0, length: dateString.utf16.count)
            let matches = regex.firstMatch(in: dateString, range: range)
            #expect(
                matches != nil,
                "Complex date format should match expected pattern, got: \(dateString)")
        }

        @Test("strftime_now with literal percent")
        func strftimeNowLiteralPercent() throws {
            let result = try Globals.strftimeNow([.string("%%Y")], [:], env)
            guard case let .string(resultString) = result else {
                #expect(Bool(false), "Expected string result")
                return
            }

            #expect(resultString == "%Y", "Should handle literal percent correctly")
        }

        @Test("strftime_now with no arguments")
        func strftimeNowNoArguments() throws {
            #expect(throws: JinjaError.self) {
                try Globals.strftimeNow([], [:], env)
            }
        }

        @Test("strftime_now with too many arguments")
        func strftimeNowTooManyArguments() throws {
            #expect(throws: JinjaError.self) {
                try Globals.strftimeNow([.string("%Y"), .string("%m")], [:], env)
            }
        }

        @Test("strftime_now with non-string argument")
        func strftimeNowNonStringArgument() throws {
            #expect(throws: JinjaError.self) {
                try Globals.strftimeNow([.int(2024)], [:], env)
            }
        }
    }
}

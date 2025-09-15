import Foundation
import Testing

@testable import Jinja

@Suite("Interpreter")
struct InterpreterTests {
    @Suite("Filters")
    struct FiltersTests {
        let env = Environment()

        @Test("upper filter")
        func testUpperFilter() throws {
            let result = try Filters.upper([.string("hello world")], kwargs: [:], env: env)
            #expect(result == .string("HELLO WORLD"))
        }

        @Test("lower filter")
        func testLowerFilter() throws {
            let result = try Filters.lower([.string("HELLO WORLD")], kwargs: [:], env: env)
            #expect(result == .string("hello world"))
        }

        @Test("length filter for strings")
        func testLengthFilterString() throws {
            let result = try Filters.length([.string("hello")], kwargs: [:], env: env)
            #expect(result == .int(5))
        }

        @Test("length filter for arrays")
        func testLengthFilterArray() throws {
            let values = [Value.int(1), .int(2), .int(3)]
            let result = try Filters.length([.array(values)], kwargs: [:], env: env)
            #expect(result == .int(3))
        }

        @Test("join filter")
        func testJoinFilter() throws {
            let values = [Value.string("a"), .string("b"), .string("c")]
            let result = try Filters.join([.array(values), .string(", ")], kwargs: [:], env: env)
            #expect(result == .string("a, b, c"))
        }

        @Test("default filter with undefined")
        func testDefaultFilterWithUndefined() throws {
            let result = try Filters.default(
                [.undefined, .string("fallback")], kwargs: [:], env: env)
            #expect(result == .string("fallback"))
        }

        @Test("default filter with defined value")
        func testDefaultFilterWithDefinedValue() throws {
            let result = try Filters.default(
                [.string("actual"), .string("fallback")], kwargs: [:], env: env)
            #expect(result == .string("actual"))
        }

        @Test("first filter with array")
        func testFirstFilterWithArray() throws {
            let values = [Value.string("a"), .string("b"), .string("c")]
            let result = try Filters.first([.array(values)], kwargs: [:], env: env)
            #expect(result == .string("a"))
        }

        @Test("last filter with array")
        func testLastFilterWithArray() throws {
            let values = [Value.string("a"), .string("b"), .string("c")]
            let result = try Filters.last([.array(values)], kwargs: [:], env: env)
            #expect(result == .string("c"))
        }

        @Test("reverse filter with array")
        func testReverseFilterWithArray() throws {
            let values = [Value.int(1), .int(2), .int(3)]
            let result = try Filters.reverse([.array(values)], kwargs: [:], env: env)
            let expected = Value.array([.int(3), .int(2), .int(1)])
            #expect(result == expected)
        }

        @Test("abs filter with negative integer")
        func testAbsFilterWithNegativeInteger() throws {
            let result = try Filters.abs([.int(-5)], kwargs: [:], env: env)
            #expect(result == .int(5))
        }

        @Test("abs filter with negative number")
        func testAbsFilterWithNegativeNumber() throws {
            let result = try Filters.abs([.double(-3.14)], kwargs: [:], env: env)
            #expect(result == .double(3.14))
        }

        @Test("capitalize filter")
        func testCapitalizeFilter() throws {
            let result = try Filters.capitalize([.string("hello world")], kwargs: [:], env: env)
            #expect(result == .string("Hello world"))
        }

        @Test("trim filter")
        func testTrimFilter() throws {
            let result = try Filters.trim([.string("  hello world  ")], kwargs: [:], env: env)
            #expect(result == .string("hello world"))
        }

        @Test("float filter")
        func testFloatFilter() throws {
            let result = try Filters.float([.int(42)], kwargs: [:], env: env)
            #expect(result == .double(42.0))
        }

        @Test("int filter")
        func testIntFilter() throws {
            let result = try Filters.int([.double(3.14)], kwargs: [:], env: env)
            #expect(result == .int(3))
        }

        @Test("unique filter")
        func testUniqueFilter() throws {
            let values = [Value.int(1), .int(2), .int(1), .int(3), .int(2)]
            let result = try Filters.unique([.array(values)], kwargs: [:], env: env)
            let expected = Value.array([.int(1), .int(2), .int(3)])
            #expect(result == expected)
        }

        @Test("dictsort filter")
        func testDictsortFilter() throws {
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
        func testDictsortFilterWithReverse() throws {
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
        func testPprintFilter() throws {
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
        func testUrlizeFilter() throws {
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
        func testSumFilterWithAttribute() throws {
            let items = Value.array([
                .object(["price": .double(10.5)]),
                .object(["price": .double(20.0)]),
                .object(["price": .double(15.5)]),
            ])
            let result = try Filters.sum([items, .string("price")], kwargs: [:], env: env)
            #expect(result == .double(46.0))
        }

        @Test("indent filter")
        func testIndentFilter() throws {
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
        func testIndentFilterWithFirst() throws {
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
        func testDefinedWithDefinedValue() throws {
            let result = try Tests.defined([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("defined test with undefined value")
        func testDefinedWithUndefinedValue() throws {
            let result = try Tests.defined([.undefined], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("defined test with empty values")
        func testDefinedWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.defined([], kwargs: [:], env: env)
            }
        }

        @Test("undefined test with undefined value")
        func testUndefinedWithUndefinedValue() throws {
            let result = try Tests.undefined([.undefined], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("undefined test with defined value")
        func testUndefinedWithDefinedValue() throws {
            let result = try Tests.undefined([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("undefined test with empty values")
        func testUndefinedWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.undefined([], kwargs: [:], env: env)
            }
        }

        @Test("none test with null value")
        func testNoneWithNullValue() throws {
            let result = try Tests.none([.null], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("none test with non-null value")
        func testNoneWithNonNullValue() throws {
            let result = try Tests.none([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("none test with empty values")
        func testNoneWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.none([], kwargs: [:], env: env)
            }
        }

        @Test("string test with string value")
        func testStringWithStringValue() throws {
            let result = try Tests.string([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("string test with non-string value")
        func testStringWithNonStringValue() throws {
            let result = try Tests.string([.int(42)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("string test with empty values")
        func testStringWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.string([], kwargs: [:], env: env)
            }
        }

        @Test("number test with integer value")
        func testNumberWithIntegerValue() throws {
            let result = try Tests.number([.int(42)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("number test with float value")
        func testNumberWithFloatValue() throws {
            let result = try Tests.number([.double(3.14)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("number test with non-number value")
        func testNumberWithNonNumberValue() throws {
            let result = try Tests.number([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("number test with empty values")
        func testNumberWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.number([], kwargs: [:], env: env)
            }
        }

        @Test("boolean test with true value")
        func testBooleanWithTrueValue() throws {
            let result = try Tests.boolean([.boolean(true)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("boolean test with false value")
        func testBooleanWithFalseValue() throws {
            let result = try Tests.boolean([.boolean(false)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("boolean test with non-boolean value")
        func testBooleanWithNonBooleanValue() throws {
            let result = try Tests.boolean([.string("true")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("boolean test with empty values")
        func testBooleanWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.boolean([], kwargs: [:], env: env)
            }
        }

        @Test("iterable test with array value")
        func testIterableWithArrayValue() throws {
            let result = try Tests.iterable(
                [.array([.string("a"), .string("b")])], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("iterable test with object value")
        func testIterableWithObjectValue() throws {
            let result = try Tests.iterable(
                [.object(["key": .string("value")])], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("iterable test with string value")
        func testIterableWithStringValue() throws {
            let result = try Tests.iterable([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("iterable test with non-iterable value")
        func testIterableWithNonIterableValue() throws {
            let result = try Tests.iterable([.int(42)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("iterable test with empty values")
        func testIterableWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.iterable([], kwargs: [:], env: env)
            }
        }

        // MARK: - Numeric Tests

        @Test("even test with even integer")
        func testEvenWithEvenInteger() throws {
            let result = try Tests.even([.int(4)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("even test with odd integer")
        func testEvenWithOddInteger() throws {
            let result = try Tests.even([.int(5)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("even test with even float")
        func testEvenWithEvenFloat() throws {
            let result = try Tests.even([.double(4.0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("even test with odd float")
        func testEvenWithOddFloat() throws {
            let result = try Tests.even([.double(5.0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("even test with non-number value")
        func testEvenWithNonNumberValue() throws {
            let result = try Tests.even([.string("4")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("even test with zero")
        func testEvenWithZero() throws {
            let result = try Tests.even([.int(0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("even test with empty values")
        func testEvenWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.even([], kwargs: [:], env: env)
            }
        }

        @Test("odd test with odd integer")
        func testOddWithOddInteger() throws {
            let result = try Tests.odd([.int(3)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("odd test with even integer")
        func testOddWithEvenInteger() throws {
            let result = try Tests.odd([.int(4)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("odd test with odd float")
        func testOddWithOddFloat() throws {
            let result = try Tests.odd([.double(3.0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("odd test with even float")
        func testOddWithEvenFloat() throws {
            let result = try Tests.odd([.double(4.0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("odd test with non-number value")
        func testOddWithNonNumberValue() throws {
            let result = try Tests.odd([.string("3")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("odd test with empty values")
        func testOddWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.odd([], kwargs: [:], env: env)
            }
        }

        @Test("divisibleby test with divisible integers")
        func testDivisiblebyWithDivisibleIntegers() throws {
            let result = try Tests.divisibleby([.int(10), .int(2)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("divisibleby test with non-divisible integers")
        func testDivisiblebyWithNonDivisibleIntegers() throws {
            let result = try Tests.divisibleby([.int(10), .int(3)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with divisible floats")
        func testDivisiblebyWithDivisibleFloats() throws {
            let result = try Tests.divisibleby(
                [.double(10.0), .double(2.0)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("divisibleby test with non-divisible floats")
        func testDivisiblebyWithNonDivisibleFloats() throws {
            let result = try Tests.divisibleby(
                [.double(10.0), .double(3.0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with zero divisor")
        func testDivisiblebyWithZeroDivisor() throws {
            let result = try Tests.divisibleby([.int(10), .int(0)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with non-number values")
        func testDivisiblebyWithNonNumberValues() throws {
            let result = try Tests.divisibleby(
                [.string("10"), .string("2")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("divisibleby test with insufficient arguments")
        func testDivisiblebyWithInsufficientArguments() throws {
            #expect(throws: JinjaError.self) {
                try Tests.divisibleby([.int(10)], kwargs: [:], env: env)
            }
        }

        @Test("divisibleby test with empty values")
        func testDivisiblebyWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.divisibleby([], kwargs: [:], env: env)
            }
        }

        // MARK: - Comparison Tests

        @Test("equalto test with equal integers")
        func testEqualtoWithEqualIntegers() throws {
            let result = try Tests.eq([.int(42), .int(42)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different integers")
        func testEqualtoWithDifferentIntegers() throws {
            let result = try Tests.eq([.int(42), .int(43)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with equal strings")
        func testEqualtoWithEqualStrings() throws {
            let result = try Tests.eq(
                [.string("hello"), .string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different strings")
        func testEqualtoWithDifferentStrings() throws {
            let result = try Tests.eq(
                [.string("hello"), .string("world")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with equal booleans")
        func testEqualtoWithEqualBooleans() throws {
            let result = try Tests.eq([.boolean(true), .boolean(true)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different booleans")
        func testEqualtoWithDifferentBooleans() throws {
            let result = try Tests.eq(
                [.boolean(true), .boolean(false)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with equal null values")
        func testEqualtoWithEqualNullValues() throws {
            let result = try Tests.eq([.null, .null], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with equal undefined values")
        func testEqualtoWithEqualUndefinedValues() throws {
            let result = try Tests.eq([.undefined, .undefined], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("equalto test with different types")
        func testEqualtoWithDifferentTypes() throws {
            let result = try Tests.eq([.int(42), .string("42")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("equalto test with insufficient arguments")
        func testEqualtoWithInsufficientArguments() throws {
            #expect(throws: JinjaError.self) {
                try Tests.eq([.int(42)], kwargs: [:], env: env)
            }
        }

        @Test("equalto test with empty values")
        func testEqualtoWithEmptyValues() throws {
            #expect(throws: JinjaError.self) {
                try Tests.eq([], kwargs: [:], env: env)
            }
        }

        // MARK: - Edge Cases

        @Test("Tests with null values")
        func testTestsWithNullValues() throws {
            let definedResult = try Tests.defined([.null], kwargs: [:], env: env)
            #expect(definedResult == true)  // null is defined, just null

            let undefinedResult = try Tests.undefined([.null], kwargs: [:], env: env)
            #expect(undefinedResult == false)  // null is not undefined

            let noneResult = try Tests.none([.null], kwargs: [:], env: env)
            #expect(noneResult == true)  // null is none
        }

        @Test("Tests with empty arrays and objects")
        func testTestsWithEmptyArraysAndObjects() throws {
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
        func testTestsWithNegativeNumbers() throws {
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
        func testTestsWithFloatingPointPrecision() throws {
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
        func testFloatWithNumberValue() throws {
            let result = try Tests.float([.double(3.14)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("float test with integer value")
        func testFloatWithIntegerValue() throws {
            let result = try Tests.float([.int(42)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("sequence test with array")
        func testSequenceWithArray() throws {
            let result = try Tests.sequence(
                [.array([.string("a"), .string("b")])], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("sequence test with string")
        func testSequenceWithString() throws {
            let result = try Tests.sequence([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("sequence test with object")
        func testSequenceWithObject() throws {
            let result = try Tests.sequence(
                [.object(["key": .string("value")])], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("escaped test")
        func testEscaped() throws {
            // Basic implementation always returns false
            let result = try Tests.escaped([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("filter test with existing filter")
        func testFilterWithExistingFilter() throws {
            let result = try Tests.filter([.string("upper")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("filter test with non-existing filter")
        func testFilterWithNonExistingFilter() throws {
            let result = try Tests.filter([.string("nonexistent")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("test test with existing test")
        func testTestWithExistingTest() throws {
            let result = try Tests.test([.string("defined")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("test test with non-existing test")
        func testTestWithNonExistingTest() throws {
            let result = try Tests.test([.string("nonexistent")], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("sameas test with equal values")
        func testSameasWithEqualValues() throws {
            let result = try Tests.sameas([.int(42), .int(42)], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("sameas test with different values")
        func testSameasWithDifferentValues() throws {
            let result = try Tests.sameas([.int(42), .int(43)], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("in test with value in array")
        func testInWithValueInArray() throws {
            let array = Value.array([.string("a"), .string("b"), .string("c")])
            let result = try Tests.`in`([.string("b"), array], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("in test with value not in array")
        func testInWithValueNotInArray() throws {
            let array = Value.array([.string("a"), .string("b"), .string("c")])
            let result = try Tests.`in`([.string("d"), array], kwargs: [:], env: env)
            #expect(result == false)
        }

        @Test("in test with substring in string")
        func testInWithSubstringInString() throws {
            let result = try Tests.`in`([.string("ell"), .string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("in test with key in object")
        func testInWithKeyInObject() throws {
            let obj = Value.object(["name": .string("test"), "age": .int(25)])
            let result = try Tests.`in`([.string("name"), obj], kwargs: [:], env: env)
            #expect(result == true)
        }

        @Test("comparison tests")
        func testComparisonTests() throws {
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
        func testFloorDivisionIntegers() throws {
            let result = try Interpreter.evaluateBinaryValues(.floorDivide, .int(20), .int(7))
            #expect(result == .int(2))
        }

        @Test("Floor division with mixed types")
        func testFloorDivisionMixed() throws {
            let result = try Interpreter.evaluateBinaryValues(.floorDivide, .double(20.5), .int(7))
            #expect(result == .int(2))
        }

        @Test("Floor division by zero throws error")
        func testFloorDivisionByZero() throws {
            #expect(throws: JinjaError.self) {
                try Interpreter.evaluateBinaryValues(.floorDivide, .int(10), .int(0))
            }
        }

        @Test("Exponentiation with integers")
        func testExponentiationIntegers() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .int(3))
            #expect(result == .int(8))
        }

        @Test("Exponentiation with mixed types")
        func testExponentiationMixed() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .double(3.0))
            #expect(result == .double(8.0))
        }

        @Test("Exponentiation with negative exponent")
        func testExponentiationNegative() throws {
            let result = try Interpreter.evaluateBinaryValues(.power, .int(2), .int(-2))
            #expect(result == .double(0.25))
        }

    }

    @Suite("Globals")
    struct GlobalsTests {
        let env = Environment()

        @Test("raise_exception() built-in function")
        func testRaiseException() throws {
            #expect(throws: Exception.self) {
                try Globals.raiseException([], [:], env)
            }
        }

        @Test("raise_exception() with custom message")
        func testRaiseExceptionWithMessage() throws {
            do {
                try Globals.raiseException(["Template error: invalid input"], [:], env)
            } catch let error as Exception {
                #expect(error.message == "Template error: invalid input")
            }
        }
    }
}

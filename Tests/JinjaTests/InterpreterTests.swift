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
            #expect(result == .integer(5))
        }
        
        @Test("length filter for arrays")
        func testLengthFilterArray() throws {
            let values = [Value.integer(1), .integer(2), .integer(3)]
            let result = try Filters.length([.array(values)], kwargs: [:], env: env)
            #expect(result == .integer(3))
        }
        
        @Test("join filter")
        func testJoinFilter() throws {
            let values = [Value.string("a"), .string("b"), .string("c")]
            let result = try Filters.join([.array(values), .string(", ")], kwargs: [:], env: env)
            #expect(result == .string("a, b, c"))
        }
        
        @Test("default filter with undefined")
        func testDefaultFilterWithUndefined() throws {
            let result = try Filters.default([.undefined, .string("fallback")], kwargs: [:], env: env)
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
            let values = [Value.integer(1), .integer(2), .integer(3)]
            let result = try Filters.reverse([.array(values)], kwargs: [:], env: env)
            let expected = Value.array([.integer(3), .integer(2), .integer(1)])
            #expect(result == expected)
        }
        
        @Test("abs filter with negative integer")
        func testAbsFilterWithNegativeInteger() throws {
            let result = try Filters.abs([.integer(-5)], kwargs: [:], env: env)
            #expect(result == .integer(5))
        }
        
        @Test("abs filter with negative number")
        func testAbsFilterWithNegativeNumber() throws {
            let result = try Filters.abs([.number(-3.14)], kwargs: [:], env: env)
            #expect(result == .number(3.14))
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
            let result = try Filters.float([.integer(42)], kwargs: [:], env: env)
            #expect(result == .number(42.0))
        }
        
        @Test("int filter")
        func testIntFilter() throws {
            let result = try Filters.int([.number(3.14)], kwargs: [:], env: env)
            #expect(result == .integer(3))
        }
        
        @Test("unique filter")
        func testUniqueFilter() throws {
            let values = [Value.integer(1), .integer(2), .integer(1), .integer(3), .integer(2)]
            let result = try Filters.unique([.array(values)], kwargs: [:], env: env)
            let expected = Value.array([.integer(1), .integer(2), .integer(3)])
            #expect(result == expected)
        }
        
        @Test("defined test filter")
        func testDefinedFilter() throws {
            let result1 = try Filters.defined([.string("hello")], kwargs: [:], env: env)
            #expect(result1 == .boolean(true))
            
            let result2 = try Filters.defined([.undefined], kwargs: [:], env: env)
            #expect(result2 == .boolean(false))
        }
        
        @Test("undefined test filter")
        func testUndefinedFilter() throws {
            let result1 = try Filters.undefined([.string("hello")], kwargs: [:], env: env)
            #expect(result1 == .boolean(false))
            
            let result2 = try Filters.undefined([.undefined], kwargs: [:], env: env)
            #expect(result2 == .boolean(true))
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
            let result = try Tests.defined([], kwargs: [:], env: env)
            #expect(result == false)
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
            let result = try Tests.undefined([], kwargs: [:], env: env)
            #expect(result == true)
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
            let result = try Tests.none([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("string test with string value")
        func testStringWithStringValue() throws {
            let result = try Tests.string([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("string test with non-string value")
        func testStringWithNonStringValue() throws {
            let result = try Tests.string([.integer(42)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("string test with empty values")
        func testStringWithEmptyValues() throws {
            let result = try Tests.string([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("number test with integer value")
        func testNumberWithIntegerValue() throws {
            let result = try Tests.number([.integer(42)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("number test with float value")
        func testNumberWithFloatValue() throws {
            let result = try Tests.number([.number(3.14)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("number test with non-number value")
        func testNumberWithNonNumberValue() throws {
            let result = try Tests.number([.string("hello")], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("number test with empty values")
        func testNumberWithEmptyValues() throws {
            let result = try Tests.number([], kwargs: [:], env: env)
            #expect(result == false)
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
            let result = try Tests.boolean([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("iterable test with array value")
        func testIterableWithArrayValue() throws {
            let result = try Tests.iterable(
                [.array([.string("a"), .string("b")])], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("iterable test with object value")
        func testIterableWithObjectValue() throws {
            let result = try Tests.iterable([.object(["key": .string("value")])], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("iterable test with string value")
        func testIterableWithStringValue() throws {
            let result = try Tests.iterable([.string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("iterable test with non-iterable value")
        func testIterableWithNonIterableValue() throws {
            let result = try Tests.iterable([.integer(42)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("iterable test with empty values")
        func testIterableWithEmptyValues() throws {
            let result = try Tests.iterable([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        // MARK: - Numeric Tests
        
        @Test("even test with even integer")
        func testEvenWithEvenInteger() throws {
            let result = try Tests.even([.integer(4)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("even test with odd integer")
        func testEvenWithOddInteger() throws {
            let result = try Tests.even([.integer(5)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("even test with even float")
        func testEvenWithEvenFloat() throws {
            let result = try Tests.even([.number(4.0)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("even test with odd float")
        func testEvenWithOddFloat() throws {
            let result = try Tests.even([.number(5.0)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("even test with non-number value")
        func testEvenWithNonNumberValue() throws {
            let result = try Tests.even([.string("4")], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("even test with zero")
        func testEvenWithZero() throws {
            let result = try Tests.even([.integer(0)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("even test with empty values")
        func testEvenWithEmptyValues() throws {
            let result = try Tests.even([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("odd test with odd integer")
        func testOddWithOddInteger() throws {
            let result = try Tests.odd([.integer(3)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("odd test with even integer")
        func testOddWithEvenInteger() throws {
            let result = try Tests.odd([.integer(4)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("odd test with odd float")
        func testOddWithOddFloat() throws {
            let result = try Tests.odd([.number(3.0)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("odd test with even float")
        func testOddWithEvenFloat() throws {
            let result = try Tests.odd([.number(4.0)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("odd test with non-number value")
        func testOddWithNonNumberValue() throws {
            let result = try Tests.odd([.string("3")], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("odd test with empty values")
        func testOddWithEmptyValues() throws {
            let result = try Tests.odd([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("divisibleby test with divisible integers")
        func testDivisiblebyWithDivisibleIntegers() throws {
            let result = try Tests.divisibleby([.integer(10), .integer(2)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("divisibleby test with non-divisible integers")
        func testDivisiblebyWithNonDivisibleIntegers() throws {
            let result = try Tests.divisibleby([.integer(10), .integer(3)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("divisibleby test with divisible floats")
        func testDivisiblebyWithDivisibleFloats() throws {
            let result = try Tests.divisibleby([.number(10.0), .number(2.0)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("divisibleby test with non-divisible floats")
        func testDivisiblebyWithNonDivisibleFloats() throws {
            let result = try Tests.divisibleby([.number(10.0), .number(3.0)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("divisibleby test with zero divisor")
        func testDivisiblebyWithZeroDivisor() throws {
            let result = try Tests.divisibleby([.integer(10), .integer(0)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("divisibleby test with non-number values")
        func testDivisiblebyWithNonNumberValues() throws {
            let result = try Tests.divisibleby([.string("10"), .string("2")], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("divisibleby test with insufficient arguments")
        func testDivisiblebyWithInsufficientArguments() throws {
            let result = try Tests.divisibleby([.integer(10)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("divisibleby test with empty values")
        func testDivisiblebyWithEmptyValues() throws {
            let result = try Tests.divisibleby([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        // MARK: - Comparison Tests
        
        @Test("equalto test with equal integers")
        func testEqualtoWithEqualIntegers() throws {
            let result = try Tests.equalto([.integer(42), .integer(42)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("equalto test with different integers")
        func testEqualtoWithDifferentIntegers() throws {
            let result = try Tests.equalto([.integer(42), .integer(43)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("equalto test with equal strings")
        func testEqualtoWithEqualStrings() throws {
            let result = try Tests.equalto([.string("hello"), .string("hello")], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("equalto test with different strings")
        func testEqualtoWithDifferentStrings() throws {
            let result = try Tests.equalto([.string("hello"), .string("world")], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("equalto test with equal booleans")
        func testEqualtoWithEqualBooleans() throws {
            let result = try Tests.equalto([.boolean(true), .boolean(true)], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("equalto test with different booleans")
        func testEqualtoWithDifferentBooleans() throws {
            let result = try Tests.equalto([.boolean(true), .boolean(false)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("equalto test with equal null values")
        func testEqualtoWithEqualNullValues() throws {
            let result = try Tests.equalto([.null, .null], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("equalto test with equal undefined values")
        func testEqualtoWithEqualUndefinedValues() throws {
            let result = try Tests.equalto([.undefined, .undefined], kwargs: [:], env: env)
            #expect(result == true)
        }
        
        @Test("equalto test with different types")
        func testEqualtoWithDifferentTypes() throws {
            let result = try Tests.equalto([.integer(42), .string("42")], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("equalto test with insufficient arguments")
        func testEqualtoWithInsufficientArguments() throws {
            let result = try Tests.equalto([.integer(42)], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        @Test("equalto test with empty values")
        func testEqualtoWithEmptyValues() throws {
            let result = try Tests.equalto([], kwargs: [:], env: env)
            #expect(result == false)
        }
        
        // MARK: - Tests Dictionary
        
        @Test("Tests.default dictionary contains all tests")
        func testTestsDefaultDictionary() throws {
            let expectedTests = [
                "defined", "undefined", "none", "string", "number", "boolean", "iterable",
                "even", "odd", "divisibleby", "equalto",
            ]
            
            for testName in expectedTests {
                #expect(
                    Tests.default[testName] != nil,
                    "Test '\(testName)' should be in Tests.default dictionary")
            }
            
            #expect(
                Tests.default.count == expectedTests.count,
                "Tests.default should contain exactly \(expectedTests.count) tests")
        }
        
        @Test("Tests.default dictionary functions work correctly")
        func testTestsDefaultDictionaryFunctions() throws {
            // Test defined
            let definedResult = try Tests.default["defined"]!([.string("hello")], [:], env)
            #expect(definedResult == true)
            
            // Test even
            let evenResult = try Tests.default["even"]!([.integer(4)], [:], env)
            #expect(evenResult == true)
            
            // Test equalto
            let equaltoResult = try Tests.default["equalto"]!([.integer(42), .integer(42)], [:], env)
            #expect(equaltoResult == true)
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
            let evenResult = try Tests.even([.integer(-4)], kwargs: [:], env: env)
            #expect(evenResult == true)
            
            // Negative odd number
            let oddResult = try Tests.odd([.integer(-3)], kwargs: [:], env: env)
            #expect(oddResult == true)
            
            // Divisibility with negative numbers
            let divisibleResult = try Tests.divisibleby(
                [.integer(-10), .integer(2)], kwargs: [:], env: env)
            #expect(divisibleResult == true)
        }
        
        @Test("Tests with floating point precision")
        func testTestsWithFloatingPointPrecision() throws {
            // Test even with floating point that should be even
            let evenResult = try Tests.even([.number(4.0)], kwargs: [:], env: env)
            #expect(evenResult == true)
            
            // Test even with floating point that should be odd
            let oddResult = try Tests.odd([.number(3.0)], kwargs: [:], env: env)
            #expect(oddResult == true)
            
            // Test divisibility with floating point
            let divisibleResult = try Tests.divisibleby(
                [.number(10.0), .number(2.0)], kwargs: [:], env: env)
            #expect(divisibleResult == true)
        }
    }
}

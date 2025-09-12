import Foundation
import Testing
@testable import Jinja

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
        let result = try Filters.default([.string("actual"), .string("fallback")], kwargs: [:], env: env)
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

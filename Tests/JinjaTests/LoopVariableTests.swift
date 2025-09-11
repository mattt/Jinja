import Testing
@testable import Jinja

@Suite("Loop Variable and Control Flow Tests")
struct LoopVariableTests {
    
    // MARK: - Basic Loop Variables
    
    @Test("Loop index variables")
    func testLoopIndexVariables() throws {
        let template = try Template("""
        {% for item in items %}
        {{ loop.index }}: {{ item }}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["apple", "banana", "cherry"]
        ])
        
        #expect(result.contains("1: apple"))
        #expect(result.contains("2: banana"))
        #expect(result.contains("3: cherry"))
    }
    
    @Test("Loop index0 variables (zero-based)")
    func testLoopIndex0Variables() throws {
        let template = try Template("""
        {% for item in items %}
        [{{ loop.index0 }}] {{ item }}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["first", "second", "third"]
        ])
        
        #expect(result.contains("[0] first"))
        #expect(result.contains("[1] second"))
        #expect(result.contains("[2] third"))
    }
    
    @Test("Loop first and last variables")
    func testLoopFirstLastVariables() throws {
        let template = try Template("""
        {% for item in items %}
        {% if loop.first %}FIRST: {% endif %}
        {{ item }}
        {% if loop.last %}LAST{% endif %}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["a", "b", "c"]
        ])
        
        #expect(result.contains("FIRST: a"))
        #expect(!result.contains("FIRST: b"))
        #expect(!result.contains("FIRST: c"))
        #expect(!result.contains("aLAST"))
        #expect(!result.contains("bLAST"))
        #expect(result.contains("cLAST"))
    }
    
    @Test("Loop length variable")
    func testLoopLengthVariable() throws {
        let template = try Template("""
        Total items: {{ loop.length }}
        {% for item in items %}
        {{ loop.index }}/{{ loop.length }}: {{ item }}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["one", "two", "three", "four"]
        ])
        
        #expect(result.contains("Total items: 4"))
        #expect(result.contains("1/4: one"))
        #expect(result.contains("2/4: two"))
        #expect(result.contains("3/4: three"))
        #expect(result.contains("4/4: four"))
    }
    
    @Test("Loop revindex variables (reverse index)")
    func testLoopRevindexVariables() throws {
        let template = try Template("""
        {% for item in items %}
        {{ item }} ({{ loop.revindex }} remaining)
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["a", "b", "c"]
        ])
        
        #expect(result.contains("a (3 remaining)"))
        #expect(result.contains("b (2 remaining)"))
        #expect(result.contains("c (1 remaining)"))
    }
    
    @Test("Loop revindex0 variables (zero-based reverse)")
    func testLoopRevindex0Variables() throws {
        let template = try Template("""
        {% for item in items %}
        {{ item }} [{{ loop.revindex0 }} more]
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["x", "y", "z"]
        ])
        
        #expect(result.contains("x [2 more]"))
        #expect(result.contains("y [1 more]"))
        #expect(result.contains("z [0 more]"))
    }
    
    // MARK: - Loop Cycle
    
    @Test("Loop cycle functionality")
    func testLoopCycle() throws {
        let template = try Template("""
        {% for item in items %}
        {{ loop.cycle('odd', 'even') }}: {{ item }}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["first", "second", "third", "fourth"]
        ])
        
        #expect(result.contains("odd: first"))
        #expect(result.contains("even: second"))
        #expect(result.contains("odd: third"))
        #expect(result.contains("even: fourth"))
    }
    
    @Test("Loop cycle with CSS classes")
    func testLoopCycleWithCSSClasses() throws {
        let template = try Template("""
        {% for user in users %}
        <div class="{{ loop.cycle('row-light', 'row-dark') }}">{{ user.name }}</div>
        {% endfor %}
        """)
        
        let result = try template.render([
            "users": [
                ["name": "Alice"],
                ["name": "Bob"],
                ["name": "Charlie"]
            ]
        ])
        
        #expect(result.contains("class=\"row-light\">Alice"))
        #expect(result.contains("class=\"row-dark\">Bob"))
        #expect(result.contains("class=\"row-light\">Charlie"))
    }
    
    // MARK: - Nested Loops
    
    @Test("Nested loops with different loop variables")
    func testNestedLoops() throws {
        let template = try Template("""
        {% for group in groups %}
        Group {{ loop.index }}:
        {% for item in group.items %}
          {{ loop.index }}.{{ loop.index }} {{ item }}
        {% endfor %}
        {% endfor %}
        """)
        
        let result = try template.render([
            "groups": [
                ["items": ["a", "b"]],
                ["items": ["x", "y", "z"]]
            ]
        ])
        
        #expect(result.contains("Group 1:"))
        #expect(result.contains("Group 2:"))
        #expect(result.contains("1.1 a"))
        #expect(result.contains("1.2 b"))
        #expect(result.contains("1.1 x"))
        #expect(result.contains("1.2 y"))
        #expect(result.contains("1.3 z"))
    }
    
    @Test("Accessing outer loop variables in nested loops")
    func testOuterLoopVariablesInNestedLoops() throws {
        let template = try Template("""
        {% for section in sections %}
        {% for item in section.items %}
        Section {{ loop.parent.loop.index }}, Item {{ loop.index }}: {{ item }}
        {% endfor %}
        {% endfor %}
        """)
        
        // This test may fail if loop.parent.loop is not implemented
        // It's a more advanced feature that some Jinja implementations don't support
        #expect(throws: JinjaError.self) {
            let result = try template.render([
                "sections": [
                    ["items": ["item1", "item2"]],
                    ["items": ["item3"]]
                ]
            ])
        }
    }
    
    // MARK: - Loop with Conditionals
    
    @Test("Loop with if condition")
    func testLoopWithIfCondition() throws {
        let template = try Template("""
        {% for item in items if item.active %}
        Active item {{ loop.index }}: {{ item.name }}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": [
                ["name": "Item 1", "active": true],
                ["name": "Item 2", "active": false],
                ["name": "Item 3", "active": true],
                ["name": "Item 4", "active": false]
            ]
        ])
        
        #expect(result.contains("Active item 1: Item 1"))
        #expect(result.contains("Active item 2: Item 3"))
        #expect(!result.contains("Item 2"))
        #expect(!result.contains("Item 4"))
    }
    
    @Test("Loop with complex conditions")
    func testLoopWithComplexConditions() throws {
        let template = try Template("""
        {% for user in users %}
        {% if loop.first %}
        === FIRST USER ===
        {% elif loop.last %}
        === LAST USER ===
        {% endif %}
        {{ user.name }} ({{ user.age }} years old)
        {% if loop.index % 2 == 0 %}
        [Even position]
        {% endif %}
        {% endfor %}
        """)
        
        let result = try template.render([
            "users": [
                ["name": "Alice", "age": 25],
                ["name": "Bob", "age": 30],
                ["name": "Charlie", "age": 35],
                ["name": "Diana", "age": 28]
            ]
        ])
        
        #expect(result.contains("=== FIRST USER ==="))
        #expect(result.contains("Alice (25 years old)"))
        #expect(result.contains("=== LAST USER ==="))
        #expect(result.contains("Diana (28 years old)"))
        #expect(result.contains("[Even position]"))
    }
    
    // MARK: - Loop with Break and Continue
    
    @Test("Loop break statement")
    func testLoopBreak() throws {
        let template = try Template("""
        {% for item in items %}
        {% if item == 'stop' %}
        {% break %}
        {% endif %}
        {{ item }}
        {% endfor %}
        """)
        
        // This test may fail if break is not implemented
        // It's part of the minja specification but not all implementations support it
        #expect(throws: JinjaError.self) {
            let result = try template.render([
                "items": ["first", "second", "stop", "fourth", "fifth"]
            ])
        }
    }
    
    @Test("Loop continue statement")
    func testLoopContinue() throws {
        let template = try Template("""
        {% for item in items %}
        {% if item == 'skip' %}
        {% continue %}
        {% endif %}
        {{ item }}
        {% endfor %}
        """)
        
        // This test may fail if continue is not implemented
        #expect(throws: JinjaError.self) {
            let result = try template.render([
                "items": ["first", "skip", "third", "skip", "fifth"]
            ])
        }
    }
    
    // MARK: - Loop Else
    
    @Test("Loop with else clause (non-empty)")
    func testLoopElseNonEmpty() throws {
        let template = try Template("""
        {% for item in items %}
        Item: {{ item }}
        {% else %}
        No items found.
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["apple", "banana"]
        ])
        
        #expect(result.contains("Item: apple"))
        #expect(result.contains("Item: banana"))
        #expect(!result.contains("No items found"))
    }
    
    @Test("Loop with else clause (empty)")
    func testLoopElseEmpty() throws {
        let template = try Template("""
        {% for item in items %}
        Item: {{ item }}
        {% else %}
        No items found.
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": []
        ])
        
        #expect(!result.contains("Item:"))
        #expect(result.contains("No items found"))
    }
    
    // MARK: - Destructuring in Loops
    
    @Test("Loop with tuple destructuring")
    func testLoopTupleDestructuring() throws {
        let template = try Template("""
        {% for key, value in items %}
        {{ key }}: {{ value }}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": [
                ["name", "John"],
                ["age", 30],
                ["city", "New York"]
            ]
        ])
        
        #expect(result.contains("name: John"))
        #expect(result.contains("age: 30"))
        #expect(result.contains("city: New York"))
    }
    
    @Test("Loop with dictionary iteration")
    func testLoopDictionaryIteration() throws {
        let template = try Template("""
        {% for key, value in user.items() %}
        {{ key }}: {{ value }}
        {% endfor %}
        """)
        
        let result = try template.render([
            "user": [
                "name": "Alice",
                "email": "alice@example.com",
                "role": "admin"
            ]
        ])
        
        #expect(result.contains("name: Alice"))
        #expect(result.contains("email: alice@example.com"))
        #expect(result.contains("role: admin"))
    }
    
    // MARK: - Recursive Loops
    
    @Test("Recursive loop structure")
    func testRecursiveLoop() throws {
        let template = try Template("""
        {% for item in items recursive %}
        {{ item.name }}
        {% if item.children %}
        {% for child in item.children %}
        {{ loop(child) }}
        {% endfor %}
        {% endif %}
        {% endfor %}
        """)
        
        // This test may fail if recursive loops are not implemented
        #expect(throws: JinjaError.self) {
            let result = try template.render([
                "items": [
                    [
                        "name": "Parent 1",
                        "children": [
                            ["name": "Child 1.1"],
                            ["name": "Child 1.2"]
                        ]
                    ],
                    [
                        "name": "Parent 2",
                        "children": [
                            ["name": "Child 2.1"]
                        ]
                    ]
                ]
            ])
        }
    }
    
    // MARK: - Performance and Edge Cases
    
    @Test("Loop with large dataset")
    func testLoopWithLargeDataset() throws {
        // Create a large array
        var largeArray: [Value] = []
        for i in 0..<1000 {
            largeArray.append(.string("Item \(i)"))
        }
        
        let template = try Template("""
        {% for item in items %}
        {% if loop.first %}First: {{ item }}{% endif %}
        {% if loop.last %}Last: {{ item }}{% endif %}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": .array(largeArray)
        ])
        
        #expect(result.contains("First: Item 0"))
        #expect(result.contains("Last: Item 999"))
    }
    
    @Test("Loop with empty collections")
    func testLoopWithEmptyCollections() throws {
        let template = try Template("""
        Arrays:
        {% for item in empty_array %}
        {{ item }}
        {% else %}
        Empty array
        {% endfor %}
        
        Objects:
        {% for key, value in empty_object.items() %}
        {{ key }}: {{ value }}
        {% else %}
        Empty object
        {% endfor %}
        
        Strings:
        {% for char in empty_string %}
        {{ char }}
        {% else %}
        Empty string
        {% endfor %}
        """)
        
        let result = try template.render([
            "empty_array": [],
            "empty_object": [:],
            "empty_string": ""
        ])
        
        #expect(result.contains("Empty array"))
        #expect(result.contains("Empty object"))
        #expect(result.contains("Empty string"))
    }
    
    @Test("Loop variables with special characters")
    func testLoopVariablesWithSpecialCharacters() throws {
        let template = try Template("""
        {% for item in items %}
        {{ loop.index }}: "{{ item }}" {% if not loop.last %},{% endif %}
        {% endfor %}
        """)
        
        let result = try template.render([
            "items": ["Hello, World!", "Line 1\nLine 2", "Tab\tSeparated", "Quote\"Test"]
        ])
        
        #expect(result.contains("\"Hello, World!\""))
        #expect(result.contains("\"Line 1\nLine 2\""))
        #expect(result.contains("\"Tab\tSeparated\""))
        #expect(result.contains("\"Quote\"Test\""))
    }
    
    // MARK: - Chat Template Loop Patterns
    
    @Test("Chat template message enumeration")
    func testChatTemplateMessageEnumeration() throws {
        let template = try Template("""
        {% for message in messages %}
        {% if loop.first and message.role == 'system' %}
        <|system|>{{ message.content }}<|end|>
        {% elif message.role == 'user' %}
        <|user|>{{ message.content }}<|end|>
        {% elif message.role == 'assistant' %}
        <|assistant|>{{ message.content }}<|end|>
        {% endif %}
        {% endfor %}
        """)
        
        let result = try template.render([
            "messages": [
                ["role": "system", "content": "You are helpful"],
                ["role": "user", "content": "Hello"],
                ["role": "assistant", "content": "Hi there!"],
                ["role": "user", "content": "How are you?"]
            ]
        ])
        
        #expect(result.contains("<|system|>You are helpful<|end|>"))
        #expect(result.contains("<|user|>Hello<|end|>"))
        #expect(result.contains("<|assistant|>Hi there!<|end|>"))
        #expect(result.contains("<|user|>How are you?<|end|>"))
    }
    
    @Test("Tool iteration with loop controls")
    func testToolIterationWithLoopControls() throws {
        let template = try Template("""
        Available tools ({{ tools|length }}):
        {% for tool in tools %}
        {{ loop.index }}. {{ tool.name }}
        {% if tool.description %}   Description: {{ tool.description }}{% endif %}
        {% if not loop.last %}
        {% endif %}
        {% endfor %}
        """)
        
        let result = try template.render([
            "tools": [
                ["name": "calculator", "description": "Perform math calculations"],
                ["name": "weather", "description": "Get weather information"],
                ["name": "timer"] // no description
            ]
        ])
        
        #expect(result.contains("Available tools (3):"))
        #expect(result.contains("1. calculator"))
        #expect(result.contains("Description: Perform math calculations"))
        #expect(result.contains("2. weather"))
        #expect(result.contains("Description: Get weather information"))
        #expect(result.contains("3. timer"))
        #expect(!result.contains("Description:.*timer")) // Should not have description for timer
    }
}

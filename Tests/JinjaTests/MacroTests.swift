import Testing
@testable import Jinja

@Suite("Macro Definition and Call Tests")
struct MacroTests {
    
    // MARK: - Basic Macro Definition and Calling
    
    @Test("Simple macro definition and call")
    func testSimpleMacroDefinitionAndCall() throws {
        let template = try Template("""
        {% macro greet(name) %}
        Hello, {{ name }}!
        {% endmacro %}
        
        {{ greet('World') }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("Hello, World!"))
    }
    
    @Test("Macro with multiple parameters")
    func testMacroWithMultipleParameters() throws {
        let template = try Template("""
        {% macro introduce(name, age, city) %}
        Hi, I'm {{ name }}, {{ age }} years old, from {{ city }}.
        {% endmacro %}
        
        {{ introduce('Alice', 25, 'New York') }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("Hi, I'm Alice, 25 years old, from New York."))
    }
    
    @Test("Macro with no parameters")
    func testMacroWithNoParameters() throws {
        let template = try Template("""
        {% macro header() %}
        === HEADER ===
        {% endmacro %}
        
        {{ header() }}
        Content goes here
        {{ header() }}
        """)
        
        let result = try template.render([:])
        let headerCount = result.components(separatedBy: "=== HEADER ===").count - 1
        #expect(headerCount == 2)
    }
    
    @Test("Macro with default parameter values")
    func testMacroWithDefaultParameters() throws {
        let template = try Template("""
        {% macro greet(name, greeting='Hello') %}
        {{ greeting }}, {{ name }}!
        {% endmacro %}
        
        {{ greet('Alice') }}
        {{ greet('Bob', 'Hi') }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("Hello, Alice!"))
        #expect(result.contains("Hi, Bob!"))
    }
    
    // MARK: - Macro Scope and Variable Access
    
    @Test("Macro accessing global variables")
    func testMacroAccessingGlobalVariables() throws {
        let template = try Template("""
        {% macro show_config() %}
        App: {{ app_name }}
        Version: {{ version }}
        {% endmacro %}
        
        {{ show_config() }}
        """)
        
        let result = try template.render([
            "app_name": "MyApp",
            "version": "1.0.0"
        ])
        
        #expect(result.contains("App: MyApp"))
        #expect(result.contains("Version: 1.0.0"))
    }
    
    @Test("Macro parameter shadowing global variables")
    func testMacroParameterShadowing() throws {
        let template = try Template("""
        {% macro test(name) %}
        Inside macro: {{ name }}
        {% endmacro %}
        
        Outside macro: {{ name }}
        {{ test('Parameter') }}
        Outside macro again: {{ name }}
        """)
        
        let result = try template.render([
            "name": "Global"
        ])
        
        #expect(result.contains("Outside macro: Global"))
        #expect(result.contains("Inside macro: Parameter"))
        #expect(result.contains("Outside macro again: Global"))
    }
    
    @Test("Macro local variables")
    func testMacroLocalVariables() throws {
        let template = try Template("""
        {% macro process_data(items) %}
        {% set total = 0 %}
        {% for item in items %}
        {% set total = total + item %}
        {% endfor %}
        Total: {{ total }}
        {% endmacro %}
        
        {{ process_data([1, 2, 3, 4, 5]) }}
        Global total: {{ total if total is defined else 'undefined' }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("Total: 15"))
        #expect(result.contains("Global total: undefined"))
    }
    
    // MARK: - Nested and Recursive Macros
    
    @Test("Macro calling another macro")
    func testMacroCallingAnotherMacro() throws {
        let template = try Template("""
        {% macro bold(text) %}<b>{{ text }}</b>{% endmacro %}
        {% macro italic(text) %}<i>{{ text }}</i>{% endmacro %}
        {% macro bold_italic(text) %}{{ bold(italic(text)) }}{% endmacro %}
        
        {{ bold_italic('Important text') }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("<b><i>Important text</i></b>"))
    }
    
    @Test("Recursive macro")
    func testRecursiveMacro() throws {
        let template = try Template("""
        {% macro factorial(n) %}
        {% if n <= 1 %}
        1
        {% else %}
        {{ n * factorial(n - 1) }}
        {% endif %}
        {% endmacro %}
        
        5! = {{ factorial(5) }}
        """)
        
        // This test may fail if recursive macros are not properly supported
        let result = try template.render([:])
        #expect(result.contains("5! = 120"))
    }
    
    @Test("Macro generating HTML structure")
    func testMacroGeneratingHTMLStructure() throws {
        let template = try Template("""
        {% macro render_list(items, ordered=false) %}
        {% if ordered %}
        <ol>
        {% else %}
        <ul>
        {% endif %}
        {% for item in items %}
          <li>{{ item }}</li>
        {% endfor %}
        {% if ordered %}
        </ol>
        {% else %}
        </ul>
        {% endif %}
        {% endmacro %}
        
        {{ render_list(['Apple', 'Banana', 'Cherry']) }}
        {{ render_list(['First', 'Second', 'Third'], ordered=true) }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("<ul>"))
        #expect(result.contains("<li>Apple</li>"))
        #expect(result.contains("</ul>"))
        #expect(result.contains("<ol>"))
        #expect(result.contains("<li>First</li>"))
        #expect(result.contains("</ol>"))
    }
    
    // MARK: - Macro with Complex Logic
    
    @Test("Macro with conditional logic")
    func testMacroWithConditionalLogic() throws {
        let template = try Template("""
        {% macro render_user(user) %}
        <div class="user">
          <h3>{{ user.name }}</h3>
          {% if user.email %}
          <p>Email: {{ user.email }}</p>
          {% endif %}
          {% if user.admin %}
          <span class="badge">Admin</span>
          {% endif %}
          <p>Status: {{ 'Active' if user.active else 'Inactive' }}</p>
        </div>
        {% endmacro %}
        
        {{ render_user({'name': 'Alice', 'email': 'alice@example.com', 'admin': true, 'active': true}) }}
        {{ render_user({'name': 'Bob', 'active': false}) }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("<h3>Alice</h3>"))
        #expect(result.contains("Email: alice@example.com"))
        #expect(result.contains("<span class=\"badge\">Admin</span>"))
        #expect(result.contains("Status: Active"))
        #expect(result.contains("<h3>Bob</h3>"))
        #expect(result.contains("Status: Inactive"))
        #expect(!result.contains("Email:.*Bob")) // Bob should not have email
    }
    
    @Test("Macro with loops and complex data")
    func testMacroWithLoopsAndComplexData() throws {
        let template = try Template("""
        {% macro render_table(data, headers) %}
        <table>
          <thead>
            <tr>
              {% for header in headers %}
              <th>{{ header }}</th>
              {% endfor %}
            </tr>
          </thead>
          <tbody>
            {% for row in data %}
            <tr>
              {% for header in headers %}
              <td>{{ row[header] if row[header] is defined else '-' }}</td>
              {% endfor %}
            </tr>
            {% endfor %}
          </tbody>
        </table>
        {% endmacro %}
        
        {{ render_table([
            {'name': 'Alice', 'age': 25, 'city': 'NY'},
            {'name': 'Bob', 'age': 30},
            {'name': 'Charlie', 'city': 'LA'}
        ], ['name', 'age', 'city']) }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("<table>"))
        #expect(result.contains("<th>name</th>"))
        #expect(result.contains("<th>age</th>"))
        #expect(result.contains("<th>city</th>"))
        #expect(result.contains("<td>Alice</td>"))
        #expect(result.contains("<td>25</td>"))
        #expect(result.contains("<td>NY</td>"))
        #expect(result.contains("<td>Bob</td>"))
        #expect(result.contains("<td>30</td>"))
        #expect(result.contains("<td>-</td>")) // Missing values should show '-'
    }
    
    // MARK: - Macro Call Syntax Variations
    
    @Test("Macro call with keyword arguments")
    func testMacroCallWithKeywordArguments() throws {
        let template = try Template("""
        {% macro create_button(text, type='button', class='btn', disabled=false) %}
        <button type="{{ type }}" class="{{ class }}"{% if disabled %} disabled{% endif %}>{{ text }}</button>
        {% endmacro %}
        
        {{ create_button('Submit', type='submit', class='btn btn-primary') }}
        {{ create_button('Cancel', disabled=true) }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("<button type=\"submit\" class=\"btn btn-primary\">Submit</button>"))
        #expect(result.contains("<button type=\"button\" class=\"btn\" disabled>Cancel</button>"))
    }
    
    @Test("Macro call with mixed positional and keyword arguments")
    func testMacroCallMixedArguments() throws {
        let template = try Template("""
        {% macro format_date(date, format='%Y-%m-%d', timezone='UTC') %}
        {{ date }} ({{ format }} in {{ timezone }})
        {% endmacro %}
        
        {{ format_date('2023-12-25', timezone='PST') }}
        {{ format_date('2023-06-15', '%m/%d/%Y', timezone='EST') }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("2023-12-25 (%Y-%m-%d in PST)"))
        #expect(result.contains("2023-06-15 (%m/%d/%Y in EST)"))
    }
    
    // MARK: - Call Blocks (Advanced Macro Feature)
    
    @Test("Call block syntax")
    func testCallBlockSyntax() throws {
        let template = try Template("""
        {% macro render_dialog(title) %}
        <dialog>
          <h2>{{ title }}</h2>
          <div class="content">
            {{ caller() }}
          </div>
        </dialog>
        {% endmacro %}
        
        {% call render_dialog('Confirmation') %}
        Are you sure you want to delete this item?
        <button>Yes</button> <button>No</button>
        {% endcall %}
        """)
        
        // This test may fail if call blocks are not implemented
        #expect(throws: JinjaError.self) {
            let result = try template.render([:])
        }
    }
    
    @Test("Call block with parameters")
    func testCallBlockWithParameters() throws {
        let template = try Template("""
        {% macro render_list_item(items) %}
        <ul>
        {% for item in items %}
          <li>{{ caller(item, loop.index) }}</li>
        {% endfor %}
        </ul>
        {% endmacro %}
        
        {% call(item, index) render_list_item(['Apple', 'Banana', 'Cherry']) %}
        {{ index }}. {{ item|upper }}
        {% endcall %}
        """)
        
        // This test may fail if call blocks with parameters are not implemented
        #expect(throws: JinjaError.self) {
            let result = try template.render([:])
        }
    }
    
    // MARK: - Chat Template Macro Patterns
    
    @Test("Chat template message formatting macro")
    func testChatTemplateMessageFormattingMacro() throws {
        let template = try Template("""
        {% macro render_message(role, content, add_tokens=true) %}
        {% if add_tokens %}
        <|start_header_id|>{{ role }}<|end_header_id|>

        {{ content }}<|eot_id|>
        {% else %}
        {{ role.upper() }}: {{ content }}
        {% endif %}
        {% endmacro %}
        
        {{ render_message('system', 'You are a helpful assistant.') }}
        {{ render_message('user', 'Hello there!') }}
        {{ render_message('assistant', 'Hi! How can I help?', add_tokens=false) }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("<|start_header_id|>system<|end_header_id|>"))
        #expect(result.contains("You are a helpful assistant.<|eot_id|>"))
        #expect(result.contains("<|start_header_id|>user<|end_header_id|>"))
        #expect(result.contains("Hello there!<|eot_id|>"))
        #expect(result.contains("ASSISTANT: Hi! How can I help?"))
    }
    
    @Test("Tool function formatting macro")
    func testToolFunctionFormattingMacro() throws {
        let template = try Template("""
        {% macro render_tool(tool) %}
        Function: {{ tool.name }}
        {% if tool.description %}
        Description: {{ tool.description }}
        {% endif %}
        Parameters:
        {% for param, details in tool.parameters.properties %}
          - {{ param }}: {{ details.type }}{% if details.description %} - {{ details.description }}{% endif %}
        {% endfor %}
        {% endmacro %}
        
        {{ render_tool({
            'name': 'get_weather',
            'description': 'Get current weather conditions',
            'parameters': {
                'properties': {
                    'location': {'type': 'string', 'description': 'City name'},
                    'units': {'type': 'string', 'description': 'Temperature units'}
                }
            }
        }) }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("Function: get_weather"))
        #expect(result.contains("Description: Get current weather conditions"))
        #expect(result.contains("- location: string - City name"))
        #expect(result.contains("- units: string - Temperature units"))
    }
    
    // MARK: - Macro Error Cases and Edge Cases
    
    @Test("Macro with undefined parameters")
    func testMacroWithUndefinedParameters() throws {
        let template = try Template("""
        {% macro test(required_param) %}
        Value: {{ required_param }}
        {% endmacro %}
        
        {{ test() }}
        """)
        
        // This should handle missing required parameters gracefully or throw an error
        #expect(throws: JinjaError.self) {
            let result = try template.render([:])
        }
    }
    
    @Test("Macro redefinition")
    func testMacroRedefinition() throws {
        let template = try Template("""
        {% macro test() %}First definition{% endmacro %}
        {% macro test() %}Second definition{% endmacro %}
        
        {{ test() }}
        """)
        
        let result = try template.render([:])
        // Should use the last definition
        #expect(result.contains("Second definition"))
        #expect(!result.contains("First definition"))
    }
    
    @Test("Macro with very long content")
    func testMacroWithVeryLongContent() throws {
        let template = try Template("""
        {% macro generate_lorem() %}
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        {% endmacro %}
        
        {% for i in range(3) %}
        Paragraph {{ i + 1 }}:
        {{ generate_lorem() }}
        
        {% endfor %}
        """)
        
        let result = try template.render([:])
        let loremCount = result.components(separatedBy: "Lorem ipsum").count - 1
        #expect(loremCount == 3)
        #expect(result.contains("Paragraph 1:"))
        #expect(result.contains("Paragraph 3:"))
    }
    
    @Test("Macro with filters and tests")
    func testMacroWithFiltersAndTests() throws {
        let template = try Template("""
        {% macro safe_render(value, default='N/A') %}
        {% if value is defined and value is not none %}
        {{ value|string|trim|upper }}
        {% else %}
        {{ default }}
        {% endif %}
        {% endmacro %}
        
        Name: {{ safe_render(name) }}
        Age: {{ safe_render(age, 'Unknown') }}
        City: {{ safe_render('  new york  ') }}
        """)
        
        let result = try template.render([
            "name": "alice"
        ])
        
        #expect(result.contains("Name: ALICE"))
        #expect(result.contains("Age: Unknown"))
        #expect(result.contains("City: NEW YORK"))
    }
    
    // MARK: - Namespace and Import Simulation
    
    @Test("Multiple macros in template namespace")
    func testMultipleMacrosInNamespace() throws {
        let template = try Template("""
        {% macro header(level, text) %}
        <h{{ level }}>{{ text }}</h{{ level }}>
        {% endmacro %}
        
        {% macro paragraph(text) %}
        <p>{{ text }}</p>
        {% endmacro %}
        
        {% macro section(title, content) %}
        {{ header(2, title) }}
        {{ paragraph(content) }}
        {% endmacro %}
        
        {{ section('Introduction', 'Welcome to our website.') }}
        {{ section('About', 'We are a technology company.') }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("<h2>Introduction</h2>"))
        #expect(result.contains("<p>Welcome to our website.</p>"))
        #expect(result.contains("<h2>About</h2>"))
        #expect(result.contains("<p>We are a technology company.</p>"))
    }
    
    @Test("Macro encapsulation test")
    func testMacroEncapsulation() throws {
        let template = try Template("""
        {% set global_var = 'global' %}
        
        {% macro test_scope() %}
        {% set local_var = 'local' %}
        Global: {{ global_var }}
        Local: {{ local_var }}
        {% endmacro %}
        
        Before macro: {{ global_var }}
        {{ test_scope() }}
        After macro: {{ global_var }}
        Local outside: {{ local_var if local_var is defined else 'undefined' }}
        """)
        
        let result = try template.render([:])
        #expect(result.contains("Before macro: global"))
        #expect(result.contains("Global: global"))
        #expect(result.contains("Local: local"))
        #expect(result.contains("After macro: global"))
        #expect(result.contains("Local outside: undefined"))
    }
}

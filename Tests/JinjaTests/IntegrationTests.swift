import Testing

@testable import Jinja

@Suite("Integration Tests with Real Chat Templates", .enabled(if: true))
struct IntegrationTests {

    let options = Template.Options(lstripBlocks: true, trimBlocks: true)

    // MARK: - Chat Template Data

    private static let sampleMessages: [String: Value] = [
        "messages": .array([
            .object([
                "role": .string("system"),
                "content": .string(
                    "You are a helpful assistant that provides weather information."),
            ]),
            .object([
                "role": .string("user"),
                "content": .string("What's the weather like today?"),
            ]),
            .object([
                "role": .string("assistant"),
                "content": .string(
                    "I'd be happy to help you with the weather! However, I need to know your location first."
                ),
            ]),
        ])
    ]

    private static let multiTurnConversation: [String: Value] = [
        "messages": .array([
            .object([
                "role": .string("system"),
                "content": .string("You are a coding assistant."),
            ]),
            .object([
                "role": .string("user"),
                "content": .string("How do I create a for loop in Python?"),
            ]),
            .object([
                "role": .string("assistant"),
                "content": .string(
                    "In Python, you can create a for loop using this syntax:\n\n```python\nfor item in sequence:\n    # code here\n```"
                ),
            ]),
            .object([
                "role": .string("user"),
                "content": .string("Can you show me an example with numbers?"),
            ]),
            .object([
                "role": .string("assistant"),
                "content": .string(
                    "Sure! Here's an example:\n\n```python\nfor i in range(5):\n    print(i)\n```\n\nThis will print numbers 0 through 4."
                ),
            ]),
        ])
    ]

    // MARK: - Llama 3 Instruct Template

    @Test("Llama 3 Instruct chat template")
    func testLlama3InstructTemplate() throws {
        let template = try Template(
            """
            {% for message in messages %}
                {% if message['role'] == 'user' %}
                    <|start_header_id|>user<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% elif message['role'] == 'assistant' %}
                    <|start_header_id|>assistant<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% elif message['role'] == 'system' %}
                    <|start_header_id|>system<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% endif %}
            {% endfor %}
            {% if add_generation_prompt %}
            <|start_header_id|>assistant<|end_header_id|>

            {% endif %}
            """)

        var context = Self.sampleMessages
        context["add_generation_prompt"] = .boolean(true)

        let result = try template.render(context)

        // Verify structure
        #expect(result.contains("<|start_header_id|>system<|end_header_id|>"))
        #expect(result.contains("You are a helpful assistant"))
        #expect(result.contains("<|start_header_id|>user<|end_header_id|>"))
        #expect(result.contains("What's the weather like today?"))
        #expect(result.contains("<|start_header_id|>assistant<|end_header_id|>"))
        #expect(result.contains("I'd be happy to help"))
        #expect(result.contains("<|eot_id|>"))

        // Verify generation prompt is added
        #expect(result.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\n"))
    }

    @Test("Llama 3 template without generation prompt")
    func testLlama3TemplateWithoutGenerationPrompt() throws {
        let template = try Template(
            """
            {% for message in messages %}
                {% if message['role'] == 'user' %}
                    <|start_header_id|>user<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% elif message['role'] == 'assistant' %}
                    <|start_header_id|>assistant<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% elif message['role'] == 'system' %}
                    <|start_header_id|>system<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% endif %}
            {% endfor %}
            {% if add_generation_prompt %}
            <|start_header_id|>assistant<|end_header_id|>

            {% endif %}
            """, with: options)

        var context = Self.sampleMessages
        context["add_generation_prompt"] = .boolean(false)

        let result = try template.render(context)

        // Should not end with generation prompt
        #expect(!result.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\n"))
        #expect(result.hasSuffix("<|eot_id|>"))
    }

    // MARK: - ChatML Template (Qwen, Yi, Orca-2)

    @Test("ChatML format template")
    func testChatMLTemplate() throws {
        let template = try Template(
            """
            {% for message in messages %}
                {% if message['role'] == 'user' %}
                    <|im_start|>user
            {{ message['content'] }}<|im_end|>
                {% elif message['role'] == 'assistant' %}
                    <|im_start|>assistant
            {{ message['content'] }}<|im_end|>
                {% elif message['role'] == 'system' %}
                    <|im_start|>system
            {{ message['content'] }}<|im_end|>
                {% endif %}
            {% endfor %}
            {% if add_generation_prompt %}
            <|im_start|>assistant
            {% endif %}
            """, with: options)

        var context = Self.sampleMessages
        context["add_generation_prompt"] = .boolean(true)

        let result = try template.render(context)

        // Verify ChatML structure
        #expect(result.contains("<|im_start|>system"))
        #expect(result.contains("<|im_start|>user"))
        #expect(result.contains("<|im_start|>assistant"))
        #expect(result.contains("<|im_end|>"))
        #expect(result.contains("You are a helpful assistant"))
        #expect(result.contains("What's the weather like today?"))
        #expect(result.contains("I'd be happy to help"))

        // Verify generation prompt
        #expect(result.hasSuffix("<|im_start|>assistant\n"))
    }

    // MARK: - Mistral Instruct Template

    @Test("Mistral Instruct template")
    func testMistralInstructTemplate() throws {
        let template = try Template(
            """
            {% for message in messages %}
                {% if message['role'] == 'user' %}
                    {% if loop.first and system_message %}
                        [INST] {{ system_message }}

            {{ message['content'] }} [/INST]
                    {% else %}
                        [INST] {{ message['content'] }} [/INST]
                    {% endif %}
                {% elif message['role'] == 'assistant' %}
                    {{ message['content'] }}</s>
                {% elif message['role'] == 'system' %}
                    {% set system_message = message['content'] %}
                {% endif %}
            {% endfor %}
            {% if add_generation_prompt %}
            [INST] {% endif %}
            """, with: options)

        var context = Self.sampleMessages
        context["add_generation_prompt"] = .boolean(false)

        let result = try template.render(context)

        // Should include system message in first user turn
        #expect(result.contains("[INST] You are a helpful assistant"))
        #expect(result.contains("What's the weather like today? [/INST]"))
        #expect(result.contains("I'd be happy to help"))
        #expect(result.contains("</s>"))
    }

    // MARK: - Vicuna Template

    @Test("Vicuna chat template")
    func testVicunaTemplate() throws {
        let template = try Template(
            """
            {% for message in messages %}
                {% if message['role'] == 'user' %}
                    USER: {{ message['content'] }}
                {% elif message['role'] == 'assistant' %}
                    ASSISTANT: {{ message['content'] }}
                {% elif message['role'] == 'system' %}
                    {{ message['content'] }}
                {% endif %}
                {% if not loop.last and loop.nextitem['role'] == 'user' %}
            </s>
                {% endif %}
            {% endfor %}
            {% if add_generation_prompt %}
            ASSISTANT:{% endif %}
            """, with: options)

        var context = Self.sampleMessages
        context["add_generation_prompt"] = .boolean(true)

        let result = try template.render(context)

        #expect(result.contains("You are a helpful assistant"))
        #expect(result.contains("USER: What's the weather like today?"))
        #expect(result.contains("ASSISTANT: I'd be happy to help"))
        #expect(result.contains("</s>"))
        #expect(result.hasSuffix("ASSISTANT:"))
    }

    // MARK: - Gemma IT Template

    @Test("Gemma IT template")
    func testGemmaITTemplate() throws {
        let template = try Template(
            """
            {% if messages[0]['role'] == 'system' %}
                {% set system_message = messages[0]['content'] %}
                {% set messages = messages[1:] %}
            {% else %}
                {% set system_message = '' %}
            {% endif %}
            {% if system_message %}
                <|system|>
            {{ system_message }}
            {% endif %}
            {% for message in messages %}
                {% if message['role'] == 'user' %}
                    <|user|>
            {{ message['content'] }}
                {% elif message['role'] == 'assistant' %}
                    <|assistant|>
            {{ message['content'] }}
                {% endif %}
            {% endfor %}
            {% if add_generation_prompt %}
            <|assistant|>
            {% endif %}
            """, with: options)

        var context = Self.sampleMessages
        context["add_generation_prompt"] = .boolean(true)

        let result = try template.render(context)

        #expect(result.contains("<|system|>"))
        #expect(result.contains("You are a helpful assistant"))
        #expect(result.contains("<|user|>"))
        #expect(result.contains("What's the weather like today?"))
        #expect(result.contains("<|assistant|>"))
        #expect(result.contains("I'd be happy to help"))
        #expect(result.hasSuffix("<|assistant|>\n"))
    }

    // MARK: - Multi-turn Conversation Tests

    @Test("Multi-turn conversation with Llama 3")
    func testMultiTurnConversationLlama3() throws {
        let template = try Template(
            """
            {% for message in messages %}
                {% if message['role'] == 'system' %}
            <|start_header_id|>system<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% elif message['role'] == 'user' %}
            <|start_header_id|>user<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% elif message['role'] == 'assistant' %}
            <|start_header_id|>assistant<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
                {% endif %}
            {% endfor %}
            """, with: options)

        let result = try template.render(Self.multiTurnConversation)

        // Count the number of turns
        let systemCount =
            result.components(separatedBy: "<|start_header_id|>system<|end_header_id|>").count - 1
        let userCount =
            result.components(separatedBy: "<|start_header_id|>user<|end_header_id|>").count - 1
        let assistantCount =
            result.components(separatedBy: "<|start_header_id|>assistant<|end_header_id|>").count
            - 1

        #expect(systemCount == 1)
        #expect(userCount == 2)
        #expect(assistantCount == 2)

        // Verify content order
        #expect(result.contains("You are a coding assistant"))
        #expect(result.contains("How do I create a for loop"))
        #expect(result.contains("In Python, you can create"))
        #expect(result.contains("Can you show me an example"))
        #expect(result.contains("Sure! Here's an example"))
    }

    // MARK: - Tool/Function Call Templates

    @Test("Functionary template with tools")
    func testFunctionaryTemplateWithTools() throws {
        let template = try Template(
            """
            {{ bos_token }}<|start_header_id|>system<|end_header_id|>

            You are capable of executing available function(s) if required.
            Available functions:
            {% for tool in tools %}
            - {{ tool.name }}: {{ tool.description }}
            {% endfor %}<|eot_id|>
            {% for message in messages %}
            {% if message['role'] == 'user' %}
            <|start_header_id|>user<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
            {% elif message['role'] == 'assistant' %}
            <|start_header_id|>assistant<|end_header_id|>

            {{ message['content'] }}<|eot_id|>
            {% endif %}
            {% endfor %}
            """, with: options)

        let context: [String: Value] = [
            "bos_token": .string("<|begin_of_text|>"),
            "tools": .array([
                .object([
                    "name": .string("get_weather"),
                    "description": .string("Get current weather for a location"),
                ]),
                .object([
                    "name": .string("calculate"),
                    "description": .string("Perform mathematical calculations"),
                ]),
            ]),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("What's the weather in Paris and what's 25 * 4?"),
                ])
            ]),
        ]

        let result = try template.render(context)

        #expect(result.contains("<|begin_of_text|>"))
        #expect(result.contains("You are capable of executing available function(s)"))
        #expect(result.contains("- get_weather: Get current weather"))
        #expect(result.contains("- calculate: Perform mathematical"))
        #expect(result.contains("What's the weather in Paris"))
    }

    // MARK: - Advanced Template Features

    @Test("Template with loop variables")
    func testTemplateWithLoopVariables() throws {
        let template = try Template(
            """
            {% for message in messages %}
            Message {{ loop.index }}/{{ loop.length }}: 
            {% if loop.first %}[FIRST] {% endif %}
            {% if message['role'] == 'system' %}SYSTEM{% endif %}
            {% if message['role'] == 'user' %}USER{% endif %}
            {% if message['role'] == 'assistant' %}ASSISTANT{% endif %}
            : {{ message['content'] }}
            {% if loop.last %}[LAST]{% endif %}

            {% endfor %}
            """, with: options)

        let result = try template.render(Self.sampleMessages)

        #expect(result.contains("Message 1/3"))
        #expect(result.contains("Message 2/3"))
        #expect(result.contains("Message 3/3"))
        #expect(result.contains("[FIRST] SYSTEM"))
        #expect(result.contains("[LAST]"))
        #expect(result.contains("USER: What's the weather"))
        #expect(result.contains("ASSISTANT: I'd be happy"))
    }

    @Test("Template with conditional system message handling")
    func testTemplateWithConditionalSystemMessage() throws {
        let template = try Template(
            """
            {% set has_system = false %}
            {% for message in messages %}
            {% if message['role'] == 'system' %}
            {% set has_system = true %}
            SYSTEM: {{ message['content'] }}

            {% endif %}
            {% endfor %}

            {% if not has_system %}
            SYSTEM: Default system message

            {% endif %}

            {% for message in messages %}
            {% if message['role'] != 'system' %}
            {{ message['role']|upper }}: {{ message['content'] }}

            {% endif %}
            {% endfor %}
            """, with: options)

        // Test with system message
        let resultWithSystem = try template.render(Self.sampleMessages)
        #expect(resultWithSystem.contains("SYSTEM: You are a helpful assistant"))
        #expect(!resultWithSystem.contains("Default system message"))

        // Test without system message
        let messagesWithoutSystem: [String: Value] = [
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Hello"),
                ]),
                .object([
                    "role": .string("assistant"),
                    "content": .string("Hi there!"),
                ]),
            ])
        ]

        let resultWithoutSystem = try template.render(messagesWithoutSystem)
        #expect(resultWithoutSystem.contains("SYSTEM: Default system message"))
        #expect(resultWithoutSystem.contains("USER: Hello"))
        #expect(resultWithoutSystem.contains("ASSISTANT: Hi there!"))
    }

    // MARK: - Error Cases and Edge Cases

    @Test("Template with missing message fields")
    func testTemplateWithMissingFields() throws {
        let template = try Template(
            """
            {% for message in messages %}
            {% if message.role is defined and message.content is defined %}
            {{ message.role }}: {{ message.content }}
            {% else %}
            [INVALID MESSAGE]
            {% endif %}
            {% endfor %}
            """, with: options)

        let messagesWithMissing: [String: Value] = [
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Complete message"),
                ]),
                .object([
                    "role": .string("assistant")
                    // missing content
                ]),
                .object([
                    "content": .string("Message without role")
                    // missing role
                ]),
            ])
        ]

        let result = try template.render(messagesWithMissing)

        #expect(result.contains("user: Complete message"))
        #expect(result.contains("[INVALID MESSAGE]"))

        // Count invalid messages
        let invalidCount = result.components(separatedBy: "[INVALID MESSAGE]").count - 1
        #expect(invalidCount == 2)  // Two messages with missing fields
    }

    @Test("Empty messages array")
    func testEmptyMessagesArray() throws {
        let template = try Template(
            """
            {% if messages %}
            {% for message in messages %}
            {{ message.role }}: {{ message.content }}
            {% endfor %}
            {% else %}
            No messages to display.
            {% endif %}
            """, with: options)

        let emptyContext: [String: Value] = [
            "messages": .array([])
        ]

        let result = try template.render(emptyContext)
        #expect(result.contains("No messages to display."))
    }

    @Test("Complex nested template structure")
    func testComplexNestedTemplateStructure() throws {
        let template = try Template(
            """
            {% macro render_message(msg, show_role=true) %}
            {% if show_role %}{{ msg.role|upper }}: {% endif %}{{ msg.content }}
            {% endmacro %}

            {% for message in messages %}
            {% if message.role == 'system' %}
            === SYSTEM PROMPT ===
            {{ render_message(message, show_role=false) }}
            === END SYSTEM PROMPT ===

            {% else %}
            {{ render_message(message) }}

            {% endif %}
            {% endfor %}
            """, with: options)

        let result = try template.render(Self.sampleMessages)

        #expect(result.contains("=== SYSTEM PROMPT ==="))
        #expect(result.contains("You are a helpful assistant"))
        #expect(result.contains("=== END SYSTEM PROMPT ==="))
        #expect(result.contains("USER: What's the weather"))
        #expect(result.contains("ASSISTANT: I'd be happy"))
    }

    // MARK: - Performance Test with Large Template

    @Test("Large conversation template performance")
    func testLargeConversationTemplate() throws {
        // Create a large conversation
        var largeMessages: [Value] = []

        for i in 0..<100 {
            largeMessages.append(
                .object([
                    "role": .string(i % 2 == 0 ? "user" : "assistant"),
                    "content": .string("Message number \(i + 1) in this conversation."),
                ]))
        }

        let template = try Template(
            """
            {% for message in messages %}
            {{ loop.index }}. {{ message.role|upper }}: {{ message.content }}
            {% endfor %}
            """, with: options)

        let context: [String: Value] = [
            "messages": .array(largeMessages)
        ]

        let result = try template.render(context)

        // Verify it contains all messages
        #expect(result.contains("1. USER: Message number 1"))
        #expect(result.contains("100. ASSISTANT: Message number 100"))

        // Count lines to ensure all messages are present
        let lines = result.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 100)
    }

    // MARK: - Real-world Template Variations

    @Test("Alpaca template variation")
    func testAlpacaTemplate() throws {
        let template = try Template(
            """
            {% if system_message %}{{ system_message }}

            {% endif %}{% for message in messages %}{% if message['role'] == 'user' %}### Instruction:
            {{ message['content'] }}

            ### Response:
            {% elif message['role'] == 'assistant' %}{{ message['content'] }}{% if not loop.last %}

            {% endif %}{% endif %}{% endfor %}
            """, with: options)

        let context: [String: Value] = [
            "system_message": .string(
                "Below is an instruction that describes a task. Write a response that appropriately completes the request."
            ),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Explain quantum computing in simple terms."),
                ]),
                .object([
                    "role": .string("assistant"),
                    "content": .string(
                        "Quantum computing uses quantum mechanical phenomena like superposition and entanglement to perform calculations."
                    ),
                ]),
            ]),
        ]

        let result = try template.render(context)

        #expect(result.contains("Below is an instruction that describes a task"))
        #expect(result.contains("### Instruction:"))
        #expect(result.contains("Explain quantum computing"))
        #expect(result.contains("### Response:"))
        #expect(result.contains("Quantum computing uses quantum mechanical"))
    }
}

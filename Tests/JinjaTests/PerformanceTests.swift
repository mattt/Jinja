// https://github.com/johnmai-dev/Jinja/blob/main/Tests/PerformanceTests.swift

import Foundation
import Testing

@testable import Jinja

@Suite("Performance Tests")
struct PerformanceTests {

    // MARK: - Test Data

    private static let llama3_2Template = """
        {%- for message in messages -%}
        {%- if message.role == 'system' -%}
        <|start_header_id|>system<|end_header_id|>

        {{ message.content }}<|eot_id|>
        {%- elif message.role == 'user' -%}
        <|start_header_id|>user<|end_header_id|>

        {{ message.content }}<|eot_id|>
        {%- elif message.role == 'assistant' -%}
        <|start_header_id|>assistant<|end_header_id|>

        {{ message.content }}<|eot_id|>
        {%- endif -%}
        {%- endfor -%}
        {%- if add_generation_prompt -%}
        <|start_header_id|>assistant<|end_header_id|>

        {%- endif -%}
        """

    private static let weatherQueryMessages: [String: Value] = [
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
        ])
    ]

    // MARK: - Performance Measurement Helper

    private func measureMs(iterations: Int = 100, warmup: Int = 10, _ body: () throws -> Void)
        rethrows -> Double
    {
        // Warmup
        for _ in 0..<warmup { try body() }

        var total: Double = 0
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            let end = DispatchTime.now().uptimeNanoseconds
            total += Double(end - start) / 1_000_000.0
        }
        return total / Double(iterations)
    }

    // MARK: - Performance Tests

    @Test("Template render performance")
    func testTemplateRenderPerformance() async throws {
        let template = try Template(Self.llama3_2Template)

        let avgMs = try measureMs {
            _ = try template.render([
                "messages": Self.weatherQueryMessages["messages"]!,
                "add_generation_prompt": true,
            ])
        }
        print("Template.render avg: \(String(format: "%.3f", avgMs)) ms")
    }

    @Test("Pipeline stages performance")
    func testPipelineStagesPerformance() async throws {
        let template = Self.llama3_2Template

        // tokenize
        let tokenizeMs = try measureMs {
            _ = try Lexer.tokenize(template)
        }

        let tokens = try Lexer.tokenize(template)

        // parse
        let parseMs = try measureMs {
            _ = try Parser.parse(tokens)
        }

        let program = try Parser.parse(tokens)

        // interpret
        let env = Environment()
        env["messages"] = Self.weatherQueryMessages["messages"]!
        env["add_generation_prompt"] = .boolean(false)

        let runMs = try measureMs {
            _ = try Interpreter.interpret(program, environment: env)
        }

        print(
            "tokenize avg: \(String(format: "%.3f", tokenizeMs)) ms | parse avg: \(String(format: "%.3f", parseMs)) ms | run avg: \(String(format: "%.3f", runMs)) ms"
        )
    }
}

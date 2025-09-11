//
//  JinjaTemplate.swift
//  Jinja - Swift 6 optimized template with API compatibility
//

import Foundation
import OrderedCollections

/// High-performance Jinja template implementation with Swift 6 structured concurrency
public struct Template: Sendable {
    let nodes: [Node]

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// Initialize template from string
    /// - Parameter template: Jinja template string
    /// - Throws: JinjaError on parsing failure
    public init(_ template: String) throws {
        let tokens = try Lexer.tokenize(template)
        self.nodes = try Parser.parse(tokens)
    }

    /// Render template with context variables
    /// - Parameters:
    ///   - context: Dictionary of template variables
    ///   - environment: Optional parent environment
    /// - Returns: Rendered template string
    /// - Throws: JinjaError on rendering failure
    public func render(
        _ context: [String: Value],
        environment: Environment? = nil
    ) throws -> String {
        let env = environment ?? Environment()

        // Set context values directly
        for (key, value) in context {
            env.set(key, value: value)
        }

        return try Interpreter.interpret(nodes, environment: env)
    }
}

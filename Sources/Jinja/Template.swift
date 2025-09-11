import Foundation
import OrderedCollections

/// A compiled Jinja template that can be rendered with context data.
public struct Template: Sendable {
    let nodes: [Node]

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// Creates a template by parsing the given template string.
    public init(_ template: String) throws {
        let tokens = try Lexer.tokenize(template)
        self.nodes = try Parser.parse(tokens)
    }

    /// Renders the template with the given context variables.
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

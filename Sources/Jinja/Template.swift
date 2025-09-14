import Foundation
import OrderedCollections

/// A compiled Jinja template that can be rendered with context data.
public struct Template: Hashable, Sendable {
    public struct Options: Hashable, Sendable {
        /// Whether leading spaces and tabs are stripped from the start of a line to a block.
        /// The default value is `false`.
        public var lstripBlocks: Bool = false

        /// Whether the first newline after a block is removed.
        /// This applies to block tags, not variable tags.
        /// The default value is `false`.
        public var trimBlocks: Bool = false

        public init(lstripBlocks: Bool = false, trimBlocks: Bool = false) {
            self.lstripBlocks = lstripBlocks
            self.trimBlocks = trimBlocks
        }
    }

    let nodes: [Node]

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// Creates a template by parsing the given template string.
    public init(_ template: String, with options: Options = .init()) throws {
        var source = template

        // Apply lstrip_blocks if enabled
        if options.lstripBlocks {
            // Strip tabs and spaces from the beginning of a line to the start of a block
            // This matches lines that start with spaces/tabs followed by {%, {#, or {-
            let lines = template.components(separatedBy: .newlines)
            source = lines.map { line in
                if line.range(of: "^[ \\t]*{[#%]", options: .regularExpression) != nil {
                    return line.replacingOccurrences(
                        of: "^[ \\t]*", with: "", options: .regularExpression)
                }
                return line
            }.joined(separator: "\n")
        }

        // Apply trim_blocks if enabled
        if options.trimBlocks {
            // Remove the first newline after a template tag
            source = source.replacingOccurrences(
                of: "%}\\n", with: "%}", options: .regularExpression)
            source = source.replacingOccurrences(
                of: "#}\\n", with: "#}", options: .regularExpression)
        }

        let tokens = try Lexer.tokenize(source)
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
            env[key] = value
        }

        return try Interpreter.interpret(nodes, environment: env)
    }
}

import Foundation
import OrderedCollections

/// A compiled Jinja template that can be rendered with context data.
public struct Template: Hashable, Sendable {
    /// Configuration options for template parsing and rendering behavior.
    public struct Options: Hashable, Sendable {
        /// Whether leading spaces and tabs are stripped from the start of a line to a block.
        /// The default value is `false`.
        public var lstripBlocks: Bool = false

        /// Whether the first newline after a block is removed.
        /// This applies to block tags, not variable tags.
        /// The default value is `false`.
        public var trimBlocks: Bool = false

        /// Creates template options with the specified settings.
        ///
        /// - Parameters:
        ///   - lstripBlocks: Whether to strip leading whitespace from blocks
        ///   - trimBlocks: Whether to remove the first newline after blocks
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
    ///
    /// - Parameters:
    ///   - template: The Jinja template source code to parse
    ///   - options: Configuration options for template parsing
    /// - Throws: `JinjaError` if the template contains syntax errors
    public init(_ template: String, with options: Options = .init()) throws {
        var source = template

        // Handle Jinja whitespace control first (more efficient than original 4 regex approach)
        source = Self.preprocessWhitespaceControl(source)

        // Apply lstrip_blocks if enabled
        if options.lstripBlocks {
            // Strip tabs and spaces from the beginning of a line to the start of a block
            // This matches lines that start with spaces/tabs followed by {%, {#, or {-
            let lines = source.components(separatedBy: .newlines)
            let leadingWhitespace = /^[ \t]*{[#%]/
            let removeWhitespace = /^[ \t]*/
            source = lines.map { line in
                if line.contains(leadingWhitespace) {
                    return line.replacing(removeWhitespace, with: "")
                }
                return line
            }.joined(separator: "\n")
        }

        // Apply trim_blocks if enabled
        if options.trimBlocks {
            // Remove the first newline after a template tag
            let blockEnd = /%}\n/
            let commentEnd = /#}\n/
            source = source.replacing(blockEnd, with: "%}")
            source = source.replacing(commentEnd, with: "#}")
        }

        let tokens = try Lexer.tokenize(source)
        self.nodes = try Parser.parse(tokens)
    }

    private static func preprocessWhitespaceControl(_ template: String) -> String {
        var result = ""
        result.reserveCapacity(template.count)

        var i = template.startIndex

        while i < template.endIndex {
            let char = template[i]

            if char == "{" {
                let next = template.index(after: i)
                if next < template.endIndex {
                    let nextChar = template[next]
                    if nextChar == "%" || nextChar == "{" {
                        // Look for {%- or {{-
                        let afterNext = template.index(after: next)
                        if afterNext < template.endIndex && template[afterNext] == "-" {
                            // Strip preceding whitespace
                            while !result.isEmpty && result.last!.isWhitespace {
                                result.removeLast()
                            }
                            // Add the delimiter without the dash
                            result += String(template[i..<next])
                            i = template.index(after: afterNext)
                            continue
                        }
                    }
                }
            } else if char == "-" {
                let next = template.index(after: i)
                if next < template.endIndex {
                    let nextChar = template[next]
                    if nextChar == "}" {
                        let afterNext = template.index(after: next)
                        if afterNext < template.endIndex && template[afterNext] == "}" {
                            // -}} case - add closing delimiter and skip following whitespace
                            result += "}}"
                            i = template.index(after: afterNext)
                            // Skip following whitespace
                            while i < template.endIndex && template[i].isWhitespace {
                                i = template.index(after: i)
                            }
                            continue
                        } else {
                            // -%} case - add closing delimiter and skip following whitespace
                            result += "%}"
                            i = template.index(after: next)
                            // Skip following whitespace
                            while i < template.endIndex && template[i].isWhitespace {
                                i = template.index(after: i)
                            }
                            continue
                        }
                    }
                }
            }

            result += String(char)
            i = template.index(after: i)
        }

        return result
    }

    /// Renders the template with the given context variables.
    ///
    /// - Parameters:
    ///   - context: Variables and values to use during template rendering
    ///   - environment: Optional environment containing additional variables and settings
    /// - Returns: The rendered template as a string
    /// - Throws: `JinjaError` if an error occurs during template rendering
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

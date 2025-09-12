import Testing

@testable import Jinja

@Suite("Template Tests")
struct TemplateTests {

    @Test("No template")
    func noTemplate() throws {
        let string = #"Hello, world!"#
        let context: Context = [:]

        // Check result of lexer
        let tokens = try Lexer.tokenize(string)
        #expect(
            tokens == [
                Token(kind: .text, value: "Hello, world!", position: 0),
                Token(kind: .eof, value: "", position: 13),
            ]
        )

        // Check result of parser
        let nodes = try Parser.parse(tokens)
        #expect(
            nodes == [
                .text("Hello, world!")
            ]
        )

        // Check result of template initialized with string
        let rendered = try Template(string).render(context)
        #expect(rendered == "Hello, world!")

        // Check result of template initialized with nodes
        #expect(rendered == (try Template(nodes: nodes).render(context)))
    }
}

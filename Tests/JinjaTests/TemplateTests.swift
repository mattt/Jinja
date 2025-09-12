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

    @Test("Text nodes")
    func textNodes() throws {
        let string = #"0{{ 'A' }}1{{ 'B' }}{{ 'C' }}2{{ 'D' }}3"#
        let context: Context = [:]

        // Check result of lexer
        let tokens = try Lexer.tokenize(string)
        #expect(
            tokens == [
                Token(kind: .text, value: "0", position: 0),
                Token(kind: .expression, value: "'A'", position: 1),
                Token(kind: .text, value: "1", position: 10),
                Token(kind: .expression, value: "'B'", position: 11),
                Token(kind: .expression, value: "'C'", position: 20),
                Token(kind: .text, value: "2", position: 29),
                Token(kind: .expression, value: "'D'", position: 30),
                Token(kind: .text, value: "3", position: 39),
                Token(kind: .eof, value: "", position: 40),
            ]
        )

        // Check result of parser
        let nodes = try Parser.parse(tokens)
        #expect(
            nodes == [
                .text("0"),
                .expression(.string("A")),
                .text("1"),
                .expression(.string("B")),
                .expression(.string("C")),
                .text("2"),
                .expression(.string("D")),
                .text("3"),
            ]
        )

        // Check result of template initialized with string
        let rendered = try Template(string).render(context)
        #expect(rendered == "0A1BC2D3")

        // Check result of template initialized with nodes
        #expect(rendered == (try Template(nodes: nodes).render(context)))
    }
}
